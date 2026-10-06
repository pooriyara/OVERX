import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overx/core/models/app_package.dart';

// پیاده‌سازی‌ها را هم export می‌کنیم تا مصرف‌کننده فقط یک فایل را import کند
import 'android_bridge.dart';
import 'desktop_bridge.dart';
import 'stub_bridge.dart';

export 'android_bridge.dart' show AndroidBridge;
export 'desktop_bridge.dart' show DesktopBridge;
export 'stub_bridge.dart' show StubBridge;

/// قابلیت‌هایی که پلتفرمِ میزبان به ما می‌دهد.
enum PlatformFeature {
  /// می‌توان فهرست برنامه‌های نصب‌شده را گرفت و مسیریابی را محدود کرد
  /// (اندروید + libbox).
  perAppProxy,

  /// می‌توان یک اینترفیس TUN ساخت و fd آن را گرفت (اندروید VpnService).
  tunFd,

  /// می‌توان پروکسیِ کل سیستم را تغییر داد (دسکتاپ‌ها).
  systemProxy,

  /// می‌توان برنامه را در شروع سیستم اجرا کرد.
  autoStart,

  /// پلتفرم سرویس VPN دارد (اندروید).
  vpnService,
}

/// مجموعه‌ی قابلیت‌ها.
class PlatformFeatures {
  const PlatformFeatures(this.items);

  final Set<PlatformFeature> items;

  bool has(PlatformFeature f) => items.contains(f);

  static const none = PlatformFeatures(<PlatformFeature>{});
}

/// دسته‌ی TUNی که از پلتفرم گرفته‌ایم.
class TunHandle {
  const TunHandle({
    required this.fd,
    required this.mtu,
    this.interfaceName = 'tun0',
  });

  /// فایل‌دسکریپتور اینترفیس.
  final int fd;

  final int mtu;
  final String interfaceName;

  /// متغیرهای محیطی‌ای که باید به فرآیند هسته داده شوند.
  ///
  /// Xray-core روی اندروید/آی‌او‌اس fd را از `XRAY_TUN_FD` می‌خواند:
  /// https://xtls.github.io/en/config/inbounds/tun.html
  Map<String, String> get env => {
        'XRAY_TUN_FD': '$fd',
        'XRAY_TUN_MTU': '$mtu',
      };

  @override
  String toString() => 'TunHandle(fd: $fd, mtu: $mtu, iface: $interfaceName)';
}

/// قراردادِ بین برنامه و سیستم‌عامل.
///
/// سه پیاده‌سازی دارد: اندروید (MethodChannel)، دسکتاپ (دستورات سیستم)
/// و یک پیاده‌سازی ساختگی برای تست‌ها.
abstract class PlatformBridge {
  PlatformFeatures get features;

  /// آماده‌سازی پیش از اجرا — روی اندروید مجوز VPN را می‌گیرد.
  /// برگشتِ false یعنی کاربر رد کرده (یا پلتفرم پشتیبانی نمی‌کند).
  Future<bool> prepare();

  /// گرفتن fd اینترفیس TUN. اگر ممکن نباشد null برمی‌گرداند.
  Future<TunHandle?> acquireTun({int mtu = 9000});

  Future<void> releaseTun();

  /// تنظیم پروکسیِ کل سیستم (دسکتاپ).
  Future<bool> setSystemProxy({required String host, required int port});

  Future<bool> clearSystemProxy();

  Future<bool> setAutoStart(bool enable);

  Future<bool> isAutoStartEnabled();

  /// پوشه‌ی کتابخانه‌های بومی — برای پیدا کردن باینری هسته روی اندروید.
  Future<String?> nativeLibraryDir();

  /// فهرست برنامه‌های نصب‌شده (برای مسیریابیِ هر برنامه).
  ///
  /// پیاده‌سازیِ پیش‌فرض لیستِ تهی برمی‌گرداند؛ فقط اندروید آن را بازنویسی
  /// می‌کند.
  /// آیکونِ یک برنامه به صورت PNG.
  ///
  /// فقط اندروید مقدار برمی‌گرداند؛ بقیه‌ی سکوها `null`. چون حجمِ هر آیکون
  /// چند کیلوبایت است، همراهِ [listInstalledPackages] فرستاده نمی‌شود و باید
  /// یکی‌یکی و هنگامِ نیاز گرفته شود (نگاه کن به `AppIconService`).
  Future<Uint8List?> appIcon(String packageName, {int size = 64}) async => null;

  Future<List<AppPackage>> listInstalledPackages({
    bool includeSystem = false,
  }) async =>
      const <AppPackage>[];

  /// باینری‌هایی که همراه برنامه آمده و آماده‌ی اجرا شده‌اند.
  ///
  /// روی اندروید فایل‌های `.so` همراه APK غیرقابل‌اجرا هستند و باید کپی و
  /// `chmod +x` شوند. خروجی: نگاشتِ نام هسته (مانند `xray`) به مسیر آماده.
  /// پیاده‌سازیِ پیش‌فرض نگاشتِ تهی برمی‌گرداند (یعنی کاری لازم نیست).
  Future<Map<String, String>> installedBinaries() async => const <String, String>{};

  /// پیامِ آخرین خطا (برای نمایش در لاگ/UI).
  String? get lastError;

  Future<void> dispose();
}

/// Provider سراسری — در main با پیاده‌سازی مناسب override می‌شود.
final platformBridgeProvider = Provider<PlatformBridge>((ref) {
  throw UnimplementedError(
    'platformBridgeProvider must be overridden in main()',
  );
});

/// انتخاب پیاده‌سازی بر اساس پلتفرم.
PlatformBridge createPlatformBridge() {
  if (Platform.isAndroid) return AndroidBridge();
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    return DesktopBridge();
  }
  return StubBridge();
}
