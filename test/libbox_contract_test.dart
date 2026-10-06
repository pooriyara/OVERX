import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// قراردادِ libbox — تأییدِ چیزی که **بدون دستگاه** می‌توان تأیید کرد.
///
/// چرا این فایل وجود دارد؟
/// چون لایه‌ی اندروید هیچ‌وقت کامپایل نشده (نداشتنِ `libbox.aar`) و بدترین
/// نوعِ باگ اینجاست: کدی که کاملاً معقول به نظر می‌رسد اما با اولین کامپایلِ
/// واقعی فرو می‌ریزد، یا بدتر — کامپایل می‌شود ولی سوکتِ فرمان بالا نمی‌آید.
///
/// حقایقِ اینجا از **سورسِ واقعیِ sing-box v1.14.2** استخراج شده‌اند
/// (آدرسِ هر کدام بالای هر مجموعه نوشته شده) و از روی
/// `golang/mobile/bind/genjava.go` نگاشت شده‌اند به جاوا:
///
///   * اینترفیسِ Go ⇒ `public interface` جاوا (نه کلاسِ abstract)
///   * نامِ متد = حرفِ اولِ کوچک (`OpenTun` → `openTun`)
///   * خروجیِ `(T, error)` ⇒ جاوا `T` + throws
///   * خروجیِ `error` ⇒ جاوا **`void`** + throws
///   * فیلدِ ساختارِ Go ⇒ `get<Field>()/set<Field>()` با نامِ دست‌نخورده
///
/// این تست فقط «هماهنگیِ دو طرف» را قفل می‌کند؛ اثباتِ صحتِ رفتار در زمانِ
/// اجرا روی دستگاه هنوز باقی است (نگاه کن به docs/LIBBOX_CONTRACT.md).

const _kLibboxVpnService =
    'android/app/src/main/kotlin/com/overx/overx/LibboxVpnService.kt';
const _kLibboxPlatformInterface =
    'android/app/src/main/kotlin/com/overx/overx/LibboxPlatformInterface.kt';
const _kCoreCommandClient =
    'android/app/src/main/kotlin/com/overx/overx/CoreCommandClient.kt';

String _read(String path) {
  final file = File(path);
  if (file.existsSync()) return file.readAsStringSync();
  final alt = File('${Directory.current.path}/$path');
  if (alt.existsSync()) return alt.readAsStringSync();
  fail('فایل پیدا نشد: $path (cwd=${Directory.current.path})');
}

/// نامِ متدهایی که یک کلاسِ کاتلین با `override fun …` پیاده‌سازی کرده.
Set<String> _kotlinOverrides(String source) => RegExp(
      r'override fun (\w+)\s*\(',
    ).allMatches(source).map((m) => m.group(1)!).toSet();

/// بخشی از فایل را بین دو نشانگر می‌برد.
///
/// چرا لازم است؟ چون `LibboxVpnService` علاوه بر `CommandServerHandler`
/// متدهای چرخه‌ی حیاتِ `VpnService` را هم override می‌کند و
/// `LibboxPlatformInterface` در انتها دو کلاسِ کمکی دارد؛ اگر کلِ فایل را
/// بگیریم، مقایسه بی‌دلیل شکست می‌خورد.
String _section(String source, String start, String end) {
  final a = source.indexOf(start);
  expect(a, greaterThanOrEqualTo(0), reason: 'نشانگر پیدا نشد: $start');
  final b = source.indexOf(end, a);
  expect(b, greaterThan(a), reason: 'نشانگرِ پایان پیدا نشد: $end');
  return source.substring(a, b);
}

/// توضیحات را حذف می‌کند تا متنِ داخلِ کامنت باعثِ تطابقِ ناخواسته نشود.
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// آیا [name] در کاتلین «بدون نوعِ خروجی» تعریف شده؟ (یعنی `Unit`/`void` است)
///
/// پارامترها خودشان `:` دارند، پس پرانتزِ باز و بسته را با شمارشِ عمق پیدا
/// می‌کنیم و بعد می‌بینیم بلافاصله بعد از پرانتزِ بسته چه آمده.
bool _returnsUnit(String source, String name) {
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
      after.startsWith('//') ||
      after.startsWith('\n');
}

// --------------------------------------------------------------------- Go 1.14.2

/// `experimental/libbox/command_client.go` → `type CommandClientHandler interface`
const goCommandClientHandler = <String>{
  'connected',
  'disconnected',
  'setDefaultLogLevel',
  'clearLogs',
  'writeLogs',
  'writeStatus',
  'writeGroups',
  'writeOutbounds',
  'initializeClashMode',
  'updateClashMode',
  'writeConnectionEvents',
};

/// `experimental/libbox/command_server.go` → `type CommandServerHandler interface`
const goCommandServerHandler = <String>{
  'serviceStop',
  'serviceReload',
  'getSystemProxyStatus',
  'setSystemProxyEnabled',
  'triggerNativeCrash',
  'writeDebugMessage',
  'connectSSHAgent',
};

