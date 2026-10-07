import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:overx/core/engine/core_type.dart';

/// دانلود و نصبِ خودکارِ باینریِ هسته روی دسکتاپ.
///
/// چرا؟ چون «بررسی» تا امروز فقط دنبالِ باینری می‌گشت و اگر نبود می‌گفت
/// «پیدا نشد». حالا در صورت نبودن، آخرین نسخه را از GitHub می‌گیرد و در
/// پوشه‌ی داده‌ی برنامه نصب می‌کند تا بررسی/اجرا کار کند.
class CoreInstaller {
  const CoreInstaller._();

  static bool get supported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  static String get _arch => _isArm() ? 'arm64' : 'amd64';

  static bool _isArm() {
    final env = Platform.environment['OVERX_ARCH'];
    return env == 'arm64' || env == 'aarch64';
  }

  static String get _singboxOs => Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
          ? 'darwin'
          : 'linux';

  static String get _xrayAsset {
    if (Platform.isWindows) return 'Xray-windows-64.zip';
    if (Platform.isMacOS) return 'Xray-macos-64.zip';
    return 'Xray-linux-64.zip';
  }

  /// اطلاعاتِ آخرین انتشار (نسخه + نشانی + حجم).
  ///
  /// با [includePrerelease] نسخه‌های بتا/پیش‌انتشار هم در نظر گرفته می‌شوند.
  static Future<CoreRelease> latestRelease(
    CoreType type, {
    bool includePrerelease = false,
  }) async {
    final repo = type == CoreType.singbox
        ? 'SagerNet/sing-box'
        : 'XTLS/Xray-core';
    final endpoint = includePrerelease
        ? 'https://api.github.com/repos/$repo/releases?per_page=1'
        : 'https://api.github.com/repos/$repo/releases/latest';
    final client = HttpClient()..userAgent = 'overx';
    try {
      final req = await client.getUrl(Uri.parse(endpoint));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      final json = decoded is List
          ? (decoded.first as Map<String, dynamic>)
          : (decoded as Map<String, dynamic>);
      final version = (json['tag_name'] as String?) ?? '';
      final assets = (json['assets'] as List).cast<Map<String, dynamic>>();
      for (final a in assets) {
        final name = a['name'] as String;
        final ok = type == CoreType.singbox
            ? (name.contains(_singboxOs) &&
                name.contains(_archForSingbox()) &&
                (name.endsWith('.tar.gz') || name.endsWith('.zip')))
            : (name == _xrayAsset);
        if (ok) {
          return CoreRelease(
            version: version,
            assetUrl: a['browser_download_url'] as String,
            sizeBytes: (a['size'] as num?)?.toInt() ?? 0,
          );
        }
      }
      throw const CoreInstallException('فایل مناسب برای این سیستم پیدا نشد');
    } finally {
      client.close(force: true);
    }
  }

  /// نشانیِ فایلِ انتشارِ آخرین نسخه برای هسته‌ی [type].
  static Future<String> latestAssetUrl(CoreType type) =>
      latestRelease(type).then((r) => r.assetUrl);

  static String _archForSingbox() =>
      _arch == 'arm64' ? 'arm64' : 'amd64';

  /// نصب و برگرداندنِ مسیرِ باینری.
  static Future<String> install(CoreType type, {CoreRelease? release}) async {
    if (!supported) {
      throw const CoreInstallException('نصب خودکار روی این سیستم پشتیبانی نمی‌شود');
    }
    final rel = release ?? await latestRelease(type);
    final url = rel.assetUrl;
    final support = await getApplicationSupportDirectory();
    final coreDir = Directory(p.join(support.path, 'core'))
      ..createSync(recursive: true);
    final tmp = Directory.systemTemp.createTempSync('overx-core');
    final fileExt = url.endsWith('.zip') ? '.zip' : '.tar.gz';
    final archive = File(p.join(tmp.path, 'dl$fileExt'));

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      await res.pipe(archive.openWrite());
    } finally {
      client.close(force: true);
    }

    // استخراج
    if (fileExt == '.zip') {
      if (Platform.isWindows) {
        await Process.run('powershell', [
          '-NoProfile', '-Command',
          'Expand-Archive', '-LiteralPath', archive.path,
          '-DestinationPath', tmp.path, '-Force',
        ]);
      } else {
        await Process.run('unzip', ['-o', '-q', archive.path, '-d', tmp.path]);
      }
    } else {
      await Process.run('tar', ['-xzf', archive.path, '-C', tmp.path]);
    }

    // پیدا کردن باینری
    final binName = type.binaryName;
    String? found;
    for (final f in tmp.listSync(recursive: true)) {
      if (f is File && p.basename(f.path) == binName) {
        found = f.path;
        break;
      }
    }
    if (found == null) {
      throw const CoreInstallException('باینری داخل بسته پیدا نشد');
    }

    final dest = File(p.join(coreDir.path, binName));
    File(found).copySync(dest.path);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', dest.path]);
    }
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
    return dest.path;
  }
}

/// اطلاعاتِ یک انتشار برای نمایش به کاربر پیش از دانلود.
class CoreRelease {
  const CoreRelease({
    required this.version,
    required this.assetUrl,
    required this.sizeBytes,
  });
  final String version;
  final String assetUrl;
  final int sizeBytes;

  String get sizeLabel {
    final mb = sizeBytes / 1024 / 1024;
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${sizeBytes ~/ 1024} KB';
  }
}

class CoreInstallException implements Exception {
  const CoreInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}
