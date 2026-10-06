import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_bridge.dart';

/// اندازه‌ی آیکونِ درخواستی از PackageManager (پیکسل).
///
/// ۶۴ برای کاشی‌های ۳۴dp کافی است (تراکمِ ۲x) و حجم هر PNG را
/// زیر ۴ کیلوبایت نگه می‌دارد.
const int kAppIconSize = 64;

/// کش و واکشیِ تدریجیِ آیکونِ برنامه‌ها.
///
/// آیکون‌ها همراهِ فهرستِ برنامه‌ها نمی‌آیند: با صد برنامه، چند مگابایت
/// باید از کانالِ متد رد می‌شد. در عوض هر کاشی هنگامِ نمایش، آیکونِ خودش را
/// درخواست می‌کند و نتیجه اینجا نگه داشته می‌شود.
///
/// روی دسکتاپ/وب [PlatformBridge.appIcon] همیشه `null` برمی‌گرداند؛ آن را
/// هم کش می‌کنیم تا برای هر برنامه فقط یک بار صدا زده شود.
class AppIconService extends ChangeNotifier {
  AppIconService(this._bridge);

  final PlatformBridge _bridge;

  final Map<String, Uint8List?> _cache = <String, Uint8List?>{};
  final Set<String> _inFlight = <String>{};

  /// آیکونِ آماده (بدون واکشی)؛ `null` یعنی هنوز نیامده یا اصلاً ندارد.
  Uint8List? peek(String packageName) => _cache[packageName];

  /// آیکون را (اگر لازم باشد) واکشی می‌کند و شنوندگان را آگاه می‌سازد.
  ///
  /// فراخوانیِ تکراری برای یک بسته در حالِ انجام، درخواستِ دومی نمی‌فرستد.
  Future<void> load(String packageName) async {
    if (_cache.containsKey(packageName) || _inFlight.contains(packageName)) {
      return;
    }
    _inFlight.add(packageName);
    Uint8List? bytes;
    try {
      bytes = await _bridge.appIcon(packageName, size: kAppIconSize);
    } catch (_) {
      bytes = null;
    }
    _inFlight.remove(packageName);
    _cache[packageName] = bytes;
    notifyListeners();
  }

  /// واکشیِ دسته‌جمعی — برای وقتی که کلِ فهرست روی صفحه است.
  Future<void> loadAll(Iterable<String> packageNames) async {
    for (final name in packageNames) {
      await load(name);
    }
  }

  /// کش را خالی می‌کند (مثلاً بعد از نصب/حذفِ یک برنامه).
  void clear() {
    _cache.clear();
    _inFlight.clear();
    notifyListeners();
  }
}

/// سرویسِ سراسریِ آیکونِ برنامه‌ها.
final appIconServiceProvider = ChangeNotifierProvider<AppIconService>((ref) {
  return AppIconService(ref.watch(platformBridgeProvider));
});
