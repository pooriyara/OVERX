// ignore_for_file: invalid_use_of_visible_for_testing_member
// ابزارِ تولید تصویر از رابط واقعی برنامه (برای مستندات / بررسی طراحی).
//
// این فایل عمداً در پوشه‌ی `test/` نیست تا همراه `flutter test` اجرا نشود
// (تست‌های golden به فونت و نسخه‌ی فلاتر حساس‌اند).
//
// اجرا:
//   flutter test tool/generate_screenshots_test.dart --update-goldens
//
// خروجی: tool/goldens/*.png
import 'package:overx/app.dart';
import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/app_package.dart';
import 'package:overx/core/models/network.dart';
import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/settings.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:overx/core/storage/repositories.dart';
import 'package:overx/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _demoProfiles = <Profile>[
  Profile(
    id: 'p1',
    name: 'DE-Fra-01',
    protocol: ProfileProtocol.vless,
    address: 'fra1.example.net',
    port: 443,
    latencyMs: 48,
    fields: const {'network': 'ws', 'security': 'reality'},
  ),
  Profile(
    id: 'p2',
    name: 'NL-Ams-02',
    protocol: ProfileProtocol.hysteria2,
    address: 'ams2.example.net',
    port: 443,
    latencyMs: 63,
  ),
  Profile(
    id: 'p3',
    name: 'US-Lax-03',
    protocol: ProfileProtocol.vmess,
    address: 'lax3.example.net',
    port: 443,
    latencyMs: 158,
    fields: const {'network': 'grpc'},
  ),
];

final _demoPackages = <AppPackage>[
  const AppPackage(packageName: 'org.telegram.messenger', label: 'Telegram'),
  const AppPackage(packageName: 'com.whatsapp', label: 'WhatsApp'),
  const AppPackage(packageName: 'com.google.android.youtube', label: 'YouTube'),
  const AppPackage(packageName: 'com.android.chrome', label: 'Chrome'),
  const AppPackage(packageName: 'com.spotify.music', label: 'Spotify'),
  const AppPackage(packageName: 'com.discord', label: 'Discord'),
  const AppPackage(packageName: 'com.instagram.android', label: 'Instagram'),
  const AppPackage(packageName: 'com.google.android.gm', label: 'Gmail'),
];

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required ThemeModePref theme,
  required AppLang lang,
  LibboxService? libbox,
  PlatformBridge? bridge,
  List<AppPackage> packages = const <AppPackage>[],
  bool perAppEnabled = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        profileRepositoryProvider.overrideWithValue(ProfileRepository(prefs)),
        libboxServiceProvider
            .overrideWithValue(libbox ?? const UnavailableLibboxService()),
        platformBridgeProvider
            .overrideWithValue(bridge ?? _ShotBridge(packages)),
      ],
      child: RepaintBoundary(
        key: const Key('golden'),
        child: const OverxApp(),
      ),
    ),
  );
  await tester.pump();

  // تنظیماتِ دلخواه برای تصویر
  final c = ProviderScope.containerOf(
    tester.element(find.byType(OverxApp)),
  );
  await c.read(settingsProvider.notifier).prime(theme: theme, lang: lang);
  await c.read(profilesProvider.notifier).seed(_demoProfiles);
  if (perAppEnabled) {
    await c.read(settingsProvider.notifier).setPerAppProxyEnabled(true);
    await c.read(settingsProvider.notifier)
        .setPerAppPackages(packages.take(2).map((p) => p.packageName).toList());
  }

  await tester.pumpAndSettle(const Duration(milliseconds: 600));
}

/// گروه‌های نمونه برای تصویرِ صفحه‌ی شبکه.
const _demoGroups = <OutboundGroup>[
  OutboundGroup(
    tag: 'proxy',
    type: 'selector',
    selectable: true,
    selected: 'EU-Frankfurt-01',
    items: <OutboundItem>[
      OutboundItem(
        tag: 'EU-Frankfurt-01',
        type: 'vless',
        urlTestDelay: 138,
        urlTestTime: 1,
      ),
      OutboundItem(
        tag: 'US-LosAngeles-02',
        type: 'vmess',
        urlTestDelay: 254,
        urlTestTime: 1,
      ),
      OutboundItem(tag: 'TR-Istanbul-03', type: 'trojan'),
    ],
  ),
  OutboundGroup(
    tag: 'auto',
    type: 'urltest',
    selectable: false,
    selected: 'EU-Frankfurt-01',
    items: <OutboundItem>[
      OutboundItem(
        tag: 'EU-Frankfurt-01',
        type: 'vless',
        urlTestDelay: 138,
        urlTestTime: 1,
      ),
      OutboundItem(
        tag: 'US-LosAngeles-02',
        type: 'vmess',
        urlTestDelay: 254,
        urlTestTime: 1,
      ),
    ],
  ),
];

