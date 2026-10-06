import 'package:overx/app.dart';
import 'package:overx/ui/widgets/setting_tile.dart';
import 'package:overx/ui/settings/settings_page.dart';
import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/app_package.dart';
import 'package:overx/core/models/network.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:overx/core/storage/repositories.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// یک smoke test برای اینکه مطمئن شویم کل درخت UI کامپایل و اجرا می‌شود.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 900),
    PlatformBridge? bridge,
    LibboxService? libbox,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider
              .overrideWithValue(SettingsRepository(prefs)),
          profileRepositoryProvider.overrideWithValue(ProfileRepository(prefs)),
        libboxServiceProvider
            .overrideWithValue(libbox ?? const UnavailableLibboxService()),
          platformBridgeProvider.overrideWithValue(bridge ?? FakeBridge()),
        ],
        child: const OverxApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('برنامه بالا می‌آید و صفحه‌ی اصلی نمایش داده می‌شود',
      (tester) async {
    await pump(tester);
    expect(find.text('OVERX'), findsWidgets);
    expect(find.text('خانه'), findsWidgets);
    // دکمه اتصال روی خانه
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
  });

  testWidgets('در حالت عریض منو ثابت است و همبرگری وجود ندارد',
      (tester) async {
    await pump(tester, size: const Size(1280, 900));
    // منو ثابت است: آیتم‌ها بدون نیاز به همبرگری دیده می‌شوند
    expect(find.text('پروفایل‌ها'), findsWidgets);
    expect(find.text('تنظیمات'), findsWidgets);
    expect(find.byType(DrawerButton), findsNothing);
  });

  testWidgets('در حالت باریک همبرگری ظاهر می‌شود و منو باز می‌شود',
      (tester) async {
    await pump(tester, size: const Size(430, 860));

    // دکمه‌ی همبرگری فلاتر (tooltip آن بومی‌سازی شده، پس با نوع ویجت پیدایش می‌کنیم)
    final hamburger = find.byType(DrawerButton);
    expect(hamburger, findsOneWidget);

    await tester.tap(hamburger);
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('تنظیمات'), findsWidgets);
    expect(find.text('درباره'), findsWidgets);
  });

  testWidgets('رفتن به صفحه تنظیمات از طریق منو', (tester) async {
    await pump(tester, size: const Size(430, 860));

    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();

    // تیتر AppBar و گروه‌های بالای صفحه
    expect(find.text('تنظیمات'), findsWidgets);
    expect(find.text('عمومی'), findsWidgets);
    expect(find.text('ظاهر'), findsWidgets);

    // ListView تنبل است — برای دیدن گروه‌های پایین باید اسکرول کرد
    await tester.drag(find.byType(SettingsPage), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('شبکه'), findsWidgets);
  });

  testWidgets('تغییر زبان به انگلیسی', (tester) async {
    await pump(tester, size: const Size(1280, 900));
    expect(find.text('خانه'), findsWidgets);

    await tester.tap(find.byTooltip('Language'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    // منو باید انگلیسی شده باشد
    expect(find.text('Profiles'), findsWidgets);
    // و راست‌به‌چپ به چپ‌به‌راست تغییر کرده
    expect(
      Directionality.of(tester.element(find.text('Home').first)),
      TextDirection.ltr,
    );
  });

  testWidgets('سوییچِ autoStart در تنظیمات، پلتفرم را صدا می‌زند',
      (tester) async {
    final bridge = FakeBridge();
    await pump(tester, size: const Size(1280, 1000), bridge: bridge);

    // رفتن به صفحه‌ی تنظیمات (در حالت عریض منو ثابت است)
    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();

    expect(bridge.autoStart, false);

    // اولین سوییچِ صفحه = «اجرا در شروع سیستم»
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(bridge.autoStart, true);
  });

  testWidgets('پلتفرمی که autoStart ندارد، پیام می‌دهد و تغییری ذخیره نمی‌شود',
      (tester) async {
    final bridge = FakeBridge()..autoStartResult = false;
    await pump(tester, size: const Size(1280, 1000), bridge: bridge);

    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // پلتفرم جواب منفی داده؛ مقدار واقعی نباید ذخیره شود
    expect(bridge.autoStart, false);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('صفحه‌ی per-app باز می‌شود و انتخاب در تنظیمات ذخیره می‌گردد',
      (tester) async {
    final bridge = FakeBridge()
      ..fakePackages = const <AppPackage>[
        AppPackage(packageName: 'com.alpha', label: 'برنامه آلفا'),
        AppPackage(packageName: 'com.beta', label: 'برنامه بتا'),
      ];

    await pump(
      tester,
      size: const Size(1280, 1100),
      bridge: bridge,
      libbox: const FakeLibbox(available: true),
    );

    // رفتن به تنظیمات
    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();

    // کاشیِ per-app باید فعال باشد (چون libbox در دسترس است)
    final tile = find.text('مسیریابیِ هر برنامه');
    expect(tile, findsWidgets);

    await tester.tap(tile.last);
    await tester.pumpAndSettle();

    // صفحه باز شده و هر دو برنامه را نشان می‌دهد
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.text('برنامه آلفا'), findsOneWidget);

    // تا وقتی قابلیت خاموش است، ابزارهای انتخاب پنهان‌اند و چک‌باکس‌ها
    // غیرفعال. ابتدا آن را روشن می‌کنیم.
    expect(find.text('انتخاب همه'), findsNothing);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('انتخاب همه'), findsOneWidget);

    // هنوز چیزی انتخاب نشده
    expect(find.text('0 انتخاب شده'), findsOneWidget);

    // انتخابِ یکی
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('1 انتخاب شده'), findsOneWidget);

    // و انتخابِ دومی
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pumpAndSettle();
    expect(find.text('2 انتخاب شده'), findsOneWidget);

    // پاک‌کردن
    await tester.tap(find.text('پاک‌کردن'));
    await tester.pumpAndSettle();
    expect(find.text('0 انتخاب شده'), findsOneWidget);
  });

  testWidgets('بدون libbox کاشیِ per-app غیرفعال است', (tester) async {
    await pump(tester, size: const Size(1280, 1000));

    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();

    // کاشی هست اما لمس نمی‌پذیرد
    final tile = find.ancestor(
      of: find.text('مسیریابیِ هر برنامه'),
      matching: find.byType(ActionSetting),
    );
    expect(tile, findsOneWidget);
    expect(
      tester.widget<ActionSetting>(tile).enabled,
      false,
    );
  });
}

