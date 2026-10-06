import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// این تست جایگزینِ «اجرا روی دستگاه واقعی» برای یک دسته از خطاهاست:
/// اینکه نامِ متدهای دو سمتِ کانال از هم جدا بیفتند.
///
/// اگر سمت کاتلین متدی را نشناسد، `result.notImplemented()` برمی‌گردد و سمت
/// دارت بی‌سروصدا `null` می‌گیرد — خطایی که در هیچ تستِ واحدی دیده نمی‌شود،
/// چون اصلاً دارت درگیر نمی‌شود. اینجا متنِ دو طرف را می‌خوانیم و مقایسه
/// می‌کنیم تا هرگونه جدا‌افتادگی همان لحظه شکست بخورد.
///
/// توجه: این تست عمداً متن را می‌خواند (تحلیلِ کد نه)؛ هدفش گرفتنِ ناهماهنگیِ
/// تصادفی است، نه اثباتِ صحت.

const _mainActivity =
    'android/app/src/main/kotlin/com/overx/overx/MainActivity.kt';
const _libboxChannel =
    'android/app/src/main/kotlin/com/overx/overx/LibboxChannel.kt';
const _androidBridge = 'lib/core/platform/android_bridge.dart';
const _libboxDart = 'lib/core/platform/libbox.dart';
const _coreCommandClient =
    'android/app/src/main/kotlin/com/overx/overx/CoreCommandClient.kt';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    // اگر تست از جای دیگری اجرا شده، با مسیرِ نسبت به بسته تلاش می‌کنیم
    final alt = File('${Directory.current.path}/$path');
    if (!alt.existsSync()) {
      fail('فایلِ مورد انتظار پیدا نشد: $path (cwd=${Directory.current.path})');
    }
    return alt.readAsStringSync();
  }
  return file.readAsStringSync();
}