/// اتصال‌های نمونه برای تصویرِ صفحه‌ی شبکه.
const _demoConnections = <ConnectionEntry>[
  ConnectionEntry(
    id: 'c1',
    outbound: 'proxy',
    protocol: 'tcp',
    network: 'tcp',
    destination: '172.217.16.14:443',
    domain: 'google.com',
    source: '10.0.0.5:41234',
    uplinkTotal: 245678,
    downlinkTotal: 3145728,
    createdAt: 0,
    closedAt: 0,
  ),
  ConnectionEntry(
    id: 'c2',
    outbound: 'proxy',
    protocol: 'udp',
    network: 'udp',
    destination: '1.1.1.1:443',
    domain: 'cloudflare-dns.com',
    source: '10.0.0.5:51222',
    uplinkTotal: 8192,
    downlinkTotal: 65536,
    createdAt: 0,
    closedAt: 0,
  ),
  ConnectionEntry(
    id: 'c3',
    outbound: 'direct',
    protocol: 'tcp',
    network: 'tcp',
    destination: '185.143.233.10:443',
    domain: '',
    source: '10.0.0.5:39876',
    uplinkTotal: 1204,
    downlinkTotal: 4096,
    createdAt: 0,
    closedAt: 1, // بسته‌شده
  ),
];

/// سرویس libbox ساختگی که «در دسترس»报告 می‌دهد تا صفحه‌ی per-app فعال شود.
class _ShotLibbox implements LibboxService {
  const _ShotLibbox({
    this.groups = const <OutboundGroup>[],
    this.connections = const <ConnectionEntry>[],
  });

  final List<OutboundGroup> groups;
  final List<ConnectionEntry> connections;

  @override
  bool get available => true;

  @override
  String? get lastError => null;

  @override
  Stream<LibboxLogLine> get logs => const Stream<LibboxLogLine>.empty();

  @override
  Stream<void> get logsCleared => const Stream<void>.empty();

  @override
  Future<List<OutboundGroup>> getGroups() async => groups;

  @override
  Future<List<ConnectionEntry>> getConnections() async => connections;

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

/// پل ساختگی که فقط فهرست برنامه‌ها را پاسخ می‌دهد.
class _ShotBridge extends StubBridge {
  _ShotBridge(this._packages);

  final List<AppPackage> _packages;

  @override
  Future<List<AppPackage>> listInstalledPackages({
    bool includeSystem = false,
  }) async =>
      _packages;
}

Future<void> _shot(WidgetTester tester, String name) async {
  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home — desktop dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 820),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
    );
    await _shot(tester, '01_home_desktop_dark_fa');
  });

  testWidgets('home — desktop light (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 820),
      theme: ThemeModePref.light,
      lang: AppLang.fa,
    );
    await _shot(tester, '02_home_desktop_light_fa');
  });

  testWidgets('home — desktop dark (en)', (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 820),
      theme: ThemeModePref.dark,
      lang: AppLang.en,
    );
    await _shot(tester, '03_home_desktop_dark_en');
  });

  testWidgets('home — mobile dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(430, 860),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
    );
    await _shot(tester, '04_home_mobile_dark_fa');
  });

  testWidgets('drawer open — mobile dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(430, 860),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
    );
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
    await _shot(tester, '05_drawer_mobile_dark_fa');
  });

  testWidgets('settings — mobile dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(430, 860),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
    );
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();
    await _shot(tester, '06_settings_mobile_dark_fa');
  });

  testWidgets('profiles — desktop dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 820),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
    );
    await tester.tap(find.text('پروفایل‌ها'));
    await tester.pumpAndSettle();
    await _shot(tester, '07_profiles_desktop_dark_fa');
  });

  testWidgets('cores — desktop dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 820),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
    );
    await tester.tap(find.text('هسته‌ها'));
    await tester.pumpAndSettle();
    await _shot(tester, '08_cores_desktop_dark_fa');
  });

  testWidgets('network — desktop dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 820),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
      libbox: const _ShotLibbox(
        groups: _demoGroups,
        connections: _demoConnections,
      ),
    );
    await tester.tap(find.text('شبکه'));
    await tester.pumpAndSettle();
    await _shot(tester, '09_network_desktop_dark_fa');
  });

  testWidgets('network connections — desktop dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 820),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
      libbox: const _ShotLibbox(
        groups: _demoGroups,
        connections: _demoConnections,
      ),
    );
    await tester.tap(find.text('شبکه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اتصال‌ها'));
    await tester.pumpAndSettle();
    await _shot(tester, '10_network_connections_desktop_dark_fa');
  });

  testWidgets('per-app proxy — mobile dark (fa)', (tester) async {
    await _pump(
      tester,
      size: const Size(430, 860),
      theme: ThemeModePref.dark,
      lang: AppLang.fa,
      libbox: const _ShotLibbox(),
      bridge: _ShotBridge(_demoPackages),
      packages: _demoPackages,
      perAppEnabled: true,
    );
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تنظیمات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مسیریابیِ هر برنامه').last);
    await tester.pumpAndSettle();
    await _shot(tester, '09_per_app_mobile_dark_fa');
  });
}