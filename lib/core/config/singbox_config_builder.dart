import 'dart:convert';

import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/settings.dart';
import 'dart:io';

/// تولید کانفیگ JSON برای sing-box.
///
/// منبعِ ساختار: https://sing-box.sagernet.org/configuration/
class SingboxConfigBuilder {
  const SingboxConfigBuilder._();

  static String build({
    required Profile profile,
    required AppSettings settings,

    /// fd اینترفیس TUN (فقط وقتی پلتفرم آن را ساخته باشد — یعنی اندروید).
    ///
    /// ⚠️ sing-box این مقدار را از JSON کانفیگ نمی‌گیرد (فقط کتابخانه‌ی
    /// sing-tun هنگام استفاده از libbox آن را می‌پذیرد). بنابراین اگر
    /// tunFd داده شود، inbound شبیه‌سازی‌شده نمی‌سازیم و ترافیک فقط از
    /// پورت محلی عبور می‌کند — برای مسیریابیِ کل دستگاه روی اندروید
    /// باید از باینری libbox یا یک tun2socks استفاده شود.
    int? tunFd,
  }) {
    final cfg = <String, dynamic>{
      'log': {
        'level': settings.logLevel.name,
        'timestamp': true,
      },
      'dns': _dns(settings),
      'inbounds': _inbounds(settings, tunFd: tunFd),
      'outbounds': [
        _outbound(profile, settings),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': _route(settings),
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:${settings.singboxApiPort}',
          'default_mode': switch (settings.routeMode) {
            RouteMode.global => 'Global',
            RouteMode.direct => 'Direct',
            RouteMode.rule => 'Rule',
          },
          'access_control_allow_origin': const ['http://127.0.0.1'],
          'access_control_allow_private_network': true,
        },
        // `store` در 1.14 معنا ندارد؛ ذخيره با کلیدهاي store_* کنترل مي‌شود
        'cache_file': {'enabled': true, 'store_fakeip': true},
      },
    };

    if (!settings.ipv6) {
      // جلوگیری از نشت/خطای IPv6 روی شبکه‌هایی که ندارند
      cfg['route']['rules'].insert(0, {
        'ip_is_private': false,
        'network': 'udp',
        'protocol': 'dns',
        'action': 'hijack-dns',
      });
    }

