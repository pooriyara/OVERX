import 'traffic.dart';

/// یک خروجی (outbound) درونِ یک گروه.
class OutboundItem {
  const OutboundItem({
    required this.tag,
    required this.type,
    this.urlTestDelay = 0,
    this.urlTestTime = 0,
  });

  final String tag;
  final String type;

  /// تأخیرِ آخرین تستِ URL به **میلی‌ثانیه**؛ صفر یعنی هنوز تست نشده.
  final int urlTestDelay;

  /// زمانِ آخرین تست (میلی‌ثانیه از epoch)؛ صفر یعنی هرگز.
  final int urlTestTime;

  /// آیا تاکنون تست شده؟ (تأخیرِ صفر می‌تواند به معنای «تست نشده» باشد)
  bool get tested => urlTestTime != 0;

  /// متنِ تأخیر برای نمایش؛ «—» اگر تست نشده باشد.
  String get delayText => tested ? '${urlTestDelay} ms' : '—';

  factory OutboundItem.fromJson(Map<Object?, Object?> j) => OutboundItem(
        tag: j['tag'] as String? ?? '',
        type: j['type'] as String? ?? '',
        urlTestDelay: _asInt(j['urlTestDelay']),
        urlTestTime: _asInt(j['urlTestTime']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tag': tag,
        'type': type,
        'urlTestDelay': urlTestDelay,
        'urlTestTime': urlTestTime,
      };

  @override
  String toString() => 'OutboundItem($tag, $type, ${delayText})';
}

/// یک گروه خروجی (مانند `selector` یا `urltest`).
///
/// چرا جدا از [OutboundItem] است؟ چون فقط گروه‌ها «انتخاب‌پذیر» ند؛ بقیه‌ی
/// خروجی‌ها را کاربر نمی‌تواند عوض کند.
class OutboundGroup {
  const OutboundGroup({
    required this.tag,
    required this.type,
    required this.items,
    this.selectable = false,
    this.selected = '',
    this.isExpand = false,
  });

  final String tag;
  final String type;

  /// آیا کاربر می‌تواند خروجیِ این گروه را عوض کند؟
  final bool selectable;

  /// تگِ خروجیِ انتخاب‌شده (فقط برای گروه‌های [selectable]).
  final String selected;

  /// آیا گروه در رابط باز است؟ (sing-box این را برای urltest هم می‌فرستد)
  final bool isExpand;

  final List<OutboundItem> items;

  /// ایتمِ انتخاب‌شده، اگر در فهرست باشد.
  OutboundItem? get selectedItem {
    for (final item in items) {
      if (item.tag == selected) return item;
    }
    return null;
  }

  factory OutboundGroup.fromJson(Map<Object?, Object?> j) => OutboundGroup(
        tag: j['tag'] as String? ?? '',
        type: j['type'] as String? ?? '',
        selectable: j['selectable'] as bool? ?? false,
        selected: j['selected'] as String? ?? '',
        isExpand: j['isExpand'] as bool? ?? false,
        items: (j['items'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(OutboundItem.fromJson)
            .where((i) => i.tag.isNotEmpty)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tag': tag,
        'type': type,
        'selectable': selectable,
        'selected': selected,
        'isExpand': isExpand,
        'items': items.map((i) => i.toJson()).toList(growable: false),
      };

  @override
  String toString() => 'OutboundGroup($tag, $type, ${items.length} items)';
}

/// یک اتصالِ زنده (یا تازه‌بسته‌شده) گزارش‌شده از هسته.
class ConnectionEntry {
  const ConnectionEntry({
    required this.id,
    required this.outbound,
    required this.protocol,
    required this.network,
    required this.destination,
    required this.domain,
    required this.source,
    required this.uplinkTotal,
    required this.downlinkTotal,
    required this.createdAt,
    required this.closedAt,
    this.processPath = '',
  });

  final String id;
  final String outbound;
  final String protocol;
  final String network;
  final String destination;
  final String domain;
  final String source;

  /// بایت‌های فرستاده‌شده (تجمعی).
  final int uplinkTotal;

  /// بایت‌های دریافت‌شده (تجمعی).
  final int downlinkTotal;

  /// زمانِ آغاز (میلی‌ثانیه از epoch).
  final int createdAt;

  /// زمانِ بسته‌شدن؛ صفر یعنی هنوز باز است.
  final int closedAt;

  /// مسیرِ فرآیندِ مبدأ — فقط وقتی هسته دسترسی داشته باشد (اندروید/لینوکس).
  final String processPath;

  bool get isClosed => closedAt != 0;

  /// مقصد برای نمایش: دامنه اگر هست، وگرنه آدرسِ خام.
  String get displayDestination => domain.isNotEmpty ? domain : destination;

  /// کلِ ترافیکِ این اتصال، قالب‌بندی‌شده.
  String get totalText {
    final total = uplinkTotal + downlinkTotal;
    if (total <= 0 && uplinkTotal == 0 && downlinkTotal == 0) return '—';
    return formatBytes(total);
  }

  factory ConnectionEntry.fromJson(Map<Object?, Object?> j) => ConnectionEntry(
        id: j['id'] as String? ?? '',
        outbound: j['outbound'] as String? ?? '',
        protocol: j['protocol'] as String? ?? '',
        network: j['network'] as String? ?? '',
        destination: j['destination'] as String? ?? '',
        domain: j['domain'] as String? ?? '',
        source: j['source'] as String? ?? '',
        uplinkTotal: _asInt(j['uplinkTotal']),
        downlinkTotal: _asInt(j['downlinkTotal']),
        createdAt: _asInt(j['createdAt']),
        closedAt: _asInt(j['closedAt']),
        processPath: j['processPath'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'outbound': outbound,
        'protocol': protocol,
        'network': network,
        'destination': destination,
        'domain': domain,
        'source': source,
        'uplinkTotal': uplinkTotal,
        'downlinkTotal': downlinkTotal,
        'createdAt': createdAt,
        'closedAt': closedAt,
        'processPath': processPath,
      };

  @override
  String toString() => 'ConnectionEntry($id, $displayDestination, $outbound)';
}

/// عددِ صحیح از یک مقدارِ کانال — اندروید ممکن است Int یا Int64 بفرستد.
int _asInt(Object? value) => switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
