import 'dart:convert';

import 'package:overx/core/stats/clash_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// پاسخِ نمونه‌ی `GET /proxies` (شکلِ واقعیِ Clash/mihomo که sing-box هم
/// همان را تولید می‌کند).
const _proxiesJson = '''
{
  "proxies": {
    "GLOBAL": {
      "type": "Selector",
      "now": "node-eu",
      "all": ["node-eu", "node-us", "DIRECT"],
      "history": []
    },
    "auto": {
      "type": "URLTest",
      "now": "node-eu",
      "all": ["node-eu", "node-us"]
    },
    "node-eu": {
      "type": "Vmess",
      "history": [{"time": "2026-10-06T10:00:00.000Z", "delay": 138}]
    },
    "node-us": {
      "type": "Trojan",
      "history": [{"time": "2026-10-06T09:00:00.000Z", "delay": 0}]
    },
    "DIRECT": {"type": "Direct", "history": []}
  }
}
''';

/// پاسخِ نمونه‌ی `GET /connections`.
const _connectionsJson = '''
{
  "downloadTotal": 3145728,
  "uploadTotal": 102400,
  "connections": [
    {
      "id": "aaaa-1111",
      "metadata": {
        "network": "tcp",
        "type": "HTTP",
        "sourceIP": "127.0.0.1",
        "sourcePort": "51234",
        "destinationIP": "172.217.16.14",
        "destinationPort": "443",
        "host": "google.com",
        "processPath": "/usr/bin/curl",
        "dnsMode": "normal"
      },
      "upload": 2048,
      "download": 1048576,
      "start": "2026-10-06T10:00:00.000Z",
      "chains": ["node-eu"],
      "rule": "RuleSet",
      "rulePayload": "geosite"
    },
    {
      "id": "",
      "metadata": {},
      "chains": []
    },
    {
      "id": "bbbb-2222",
      "metadata": {
        "network": "udp",
        "type": "QUIC",
        "destinationIP": "1.1.1.1",
        "destinationPort": "443",
        "host": ""
      },
      "upload": 0,
      "download": 12,
      "start": "2026-10-06T10:00:01.000Z",
      "chains": []
    }
  ]
}
''';

