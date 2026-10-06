import 'dart:convert';

import 'package:overx/core/config/singbox_config_builder.dart';
import 'package:overx/core/config/xray_config_builder.dart';
import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/settings.dart';
import 'package:flutter_test/flutter_test.dart';

Profile vless() => Profile(
      id: 'p1',
      name: 'DE-Fra-01',
      protocol: ProfileProtocol.vless,
      address: 'fra1.example.net',
      port: 443,
      fields: const {
        'uuid': '11111111-2222-3333-4444-555555555555',
        'security': 'reality',
        'sni': 'www.microsoft.com',
        'publicKey': 'pubkey',
        'shortId': 'abcd1234',
        'flow': 'xtls-rprx-vision',
        'network': 'ws',
        'path': '/ws',
        'host': 'www.microsoft.com',
        'fingerprint': 'chrome',
      },
    );

const settings = AppSettings();

void main() {
  group('SingboxConfigBuilder', () {
    test('کانفیگ معتبر JSON تولید می‌کند', () {
      final json = SingboxConfigBuilder.build(
        profile: vless(),
        settings: settings,
      );
      final map = jsonDecode(json) as Map<String, dynamic>;
      expect(map['log'], isNotNull);
      expect(map['inbounds'], isA<List>());
      expect(map['outbounds'], isA<List>());
      expect(map['route'], isNotNull);
    });

    test('Clash API روی پورت تنظیمات گوش می‌دهد', () {
      final map = jsonDecode(
        SingboxConfigBuilder.build(
          profile: vless(),
          settings: settings.copyWith(singboxApiPort: 19090),
        ),
      ) as Map<String, dynamic>;
      final exp = map['experimental'] as Map<String, dynamic>;
      final clash = exp['clash_api'] as Map<String, dynamic>;
      expect(clash['external_controller'], '127.0.0.1:19090');
    });

    test('TUN در صورت فعال بودن اضافه می‌شود', () {
      final withTun = jsonDecode(
        SingboxConfigBuilder.build(
          profile: vless(),
          settings: settings.copyWith(tunMode: true),
        ),
      ) as Map<String, dynamic>;
      final types = (withTun['inbounds'] as List)
          .map((e) => (e as Map)['type'])
          .toList();
      expect(types, contains('tun'));

      final noTun = jsonDecode(
        SingboxConfigBuilder.build(
          profile: vless(),
          settings: settings.copyWith(tunMode: false),
        ),
      ) as Map<String, dynamic>;
      final types2 = (noTun['inbounds'] as List)
          .map((e) => (e as Map)['type'])
          .toList();
      expect(types2, isNot(contains('tun')));
      expect(types2, contains('mixed'));
    });

    test('خروجیِ vless فیلدهای درست دارد', () {
      final map = jsonDecode(
        SingboxConfigBuilder.build(profile: vless(), settings: settings),
      ) as Map<String, dynamic>;
      final proxy = (map['outbounds'] as List)
          .firstWhere((e) => (e as Map)['tag'] == 'proxy') as Map;
      expect(proxy['type'], 'vless');
      expect(proxy['server'], 'fra1.example.net');
      expect(proxy['server_port'], 443);
      expect(proxy['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(proxy['flow'], 'xtls-rprx-vision');

      final tls = proxy['tls'] as Map;
      expect(tls['enabled'], true);
      expect(tls['server_name'], 'www.microsoft.com');
      final reality = tls['reality'] as Map;
      expect(reality['enabled'], true);
      expect(reality['public_key'], 'pubkey');
      expect(reality['short_id'], 'abcd1234');

      final transport = proxy['transport'] as Map;
      expect(transport['type'], 'ws');
      expect(transport['path'], '/ws');
      expect((transport['headers'] as Map)['Host'], 'www.microsoft.com');
    });

    test('MUX فقط برای پروتکل‌های پشتیبانی‌شده', () {
      final mux = jsonDecode(
        SingboxConfigBuilder.build(
          profile: vless(),
          settings: settings.copyWith(mux: true),
        ),
      ) as Map<String, dynamic>;
      final proxy = (mux['outbounds'] as List)
          .firstWhere((e) => (e as Map)['tag'] == 'proxy') as Map;
      expect(proxy['multiplex'], isNotNull);
    });

    test('حالت مسیریابی روی final اثر می‌گذارد', () {
      for (final mode in RouteMode.values) {
        final map = jsonDecode(
          SingboxConfigBuilder.build(
            profile: vless(),
            settings: settings.copyWith(routeMode: mode),
          ),
        ) as Map<String, dynamic>;
        final finalOut = (map['route'] as Map)['final'];
        expect(finalOut, mode == RouteMode.direct ? 'direct' : 'proxy');
      }
    });
  });

  group('XrayConfigBuilder', () {
    test('کانفیگ معتبر JSON تولید می‌کند', () {
      final map = jsonDecode(
        XrayConfigBuilder.build(profile: vless(), settings: settings),
      ) as Map<String, dynamic>;
      expect(map['stats'], isA<Map>());
      expect(map['inbounds'], isA<List>());
      expect(map['outbounds'], isA<List>());
      expect(map['routing'], isA<Map>());
    });

    test('بخش آمار کامل است', () {
      final map = jsonDecode(
        XrayConfigBuilder.build(
          profile: vless(),
          settings: settings.copyWith(xrayApiPort: 18080),
        ),
      ) as Map<String, dynamic>;

      final api = map['api'] as Map;
      expect(api['tag'], 'api');
      expect(api['listen'], '127.0.0.1:18080');
      expect((api['services'] as List), contains('StatsService'));

      final policy = map['policy'] as Map;
      final system = policy['system'] as Map;
      expect(system['statsInboundUplink'], true);
      expect(system['statsOutboundUplink'], true);
      expect(system['statsInboundDownlink'], true);
      expect(system['statsOutboundDownlink'], true);

      // خروجی blackhole با تگ api باید باشد
      final outs = (map['outbounds'] as List).cast<Map>();
      expect(outs.any((o) => o['tag'] == 'api'), true);

      // و قانون مسیریابی مربوطه
      final rules = (map['routing'] as Map)['rules'] as List;
      final apiRule = rules.cast<Map>().firstWhere(
            (r) => (r['inboundTag'] as List?)?.contains('api') ?? false,
            orElse: () => <String, dynamic>{},
          );
      expect(apiRule['outboundTag'], 'api');
    });

    test('تنظیمات vless درست ترجمه می‌شود', () {
      final map = jsonDecode(
        XrayConfigBuilder.build(profile: vless(), settings: settings),
      ) as Map<String, dynamic>;
      final proxy = (map['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');

      expect(proxy['protocol'], 'vless');
      final vnext = (proxy['settings'] as Map)['vnext'] as List;
      final server = vnext.first as Map;
      expect(server['address'], 'fra1.example.net');
      expect(server['port'], 443);
      final user = (server['users'] as List).first as Map;
      expect(user['id'], '11111111-2222-3333-4444-555555555555');
      expect(user['encryption'], 'none');

      final ss = proxy['streamSettings'] as Map;
      expect(ss['security'], 'reality');
      // Xray در کنارِ REALITY فقط raw / xhttp / grpc را می‌پذیرد؛ ترکیبِ
      // reality+ws کانفیگی می‌ساخت که هنگامِ اجرا رد می‌شد:
      //   "REALITY only supports RAW, XHTTP and gRPC for now."
      expect(ss['network'], 'tcp');
      expect(ss['wsSettings'], isNull);
      final reality = ss['realitySettings'] as Map;
      expect(reality['publicKey'], 'pubkey');
      expect(reality['shortId'], 'abcd1234');
    });

    test('VLESS بدون reality ترانسپورتش را حفظ می‌کند', () {
      // تغییرِ بالا نباید روی ترکیب‌های مجاز اثر بگذارد
      final wsProfile = Profile(
        id: 'p9',
        name: 'WS',
        protocol: ProfileProtocol.vless,
        address: 'a.example.net',
        port: 443,
        fields: const {
          'uuid': '11111111-2222-3333-4444-555555555555',
          'security': 'tls',
          'network': 'ws',
          'path': '/ws',
          'host': 'a.example.net',
        },
      );
      final map = jsonDecode(
        XrayConfigBuilder.build(profile: wsProfile, settings: settings),
      ) as Map<String, dynamic>;
      final proxy = (map['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      final ss = proxy['streamSettings'] as Map;
      expect(ss['security'], 'tls');
      expect(ss['network'], 'ws');
      expect((ss['wsSettings'] as Map)['path'], '/ws');
    });

    test('پروتکل‌های پشتیبانی‌نشده خطا می‌دهند', () {
      final hy2 = Profile(
        id: 'x',
        name: 'h2',
        protocol: ProfileProtocol.hysteria2,
        address: 'h.example.net',
        port: 443,
      );
      expect(
        () => XrayConfigBuilder.build(profile: hy2, settings: settings),
        throwsA(isA<UnsupportedError>()),
      );
      expect(hy2.protocol.supportedByXray, false);
    });

    test('پورت mixed روی inbound اعمال می‌شود', () {
      final map = jsonDecode(
        XrayConfigBuilder.build(
          profile: vless(),
          settings: settings.copyWith(mixedPort: 7777),
        ),
      ) as Map<String, dynamic>;
      final socks = (map['inbounds'] as List)
          .cast<Map>()
          .firstWhere((i) => i['tag'] == 'socks-in');
      expect(socks['port'], 7777);
    });
  });
}