/// `experimental/libbox/platform.go` → `type PlatformInterface interface`
const goPlatformInterface = <String>{
  'localDNSTransport',
  'usePlatformAutoDetectInterfaceControl',
  'autoDetectInterfaceControl',
  'openTun',
  'useProcFS',
  'findConnectionOwner',
  'startDefaultInterfaceMonitor',
  'closeDefaultInterfaceMonitor',
  'getInterfaces',
  'underNetworkExtension',
  'includeAllNetworks',
  'readWIFIState',
  'clearDNSCache',
  'sendNotification',
  'cancelNotification',
  'startNeighborMonitor',
  'closeNeighborMonitor',
  'registerMyInterface',
  'usePlatformShell',
  'checkPlatformShell',
  'openShellSession',
  'lookupUser',
  'lookupSFTPServer',
  'readSystemSSHHostKey',
  'tailscaleHostname',
  'usePlatformBridge',
  'createBridge',
};

/// `experimental/libbox/command.go` → `const ( CommandLog int32 = iota … )`
const goCommandValues = <String, int>{
  'COMMAND_LOG': 0,
  'COMMAND_STATUS': 1,
  'COMMAND_GROUP': 2,
  'COMMAND_CLASH_MODE': 3,
  'COMMAND_CONNECTIONS': 4,
  'COMMAND_OUTBOUNDS': 5,
};

/// متدهای Go که تنها خروجی‌شان `error` است ⇒ در جاوا `void` می‌شوند.
/// (هر بار که اینترفیس عوض شود باید این فهرست هم به‌روز شود.)
const goErrorOnlyMethods = <String>{
  'autoDetectInterfaceControl',
  'checkPlatformShell',
  'startDefaultInterfaceMonitor',
  'closeDefaultInterfaceMonitor',
  'startNeighborMonitor',
  'closeNeighborMonitor',
  'sendNotification',
  'cancelNotification',
};