void main() {
  group('ساختِ URI', () {
    test('آدرسِ محلی با پورتِ تنظیمات', () {
      final api = ClashApi(port: 9090);
      expect(api.uri('/proxies').toString(), 'http://127.0.0.1:9090/proxies');
      expect(
        api.uri('/connections').toString(),
        'http://127.0.0.1:9090/connections',
      );
    });

    test('پارامترهایِ سنجشِ تأخیر', () {
      final api = ClashApi(port: 9999);
      final u = api.uri(
        '/proxies/node eu/delay',
        <String, String>{'url': kClashTestUrl, 'timeout': '5000'},
      );
      expect(u.host, '127.0.0.1');
      expect(u.port, 9999);
      expect(u.queryParameters['timeout'], '5000');
    });
  });

  group('تجزیه‌ی گروه‌ها', () {
    final groups = parseClashProxies(jsonDecode(_proxiesJson));

    test('فقط کلیدهایی که `all` دارند گروه‌اند', () {
      // DIRECT کلیدِ all ندارد، پس گروه نیست
      expect(groups.map((g) => g.tag), <String>['GLOBAL', 'auto']);
    });

    test('نوعِ گروه به حروفِ کوچک می‌آید', () {
      expect(groups.first.type, 'selector');
      expect(groups.last.type, 'urltest');
    });

    test('گروه‌های انتخاب‌پذیر درست مشخص می‌شوند', () {
      expect(groups.first.selectable, true); // Selector
      expect(groups.last.selectable, true); // URLTest
    });

    test('خروجیِ انتخاب‌شده (`now`) درست است', () {
      expect(groups.first.selected, 'node-eu');
      expect(groups.first.selectedItem?.tag, 'node-eu');
    });

    test('تأخیرِ تست‌شده خوانده می‌شود', () {
      final eu = groups.first.items.first;
      expect(eu.tag, 'node-eu');
      expect(eu.type, 'Vmess');
      expect(eu.tested, true);
      expect(eu.urlTestDelay, 138);
      expect(eu.delayText, '138 ms');
    });

    test('تأخیرِ صفر یعنی «تست نشده»', () {
      final us = groups.first.items[1];
      expect(us.tag, 'node-us');
      expect(us.tested, false);
      expect(us.delayText, '—');
    });

    test('ایتمِ بدون history هم ساخته می‌شود', () {
      final direct = groups.first.items[2];
      expect(direct.tag, 'DIRECT');
      expect(direct.type, 'Direct');
      expect(direct.tested, false);
    });

    test('نوع با حرفِ کوچک هم انتخاب‌پذیر است', () {
      // بعضی کلاینت‌ها/نسخه‌ها type را کوچک می‌فرستند
      final list = parseClashProxies(<String, Object?>{
        'proxies': <String, Object?>{
          'g': <String, Object?>{
            'type': 'selector',
            'now': 'n1',
            'all': <Object?>['n1'],
          },
        },
      });
      expect(list.single.selectable, true);
      expect(list.single.type, 'selector');
    });

    test('Direct/Reject انتخاب‌پذیر نیستند', () {
      final list = parseClashProxies(<String, Object?>{
        'proxies': <String, Object?>{
          'd': <String, Object?>{'type': 'Direct', 'all': <Object?>['x']},
        },
      });
      expect(list.single.selectable, false);
    });

    test('ورودی‌هایِ بد فرو نمی‌ریزند', () {
      expect(parseClashProxies(null), isEmpty);
      expect(parseClashProxies('x'), isEmpty);
      expect(parseClashProxies(<String, Object?>{'proxies': 'nope'}), isEmpty);
      expect(parseClashProxies(<String, Object?>{'other': 1}), isEmpty);
    });

    test('گروهی که ایتمش در نگاشت نیست، باز هم می‌آید', () {
      final list = parseClashProxies(<String, Object?>{
        'proxies': <String, Object?>{
          'g': <String, Object?>{
            'type': 'Selector',
            'now': '',
            'all': <Object?>['ghost'],
          },
        },
      });
      expect(list.single.items.single.tag, 'ghost');
      expect(list.single.items.single.type, '');
    });
  });

  group('تجزیه‌ی اتصال‌ها', () {
    final list = parseClashConnections(jsonDecode(_connectionsJson));

    test('اتصالِ بدون id رد می‌شود', () {
      expect(list.length, 2);
    });

    test('خروجی از chains می‌آید', () {
      expect(list.first.outbound, 'node-eu');
      // chains خالی یعنی نامعلوم
      expect(list.last.outbound, '');
    });

    test('مقصد و منبع درست ترکیب می‌شوند', () {
      expect(list.first.destination, '172.217.16.14:443');
      expect(list.first.source, '127.0.0.1:51234');
    });

    test('دامنه مقدم است وگرنه آدرس', () {
      expect(list.first.domain, 'google.com');
      expect(list.first.displayDestination, 'google.com');
      expect(list.last.displayDestination, '1.1.1.1:443');
    });

    test('ترافیک تجمعی است و زمان درست می‌آید', () {
      expect(list.first.uplinkTotal, 2048);
      expect(list.first.downlinkTotal, 1048576);
      expect(list.first.totalText, '1 MB');
      expect(list.first.createdAt, greaterThan(0));
      // سرور فقط اتصال‌های باز را می‌فرستد
      expect(list.first.closedAt, 0);
      expect(list.first.isClosed, false);
    });

    test('مسیرِ فرآیند منتقل می‌شود', () {
      expect(list.first.processPath, '/usr/bin/curl');
      expect(list.last.processPath, '');
    });

    test('ورودی‌هایِ بد فرو نمی‌ریزند', () {
      expect(parseClashConnections(null), isEmpty);
      expect(parseClashConnections(<String, Object?>{'connections': 5}), isEmpty);
      expect(
        parseClashConnections(<String, Object?>{
          'connections': <Object?>['not a map', null],
        }),
        isEmpty,
      );
    });
  });
}
