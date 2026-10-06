import 'dart:io';

import 'package:overx/core/engine/core_type.dart';
import 'package:overx/theme/app_theme.dart';
import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/profile.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:overx/core/storage/repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_smoke_test.dart' show FakeBridge;

/// یک تستِ سرتاسریِ واقعی: موتور را با یک «هسته‌ی قلابی» اجرا می‌کند.
///
/// تا پیش از این، تنها اجزای جداگانه تست شده بودند؛ خودِ مسیرِ
/// «تولید کانفیگ → اجرای فرآیند → خواندن لاگ → وصل شدن به Clash API → توقف»
/// هرگز اجرا نشده بود.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String fakeBinary;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('overx_engine_test');

    final dartExe = await _resolveDart();
    final script = File(
      p.join(Directory.current.path, 'test', 'fixtures', 'fake_core.dart'),
    );
    expect(script.existsSync(), isTrue,
        reason: 'فایل هسته‌ی قلابی باید کنار تست باشد');

    // یک wrapperِ اجرایی — درست مثل یک باینری واقعی
    final wrapper = File(p.join(tmp.path, 'sing-box'))
      ..writeAsStringSync(
        '#!/usr/bin/env bash\nexec "$dartExe" "${script.path}" "\$@"\n',
      );
    // حتماً executable شود
    await Process.run('chmod', ['+x', wrapper.path]);
    fakeBinary = wrapper.path;
  });

  tearDownAll(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ProviderContainer container(SharedPreferences prefs) => ProviderContainer(
        overrides: [
          settingsRepositoryProvider
              .overrideWithValue(SettingsRepository(prefs)),
          profileRepositoryProvider.overrideWithValue(ProfileRepository(prefs)),
          platformBridgeProvider.overrideWithValue(FakeBridge()),
          libboxServiceProvider
              .overrideWithValue(const UnavailableLibboxService()),
        ],
      );

  Profile demoProfile() => Profile(
        id: 'it-1',
        name: 'IT-Test',
        protocol: ProfileProtocol.vless,
        address: 'test.example.net',
        port: 443,
        fields: const {'network': 'ws', 'security': 'none'},
      );

  test('اتصال کامل: فرآیند اجرا می‌شود، لاگ می‌آید، آمار بالا می‌رود',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    addTearDown(c.dispose);

    // تنظیماتِ مناسب برای تست: بدون TUN و بدون پروکسی سیستم
    final settings = c.read(settingsProvider.notifier);
    await settings.setSingboxPath(fakeBinary);
    await settings.setTunMode(false);
    await settings.setSystemProxy(false);
    await settings.setSingboxApiPort(49091);

    final engine = c.read(engineProvider.notifier);

    await engine.connect(demoProfile());
    // کمی فرصت برای اجرا و وصل شدنِ آمار
    await _waitFor(
      () => engine.state.status == ConnectionState2.connected,
      timeout: const Duration(seconds: 60),
    );

    expect(engine.state.status, ConnectionState2.connected);
    expect(engine.state.core, CoreType.singbox);

    // ---------------------------------------------------------- لاگ‌ها
    // فرآیند تازه راه افتاده؛ کمی فرصت می‌دهیم خروجی برسد
    await _waitFor(
      () => c.read(logsProvider).any((l) => l.text.contains('fake-core')),
      timeout: const Duration(seconds: 30),
      orElse: 'هیچ خروجی‌ای از هسته‌ی قلابی نرسید',
    );
    final all = c.read(logsProvider).map((l) => l.text).join('\n');
    expect(all, contains('fake-core'));
    expect(all, contains('clash api listening at 127.0.0.1:49091'));
    // کانفیگ واقعاً روی دیسک نوشته شده
    expect(all, contains('config written'));

    // ------------------------------------------------------------ آمار
    await _waitFor(
      () => c.read(trafficProvider).downlinkSpeed > 0,
      timeout: const Duration(seconds: 30),
      orElse: 'هیچ نمونه‌ی ترافیکی از Clash API نرسید',
    );

    final traffic = c.read(trafficProvider);
    expect(traffic.downlinkSpeed, greaterThan(0));

    // ---------------------------------------------------------- قطع اتصال
    await engine.disconnect();
    await _waitFor(
      () => engine.state.status == ConnectionState2.disconnected,
      timeout: const Duration(seconds: 30),
    );
    expect(engine.state.status, ConnectionState2.disconnected);
  });

  test('هسته‌ای که بلافاصله با خطا خارج می‌شود → خطا ثبت می‌گردد', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    addTearDown(c.dispose);

    // یک باینری که فوراً با کدِ خطا خارج می‌شود
    final bad = File(p.join(tmp.path, 'bad-core'))
      ..writeAsStringSync(
        '#!/usr/bin/env bash\n'
        'if [ "\$1" = "version" ]; then echo "sing-box version 1.14.2 (bad)"; exit 0; fi\n'
        'echo "FATAL: bad config" >&2\n'
        'exit 23\n',
      );
    await Process.run('chmod', ['+x', bad.path]);

    final settings = c.read(settingsProvider.notifier);
    await settings.setSingboxPath(bad.path);
    await settings.setTunMode(false);
    await settings.setSystemProxy(false);

    final engine = c.read(engineProvider.notifier);
    await engine.connect(demoProfile());

    await _waitFor(
      () => engine.state.status == ConnectionState2.disconnected,
      timeout: const Duration(seconds: 60),
    );

    // خطا باید در لاگ‌ها ثبت شده باشد (و نه یک استثنای کنترل‌نشده)
    final all = c.read(logsProvider).map((l) => l.text).join('\n');
    expect(all, contains('FATAL: bad config'));
  });

  test('باینریِ پیدا‌نشده → پیامِ راهنما، بدون کرش', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    addTearDown(c.dispose);

    final settings = c.read(settingsProvider.notifier);
    await settings.setSingboxPath(p.join(tmp.path, 'does-not-exist'));
    await settings.setTunMode(false);
    await settings.setSystemProxy(false);

    final engine = c.read(engineProvider.notifier);
    await engine.connect(demoProfile());

    // باینری پیدا نشد ← وضعیتِ خطا (و نه کرش یا اتصالِ نیمه‌کاره)
    expect(engine.state.status, ConnectionState2.error);
    final all = c.read(logsProvider).map((l) => l.text).join('\n');
    expect(all, contains('not found'));
  });

  test('Xray هم با همین هسته‌ی قلابی بالا می‌آید', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    addTearDown(c.dispose);

    final settings = c.read(settingsProvider.notifier);
    await settings.setXrayPath(fakeBinary);
    await settings.setCore(CoreType.xray);
    await settings.setTunMode(false);
    await settings.setSystemProxy(false);

    final engine = c.read(engineProvider.notifier);
    await engine.connect(demoProfile());

    await _waitFor(
      () => engine.state.status == ConnectionState2.connected,
      timeout: const Duration(seconds: 60),
    );
    expect(engine.state.core, CoreType.xray);
    expect(engine.state.status, ConnectionState2.connected);

    await engine.disconnect();
  });
}

