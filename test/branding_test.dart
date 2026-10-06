import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// قراردادِ هویتِ بصریِ برنامه.
///
/// چرا این تست وجود دارد؟ چون آیکن و لوگو چیزهایی‌اند که **هیچ تستی** نمی‌بیند:
/// تصویر عوض می‌شود، فایلی جابه‌جا می‌شود، یکی `setSmallIcon` را به
/// `R.mipmap.ic_launcher` برمی‌گرداند — و برنامه همچنان کامپایل و اجرا می‌شود.
/// تنها نشانه این است که کاربر در نوارِ وضعیت یک قفلِ عمومیِ اندروید می‌بیند
/// یا آیکنِ برنامه روی صفحه نصفه می‌افتد.
///
/// پس اینجا قفل می‌کنیم:
///   ۱. دارایی‌ها سرِ جایشان هستند و اندازه‌ی درست دارند،
///   ۲. آیکنِ نوارِ وضعیت در هر سه جا همان نشانه‌ی تک‌رنگِ برنامه است،
///   ۳. آیکنِ تطبیقیِ اندروید (۸ به بالا) کامل است،
///   ۴. صفحه‌ی آغازین از لوگوی کامل استفاده می‌کند.
///
/// همه‌ی این دارایی‌ها با `tool/gen_icons.py` از روی تصویرِ منبع ساخته می‌شوند؛
/// اگر آن اسکریپت را دوباره اجرا کردید و این تست شکست، یعنی خروجی عوض شده.

const _res = 'android/app/src/main/res';
const _kotlinDir = 'android/app/src/main/kotlin/com/overx/overx';

String _read(String path) {
  final file = File(path);
  if (file.existsSync()) return file.readAsStringSync();
  final alt = File('${Directory.current.path}/$path');
  if (alt.existsSync()) return alt.readAsStringSync();
  fail('فایل پیدا نشد: $path (cwd=${Directory.current.path})');
}

/// آیا فایل وجود دارد؟ (مسیر نسبی به ریشه‌ی پروژه)
bool _exists(String path) =>
    File(path).existsSync() || File('${Directory.current.path}/$path').existsSync();

/// امضای PNG را چک می‌کند و اندازه را از IHDR می‌خواند.
({int width, int height}) _pngSize(String path) {
  final file = File(path).existsSync()
      ? File(path)
      : File('${Directory.current.path}/$path');
  if (!file.existsSync()) fail('فایل پیدا نشد: $path');
  final bytes = file.readAsBytesSync();
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  expect(
    bytes.sublist(0, 8),
    signature,
    reason: '$path یک PNG معتبر نیست',
  );
  final view = ByteData.sublistView(bytes);
  // IHDR: طول (۴ بایت) + نوع (۴ بایت) + عرض (۴) + ارتفاع (۴)
  return (width: view.getUint32(16), height: view.getUint32(20));
}

