import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/app_package.dart';
import 'package:overx/core/models/network.dart';
import 'package:overx/core/platform/android_bridge.dart';
import 'package:overx/core/platform/app_icon_service.dart';
import 'package:overx/core/platform/desktop_bridge.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:overx/core/platform/stub_bridge.dart';
import 'package:overx/core/storage/repositories.dart';
import 'package:overx/ui/settings/per_app_page.dart';

/// یک PNGِ معتبرِ ۱×۱ (کوچک‌ترین تصویری که دیکدر قبول می‌کند).
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
]);

/// پلِ ساختگی که فقط [appIcon] و فهرستِ برنامه‌ها را واقعی جواب می‌دهد.
class _IconBridge extends StubBridge {
  _IconBridge({this.bytes, this.packages = const <AppPackage>[]});

  final Uint8List? bytes;
  final List<AppPackage> packages;

  /// هر درخواست را با اندازه‌اش ثبت می‌کنیم.
  final List<String> calls = <String>[];
  final List<int> sizes = <int>[];

  @override
  final PlatformFeatures features = PlatformFeatures(<PlatformFeature>{
    PlatformFeature.perAppProxy,
    PlatformFeature.vpnService,
  });

  @override
  Future<List<AppPackage>> listInstalledPackages({
    bool includeSystem = false,
  }) async =>
      packages;

  @override
  Future<Uint8List?> appIcon(String packageName, {int size = 64}) async {
    calls.add(packageName);
    sizes.add(size);
    return bytes;
  }
}