// --------------------------------------------------------------- ابزارها

Future<String> _resolveDart() async {
  final exe = Platform.resolvedExecutable;
  if (p.basenameWithoutExtension(exe) == 'dart' && File(exe).existsSync()) {
    return exe;
  }
  final r = await Process.run('which', ['dart']);
  if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
    return (r.stdout as String).trim();
  }
  throw StateError('مفسر dart پیدا نشد؛ نمی‌توان هسته‌ی قلابی را اجرا کرد');
}

// مهلت‌ها عمداً بلند گرفته شده‌اند. این تست‌ها یک فرآیندِ واقعی اجرا می‌کنند
// (مفسرِ دارت برای «هسته‌ی قلابی»)؛ روی ماشین‌های زیرِ بار — مثل رانرِ رایگانِ
// CI یا سندباکسی با ۲ گیگابایت رم — راه‌اندازیِ فرآیند می‌تواند ده‌ها ثانیه
// طول بکشد و مهلتِ کوتاه تست را به‌شکلِ کاذب قرمز می‌کرد (یک‌بار واقعاً هم شد:
// هنگامِ اجرایِ Gradle، همین تست روی مهلتِ ۲۰ ثانیه‌ای شکست خورد در حالی که
// بلافاصله بعد از آن، روی ماشینِ خلوت گذشت). روی ماشینِ سریع، حلقه به‌محض
// برقراریِ شرط برمی‌گردد و زمانی تلف نمی‌شود.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? orElse,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (orElse != null) fail(orElse);
}
