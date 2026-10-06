import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/models/network.dart';
import 'package:overx/core/models/settings.dart' show LogLevel;

/// وضعیت سرویس libbox.
enum LibboxStatus {
  /// روی این پلتفرم اصلاً در دسترس نیست (همه‌چیز جز اندروید).
  unavailable,

  stopped,
  starting,

  started,
  stopping,
  error,
}

/// خطای سرویس libbox.
class LibboxException implements Exception {
  const LibboxException(this.message);

  final String message;

  @override
  String toString() => 'LibboxException: $message';
}

/// یک خطِ لاگِ رسیده از هسته، همراه با سطحش.
class LibboxLogLine {
  const LibboxLogLine({required this.level, required this.message});

  final LogLevel level;
  final String message;

  @override
  String toString() => '${level.name}: $message';
}

/// تبدیلِ سطحِ لاگِ sing-box به [LogLevel] ی برنامه.
///
/// مقادیر از `log/level.go` ی sing-box (نوعِ `Level = uint8`) و **برعکسِ
/// ترتیبی است که از روی نام حدس می‌زنید**:
///
/// | مقدار | معنا    | نگاشت در برنامه |
/// |---|---|---|
/// | ۰ | panic | error |
/// | ۱ | fatal | error |
/// | ۲ | error | error |
/// | ۳ | warn  | warning |
/// | ۴ | info  | info |
/// | ۵ | debug | debug |
/// | ۶ | trace | debug |
///
/// مقدارِ نامعلوم (یا `null`) در سطحِ info می‌آید تا چیزی گم نشود.
LogLevel libboxLevelToLogLevel(int? level) => switch (level) {
      0 || 1 || 2 => LogLevel.error,
      3 => LogLevel.warning,
      4 => LogLevel.info,
      5 || 6 => LogLevel.debug,
      _ => LogLevel.info,
    };

/// مدیریتِ هسته‌ی sing-box وقتی به صورت **کتابخانه‌ی بومی** اجرا می‌شود.
///
/// چرا این جداست؟
/// روی اندروید، باینری CLI هسته‌ی sing-box نمی‌تواند اینترفیس TUN را بسازد.
/// تنها راهِ درست، استفاده از `libbox` است — همان کاری که sing-box for Android
/// می‌کند. در این حالت ترتیب برعکس می‌شود: **خودِ کتابخانه با صدا زدن
/// `openTun(options)` از ما می‌خواهد اینترفیس را بسازیم و fd آن را برگردانیم.**
///
/// برای Xray نیازی به این نیست (fd را از متغیر محیطی `XRAY_TUN_FD` می‌گیرد).
abstract class LibboxService {
  /// آیا این پلتفرم libbox را دارد؟
  bool get available;

  LibboxStatus get status;

  /// پیام آخرین خطا (اگر [status] برابر [LibboxStatus.error] باشد).
  String? get lastError;

  /// خطوط لاگِ ارسالی از سمت بومی — **همراه با سطح**.
  Stream<LibboxLogLine> get logs;

  /// وقتی هسته لاگ‌هایش را پاک می‌کند (معمولاً بعد از بارگذاریِ دوباره‌ی
  /// کانفیگ). شنونده باید فهرستِ لاگِ نمایش‌داده‌شده را خالی کند.
  Stream<void> get logsCleared;

  /// گروه‌های خروجی (selector / urltest و غیره).
  ///
  /// فقط وقتی هسته از طریق libbox اجرا می‌شود معنا دارد؛ روی بقیه‌ی سکوها
  /// فهرستِ خالی برمی‌گردد.
  Future<List<OutboundGroup>> getGroups();

  /// اتصال‌های جاری (و تازه‌بسته‌شده) ی هسته.
  Future<List<ConnectionEntry>> getConnections();