    return const JsonEncoder.withIndent('  ').convert(cfg);
  }

  // ------------------------------------------------------------------- dns

  static Map<String, dynamic> _dns(AppSettings s) {
    final servers = <Map<String, dynamic>>[
      {
        'tag': 'dns-remote',
        'type': _dnsType(s.remoteDns),
        'server': _dnsHost(s.remoteDns),
        if (_isDoH(s.remoteDns)) 'server_port': 443,
        if (_isDoH(s.remoteDns)) 'path': _dnsPath(s.remoteDns),
        'detour': 'proxy',
      },
      {'tag': 'dns-local', 'type': 'udp', 'server': s.localDns, 'detour': 'direct'},
      // در sing-box 1.12، fakeip از یک بلوکِ تنظیمات به یک **سرورِ DNS**
      // تبدیل شد و بلوکِ قدیمیِ `dns.fakeip` در 1.14 حذف گردید — یعنی
      // کانفیگی که اینجا تولید می‌شد روی نسخه‌های جدید کاملاً رد می‌شد.
      {
        'tag': 'dns-fakeip',
        'type': 'fakeip',
        'inet4_range': '198.18.0.0/15',
        'inet6_range': 'fc00::/18',
      },
    ];

    return {
      'servers': servers,
      'rules': [
        {'clash_mode': 'Global', 'server': 'dns-remote'},
        {'clash_mode': 'Direct', 'server': 'dns-local'},
        // سرورِ DNS از نوعِ `block` هم در 1.14 حذف شده؛ مسدودسازی حالا
        // با یک قانون و اکشنِ reject انجام می‌شود
        {
          'rule_set': const ['geosite-category-ads-all'],
          'action': 'reject',
        },
        if (s.routeMode == RouteMode.rule)
          {'rule_set': const ['geosite-ir'], 'server': 'dns-local'},
        // سرورِ fakeip نمی‌تواند خودِ پیش‌فرض باشد (sing-box هنگامِ اجرا رد
        // می‌کند: "default server cannot be fakeip")، پس یک قانونِ فراگیر
        // برای رسیدن به آن می‌گذاریم.
        if (s.dnsMode == DnsMode.fakeIp)
          {
            'query_type': const ['A', 'AAAA'],
            'action': 'route',
            'server': 'dns-fakeip',
          },
      ],
      'final': switch (s.dnsMode) {
        DnsMode.fakeIp => 'dns-remote',
        DnsMode.remote => 'dns-remote',
        DnsMode.local => 'dns-local',
      },
    };
  }

  static bool _isDoH(String url) => url.startsWith('https://');

  static String _dnsType(String url) => switch (url) {
        _ when url.startsWith('https://') => 'https',
        _ when url.startsWith('tls://') => 'tls',
        _ when url.startsWith('quic://') => 'quic',
        _ => 'udp',
      };

  static String _dnsHost(String url) {
    var v = url;
    for (final p in const ['https://', 'tls://', 'quic://']) {
      if (v.startsWith(p)) v = v.substring(p.length);
    }
    final slash = v.indexOf('/');
    return slash < 0 ? v : v.substring(0, slash);
  }

  static String _dnsPath(String url) {
    final i = url.indexOf('/', url.indexOf('//') + 2);
    return i < 0 ? '/dns-query' : url.substring(i);
  }

  // ---------------------------------------------------------------- inbounds

  static List<Map<String, dynamic>> _inbounds(AppSettings s, {int? tunFd}) {
    final list = <Map<String, dynamic>>[];

    // TUN بومی روی دسکتاپ؛ روی اندروید به libbox/tun2socks نیاز است
    final useNativeTun = s.tunMode && tunFd == null && !Platform.isAndroid;

    if (useNativeTun) {
      list.add({
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'tun0',
        'address': [
          '172.19.0.1/30',
          if (s.ipv6) 'fdfe:dcba:9876::1/126',
        ],
        'mtu': 9000,
        'auto_route': true,
        'strict_route': true,
        'stack': 'mixed',
        'route_exclude_address': [
          if (!s.ipv6) '::/0',
        ],
        'endpoint_independent_nat': true,
      });
    }

    list.add({
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': '127.0.0.1',
      'listen_port': s.mixedPort,
      if (s.routeMode == RouteMode.direct) 'set_system_proxy': false,
    });

    return list;
  }

  // ---------------------------------------------------------------- outbounds

  static Map<String, dynamic> _outbound(Profile p, AppSettings s) {
    final base = <String, dynamic>{
      'type': p.protocol.singboxType,
      'tag': 'proxy',
      'server': p.address,
      'server_port': p.port,
    };

    switch (p.protocol) {
      case ProfileProtocol.vless:
        base.addAll({
          'uuid': p.uuid ?? '',
          if (p.flow != null) 'flow': p.flow,
          'packet_encoding': 'xudp',
          ..._tls(p),
          ..._transport(p),
        });

      case ProfileProtocol.vmess:
        base.addAll({
          'uuid': p.uuid ?? '',
          'security': p.method ?? 'auto',
          'alter_id': 0,
          'global_padding': false,
          'authenticated_length': true,
          'packet_encoding': 'xudp',
          ..._tls(p),
          ..._transport(p),
        });

      case ProfileProtocol.trojan:
        base.addAll({
          'password': p.password ?? '',
          ..._tls(p),
          ..._transport(p),
        });

      case ProfileProtocol.shadowsocks:
        base.addAll({
          'method': p.method ?? '2022-blake3-aes-128-gcm',
          'password': p.password ?? '',
          if (s.mux) 'multiplex': _mux(s),
        });

      case ProfileProtocol.hysteria2:
        base.addAll({
          'password': p.password ?? '',
          if (p.obfsPassword != null)
            'obfs': {'type': 'salamander', 'password': p.obfsPassword!},
          'up_mbps': p.upMbps ?? 100,
          'down_mbps': p.downMbps ?? 100,
          ..._tls(p),
        });

      case ProfileProtocol.tuic:
        base.addAll({
          'uuid': p.uuid ?? '',
          'password': p.password ?? '',
          'congestion_control': 'bbr',
          'udp_relay_mode': 'native',
          'zero_rtt_handshake': true,
          ..._tls(p),
        });

      case ProfileProtocol.anytls:
        base.addAll({
          'password': p.password ?? '',
          ..._tls(p),
        });
    }

    if (s.mux && _muxSupported(p.protocol)) {
      base['multiplex'] = _mux(s);
    }
    return base;
  }

  static bool _muxSupported(ProfileProtocol p) => switch (p) {
        ProfileProtocol.vless ||
        ProfileProtocol.vmess ||
        ProfileProtocol.trojan =>
          true,
        _ => false,
      };

  static Map<String, dynamic> _mux(AppSettings s) => {
        'enabled': true,
        'protocol': 'h2mux',
        'max_connections': 8,
        'min_streams': 16,
        'padding': false,
      };

  static Map<String, dynamic> _tls(Profile p) {
    final sec = p.security ?? 'tls';
    if (sec == 'none') return const {};

    final tls = <String, dynamic>{
      'enabled': true,
      if (p.sni != null) 'server_name': p.sni,
      if (p.alpn != null) 'alpn': p.alpn!.split(','),
      'utls': {
        'enabled': true,
        'fingerprint': p.fingerprint ?? 'chrome',
      },
      if (sec == 'reality')
        'reality': {
          'enabled': true,
          if (p.publicKey != null) 'public_key': p.publicKey,
          if (p.shortId != null) 'short_id': p.shortId,
        },
      'insecure': false,
    };
    return {'tls': tls};
  }

  static Map<String, dynamic> _transport(Profile p) {
    final net = p.network ?? 'tcp';
    final t = switch (net) {
      'ws' => {
          'type': 'ws',
          if (p.path != null) 'path': p.path,
          if (p.host != null)
            'headers': {'Host': p.host},
          'max_early_data': 2048,
          'early_data_header_name': 'Sec-WebSocket-Protocol',
        },
      'grpc' => {
          'type': 'grpc',
          if (p.serviceName != null) 'service_name': p.serviceName,
        },
      'http' => {
          'type': 'http',
          if (p.path != null) 'path': p.path,
          if (p.host != null) 'host': p.host!.split(','),
        },
      'quic' => const {'type': 'quic'},
      _ => null,
    };
    return t == null ? const {} : {'transport': t};
  }

  // ---------------------------------------------------------------- route

  static Map<String, dynamic> _route(AppSettings s) {
    final rules = <Map<String, dynamic>>[
      // sniff از فیلدِ inbound به یک «قانونِ مسیریابی» منتقل شده
      // (منسوخ در 1.11، حذف در 1.13)
      if (s.sniffing) const {'action': 'sniff'},
      {'protocol': 'dns', 'action': 'hijack-dns'},
      {'clash_mode': 'Direct', 'outbound': 'direct'},
      {'clash_mode': 'Global', 'outbound': 'proxy'},
      if (s.bypassLan) ...[
        {'ip_is_private': true, 'outbound': 'direct'},
      ],
      if (s.routeMode == RouteMode.rule) ...[
        // outbound ويژه‌ي `block` هم منسوخ شده -> اکشنِ reject
        {'rule_set': const ['geosite-category-ads-all'], 'action': 'reject'},
      ],
      if (s.routeMode == RouteMode.direct)
        {'network': const ['tcp', 'udp'], 'outbound': 'direct'},
    ];

    return {
      'rules': rules,
      'rule_set': [
        {
          'tag': 'geosite-category-ads-all',
          'type': 'remote',
          'format': 'binary',
          'url':
              'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs',
          'download_detour': 'direct',
        },
        // قانونِ DNS به geosite-ir ارجاع می‌دهد؛ اگر اینجا اعلان نشود،
        // sing-box هنگامِ اجرا با "rule-set not found" از کار می‌افتد
        if (s.routeMode == RouteMode.rule)
          {
            'tag': 'geosite-ir',
            'type': 'remote',
            'format': 'binary',
            'url':
                'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-ir.srs',
            'download_detour': 'direct',
          },
      ],
      'final': switch (s.routeMode) {
        RouteMode.global => 'proxy',
        RouteMode.direct => 'direct',
        RouteMode.rule => 'proxy',
      },
      // بدونِ این، sing-box هشدار می‌دهد که `domain_resolver` در dial fields
      // منسوخ شده (1.12) و در 1.14 حذف می‌شود
      'default_domain_resolver': {'server': 'dns-remote'},
      'auto_detect_interface': true,
    };
  }
}
