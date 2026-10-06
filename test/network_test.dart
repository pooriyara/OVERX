import 'package:shared_preferences/shared_preferences.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'dart:convert';

import 'package:overx/core/models/network.dart';
import 'package:overx/core/stats/clash_api.dart';
import 'package:overx/core/stats/network_source.dart';
import 'package:overx/core/storage/repositories.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:overx/ui/network/network_page.dart';

const _channel = MethodChannel('com.overx/libbox');

/// سرویسِ libbox ی قلابی که فقط گروه‌ها و اتصال‌ها را جواب می‌دهد.
///
/// از [UnavailableLibboxService] ارث می‌بریم تا مجبور نباشیم همه‌ی اعضای
/// اینترفیس را دوباره بنویسیم.
class _FakeNetworkLibbox extends UnavailableLibboxService {
  _FakeNetworkLibbox({
    this.groups = const <OutboundGroup>[],
    this.connections = const <ConnectionEntry>[],
  });

  final List<OutboundGroup> groups;
  final List<ConnectionEntry> connections;
  final List<String> calls = <String>[];

  @override
  bool get available => true;

  @override
  Future<List<OutboundGroup>> getGroups() async => groups;

  @override
  Future<List<ConnectionEntry>> getConnections() async => connections;

  @override
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) async {
    calls.add('select:$groupTag:$outboundTag');
  }

  @override
  Future<void> urlTest(String outboundTag) async {
    calls.add('urlTest:$outboundTag');
  }

  @override
  Future<void> closeConnection(String id) async {
    calls.add('close:$id');
  }

  @override
  Future<void> closeConnections() async {
    calls.add('closeAll');
  }
}

OutboundGroup _group({
  String tag = 'proxy',
  String type = 'selector',
  bool selectable = true,
  String selected = 'node-a',
  List<OutboundItem> items = const <OutboundItem>[],
}) =>
    OutboundGroup(
      tag: tag,
      type: type,
      selectable: selectable,
      selected: selected,
      items: items.isNotEmpty
          ? items
          : const <OutboundItem>[
              OutboundItem(tag: 'node-a', type: 'shadowsocks'),
              OutboundItem(tag: 'node-b', type: 'vless'),
            ],
    );

/// منبعِ قلابی برای تستِ خودِ صفحه (بدون نیاز به هسته یا وب‌سرور).
class _FakeNetworkSource implements NetworkSource {
  _FakeNetworkSource({
    this.groups = const <OutboundGroup>[],
    this.connections = const <ConnectionEntry>[],
  });

  final List<OutboundGroup> groups;

  final List<ConnectionEntry> connections;

  final List<String> calls = <String>[];

  @override
  NetworkSourceKind get kind => NetworkSourceKind.clash;

  @override
  Future<List<OutboundGroup>> getGroups() async => groups;

  @override
  Future<List<ConnectionEntry>> getConnections() async => connections;

  @override
  Future<void> selectOutbound({
    required String groupTag,
    required String outboundTag,
  }) async {
    calls.add('select:$groupTag:$outboundTag');
  }

  @override
  Future<void> urlTest(String outboundTag) async {
    calls.add('urlTest:$outboundTag');
  }

  @override
  Future<void> closeConnection(String id) async {
    calls.add('close:$id');
  }

  @override
  Future<void> closeConnections() async {
    calls.add('closeAll');
  }
}

/// یک اتصالِ نمونه برای تستِ صفحه.
const ConnectionEntry _sampleConnection = ConnectionEntry(
  id: '1',
  outbound: 'proxy',
  protocol: 'tcp',
  network: 'tcp',
  destination: '1.2.3.4:443',
  domain: 'example.com',
  source: '127.0.0.1:5555',
  uplinkTotal: 2048,
  downlinkTotal: 1024,
  createdAt: 0,
  closedAt: 0,
);