  /// انتخابِ یک خروجی در یک گروهِ انتخاب‌پذیر.
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  });

  /// اندازه‌گیریِ تأخیرِ یک خروجی (URL test).
  Future<void> urlTest(String outboundTag);

  /// بستنِ یک اتصال.
  Future<void> closeConnection(String id);

  /// بستنِ همه‌ی اتصال‌ها.
  Future<void> closeConnections();

  /// اجرای هسته با کانفیگ داده‌شده.
  ///
  /// [includePackages] / [excludePackages] برای مسیریابیِ هر برنامه
  /// (per-app proxy) اندروید هستند.
  Future<void> start({
    required String config,
    List<String> includePackages = const <String>[],
    List<String> excludePackages = const <String>[],
  });

  Future<void> stop();
}

/// پیاده‌سازیِ پیش‌فرض برای پلتفرم‌هایی که libbox ندارند.
class UnavailableLibboxService implements LibboxService {
  const UnavailableLibboxService();

  @override
  bool get available => false;

  @override
  String? get lastError => 'libbox is only available on Android';

  @override
  Stream<LibboxLogLine> get logs => const Stream<LibboxLogLine>.empty();

  @override
  Stream<void> get logsCleared => const Stream<void>.empty();

  @override
  Future<List<OutboundGroup>> getGroups() async => const <OutboundGroup>[];

  @override
  Future<List<ConnectionEntry>> getConnections() async =>
      const <ConnectionEntry>[];

  @override
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) async {
    throw const LibboxException('libbox is not available on this platform');
  }

  @override
  Future<void> urlTest(String outboundTag) async {
    throw const LibboxException('libbox is not available on this platform');
  }

  @override
  Future<void> closeConnection(String id) async {
    throw const LibboxException('libbox is not available on this platform');
  }

  @override
  Future<void> closeConnections() async {
    throw const LibboxException('libbox is not available on this platform');
  }

  @override
  LibboxStatus get status => LibboxStatus.unavailable;

  @override
  Future<void> start({
    required String config,
    List<String> includePackages = const <String>[],
    List<String> excludePackages = const <String>[],
  }) async {
    throw const LibboxException('libbox is not available on this platform');
  }

  @override
  Future<void> stop() async {}
}

