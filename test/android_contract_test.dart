import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// قراردادهای اندرویدی که **بدون کامپایل** هم می‌توان چک کرد.
///
/// دو دسته خطای بی‌صدا وجود دارد که هیچ تستِ واحدی نمی‌گیرد:
///
/// ۱. مانیفست به کلاسی اشاره کند که دیگر وجود ندارد (یا نامش عوض شده باشد) —
///    برنامه کامپایل و نصب می‌شود و فقط هنگامِ راه‌اندازیِ آن کامپوننت با
///    `ClassNotFoundException` می‌ترکد.
/// ۲. دو طرفِ یک `MethodChannel` نامِ متفاوتی داشته باشند — کاتلین
///    `result.notImplemented()` می‌دهد و دارت بی‌سروصدا `null` می‌گیرد.
///
/// کامپایلِ واقعی را `tool/check_android.sh` انجام می‌دهد؛ اینجا cheap ترین
/// چیزهایی را قفل می‌کنیم که آن اسکریپت نمی‌بیند.

const _manifest = 'android/app/src/main/AndroidManifest.xml';
const _kotlinDir = 'android/app/src/main/kotlin/com/overx/overx';
const _mainActivity = '$_kotlinDir/MainActivity.kt';
const _libboxChannel = '$_kotlinDir/LibboxChannel.kt';
const _dartBridge = 'lib/core/platform/android_bridge.dart';
const _dartLibbox = 'lib/core/platform/libbox.dart';
const _libboxVpnService = '$_kotlinDir/LibboxVpnService.kt';

String _read(String path) {
  final file = File(path);
  if (file.existsSync()) return file.readAsStringSync();
  final alt = File('${Directory.current.path}/$path');
  if (alt.existsSync()) return alt.readAsStringSync();
  fail('فایل پیدا نشد: $path (cwd=${Directory.current.path})');
}

/// کلاس‌هایی که مانیفست با نامِ کوتاه (`.X`) معرفی کرده.
Set<String> _manifestClasses(String xml) => RegExp(
      r'android:name="\.([A-Za-z_][\w.]*)"',
    ).allMatches(xml).map((m) => m.group(1)!).toSet();

/// آیا کلاسی با این نام در یکی از فایل‌های کاتلین تعریف شده؟
bool _kotlinHasClass(String name) {
  final dir = Directory(_kotlinDir);
  if (!dir.existsSync()) {
    fail('پوشه‌ی کاتلین پیدا نشد: $_kotlinDir');
  }
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.kt')) continue;
    final src = file.readAsStringSync();
    if (RegExp('^\\s*(class|object)\\s+$name\\b', multiLine: true)
        .hasMatch(src)) {
      return true;
    }
  }
  return false;
}

void main() {
  group('مانیفست در برابر کاتلین', () {
    test('هر کامپوننتِ مانیفست یک کلاسِ واقعی دارد', () {
      final classes = _manifestClasses(_read(_manifest));
      expect(classes, isNotEmpty, reason: 'هیچ کامپوننتی در مانیفست نیست؟');
      for (final name in classes) {
        expect(
          _kotlinHasClass(name),
          isTrue,
          reason: 'مانیفست به .$name اشاره می‌کند اما چنین کلاسی در '
              '$_kotlinDir نیست (در زمان اجرا ClassNotFoundException می‌دهد)',
        );
      }
    });

    test('سرویس‌های VPN پرمیژن و intent-filter درست دارند', () {
      final xml = _read(_manifest);
      // هر <service> ی که کلاسش با VpnService تمام می‌شود
      final services = RegExp(
        r'<service\b[^>]*>',
        dotAll: true,
      ).allMatches(xml).map((m) => m.group(0)!).where(
            (s) => s.contains('VpnService"'),
          );
      expect(services, isNotEmpty, reason: 'هیچ سرویس VPN ی ثبت نشده');
      for (final s in services) {
        expect(
          s,
          contains('android.permission.BIND_VPN_SERVICE'),
          reason: 'سرویس VPN بدون BIND_VPN_SERVICE پذیرفته نمی‌شود',
        );
      }
      // و هر کدام باید intent-filterِ android.net.VpnService را داشته باشند
      final blocks = xml.split('<service');
      for (final block in blocks.skip(1)) {
        if (!block.contains('VpnService"')) continue;
        final body = block.split('</service>').first;
        expect(
          body,
          contains('android.net.VpnService'),
          reason: 'بدون intent-filterِ android.net.VpnService، سیستم هیچ‌وقت '
              'این سرویس را برای گرفتنِ مجوز نشان نمی‌دهد',
        );
      }
    });
  });

  group('نامِ کانال‌ها در دو سمت', () {
    test('کانالِ اصلی: کاتلین == دارت', () {
      final kotlin = RegExp(r'CHANNEL_CORE\s*=\s*"([^"]+)"')
          .firstMatch(_read(_mainActivity))
          ?.group(1);
      final dart =
          RegExp(r"kChannel\s*=\s*'([^']+)'").firstMatch(_read(_dartBridge))
              ?.group(1);
      expect(kotlin, isNotNull);
      expect(dart, isNotNull);
      expect(
        kotlin,
        dart,
        reason: 'اگر نام‌ها یکی نباشند، هر فراخوانی بی‌سروصدا null برمی‌گردد',
      );
    });

    test('کانالِ libbox: کاتلین == دارت', () {
      final kotlin = RegExp(r'NAME\s*=\s*"([^"]+)"')
          .firstMatch(_read(_libboxChannel))
          ?.group(1);
      final dart = RegExp(r"MethodChannel\('([^']+)'\)")
          .firstMatch(_read(_dartLibbox))
          ?.group(1);
      expect(kotlin, isNotNull);
      expect(dart, isNotNull);
      expect(kotlin, dart);
    });
  });

  group('CommandServerHandler — متدهای error-only', () {
    // experimental/libbox/command_server.go:
    //   ServiceStop() error | ServiceReload() error | TriggerNativeCrash() error
    //   SetSystemProxyEnabled(enabled bool) error
    // خروجیِ تنهای error در gobind به void تبدیل می‌شود.
    const errorOnly = <String>{
      'serviceStop',
      'serviceReload',
      'triggerNativeCrash',
      'setSystemProxyEnabled',
    };

    bool returnsUnit(String source, String name) {
      final at = source.indexOf('override fun $name(');
      expect(at, greaterThanOrEqualTo(0), reason: '$name در کاتلین نیست');
      var i = source.indexOf('(', at);
      var depth = 0;
      while (i < source.length) {
        final ch = source[i];
        if (ch == '(') depth++;
        if (ch == ')') {
          depth--;
          if (depth == 0) break;
        }
        i++;
      }
      final after = source.substring(i + 1).trimLeft();
      return after.startsWith('{') ||
          after.startsWith('=') ||
          after.startsWith('//');
    }

    test('همگی بدون نوعِ خروجی تعریف شده‌اند', () {
      final src = _read(_libboxVpnService);
      for (final name in errorOnly) {
        expect(
          returnsUnit(src, name),
          isTrue,
          reason: '$name در Go تنها error برمی‌گرداند ⇒ امضای جاوا void است',
        );
      }
    });
  });
}
