import 'dart:io';

/// پینگِ واقعی: یک اتصالِ TCP واقعی به آدرس:پورت می‌گیرد و زمانِ دست‌دادن
/// (handshake) را به میلی‌ثانیه برمی‌گرداند. برخلافِ «تستِ تأخیر» گروه‌های
/// outbound، این معیار مستقل از هسته است و همیشه عددِ واقعی می‌دهد.
class LatencyTester {
  const LatencyTester._();

  /// میلی‌ثانیه، یا null اگر اتصال برقرار نشد.
  static Future<int?> tcpPing(
    String address,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      await socket?.close().catchError((_) => socket);
    }
  }
}
