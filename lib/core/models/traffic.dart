/// یک نمونه‌ی لحظه‌ای از ترافیک.
class TrafficSample {
  const TrafficSample({
    required this.uplinkTotal,
    required this.downlinkTotal,
    required this.uplinkSpeed,
    required this.downlinkSpeed,
    required this.at,
  });

  static const zero = TrafficSample(
    uplinkTotal: 0,
    downlinkTotal: 0,
    uplinkSpeed: 0,
    downlinkSpeed: 0,
    at: Duration.zero,
  );

  /// مجموعِ آپلود از شروع نشست (بایت).
  final int uplinkTotal;

  /// مجموعِ دانلود از شروع نشست (بایت).
  final int downlinkTotal;

  final int uplinkSpeed; // B/s
  final int downlinkSpeed; // B/s

  /// زمانِ سپری‌شده از شروع نشست.
  final Duration at;

  @override
  String toString() =>
      '↑${_fmt(uplinkTotal)} (${_fmt(uplinkSpeed)}/s)  '
      '↓${_fmt(downlinkTotal)} (${_fmt(downlinkSpeed)}/s)';

  static String _fmt(int b) => formatBytes(b);
}

const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

/// تبدیل بایت به رشته‌ی خوانا.
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < _units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(v < 10 ? 2 : decimals);
  return '${s.replaceAll(RegExp(r'\.0+$'), '')} ${_units[i]}';
}

/// سرعت به رشته.
String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// مدت به صورت 00:00:00
String formatDuration(Duration d, {bool padHours = true}) {
  final h = d.inHours.remainder(24);
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return padHours ? '${h.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
}