/// پیاده‌سازیِ اندروید با `MethodChannel('com.overx/libbox')`.
///
/// سمت کاتلین (`LibboxVpnService`) این فراخوانی‌ها را دریافت می‌کند:
///   Dart → `start` / `stop`
///   Kotlin → `onLog` / `onStatus`
class MethodChannelLibboxService implements LibboxService {
  MethodChannelLibboxService({
    MethodChannel? channel,
    StreamController<LibboxLogLine>? logs,
    StreamController<void>? logsCleared,

    /// مقدار پیش‌فرض برای [available] تا زمانی که [probe] جواب بدهد.
    /// روی اندروید true است چون کتابخانه همراه برنامه است.
    this.defaultAvailable = false,
  })  : _channel = channel ?? const MethodChannel('com.overx/libbox'),
        _logs = logs ?? StreamController<LibboxLogLine>.broadcast(),
        _logsCleared = logsCleared ?? StreamController<void>.broadcast() {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<LibboxLogLine> _logs;
  final StreamController<void> _logsCleared;
  final bool defaultAvailable;

  LibboxStatus _status = LibboxStatus.stopped;
  String? _lastError;
  bool? _availableCache;

  @override
  bool get available => _availableCache ?? defaultAvailable;

  /// باید پیش از استفاده صدا زده شود تا دسترسی‌بودن مشخص گردد.
  Future<bool> probe() async {
    final result = await _channel.invokeMethod<bool>('available');
    _availableCache = result ?? false;
    return _availableCache!;
  }

  @override
  LibboxStatus get status => _status;

  @override
  String? get lastError => _lastError;

  @override
  Stream<LibboxLogLine> get logs => _logs.stream;

  @override
  Stream<void> get logsCleared => _logsCleared.stream;

  @override
  Future<void> start({
    required String config,
    List<String> includePackages = const <String>[],
    List<String> excludePackages = const <String>[],
  }) async {
    _status = LibboxStatus.starting;
    _lastError = null;
    try {
      final ok = await _channel.invokeMethod<bool>('start', <String, Object?>{
        'config': config,
        'includePackages': includePackages,
        'excludePackages': excludePackages,
      });
      if (ok != true) {
        _status = LibboxStatus.error;
        throw LibboxException(_lastError ?? 'libbox failed to start');
      }
      _status = LibboxStatus.started;
    } on PlatformException catch (e) {
      _status = LibboxStatus.error;
      _lastError = e.message ?? e.code;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _status = LibboxStatus.stopping;
    try {
      await _channel.invokeMethod<void>('stop');
    } finally {
      _status = LibboxStatus.stopped;
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onLog':
        _onLog(call.arguments);
        return null;
      case 'onLogsCleared':
        if (!_logsCleared.isClosed) _logsCleared.add(null);
        return null;
      case 'onStatus':
        final args = call.arguments as Map<Object?, Object?>? ?? {};
        final name = args['status'] as String?;
        _status = _parseStatus(name);
        if (args['error'] is String) _lastError = args['error'] as String;
        return null;
      default:
        return null;
    }
  }

  /// دو شکلِ پیام را می‌پذیریم: نقشه‌ی `{level, message}` (جدید) و رشته‌ی
  /// ساده (سازگاری با پیام‌هایی که سطح ندارند، مثلاً وضعیتِ خودِ سرویس).
  void _onLog(Object? arguments) {
    if (_logs.isClosed) return;
    if (arguments is Map<Object?, Object?>) {
      final message = arguments['message'] as String?;
      if (message == null) return;
      final rawLevel = arguments['level'];
      _logs.add(
        LibboxLogLine(
          level: libboxLevelToLogLevel(rawLevel is int ? rawLevel : null),
          message: message,
        ),
      );
      return;
    }
    if (arguments is String) {
      _logs.add(LibboxLogLine(level: LogLevel.info, message: arguments));
    }
  }

  @override
  Future<List<OutboundGroup>> getGroups() async =>
      decodeGroups(await _channel.invokeMethod<List<Object?>>('getGroups'));

  @override
  Future<List<ConnectionEntry>> getConnections() async => decodeConnections(
        await _channel.invokeMethod<List<Object?>>('getConnections'),
      );

  @override
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) async {
    await _channel.invokeMethod<void>(
      'selectOutbound',
      <String, Object?>{'groupTag': groupTag, 'outboundTag': outboundTag},
    );
  }

  @override
  Future<void> urlTest(String outboundTag) async {
    await _channel.invokeMethod<void>(
      'urlTest',
      <String, Object?>{'outboundTag': outboundTag},
    );
  }

  @override
  Future<void> closeConnection(String id) async {
    await _channel.invokeMethod<void>(
      'closeConnection',
      <String, Object?>{'id': id},
    );
  }

  @override
  Future<void> closeConnections() async {
    await _channel.invokeMethod<void>('closeConnections');
  }

  static LibboxStatus _parseStatus(String? name) => switch (name) {
        'starting' => LibboxStatus.starting,
        'started' => LibboxStatus.started,
        'stopping' => LibboxStatus.stopping,
        'stopped' => LibboxStatus.stopped,
        'error' => LibboxStatus.error,
        'unavailable' => LibboxStatus.unavailable,
        _ => LibboxStatus.stopped,
      };

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _logs.close();
    await _logsCleared.close();
  }
}

/// تبدیلِ پاسخِ خامِ `getGroups` به مدل.
///
/// خطاهای جزئی (مثل نبودِ کلید) را می‌بلعد تا یک فیلدِ بد کلِ فهرست را
/// خراب نکند.
List<OutboundGroup> decodeGroups(List<Object?>? raw) => (raw ?? const <Object?>[])
    .whereType<Map<Object?, Object?>>()
    .map(OutboundGroup.fromJson)
    .where((g) => g.tag.isNotEmpty)
    .toList(growable: false);

/// تبدیلِ پاسخِ خامِ `getConnections` به مدل.
List<ConnectionEntry> decodeConnections(List<Object?>? raw) =>
    (raw ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(ConnectionEntry.fromJson)
        .where((c) => c.id.isNotEmpty)
        .toList(growable: false);

/// سرویس libbox — باید در `main()` با پیاده‌سازیِ مناسب override شود.
final libboxServiceProvider = Provider<LibboxService>((ref) {
  throw UnimplementedError(
    'libboxServiceProvider must be overridden in main()',
  );
});
