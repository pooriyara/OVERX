import 'dart:convert';
import 'dart:io';

import '../models/network.dart';

/// آدرسِ پیش‌فرض برای سنجشِ تأخیر (همان چیزی که sing-box خودش پیش‌فرض دارد).
const String kClashTestUrl = 'https://www.gstatic.com/generate_204';

/// کلاینتِ بسیار سبک برای **Clash API** ی sing-box.
///
/// وقتی `experimental.clash_api.external_controller` در کانفیگ تنظیم شود
/// (که `SingBoxConfigBuilder` با پورتِ [AppSettings.singboxApiPort] انجام
/// می‌دهد)، sing-box یک سرورِ HTTP محلی بالا می‌آورد. دو مسیر برای ما مهم‌اند:
///
/// * `GET /proxies`      → گروه‌های خروجی و ایتم‌هایشان
/// * `GET /connections`  → اتصال‌های جاری
///
/// روی **دسکتاپ** — جایی که libbox در دسترس نیست — این تنها راهِ دیدنِ
/// گروه‌ها و اتصال‌هاست. Xray چنین API یی ندارد، برای همین آن هسته
/// در این صفحه پشتیبانی نمی‌شود.
///
/// شکلِ پاسخ‌ها با mihomo/Clash یکی است و در دو تابعِ
/// [parseClashProxies] و [parseClashConnections] جدا شده تا بدونِ
/// شبیه‌ساز هم قابل‌تست باشند.
class ClashApi {
  ClashApi({
    required this.port,
    HttpClient? client,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? HttpClient();

  final int port;
  final HttpClient _client;
  final Duration timeout;

  static const String host = '127.0.0.1';

  Uri uri(String path, [Map<String, String>? query]) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path,
        queryParameters: query,
      );

  /// یک درخواستِ JSON؛ در صورتِ خطای HTTP استثنا می‌اندازد.
  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final req = await _client.openUrl(method, uri(path, query)).timeout(timeout);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final resp = await req.close().timeout(timeout);
    final text = await resp.transform(utf8.decoder).join();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ClashApiException(resp.statusCode, text);
    }
    if (text.trim().isEmpty) return null;
    return jsonDecode(text);
  }

  // ------------------------------------------------------------- خواندن

  Future<List<OutboundGroup>> getGroups() async =>
      parseClashProxies(await request('GET', '/proxies'));

  Future<List<ConnectionEntry>> getConnections() async =>
      parseClashConnections(await request('GET', '/connections'));

  // ------------------------------------------------------------ فرمان‌ها

  Future<void> closeConnection(String id) async {
    await request('DELETE', '/connections/${_seg(id)}');
  }

  Future<void> closeConnections() async {
    await request('DELETE', '/connections');
  }

  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) async {
    await request(
      'PUT',
      '/proxies/${_seg(groupTag)}',
      body: <String, Object?>{'name': outboundTag},
    );
  }

  /// تأخیر را بر حسبِ میلی‌ثانیه برمی‌گرداند؛ صفر یعنی ناموفق.
  Future<int> testDelay(
    String outboundTag, {
    String url = kClashTestUrl,
    int timeoutMs = 5000,
  }) async {
    final res = await request(
      'GET',
      '/proxies/${_seg(outboundTag)}/delay',
      query: <String, String>{'url': url, 'timeout': '$timeoutMs'},
    );
    if (res is Map) {
      final delay = res['delay'];
      if (delay is num) return delay.toInt();
    }
    return 0;
  }

  static String _seg(String s) => Uri.encodeComponent(s);
}

/// خطایِ HTTP از سرورِ Clash API.
class ClashApiException implements Exception {
  const ClashApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ClashApiException($statusCode): $body';
}

// =============================================================================
// تجزیه — جدا شده تا بدونِ شبکه/شبیه‌ساز تست‌پذیر باشد
// =============================================================================

/// انواعِ گروه که کاربر می‌تواند خروجی‌شان را عوض کند.
///
/// بقیه (مثل `Reject` و `Direct`) فهرستی دارند اما انتخاب‌پذیر نیستند.
///
/// مقایسه **ناهم‌حساس به بزرگیِ حرف** انجام می‌شود: در mihomo این مقدار
/// با حرفِ بزرگ می‌آید (`Selector`) ولی بعضی کلاینت‌ها/نسخه‌ها آن را
/// کوچک می‌فرستند (`selector`). اگر حساس به حرف باشد و سرور کوچک بفرستد،
/// هیچ گروهی انتخاب‌پذیر نیست و کلِ فهرست «غیرقابل انتخاب» می‌شود.
const Set<String> kSelectableClashGroupTypes = <String>{
  'Selector',
  'URLTest',
  'Fallback',
  'LoadBalance',
  'Relay',
};

