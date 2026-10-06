import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:overx/core/engine/core_type.dart';

/// پیدا کردن باینریِ هسته روی سیستم.
///
/// ترتیب جستجو:
///  1) مسیرِ دستی کاربر (از تنظیمات)
///  2) پوشه‌ی core داخل پوشه‌ی داده‌ی برنامه
///  3) کنار فایل اجرایی برنامه
///  4) متغیر محیطی OVERX_<CORE>_PATH
///  5) PATH سیستم (which / where)
///  6) مسیرهای معمول لینوکس/مک
class BinaryLocator {
  const BinaryLocator._();

  /// مسیر کامل باینری، یا null اگر پیدا نشد.
  static Future<String?> locate(
    CoreType type, {
    String? overridePath,

    /// پوشه‌ی کتابخانه‌های بومی (اندروید) — از PlatformBridge می‌آید.
    String? nativeLibraryDir,
    bool probeVersion = true,
  }) async {
    final candidates = <String>[];

    // اندروید: هسته‌ها به صورت .so بسته‌بندی می‌شوند
    if (Platform.isAndroid && nativeLibraryDir != null) {
      candidates.add(p.join(nativeLibraryDir, androidLibName(type)));
    }

    if (overridePath != null && overridePath.isNotEmpty) {
      candidates.add(overridePath);
    }

    final env = Platform.environment['OVERX_${type.name.toUpperCase()}_PATH'];
    if (env != null && env.isNotEmpty) candidates.add(env);

    try {
      final support = await getApplicationSupportDirectory();
      candidates.add(p.join(support.path, 'core', type.binaryName));
    } catch (_) {}

    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      candidates.add(p.join(exeDir, type.binaryName));
      candidates.add(p.join(exeDir, 'core', type.binaryName));
      // حالتِ توسعه (flutter run)
      candidates.add(p.join(exeDir, '..', 'core', type.binaryName));
    } catch (_) {}

    if (!Platform.isWindows) {
      candidates.addAll([
        p.join('/usr/local/bin', type.binaryName),
        p.join('/usr/bin', type.binaryName),
        p.join('/opt', type.binaryName.toLowerCase(), type.binaryName),
        p.join('/opt/homebrew/bin', type.binaryName),
        p.join(
            Platform.environment['HOME'] ?? '', '.local', 'bin', type.binaryName),
      ]);
    }

    for (final path in candidates) {
      final f = File(path);
      if (await f.exists() && await _isExecutable(f)) {
        if (!probeVersion) return f.path;
        // یک اجرای سبک برای اطمینان از سالم بودن باینری
        final ok = await check(f.path, type);
        if (ok != null) return f.path;
      }
    }

    // PATH
    final which = Platform.isWindows ? 'where' : 'which';
    try {
      final r = await Process.run(which, [type.binaryName]);
      if (r.exitCode == 0) {
        final line = (r.stdout as String).trim().split('\n').first.trim();
        if (line.isNotEmpty && await File(line).exists()) return line;
      }
    } catch (_) {}

    return null;
  }

  /// نام کتابخانه‌ی بومی روی اندروید.
  static String androidLibName(CoreType type) =>
      'lib${type.name.toLowerCase()}.so';

  /// گرفتن نسخه: خروجیِ دستور version را برمی‌گرداند، یا null در صورت خطا.
  static Future<String?> check(String path, CoreType type) async {
    try {
      final r = await Process.run(
        path,
        type.versionArgs,
        runInShell: false,
      ).timeout(const Duration(seconds: 8));

      final out = '${r.stdout}${r.stderr}'.trim();
      if (out.isEmpty) return null;

      // sing-box: "sing-box version 1.12.0"
      // xray:     "Xray 25.3.6 (Xray, Penetrates Everything.) ..."
      final m = RegExp(
        r'(?:version\s+)?v?(\d+\.\d+(?:\.\d+)?(?:[-.\w]*)?)',
        caseSensitive: false,
      ).firstMatch(out.split('\n').first);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isExecutable(File f) async {
    try {
      if (Platform.isWindows) return true;
      final stat = await f.stat();
      // بررسی بیت اجرا برای کاربر جاری (ساده‌شده)
      return stat.mode & 0x49 != 0; // x برای owner یا other
    } catch (_) {
      return false;
    }
  }

  /// پوشه‌ای که کانفیگ و لاگ‌ها در آن نوشته می‌شوند.
  static Future<Directory> dataDirectory() async {
    try {
      final support = await getApplicationSupportDirectory();
      final d = Directory(p.join(support.path, 'run'));
      if (!await d.exists()) await d.create(recursive: true);
      return d;
    } catch (_) {
      final d = Directory(p.join(Directory.systemTemp.path, 'overx'));
      if (!await d.exists()) await d.create(recursive: true);
      return d;
    }
  }
}
