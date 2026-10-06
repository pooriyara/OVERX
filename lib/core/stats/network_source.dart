import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/core_type.dart';
import '../engine/engine_controller.dart';
import '../models/network.dart';
import '../platform/libbox.dart';
import '../../theme/app_theme.dart';
import 'clash_api.dart';

/// داده‌ی صفحه‌ی شبکه از کجا می‌آید.
enum NetworkSourceKind {
  /// سرورِ فرمانِ libbox (اندروید).
  libbox,

  /// Clash API ی sing-box روی دسکتاپ.
  clash,

  /// در دسترس نیست.
  none,
}

/// چرا منبعی در دسترس نیست — برای اینکه رابط بتواند پیامِ درست بدهد.
enum NetworkUnavailableReason {
  /// هسته اصلاً اجرا نیست.
  coreStopped,

  /// Xray روی دسکتاپ فهرستِ گروه/اتصال expose نمی‌کند.
  xray,

  /// چیزِ دیگری (پیش‌فرض).
  other,
}

/// قراردادِ یک منبعِ داده برای صفحه‌ی شبکه.
///
/// چرا این انتزاع؟ چون یک صفحه روی سه سناریو کار می‌کند:
///
/// | پلتفرم | هسته | منبع |
/// |---|---|---|
/// | اندروید | sing-box | libbox (`CoreCommandClient`) |
/// | دسکتاپ  | sing-box | Clash API روی `127.0.0.1:<singboxApiPort>` |
/// | دسکتاپ  | Xray     | ندارد |
abstract class NetworkSource {
  NetworkSourceKind get kind;

  Future<List<OutboundGroup>> getGroups();

  Future<List<ConnectionEntry>> getConnections();

  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  });

  Future<void> urlTest(String outboundTag);

  Future<void> closeConnection(String id);

  Future<void> closeConnections();
}

// ------------------------------------------------------------ پیاده‌سازی‌ها

/// منبعِ اندروید: همان متدهای libbox.
class LibboxNetworkSource implements NetworkSource {
  const LibboxNetworkSource(this._libbox);

  final LibboxService _libbox;

  @override
  NetworkSourceKind get kind => NetworkSourceKind.libbox;

  @override
  Future<List<OutboundGroup>> getGroups() => _libbox.getGroups();

  @override
  Future<List<ConnectionEntry>> getConnections() => _libbox.getConnections();

  @override
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) =>
      _libbox.selectOutbound(groupTag: groupTag, outboundTag: outboundTag);

  @override
  Future<void> urlTest(String outboundTag) => _libbox.urlTest(outboundTag);

  @override
  Future<void> closeConnection(String id) => _libbox.closeConnection(id);

  @override
  Future<void> closeConnections() => _libbox.closeConnections();
}

/// منبعِ دسکتاپ: Clash API ی sing-box.
class ClashNetworkSource implements NetworkSource {
  const ClashNetworkSource(this._api);

  final ClashApi _api;

  @override
  NetworkSourceKind get kind => NetworkSourceKind.clash;

  @override
  Future<List<OutboundGroup>> getGroups() => _api.getGroups();

  @override
  Future<List<ConnectionEntry>> getConnections() => _api.getConnections();

  @override
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) =>
      _api.selectOutbound(groupTag: groupTag, outboundTag: outboundTag);

  /// نتیجه دور انداخته می‌شود؛ صفحه خودش بعد از یک دور دوباره می‌خواند.
  @override
  Future<void> urlTest(String outboundTag) async {
    await _api.testDelay(outboundTag);
  }

  @override
  Future<void> closeConnection(String id) => _api.closeConnection(id);

  @override
  Future<void> closeConnections() => _api.closeConnections();
}

/// هیچ منبعی — همه‌چیز تهی، هیچ فرمانی کاری نمی‌کند.
class UnavailableNetworkSource implements NetworkSource {
  const UnavailableNetworkSource([
    this.reason = NetworkUnavailableReason.other,
  ]);

  final NetworkUnavailableReason reason;

  @override
  NetworkSourceKind get kind => NetworkSourceKind.none;

  @override
  Future<List<OutboundGroup>> getGroups() async => const <OutboundGroup>[];

  @override
  Future<List<ConnectionEntry>> getConnections() async =>
      const <ConnectionEntry>[];

  @override
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) async {}

  @override
  Future<void> urlTest(String outboundTag) async {}

  @override
  Future<void> closeConnection(String id) async {}

  @override
  Future<void> closeConnections() async {}
}

// ----------------------------------------------------------------- Provider

/// منبعِ فعلیِ داده‌ی شبکه.
///
/// ترتیبِ انتخاب: libbox (اگر در دسترس) → Clash API (اگر sing-box متصل است)
/// → هیچ‌کدام.
final networkSourceProvider = Provider<NetworkSource>((ref) {
  final libbox = ref.watch(libboxServiceProvider);
  if (libbox.available) return LibboxNetworkSource(libbox);

  final engine = ref.watch(engineProvider);
  if (engine.status != ConnectionState2.connected) {
    return const UnavailableNetworkSource(NetworkUnavailableReason.coreStopped);
  }
  if (engine.core != CoreType.singbox) {
    return const UnavailableNetworkSource(NetworkUnavailableReason.xray);
  }

  final port = ref.watch(settingsProvider).singboxApiPort;
  return ClashNetworkSource(ClashApi(port: port));
});