bool isSelectableClashGroupType(String type) {
  final lower = type.toLowerCase();
  return kSelectableClashGroupTypes.any((t) => t.toLowerCase() == lower);
}

/// تبدیلِ پاسخِ `GET /proxies` به مدلِ برنامه.
///
/// ساختار: یک نگاشت از **همه‌ی** خروجی‌ها (گروه‌ها و ایتم‌ها با هم)؛
/// گروه‌ها همان‌هایی‌اند که کلیدِ `all` دارند.
List<OutboundGroup> parseClashProxies(Object? root) {
  final proxies = _asMap(root)['proxies'];
  if (proxies is! Map) return const <OutboundGroup>[];

  final out = <OutboundGroup>[];
  for (final entry in proxies.entries) {
    final tag = entry.key.toString();
    final group = entry.value;
    if (group is! Map) continue;

    final all = group['all'];
    if (all is! List) continue; // فقط گروه‌ها `all` دارند

    final type = (group['type'] ?? '').toString();
    final items = <OutboundItem>[];
    for (final name in all) {
      final child = _asMap(proxies[name]);
      final delay = _lastDelay(child['history']);
      items.add(
        OutboundItem(
          tag: name.toString(),
          type: (child['type'] ?? '').toString(),
          urlTestDelay: delay.$1,
          urlTestTime: delay.$2,
        ),
      );
    }

    out.add(
      OutboundGroup(
        tag: tag,
        type: type.toLowerCase(),
        selectable: isSelectableClashGroupType(type),
        selected: (group['now'] ?? '').toString(),
        items: items,
      ),
    );
  }
  return out;
}

/// تبدیلِ پاسخِ `GET /connections` به مدلِ برنامه.
///
/// `upload`/`download` تجمعی‌اند (نه سرعتِ لحظه‌ای) و `chains[0]` نامِ
/// خروجی‌ای است که این اتصال از آن رفته.
List<ConnectionEntry> parseClashConnections(Object? root) {
  final list = _asMap(root)['connections'];
  if (list is! List) return const <ConnectionEntry>[];

  final out = <ConnectionEntry>[];
  for (final raw in list) {
    if (raw is! Map) continue;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) continue;

    final meta = _asMap(raw['metadata']);
    final chains = raw['chains'];

    out.add(
      ConnectionEntry(
        id: id,
        outbound: (chains is List && chains.isNotEmpty)
            ? chains.first.toString()
            : '',
        protocol: (meta['type'] ?? '').toString(),
        network: (meta['network'] ?? '').toString(),
        destination: _joinHostPort(
          meta['destinationIP'],
          meta['destinationPort'],
        ),
        domain: (meta['host'] ?? '').toString(),
        source: _joinHostPort(meta['sourceIP'], meta['sourcePort']),
        uplinkTotal: _asNum(raw['upload']),
        downlinkTotal: _asNum(raw['download']),
        createdAt: _parseTime(raw['start']),
        // سرور فقط اتصال‌های باز را می‌فرستد
        closedAt: 0,
        processPath: (meta['processPath'] ?? '').toString(),
      ),
    );
  }
  return out;
}

// ------------------------------------------------------------------ کمکی

Map<Object?, Object?> _asMap(Object? value) =>
    value is Map ? value : const <Object?, Object?>{};

/// آخرین تأخیرِ موفق را به صورت `(میلی‌ثانیه، زمان)` برمی‌گرداند.
///
/// `history` فهرستی از `{time, delay}` است. اگر زمان در دسترس نباشد،
/// مقدارِ ۱ برمی‌گردد تا فقط نشان بدهد «تست شده» است
/// (نگاه کن به [OutboundItem.tested]).
(int, int) _lastDelay(Object? history) {
  if (history is! List || history.isEmpty) return (0, 0);
  final last = history.last;
  if (last is! Map) return (0, 0);

  final delay = last['delay'];
  if (delay is! num || delay <= 0) return (0, 0);

  final ms = _parseTime(last['time']);
  return (delay.toInt(), ms == 0 ? 1 : ms);
}

int _parseTime(Object? value) {
  if (value == null) return 0;
  return DateTime.tryParse(value.toString())?.millisecondsSinceEpoch ?? 0;
}

int _asNum(Object? value) => value is num ? value.toInt() : 0;

String _joinHostPort(Object? ip, Object? port) {
  final h = (ip ?? '').toString();
  final p = (port ?? '').toString();
  if (h.isEmpty) return '';
  return p.isEmpty ? h : '$h:$p';
}