/// سرویس libbox ساختگی — فقط برای اینکه کاشیِ per-app در تست فعال شود.


class FakeLibbox implements LibboxService {
  const FakeLibbox({this.available = true});

  @override
  final bool available;

  @override
  String? get lastError => null;

  @override
  Stream<LibboxLogLine> get logs => const Stream<LibboxLogLine>.empty();

  @override
  Stream<void> get logsCleared => const Stream<void>.empty();

  @override
  Future<List<OutboundGroup>> getGroups() async => const <OutboundGroup>[];

  @override
  Future<List<ConnectionEntry>> getConnections() async =>
      const <ConnectionEntry>[];

  @override
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) async {}

  @override
  Future<void> urlTest(String outboundTag) async {}

  @override
  Future<void> closeConnection(String id) async {}

  @override
  Future<void> closeConnections() async {}


  @override
  LibboxStatus get status => LibboxStatus.stopped;

  @override
  Future<void> start({
    required String config,
    List<String> includePackages = const <String>[],
    List<String> excludePackages = const <String>[],
  }) async {}

  @override
  Future<void> stop() async {}
}

/// پیاده‌سازی ساختگی برای تست‌ها — هیچ کاری با سیستم‌عامل نمی‌کند.
class FakeBridge implements PlatformBridge {
  FakeBridge({
    this.tunFd,
    this.systemProxyResult = true,
    this.autoStartResult = true,
    this.prepareResult = true,
  });

  final int? tunFd;
  bool systemProxyResult;
  bool autoStartResult;
  bool prepareResult;

  List<AppPackage> fakePackages = const <AppPackage>[];

  final List<String> iconCalls = <String>[];

  int systemProxyCalls = 0;
  int clearProxyCalls = 0;
  int tunAcquired = 0;
  int tunReleased = 0;
  bool autoStart = false;

  @override
  PlatformFeatures get features => PlatformFeatures(<PlatformFeature>{
        PlatformFeature.systemProxy,
        PlatformFeature.autoStart,
        if (tunFd != null) PlatformFeature.tunFd,
        if (tunFd != null) PlatformFeature.vpnService,
      });

  @override
  String? lastError;

  @override
  Future<bool> prepare() async => prepareResult;

  @override
  Future<TunHandle?> acquireTun({int mtu = 9000}) async {
    if (tunFd == null) return null;
    tunAcquired++;
    return TunHandle(fd: tunFd!, mtu: mtu);
  }

  @override
  Future<void> releaseTun() async => tunReleased++;

  @override
  Future<bool> setSystemProxy({required String host, required int port}) async {
    systemProxyCalls++;
    return systemProxyResult;
  }

  @override
  Future<bool> clearSystemProxy() async {
    clearProxyCalls++;
    return true;
  }

  @override
  Future<bool> setAutoStart(bool enable) async {
    if (!autoStartResult) return false;
    autoStart = enable;
    return true;
  }

  @override
  Future<bool> isAutoStartEnabled() async => autoStart;

  @override
  Future<String?> nativeLibraryDir() async => null;

  @override
  Future<List<AppPackage>> listInstalledPackages({bool includeSystem = false}) async =>
      fakePackages;

  /// آیکون‌های قلابی: برای بسته‌های «icon:» یک PNG یک‌پیکسلی برمی‌گرداند.
  @override
  Future<Uint8List?> appIcon(String packageName, {int size = 64}) async {
    iconCalls.add(packageName);
    if (!packageName.startsWith('icon:')) return null;
    return Uint8List.fromList(<int>[1, 2, 3, 4]);
  }

  @override
  Future<Map<String, String>> installedBinaries() async => const <String, String>{};

  @override
  Future<void> dispose() async {}

}