void main() {
  group('دارایی‌های هویتِ بصری', () {
    test('لوگو و نشانه در assets هستند و pubspec آن را بسته‌بندی می‌کند', () {
      final pubspec = _read('pubspec.yaml');
      expect(
        pubspec.contains('assets/'),
        isTrue,
        reason: 'pubspec باید پوشه‌ی assets را اعلام کند',
      );
      for (final name in <String>[
        'assets/logo.png',
        'assets/logo_white.png',
        'assets/icon.png',
        'assets/icon_white.png',
      ]) {
        expect(_exists(name), isTrue, reason: '$name وجود ندارد');
      }
      // لوگو (نشانه + نام) باید کشیده باشد و نشانه مربع
      final logo = _pngSize('assets/logo.png');
      expect(logo.width > logo.height * 2, isTrue,
          reason: 'لوگو باید نشانه + نام باشد (کشیده)، نه فقط نشانه');
      final icon = _pngSize('assets/icon.png');
      expect(icon.width, icon.height,
          reason: 'نشانه باید مربع باشد: ${icon.width}×${icon.height}');
    });

    test('نسخه‌ی سفیدِ دارایی‌ها هم‌اندازه‌ی نسخه‌ی اصلی است', () {
      for (final pair in <(String, String)>[
        ('assets/logo.png', 'assets/logo_white.png'),
        ('assets/icon.png', 'assets/icon_white.png'),
      ]) {
        final a = _pngSize(pair.$1);
        final b = _pngSize(pair.$2);
        expect((b.width, b.height), (a.width, a.height),
            reason: '${pair.$2} باید هم‌اندازه‌ی ${pair.$1} باشد');
      }
    });
  });

  group('اندروید — آیکنِ لانچر', () {
    test('آیکنِ کلاسیک در هر پنج چگالی، مربع و هم‌اندازه است', () {
      for (final entry in <String, int>{
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      }.entries) {
        final path = '$_res/mipmap-${entry.key}/ic_launcher.png';
        final size = _pngSize(path);
        expect(size.width, entry.value, reason: '$path عرض درست ندارد');
        expect(size.height, entry.value, reason: '$path ارتفاع درست ندارد');
      }
    });

    test('آیکنِ تطبیقی: پیش‌زمینه + پس‌زمینه + anydpi-v26', () {
      final foreground = _pngSize('$_res/drawable/ic_launcher_foreground.png');
      expect(foreground.width, 432,
          reason: 'پیش‌زمینه باید ۴۳۲ پیکسل (۱۰۸dp در xxxhdpi) باشد');
      expect(foreground.height, 432);

      final background = _read('$_res/values/ic_launcher_background.xml');
      expect(background.contains('name="ic_launcher_background"'), isTrue);

      for (final name in <String>['ic_launcher.xml', 'ic_launcher_round.xml']) {
        final xml = _read('$_res/mipmap-anydpi-v26/$name');
        expect(xml.contains('adaptive-icon'), isTrue, reason: name);
        expect(xml.contains('@drawable/ic_launcher_foreground'), isTrue,
            reason: '$name باید پیش‌زمینه را صدا بزند');
        expect(xml.contains('@color/ic_launcher_background'), isTrue,
            reason: '$name باید پس‌زمینه را صدا بزند');
      }
    });
  });

  group('اندروید — نوارِ وضعیت هنگام اتصال', () {
    /// این همان چیزی است که کاربر موقعِ وصل‌بودنِ VPN در نوار بالا می‌بیند.
    test('آیکنِ تک‌رنگ در هر پنج چگالی وجود دارد', () {
      for (final entry in <String, int>{
        'mdpi': 24,
        'hdpi': 36,
        'xhdpi': 48,
        'xxhdpi': 72,
        'xxxhdpi': 96,
      }.entries) {
        final path = '$_res/drawable-${entry.key}/ic_stat_overx.png';
        final size = _pngSize(path);
        expect(size.width, entry.value, reason: '$path عرض درست ندارد');
        expect(size.height, entry.value, reason: '$path ارتفاع درست ندارد');
      }
    });

    test('هر سه اعلان از آیکنِ تک‌رنگِ برنامه استفاده می‌کنند', () {
      final files = <String>[
        '$_kotlinDir/TunVpnService.kt',
        '$_kotlinDir/LibboxVpnService.kt',
      ];
      var count = 0;
      for (final path in files) {
        final src = _read(path);
        for (final line in src.split('\n')) {
          if (!line.contains('setSmallIcon')) continue;
          count++;
          expect(
            line.contains('R.drawable.ic_stat_overx'),
            isTrue,
            reason: '$path: اعلان باید R.drawable.ic_stat_overx را بگذارد، '
                'نه آیکنِ لانچر و نه آیکنِ عمومیِ اندروید:\n  ${line.trim()}',
          );
        }
      }
      expect(count, 3,
          reason: 'انتظارِ سه اعلان (TUN، وضعیتِ libbox، پیام‌های libbox)');
    });
  });

  group('اندروید — صفحه‌ی آغازین', () {
    test('زمینه‌ی آغازین لوگوی کامل را نشان می‌دهد', () {
      for (final path in <String>[
        '$_res/drawable/launch_background.xml',
        '$_res/drawable-v21/launch_background.xml',
      ]) {
        final xml = _read(path);
        expect(xml.contains('@drawable/launch_logo'), isTrue, reason: path);
      }
      // نسخه‌ی روز و شب، در هر پنج چگالی
      for (final density in <String>['mdpi', 'hdpi', 'xhdpi', 'xxhdpi',
        'xxxhdpi']) {
        expect(_exists('$_res/drawable-$density/launch_logo.png'), isTrue,
            reason: 'launch_logo در $density نیست');
        expect(_exists('$_res/drawable-night-$density/launch_logo.png'), isTrue,
            reason: 'launch_logo شب در $density نیست');
      }
    });
  });

  group('دسکتاپ و iOS', () {
    test('آیکنِ ویندوز، مک و iOS وجود دارد', () {
      expect(_exists('windows/runner/resources/app_icon.ico'), isTrue);
      for (final size in <int>[16, 32, 64, 128, 256, 512, 1024]) {
        expect(
          _exists('macos/Runner/Assets.xcassets/AppIcon.appiconset/'
              'app_icon_$size.png'),
          isTrue,
          reason: 'آیکنِ مک $size نیست',
        );
      }
      expect(
        _exists('ios/Runner/Assets.xcassets/AppIcon.appiconset/'
            'Icon-App-1024x1024@1x.png'),
        isTrue,
      );
    });
  });
}