void main() {
  group('اینترفیس‌هایی که جاوا باید پیاده کند', () {
    test('CommandClientHandler: ۱۱ متد، دقیقاً همین‌ها', () {
      final impl = _kotlinOverrides(_read(_kCoreCommandClient));
      expect(
        goCommandClientHandler.difference(impl),
        isEmpty,
        reason: 'این متدها در CoreCommandClient پیاده نشده‌اند؛ '
            'با AARِ واقعی کامپایل نمی‌شود',
      );
      expect(
        impl.difference(goCommandClientHandler),
        isEmpty,
        reason: 'متدهایی override شده‌اند که در اینترفیسِ Go نیستند',
      );
    });

    test('CommandServerHandler: ۷ متدِ LibboxVpnService', () {
      final impl = _kotlinOverrides(
        _section(
          _read(_kLibboxVpnService),
          'پیاده‌سازی CommandServerHandler',
          'اعلان',
        ),
      );
      expect(
        goCommandServerHandler.difference(impl),
        isEmpty,
        reason: 'CommandServerHandler ناقص است',
      );
      expect(
        impl.difference(goCommandServerHandler),
        isEmpty,
        reason: 'در این بخش override ای خارج از اینترفیس هست',
      );
    });

    test('PlatformInterface: ۲۷ متدِ LibboxPlatformInterface', () {
      final impl = _kotlinOverrides(
        _section(
          _read(_kLibboxPlatformInterface),
          'PlatformInterface {',
          'ابزارهای کمکی',
        ),
      );
      expect(
        goPlatformInterface.difference(impl),
        isEmpty,
        reason: 'اینترفیسِ Go در نسخه‌ی ۱.۱۴.۲ این متدها را هم دارد',
      );
      expect(impl.difference(goPlatformInterface), isEmpty);
    });

    test('متدهای error-only باید void (Unit) باشند', () {
      final src = _read(_kLibboxPlatformInterface);
      for (final name in goErrorOnlyMethods) {
        expect(
          _returnsUnit(src, name),
          isTrue,
          reason: '$name در Go تنها error برمی‌گرداند؛ امضای جاوا void است و '
              'کاتلین نباید نوعِ خروجی داشته باشد',
        );
      }
    });
  });

  group('اینترفیس‌های Go در جاوا interface می‌شوند، نه کلاس', () {
    // bind/genjava.go → g.Printf("public interface %s", …)
    // یعنی در کاتلین باید `: StringIterator` نوشت نه `: StringIterator()`.
    test('هیچ اینترفیسی با پرانتز پیاده‌سازی نشده', () {
      final src = _stripComments(_read(_kLibboxPlatformInterface));
      expect(
        RegExp(r':\s*(StringIterator|NetworkInterfaceIterator|PlatformInterface'
                r'|CommandClientHandler|CommandServerHandler)\s*\(\s*\)')
            .allMatches(src),
        isEmpty,
        reason: 'اینترفیس سازنده ندارد؛ پرانتز باعث خطای کامپایل می‌شود',
      );
    });

    test('StringIterator هم len() دارد هم hasNext()', () {
      // experimental/libbox/iterator.go در ۱.۱۴.۲:
      //   type StringIterator interface { Len() int32; HasNext() bool; Next() string }
      final src = _read(_kLibboxPlatformInterface);
      final block = src.substring(src.indexOf('class StringArray'));
      expect(block, contains('override fun len()'));
      expect(block, contains('override fun hasNext()'));
      expect(block, contains('override fun next()'));
    });

    test('NetworkInterfaceIterator فقط next/hasNext دارد (بدون len)', () {
      // experimental/libbox/platform.go:
      //   type NetworkInterfaceIterator interface { Next() *NetworkInterface; HasNext() bool }
      final src = _read(_kLibboxPlatformInterface);
      final block = src.substring(src.indexOf('class InterfaceArray'));
      expect(block, contains('override fun hasNext()'));
      expect(block, contains('override fun next()'));
      expect(block, isNot(contains('override fun len()')));
    });
  });

  group('بالا آمدنِ gRPC روی command.sock', () {
    test('سوکت قبل از startOrReloadService گوش می‌دهد', () {
      // command_server.go → Start(): مسیر را os.Remove می‌کند، ListenUnix
      // می‌زند و `go grpcServer.Serve(listener)` را راه می‌اندازد — همه
      // **هم‌زمان** و قبل از برگشتن. پس تا وقتی ترتیبِ زیر رعایت شود،
      // کلاینت هرگز به سوکتی که هنوز ساخته نشده وصل نمی‌شود.
      final src = _read(_kLibboxVpnService);
      final startAt = src.indexOf('server.start()');
      final serviceAt = src.indexOf('startOrReloadService');
      expect(startAt, greaterThan(0));
      expect(serviceAt, greaterThan(startAt),
          reason: 'CommandServer.start() باید پیش از startOrReloadService '
              'باشد؛ وگرنه command.sock وجود ندارد و کلاینت شکست می‌خورد');
      // و کلاینت بعد از هر دو وصل می‌شود
      expect(src.indexOf('CoreCommandClient.start()'), greaterThan(serviceAt));
    });

    test('مسیرِ سوکت معلوم است: basePath ست شده و پورتی پیکربندی نشده', () {
      // هر دو سمت از filepath.Join(sBasePath, "command.sock") استفاده می‌کنند
      // (command_server.go و command_client.go). اگر CommandServerListenPort
      // صفر نباشد، هر دو به TCP روی 127.0.0.1 سوئیچ می‌کنند.
      final src = _read(_kLibboxVpnService);
      final setup = src.substring(src.indexOf('object LibboxSetup'));
      expect(setup, contains('basePath ='));
      expect(
        RegExp(r'commandServerListenPort\s*=', caseSensitive: false)
            .allMatches(src),
        isEmpty,
        reason: 'ست‌کردنِ پورت، سوکتِ یونیکس را دور می‌زند',
      );
    });

    test('کلاینت از سازنده‌ی handler-bound استفاده می‌کند (۱۰ تلاش)', () {
      // command_client.go: NewCommandClient ⇒ standalone=false ⇒
      // dialWithRetry با ۱۰ تلاش (در مجموع حدود ۳/۲ ثانیه مهلت).
      // NewStandaloneCommandClient ⇒ یک تلاشِ fail-fast.
      final src = _read(_kCoreCommandClient);
      expect(src, contains('Libbox.newCommandClient('));
      expect(src, isNot(contains('NewStandaloneCommandClient')));
    });

    test('شماره‌ی فرمان‌ها با enumِ Go یکی است', () {
      final src = _read(_kCoreCommandClient);
      for (final entry in goCommandValues.entries) {
        final m = RegExp('${entry.key}\\s*=\\s*(\\d+)').firstMatch(src);
        // ClashMode و Outbounds را استفاده نمی‌کنیم، پس تنها در صورتِ حضور
        // بررسی می‌شوند
        if (m == null) continue;
        expect(
          int.parse(m.group(1)!),
          entry.value,
          reason: '${entry.key} با experimental/libbox/command.go جور نیست',
        );
      }
      // آن‌هایی که واقعاً subscribe می‌شوند باید حتماً باشند
      for (final used in const ['COMMAND_LOG', 'COMMAND_STATUS', 'COMMAND_GROUP']) {
        expect(src, contains(used), reason: '$used باید تعریف شده باشد');
      }
    });
  });

  group('فیلدهایی که سمت Go خوانده می‌شوند', () {
    test('فاصله‌ی آمار یک ثانیه و به نانوثانیه است', () {
      // daemon.SubscribeStatus مقدار را مستقیماً به time.Duration می‌برد.
      expect(_read(_kCoreCommandClient), contains('1_000_000_000L'));
    });

    test('گروه‌ها از getItems می‌آیند و تأخیر با URL ی بزرگ خوانده می‌شود', () {
      // command_types.go:
      //   func (g *OutboundGroup) GetItems() OutboundGroupItemIterator
      //   type OutboundGroupItem struct { …; URLTestTime int64; URLTestDelay int32 }
      final src = _read(_kCoreCommandClient);
      expect(src, contains('getItems()'));
      expect(src, contains('getURLTestDelay()'));
      expect(src, contains('getURLTestTime()'));
    });
  });
}