/// شاخه‌های `when (call.method)` در هندلری که با [anchor] مشخص شده.
///
/// فقط شاخه‌هایی را می‌گیرد که به شکل `"نام" ->` باشند؛ رشته‌های دیگری که
/// درونِ بلوک هستند (مثل کلیدهای آرگومان) با `->` تمام نمی‌شوند.
Set<String> _kotlinHandled(String source, String anchor) {
  final anchorAt = source.indexOf(anchor);
  expect(anchorAt, greaterThanOrEqualTo(0), reason: 'نشد $anchor را پیدا کرد');

  final whenAt = source.indexOf('when (call.method)', anchorAt);
  expect(whenAt, greaterThan(anchorAt), reason: 'بلوکِ when بعد از $anchor نیست');

  final endAt = source.indexOf('else ->', whenAt);
  expect(endAt, greaterThan(whenAt), reason: 'بلوکِ when تمام نشده');

  final block = source.substring(whenAt, endAt);
  return RegExp(r'"(\w+)"\s*->')
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

/// مقادیرِ `static const x = 'نام';` در کلاسِ CoreMethods سمت دارت.
Set<String> _coreMethodConstants(String source) => RegExp(
      r"static const (\w+) = '([^']+)';",
    ).allMatches(source).map((m) => m.group(2)!).toSet();

/// متدهایی که دارت روی کانالِ libbox صدا می‌زند.
///
/// نکته: نوعِ جنریک ممکن است خودش `>` داشته باشد (`List<Object?>`)، برای همین
/// بین `<` و `(` هر چیزی جز پرانتز را می‌پذیریم نه «هر چیزی جز >» را.
Set<String> _dartInvoked(String source) => RegExp(
      r"invokeMethod<[^()]*>\(\s*'(\w+)'",
    ).allMatches(source).map((m) => m.group(1)!).toSet();

/// متدهایی که کاتلین به سمت دارت می‌فرستد (`send("onX", …)`).
Set<String> _kotlinEmitted(String source) =>
    RegExp(r'send\(\s*"(\w+)"').allMatches(source).map((m) => m.group(1)!).toSet();

/// شاخه‌های `_onCall` سمت دارت: `case 'onX':`.
Set<String> _dartHandled(String source) =>
    RegExp(r"case '(\w+)':").allMatches(source).map((m) => m.group(1)!).toSet();

void main() {
  group('قراردادِ کانالِ اصلی (com.overx/core)', () {
    test('هر متدی که دارت می‌فرستد، کاتلین می‌شناسد', () {
      final dart = _coreMethodConstants(_read(_androidBridge));
      final kotlin = _kotlinHandled(_read(_mainActivity), 'CHANNEL_CORE');

      expect(dart, isNotEmpty, reason: 'هیچ ثابتی در CoreMethods پیدا نشد');
      expect(
        dart.difference(kotlin),
        isEmpty,
        reason: 'این متدها در MainActivity هندل نشده‌اند '
            '(و در زمان اجرا notImplemented می‌دهند)',
      );
    });

    test('هر متدی که کاتلین می‌شناسد، ثابتش در دارت هست', () {
      final dart = _coreMethodConstants(_read(_androidBridge));
      final kotlin = _kotlinHandled(_read(_mainActivity), 'CHANNEL_CORE');

      expect(
        kotlin.difference(dart),
        isEmpty,
        reason: 'کاتلین متدهایی را هندل می‌کند که دارت هیچ ثابتی برایشان ندارد',
      );
    });
  });

  group('قراردادِ کانالِ libbox', () {
    test('هر متدی که دارت صدا می‌زند، کاتلین هندل کرده', () {
      final dart = _dartInvoked(_read(_libboxDart));
      final kotlin = _kotlinHandled(_read(_mainActivity), 'LibboxChannel.NAME');

      expect(dart, isNotEmpty);
      expect(
        dart.difference(kotlin),
        isEmpty,
        reason: 'دارت متدهایی را صدا می‌زند که MainActivity نمی‌شناسد',
      );
      // و برعکس: متدی که فقط کاتلین می‌شناسد یعنی یک انتهایِ بی‌استفاده
      expect(
        kotlin.difference(dart),
        isEmpty,
        reason: 'کاتلین متدهایی را هندل می‌کند که دارت هرگز صدا نمی‌زند',
      );
    });

    test('هر پیامی که کاتلین می‌فرستد، دارت هندل کرده', () {
      final kotlin = _kotlinEmitted(_read(_libboxChannel));
      final dart = _dartHandled(_read(_libboxDart));

      expect(kotlin, isNotEmpty, reason: 'هیچ send() ی در LibboxChannel پیدا نشد');
      expect(
        kotlin.difference(dart),
        isEmpty,
        reason: 'کاتلین پیام‌هایی می‌فرستد که _onCall سمت دارت نمی‌شناسد',
      );
    });

    test('نامِ پیام‌های لاگ در دو سمت یکی است', () {
      final kotlin = _kotlinEmitted(_read(_libboxChannel));
      expect(kotlin, contains('onLog'));
      expect(kotlin, contains('onStatus'));
      expect(kotlin, contains('onLogsCleared'));
    });
  });

  group('نام‌گذاریِ gobind (از روی مولد تأیید شده)', () {
    // gobind در bind/genjava.go می‌نویسد:
    //   public final native <T> get<Field>();
    // یعنی نامِ فیلدِ Go **دست‌نخورده** می‌آید؛ مخفف شکسته نمی‌شود.
    // یک بار حدسِ `getUrlTestDelay` را زدیم که غلط بود — این تست یافته را
    // قفل می‌کند تا دوباره عوض نشود.
    test('دسترسی‌سازِ URLTest با حروفِ بزرگِ URL است', () {
      final src = _read(_coreCommandClient);
      expect(src, contains('getURLTestDelay()'));
      expect(src, contains('getURLTestTime()'));
      expect(src, isNot(contains('getUrlTestDelay')));
      expect(src, isNot(contains('getUrlTestTime')));
    });

    test('تکرارگرها از hasNext استفاده نمی‌کنند (gobind نمی‌سازد)', () {
      final src = _read(_coreCommandClient);
      expect(src, isNot(contains('hasNext')));
      // پايانِ پيمایش با nil
      expect(src, contains('iterator.next() ?: break'));
    });
  });
}
