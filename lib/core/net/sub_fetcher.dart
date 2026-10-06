import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// دریافتِ بدنه‌ی یک لینکِ اشتراک و نرمال‌سازیِ آن به متنِ حاوی لینک‌ها.
///
/// بسیاری از پنل‌ها بدنه را به‌صورت base64ِ یک فهرستِ خط‌به‌خط برمی‌گردانند؛
/// این تابع در صورت نیاز base64 را باز می‌کند و متنِ نهایی را می‌دهد.
class SubscriptionFetcher {
  const SubscriptionFetcher._();

  static const _ua =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Safari/537.36';

  /// بدنه‌ی خامِ اشتراک. خطاها را به‌صورت [SubscriptionFetchException] می‌اندازد.
  static Future<String> fetchBody(String url) async {
    final uri = Uri.parse(url.trim());
    if (!uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const SubscriptionFetchException('لینک اشتراک معتبر نیست');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = _ua;
    try {
      final req = await client.getUrl(uri);
      req.headers.set('Accept', '*/*');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) {
        throw SubscriptionFetchException('HTTP ${res.statusCode}');
      }
      final bytes = await res
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          .timeout(const Duration(seconds: 20));
      return decodeBody(bytes);
    } on SubscriptionFetchException {
      rethrow;
    } on SocketException catch (e) {
      throw SubscriptionFetchException('خطای شبکه: ${e.message}');
    } on TimeoutException {
      throw const SubscriptionFetchException('زمانِ درخواست تمام شد');
    } catch (e) {
      throw SubscriptionFetchException('خطا در دریافت اشتراک: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// بدنه‌ی بایتی را به متنِ لینک‌ها تبدیل می‌کند (با بازکردنِ base64 در صورت نیاز).
  static String decodeBody(List<int> bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true).trim();
    // اگر همین حالا حاوی لینک است، همان را برگردان.
    if (raw.contains('://')) return raw;
    // وگرنه base64 فرض کن.
    try {
      final normalized = raw.replaceAll('\n', '').replaceAll('\r', '');
      final decoded = utf8.decode(base64.decode(normalized),
          allowMalformed: true);
      if (decoded.contains('://')) return decoded;
    } catch (_) {}
    // وگرنه شاید base64-url-safe باشد.
    try {
      final decoded = utf8.decode(base64Url.decode(raw), allowMalformed: true);
      if (decoded.contains('://')) return decoded;
    } catch (_) {}
    return raw;
  }
}

class SubscriptionFetchException implements Exception {
  const SubscriptionFetchException(this.message);
  final String message;
  @override
  String toString() => message;
}
