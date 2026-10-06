import 'dart:typed_data';

import 'package:overx/core/models/app_package.dart';

import 'platform_bridge.dart';

/// پیاده‌سازیِ بی‌اثر برای پلتفرم‌های پشتیبانی‌نشده (مثل وب).
class StubBridge implements PlatformBridge {
  @override
  final PlatformFeatures features = PlatformFeatures.none;

  @override
  String? lastError;

  @override
  Future<bool> prepare() async => true;

  @override
  Future<TunHandle?> acquireTun({int mtu = 9000}) async => null;

  @override
  Future<void> releaseTun() async {}

  @override
  Future<bool> setSystemProxy({required String host, required int port}) async =>
      false;

  @override
  Future<bool> clearSystemProxy() async => false;

  @override
  Future<bool> setAutoStart(bool enable) async => false;

  @override
  Future<bool> isAutoStartEnabled() async => false;

  @override
  Future<String?> nativeLibraryDir() async => null;

  @override
  Future<Uint8List?> appIcon(String packageName, {int size = 64}) async => null;

  @override
  Future<List<AppPackage>> listInstalledPackages({
    bool includeSystem = false,
  }) async =>
      const <AppPackage>[];

  @override
  Future<Map<String, String>> installedBinaries() async => const <String, String>{};


  @override
  Future<void> dispose() async {}
}
