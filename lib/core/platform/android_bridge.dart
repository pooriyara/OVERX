import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:overx/core/models/app_package.dart';

import 'platform_bridge.dart';

/// نام کانال و متدها — باید دقیقاً با سمت کاتلین (`MainActivity.kt`) یکی باشد.
const String kChannel = 'com.overx/core';

abstract class CoreMethods {
  static const prepare = 'prepareVpn';
  static const acquireTun = 'acquireTun';
  static const releaseTun = 'releaseTun';
  static const nativeLibraryDir = 'nativeLibraryDir';
  static const setAutoStart = 'setAutoStart';
  static const isAutoStart = 'isAutoStartEnabled';
  static const listPackages = 'listPackages';
  static const appIcon = 'appIcon';
  static const installBinaries = 'installBinaries';
}

/// پل ارتباطی با سمت اندروید.
///
/// سمت مقابل: `android/app/src/main/kotlin/com/overx/overx/`
///   - `MainActivity.kt`      → هندلر کانال
///   - `TunVpnService.kt`     → VpnService و ساخت اینترفیس TUN (Xray)
///   - `LibboxVpnService.kt`  → اجرای sing-box به صورت libbox
class AndroidBridge implements PlatformBridge {
  AndroidBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(kChannel);

  final MethodChannel _channel;

  @override
  final PlatformFeatures features = const PlatformFeatures(<PlatformFeature>{
    PlatformFeature.tunFd,
    PlatformFeature.vpnService,
    PlatformFeature.perAppProxy,
    PlatformFeature.autoStart,
    // اندروید اجازه‌ی تغییر پروکسی سیستم را به اپ‌های عادی نمی‌دهد؛
    // ترافیک از طریق VpnService هدایت می‌شود.
  });

  @override
  String? lastError;

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      lastError = '${e.code}: ${e.message}';
      return null;
    } on MissingPluginException catch (e) {
      lastError = e.message;
      return null;
    }
  }

  /// درخواست مجوز VPN از کاربر.
  /// خروجیِ null یعنی کاربر رد کرده یا خطا رخ داده.
  @override
  Future<bool> prepare() async {
    final r = await _invoke<bool>(CoreMethods.prepare);
    return r ?? false;
  }

  @override
  Future<TunHandle?> acquireTun({int mtu = 9000}) async {
    final r = await _invoke<Map<Object?, Object?>>(
      CoreMethods.acquireTun,
      <String, Object?>{'mtu': mtu},
    );
    if (r == null) return null;

    final fd = r['fd'];
    if (fd is! int) return null;

    return TunHandle(
      fd: fd,
      mtu: (r['mtu'] as num?)?.toInt() ?? mtu,
      interfaceName: r['interfaceName'] as String? ?? 'tun0',
    );
  }

  @override
  Future<void> releaseTun() => _invoke<void>(CoreMethods.releaseTun);

  @override
  Future<bool> setSystemProxy({required String host, required int port}) async =>
      false; // روی اندروید از VpnService استفاده می‌شود

  @override
  Future<bool> clearSystemProxy() async => false;

  @override
  Future<bool> setAutoStart(bool enable) async =>
      await _invoke<bool>(CoreMethods.setAutoStart, {'enable': enable}) ?? false;

  @override
  Future<bool> isAutoStartEnabled() async =>
      await _invoke<bool>(CoreMethods.isAutoStart) ?? false;

  @override
  Future<String?> nativeLibraryDir() =>
      _invoke<String>(CoreMethods.nativeLibraryDir);

  /// آیکونِ یک برنامه به صورت PNG (بایت‌های خام روی کانال).
  @override
  Future<Uint8List?> appIcon(String packageName, {int size = 64}) =>
      _invoke<Uint8List>(CoreMethods.appIcon, <String, Object?>{
        'packageName': packageName,
        'size': size,
      });

  @override
  Future<List<AppPackage>> listInstalledPackages({
    bool includeSystem = false,
  }) async {
    final raw = await _invoke<List<Object?>>(
      CoreMethods.listPackages,
      {'includeSystem': includeSystem},
    );
    if (raw == null) return const <AppPackage>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(AppPackage.fromJson)
        .where((p) => p.packageName.isNotEmpty)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  /// باینری‌های همراه برنامه را در حافظه‌ی داخلی executable می‌کند.
  ///
  /// APK فایل‌های `.so` را غیرقابل‌اجرا extract می‌کند، بنابراین باید ابتدا
  /// به `filesDir` کپی و `chmod +x` شوند. خروجی: مسیر فایل‌های آماده.
  @override
  Future<Map<String, String>> installedBinaries() async => installBinaries();

  Future<Map<String, String>> installBinaries() async {
    final raw = await _invoke<Map<Object?, Object?>>(CoreMethods.installBinaries);
    if (raw == null) return const <String, String>{};
    return raw.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  @override
  Future<void> dispose() async {}
}