/// پاسخِ نمونه‌ی Clash API برای سناریویِ دسکتاپ.
const String _clashProxies = """
{
  "proxies": {
    "GLOBAL": {
      "type": "Selector",
      "now": "node-eu",
      "all": ["node-eu", "node-us"]
    },
    "node-eu": {
      "type": "Vmess",
      "history": [{"time": "2026-10-06T10:00:00.000Z", "delay": 138}]
    },
    "node-us": {"type": "Trojan", "history": []}
  }
}
""";

const String _clashConnections = """
{
  "connections": [
    {
      "id": "a1",
      "metadata": {
        "network": "tcp",
        "type": "HTTP",
        "sourceIP": "127.0.0.1",
        "sourcePort": "51234",
        "destinationIP": "172.217.16.14",
        "destinationPort": "443",
        "host": "google.com"
      },
      "upload": 2048,
      "download": 1048576,
      "start": "2026-10-06T10:00:00.000Z",
      "chains": ["node-eu"]
    }
  ]
}
""";

ConnectionEntry _connection() => _sampleConnection;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------- مدل
  group('OutboundItem', () {
    test('تأخیرِ تست‌نشده «—» است', () {
      const item = OutboundItem(tag: 'a', type: 'vless');
      expect(item.tested, false);
      expect(item.delayText, '—');
    });

    test('تأخیرِ تست‌شده به میلی‌ثانیه نمایش داده می‌شود', () {
      const item = OutboundItem(
        tag: 'a',
        type: 'vless',
        urlTestDelay: 128,
        urlTestTime: 1700000000000,
      );
      expect(item.tested, true);
      expect(item.delayText, '128 ms');
    });

    test('JSON رفت‌وبرگشت می‌کند', () {
      const item = OutboundItem(
        tag: 'a',
        type: 'vless',
        urlTestDelay: 12,
        urlTestTime: 34,
      );
      final restored = OutboundItem.fromJson(item.toJson());
      expect(restored.tag, item.tag);
      expect(restored.urlTestDelay, 12);
      expect(restored.urlTestTime, 34);
    });
  });

  group('OutboundGroup', () {
    test('ایتمِ انتخاب‌شده پیدا می‌شود', () {
      final g = _group();
      expect(g.selectedItem?.tag, 'node-a');
    });

    test('وقتی انتخاب‌شده در فهرست نیست، null است', () {
      final g = _group(selected: 'ghost');
      expect(g.selectedItem, isNull);
    });

    test('تعدادِ ایتم‌ها درست شمرده می‌شود', () {
      expect(_group().items.length, 2);
    });

    test('JSON رفت‌وبرگشت می‌کند', () {
      final g = _group();
      final restored = OutboundGroup.fromJson(g.toJson());
      expect(restored.tag, 'proxy');
      expect(restored.type, 'selector');
      expect(restored.selectable, true);
      expect(restored.selected, 'node-a');
      expect(restored.items.map((i) => i.tag), ['node-a', 'node-b']);
    });
  });

  group('ConnectionEntry', () {
    test('مقصد: دامنه مقدم بر آدرس است', () {
      const withDomain = ConnectionEntry(
        id: '1',
        outbound: 'proxy',
        protocol: 'tcp',
        network: 'tcp',
        destination: '1.2.3.4:443',
        domain: 'example.com',
        source: '127.0.0.1:1234',
        uplinkTotal: 0,
        downlinkTotal: 0,
        createdAt: 0,
        closedAt: 0,
      );
      expect(withDomain.displayDestination, 'example.com');

      const withoutDomain = ConnectionEntry(
        id: '2',
        outbound: 'proxy',
        protocol: 'tcp',
        network: 'tcp',
        destination: '1.2.3.4:443',
        domain: '',
        source: '127.0.0.1:1234',
        uplinkTotal: 0,
        downlinkTotal: 0,
        createdAt: 0,
        closedAt: 0,
      );
      expect(withoutDomain.displayDestination, '1.2.3.4:443');
    });

    test('بسته‌بودن از closedAt فهمیده می‌شود', () {
      ConnectionEntry build(int closedAt) => ConnectionEntry(
            id: '1',
            outbound: 'proxy',
            protocol: 'tcp',
            network: 'tcp',
            destination: 'd',
            domain: '',
            source: 's',
            uplinkTotal: 0,
            downlinkTotal: 0,
            createdAt: 0,
            closedAt: closedAt,
          );
      expect(build(0).isClosed, false);
      expect(build(123).isClosed, true);
    });

    test('ترافیکِ صفر «—» و بقیه قالب‌بندی می‌شوند', () {
      ConnectionEntry build(int up, int down) => ConnectionEntry(
            id: '1',
            outbound: 'proxy',
            protocol: 'tcp',
            network: 'tcp',
            destination: 'd',
            domain: '',
            source: 's',
            uplinkTotal: up,
            downlinkTotal: down,
            createdAt: 0,
            closedAt: 0,
          );
      expect(build(0, 0).totalText, '—');
      // formatBytes با توانِ ۱۰۲۴ کار می‌کند و صفرِ انتهایی را حذف می‌کند
      expect(build(1024, 0).totalText, '1 KB');
    });
  });

  // ------------------------------------------------------- رمزگشایی
  group('رمزگشاییِ پاسخِ کانال', () {
    test('ایتم‌های بی‌نام حذف می‌شوند', () {
      final list = decodeGroups(<Object?>[
        <Object?, Object?>{
          'tag': 'ok',
          'items': <Object?>[
            <Object?, Object?>{'tag': 'a', 'type': 'x'},
            <Object?, Object?>{'type': 'بدون نام'},
          ],
        },
        <Object?, Object?>{'type': 'بدون تگ'},
      ]);
      expect(list.length, 1);
      expect(list.single.items.length, 1);
    });

    test('پاسخِ null فهرستِ خالی می‌دهد', () {
      expect(decodeGroups(null), isEmpty);
      expect(decodeConnections(null), isEmpty);
    });

    test('اتصالِ بدون id حذف می‌شود', () {
      final list = decodeConnections(<Object?>[
        <Object?, Object?>{'id': '1', 'outbound': 'proxy'},
        <Object?, Object?>{'outbound': 'proxy'},
      ]);
      expect(list.length, 1);
    });

    test('اعدادِ بزرگ (int64) درست می‌آیند', () {
      final list = decodeConnections(<Object?>[
        <Object?, Object?>{
          'id': '1',
          'uplinkTotal': 9007199254740993, // بزرگ‌تر از ۵۳ بیتِ JS
          'downlinkTotal': 0,
        },
      ]);
      expect(list.single.uplinkTotal, 9007199254740993);
    });
  });

  // ------------------------------------------------------------ سرویس
  group('MethodChannelLibboxService', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
    });

    void mock(Object? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => handler(call));
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('getGroups نامِ متد و مدل را درست برمی‌گرداند', () async {
      mock((call) {
        calls.add(call);
        return <Object?>[
          <Object?, Object?>{
            'tag': 'proxy',
            'type': 'selector',
            'selectable': true,
            'selected': 'node-a',
            'items': <Object?>[
              <Object?, Object?>{'tag': 'node-a', 'type': 'vless'},
            ],
          },
        ];
      });

      final svc = MethodChannelLibboxService(channel: _channel);
      final groups = await svc.getGroups();

      expect(calls.single.method, 'getGroups');
      expect(groups.single.tag, 'proxy');
      expect(groups.single.selectedItem?.tag, 'node-a');
    });

    test('selectOutbound آرگومان‌ها را می‌فرستد', () async {
      mock((call) {
        calls.add(call);
        return true;
      });

      final svc = MethodChannelLibboxService(channel: _channel);
      await svc.selectOutbound(groupTag: 'proxy', outboundTag: 'node-b');

      expect(calls.single.method, 'selectOutbound');
      expect(calls.single.arguments, <String, Object?>{
        'groupTag': 'proxy',
        'outboundTag': 'node-b',
      });
    });

    test('urlTest / closeConnection / closeConnections', () async {
      mock((call) {
        calls.add(call);
        return true;
      });

      final svc = MethodChannelLibboxService(channel: _channel);
      await svc.urlTest('node-a');
      await svc.closeConnection('id-7');
      await svc.closeConnections();

      expect(calls.map((c) => c.method), [
        'urlTest',
        'closeConnection',
        'closeConnections',
      ]);
      expect(calls[0].arguments, <String, Object?>{'outboundTag': 'node-a'});
      expect(calls[1].arguments, <String, Object?>{'id': 'id-7'});
    });
  });

  // -------------------------------------------------------------- رابط
  group('صفحه‌ی شبکه', () {
    Future<void> pumpPage(WidgetTester tester, NetworkSource source) async {
      // صفحه زبان را از تنظیمات می‌خواند، پس مخزن را هم override می‌کنیم
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
            profileRepositoryProvider.overrideWithValue(ProfileRepository(prefs)),
            networkSourceProvider.overrideWithValue(source),
          ],
          child: MaterialApp(
            // صفحه خودش Scaffold ندارد (مثل Logs/Cores) و در برنامه داخل
            // Scaffold ی AppShell نشسته؛ اینجا همان را شبیه‌سازی می‌کنیم.
            home: const Scaffold(
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: NetworkPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('گروه‌ها و اتصال‌ها از libbox نمایش داده می‌شوند', (tester) async {
      final libbox = _FakeNetworkLibbox(
        groups: <OutboundGroup>[_group()],
        connections: <ConnectionEntry>[_connection()],
      );
      await pumpPage(tester, LibboxNetworkSource(libbox));

      // تبِ پیش‌فرض «گروه‌ها» است
      expect(find.text('گروه‌ها'), findsOneWidget);
      expect(find.text('اتصال‌ها'), findsOneWidget);
      expect(find.text('proxy'), findsWidgets);
      expect(tester.takeException(), isNull);

      // TabBarView فقط تبِ فعلی را می‌سازد، پس باید عوضش کنیم
      await tester.tap(find.text('اتصال‌ها'));
      await tester.pumpAndSettle();
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('داده‌ی دسکتاپ (Clash API) هم نمایش داده می‌شود', (tester) async {
      final source = _FakeNetworkSource(
        groups: parseClashProxies(jsonDecode(_clashProxies)),
        connections: parseClashConnections(jsonDecode(_clashConnections)),
      );
      await pumpPage(tester, source);

      expect(find.text('GLOBAL'), findsWidgets);
      expect(find.textContaining('138 ms'), findsOneWidget);

      await tester.tap(find.text('اتصال‌ها'));
      await tester.pumpAndSettle();
      expect(find.text('google.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('نبودِ منبع پیام می‌دهد (هسته خاموش)', (tester) async {
      await pumpPage(
        tester,
        const UnavailableNetworkSource(NetworkUnavailableReason.coreStopped),
      );
      expect(find.text('داده‌ای در دسترس نیست'), findsOneWidget);
      expect(find.textContaining('وقتی هسته متصل باشد'), findsOneWidget);
    });

    testWidgets('برای Xray پیامِ مخصوص خودش می‌آید', (tester) async {
      await pumpPage(
        tester,
        const UnavailableNetworkSource(NetworkUnavailableReason.xray),
      );
      expect(find.text('داده‌ای در دسترس نیست'), findsOneWidget);
      expect(find.textContaining('Xray'), findsOneWidget);
    });

    testWidgets('بستنِ همه فراخوانی می‌شود', (tester) async {
      final libbox = _FakeNetworkLibbox(
        connections: <ConnectionEntry>[_connection()],
      );
      await pumpPage(tester, LibboxNetworkSource(libbox));

      await tester.tap(find.text('اتصال‌ها'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('بستن همه‌ی اتصال‌ها'));
      await tester.pumpAndSettle();

      expect(libbox.calls, contains('closeAll'));
    });
  });
}