class _IconLibbox implements LibboxService {
  @override
  bool get available => true;

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

Future<void> _pumpPage(WidgetTester tester, PlatformBridge bridge) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        platformBridgeProvider.overrideWithValue(bridge),
        libboxServiceProvider.overrideWithValue(_IconLibbox()),
      ],
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: PerAppPage(),
        ),
      ),
    ),
  );
  await tester.pump();
  // واکشیِ فهرست + واکشیِ آیکون‌ها
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  // ------------------------------------------------------- سرویس و کش
  group('AppIconService', () {
    test('برای هر بسته فقط یک بار درخواست می‌فرستد', () async {
      final bridge = _IconBridge(bytes: _png);
      final service = AppIconService(bridge);

      await service.load('com.alpha');
      await service.load('com.alpha');
      await service.load('com.alpha');

      expect(bridge.calls, <String>['com.alpha']);
      expect(service.peek('com.alpha'), _png);
    });

    test('بسته‌های متفاوت جداگانه واکشی می‌شوند', () async {
      final bridge = _IconBridge(bytes: _png);
      final service = AppIconService(bridge);

      await service.load('com.alpha');
      await service.load('com.beta');

      expect(bridge.calls, <String>['com.alpha', 'com.beta']);
    });

    test('نبودِ آیکون هم کش می‌شود تا دوباره درخواست نرود', () async {
      final bridge = _IconBridge(bytes: null);
      final service = AppIconService(bridge);

      await service.load('com.alpha');
      await service.load('com.alpha');

      expect(bridge.calls, <String>['com.alpha']);
      expect(service.peek('com.alpha'), isNull);
    });

    test('درخواست‌های هم‌زمان برای یک بسته ادغام می‌شوند', () async {
      final bridge = _IconBridge(bytes: _png);
      final service = AppIconService(bridge);

      // هیچ‌کدام را await نمی‌کنیم: هر سه قبل از رسیدنِ پاسخ صدا زده می‌شوند
      await Future.wait(<Future<void>>[
        service.load('com.alpha'),
        service.load('com.alpha'),
        service.load('com.alpha'),
      ]);

      expect(bridge.calls, <String>['com.alpha']);
    });

    test('clear() کش را خالی می‌کند', () async {
      final bridge = _IconBridge(bytes: _png);
      final service = AppIconService(bridge);

      await service.load('com.alpha');
      service.clear();
      expect(service.peek('com.alpha'), isNull);

      await service.load('com.alpha');
      expect(bridge.calls, <String>['com.alpha', 'com.alpha']);
    });

    test('loadAll برای همه درخواست می‌فرستد', () async {
      final bridge = _IconBridge(bytes: _png);
      final service = AppIconService(bridge);

      await service.loadAll(<String>['com.a', 'com.b', 'com.c']);

      expect(bridge.calls, <String>['com.a', 'com.b', 'com.c']);
    });

    test('استثنای پل به بیرون نشت نمی‌کند', () async {
      final service = AppIconService(_ThrowingBridge());
      await service.load('com.boom');
      expect(service.peek('com.boom'), isNull);
    });
  });

  // ------------------------------------------------------------- پل‌ها
  group('پل‌ها', () {
    test('AndroidBridge متد و آرگومان‌های درست می‌فرستد', () async {
      final calls = <MethodCall>[];
      final bridge = AndroidBridge(
        channel: MethodChannel('com.overx/core')
          ..setMockMethodCallHandler((call) async {
            calls.add(call);
            return _png;
          }),
      );

      final out = await bridge.appIcon('com.alpha');

      expect(out, _png);
      expect(calls.single.method, 'appIcon');
      expect(calls.single.arguments, <String, Object?>{
        'packageName': 'com.alpha',
        'size': 64,
      });
    });

    test('AndroidBridge اندازه‌ی دلخواه را رد می‌کند', () async {
      final calls = <MethodCall>[];
      final bridge = AndroidBridge(
        channel: MethodChannel('com.overx/core')
          ..setMockMethodCallHandler((call) async {
            calls.add(call);
            return null;
          }),
      );

      await bridge.appIcon('com.alpha', size: 96);
      expect(calls.single.arguments?['size'], 96);
    });

    test('AndroidBridge خطای پلتفرم را به null تبدیل می‌کند', () async {
      final bridge = AndroidBridge(
        channel: MethodChannel('com.overx/core')
          ..setMockMethodCallHandler((call) async {
            throw PlatformException(code: 'nope', message: 'icon unavailable');
          }),
      );

      expect(await bridge.appIcon('com.alpha'), isNull);
      expect(bridge.lastError, contains('icon unavailable'));
    });

    test('دسکتاپ و وب آیکونی ندارند', () async {
      expect(await DesktopBridge().appIcon('com.alpha'), isNull);
      expect(await StubBridge().appIcon('com.alpha'), isNull);
    });
  });

  // ------------------------------------------------------------ رابط
  group('کاشیِ برنامه', () {
    testWidgets('آیکونِ موجود به صورت تصویر نشان داده می‌شود', (tester) async {
      final bridge = _IconBridge(
        bytes: _png,
        packages: const <AppPackage>[
          AppPackage(packageName: 'com.alpha', label: 'برنامه آلفا'),
        ],
      );
      await _pumpPage(tester, bridge);

      expect(bridge.calls, <String>['com.alpha']);
      // اندازه‌ی پیش‌فرضِ سرویس
      expect(bridge.sizes, <int>[kAppIconSize]);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('بدون آیکون، حرفِ اولِ نام جایگزین می‌شود', (tester) async {
      await _pumpPage(
        tester,
        _IconBridge(
          packages: const <AppPackage>[
            AppPackage(packageName: 'com.alpha', label: 'برنامه آلفا'),
            AppPackage(packageName: 'com.beta', label: 'Beta App'),
          ],
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('ب'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('فهرستِ خالی بدون خطا رندر می‌شود', (tester) async {
      await _pumpPage(tester, _IconBridge());
      expect(tester.takeException(), isNull);
    });
  });
}

/// پلی که همیشه پرتاب می‌کند — برای اطمینان از اینکه سرویس استثنا را می‌بلعد.
class _ThrowingBridge extends StubBridge {
  @override
  Future<Uint8List?> appIcon(String packageName, {int size = 64}) async {
    throw StateError('boom');
  }
}
