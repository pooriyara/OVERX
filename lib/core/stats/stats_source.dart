import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:overx/core/models/traffic.dart';

/// قراردادِ مشترک برای خواندن آمار از هر هسته.
abstract class StatsSource {
  StatsSource({required this.interval});

  /// فاصله‌ی نمونه‌برداری (برای منابعِ polling).
  final Duration interval;

  final _controller = StreamController<TrafficSample>.broadcast();
  Timer? _clock;
  bool _running = false;

  /// جریان نمونه‌های ترافیک.
  Stream<TrafficSample> get stream => _controller.stream;

  bool get isRunning => _running;

  /// شروعِ جمع‌آوری.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await onStart();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _clock?.cancel();
    _clock = null;
    await onStop();
    if (!_controller.isClosed) {
      _controller.add(TrafficSample.zero);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  /// پیاده‌سازی‌ها این را پر می‌کنند.
  Future<void> onStart();

  Future<void> onStop();

  /// ارسال یک نمونه به UI.
  void emit(TrafficSample s) {
    if (!_controller.isClosed) _controller.add(s);
  }

  /// شروعِ یک ساعتِ داخلی که [sample] را صدا می‌زند.
  void startClock(TrafficSample Function() sample) {
    _clock?.cancel();
    _clock = Timer.periodic(interval, (_) => emit(sample()));
  }
}

/// محاسبه‌گر سرعت بر اساس اختلافِ مجموع‌ها.
class SpeedMeter {
  SpeedMeter(this.startedAt);

  final DateTime startedAt;
  int _lastUp = 0;
  int _lastDown = 0;
  DateTime _lastAt = DateTime.now();
  int _upSpeed = 0;
  int _downSpeed = 0;

  TrafficSample update(int totalUp, int totalDown) {
    final now = DateTime.now();
    final dt = now.difference(_lastAt).inMilliseconds;

    if (dt >= 400) {
      final up = totalUp - _lastUp;
      final down = totalDown - _lastDown;
      // میانگینِ نمایی برای نرم‌تر شدن نمودار
      final alpha = 0.4;
      _upSpeed = (_upSpeed + (up * 1000 / dt - _upSpeed) * alpha).round();
      _downSpeed = (_downSpeed + (down * 1000 / dt - _downSpeed) * alpha).round();
      _lastUp = totalUp;
      _lastDown = totalDown;
      _lastAt = now;
    }

    return TrafficSample(
      uplinkTotal: totalUp,
      downlinkTotal: totalDown,
      uplinkSpeed: _upSpeed < 0 ? 0 : _upSpeed,
      downlinkSpeed: _downSpeed < 0 ? 0 : _downSpeed,
      at: now.difference(startedAt),
    );
  }
}

// ============================================================================
// sing-box — Clash-compatible API
// ============================================================================

/// آمار لحظه‌ای sing-box از طریق Clash API.
///
/// نیاز در کانفیگ:
/// ```json
/// "experimental": { "clash_api": { "external_controller": "127.0.0.1:9090" } }
/// ```
/// سپس WebSocket به `ws://127.0.0.1:9090/traffic` وصل می‌شود و پیام‌هایی
/// مثل `{"up":12345,"down":67890}` می‌فرستد.
class SingBoxClashStats extends StatsSource {
  SingBoxClashStats({
    required this.port,
    super.interval = const Duration(seconds: 1),
  });

  final int port;

  WebSocket? _socket;
  SpeedMeter? _meter;
  int _retries = 0;
  Timer? _retry;
  Timer? _ticker;

  @override
  Future<void> onStart() async {
    _meter = SpeedMeter(DateTime.now());
    _retries = 0;
    _connect();
  }

  Future<void> _connect() async {
    if (!isRunning) return;
    try {
      final socket =
          await WebSocket.connect('ws://127.0.0.1:$port/traffic');
      _socket = socket;
      _retries = 0;

      socket.listen(
        (dynamic data) {
          if (!isRunning) return;
          try {
            final j = jsonDecode(data as String) as Map<String, dynamic>;
            final up = (j['up'] as num?)?.toInt() ?? 0;
            final down = (j['down'] as num?)?.toInt() ?? 0;
            // sing-box مقدار را به صورت تجمعی می‌فرستد
            emit(_meter!.update(up, down));
          } catch (_) {}
        },
        onDone: () {
          if (isRunning) _scheduleReconnect();
        },
        onError: (_) {
          if (isRunning) _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (isRunning) _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_retries > 12) return;
    final delay = Duration(milliseconds: 300 * (1 << _retries).clamp(1, 32));
    _retries++;
    _retry?.cancel();
    _retry = Timer(delay, _connect);
  }

  @override
  Future<void> onStop() async {
    _retry?.cancel();
    _ticker?.cancel();
    _retry = null;
    _ticker = null;
    await _socket?.close();
    _socket = null;
  }
}

// ============================================================================
// Xray — StatsService از طریق زیرفرمان `xray api statsquery`
// ============================================================================

/// آمار Xray.
///
/// نیاز در کانفیگ:
/// ```json
/// "stats": {},
/// "api": { "tag":"api", "listen":"127.0.0.1:8080", "services":["StatsService"] },
/// "policy": { "system": { "statsInboundUplink":true, "statsInboundDownlink":true,
///                         "statsOutboundUplink":true, "statsOutboundDownlink":true } }
/// ```
/// و یک outbound با تگ `api` + قانون مسیریابی مربوطه.
///
/// خروجیِ دستور چیزی شبیه این است:
/// ```json
/// {"stat":[{"name":"outbound>>>proxy>>>traffic>>>uplink","value":12345}]}
/// ```
class XrayCliStats extends StatsSource {
  XrayCliStats({
    required this.binaryPath,
    required this.port,
    this.outboundTag = 'proxy',
    super.interval = const Duration(seconds: 1),
  });

  final String binaryPath;
  final int port;

  /// تگِ outboundای که ترافیک کاربر از آن رد می‌شود.
  final String outboundTag;

  SpeedMeter? _meter;
  Timer? _poll;

  @override
  Future<void> onStart() async {
    _meter = SpeedMeter(DateTime.now());
    _poll?.cancel();
    _poll = Timer.periodic(interval, (_) => unawaited(_pollOnce()));
    await _pollOnce();
  }

  Future<void> _pollOnce() async {
    if (!isRunning) return;
    try {
      final r = await Process.run(
        binaryPath,
        ['api', 'statsquery', '--server=127.0.0.1:$port', '-pattern', ''],
        runInShell: false,
      ).timeout(const Duration(seconds: 4));

      final out = (r.stdout as String?)?.trim() ?? '';
      if (out.isEmpty || out == '{}') return;

      final j = jsonDecode(out) as Map<String, dynamic>;
      final stats = (j['stat'] as List<dynamic>? ?? const []);

      var up = 0;
      var down = 0;
      for (final raw in stats) {
        final s = raw as Map<String, dynamic>;
        final name = '${s['name']}';
        final value = (s['value'] as num?)?.toInt() ?? 0;
        if (name.contains('>>>uplink')) up += value;
        if (name.contains('>>>downlink')) down += value;
      }

      emit(_meter!.update(up, down));
    } catch (_) {
      // هسته هنوز بالا نیامده یا پاسخ نمی‌دهد — نمونه‌ی بعدی تلاش می‌کند
    }
  }

  @override
  Future<void> onStop() async {
    _poll?.cancel();
    _poll = null;
  }
}
