import 'dart:convert';

import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/settings.dart';
import 'dart:io';

/// تولید کانفیگ JSON برای Xray-core.
///
/// نکته‌های مهم برای آمار (StatsService):
///  - بلاکِ "stats": {} باید حضور داشته باشد
///  - api.services باید StatsService را داشته باشد و api.listen تنظیم شود
///  - policy.system باید چهار فلگِ آمار را true کند
///  - یک outbound با تگ api و یک قانونِ مسیریابی inboundTag=[api] → outboundTag=api لازم است
///  - سپس: xray api statsquery --server=127.0.0.1:<port> -pattern ""
class XrayConfigBuilder {
  const XrayConfigBuilder._();

  static String build({
    required Profile profile,
    required AppSettings settings,

    /// fd اینترفیس TUN. اگر داده شود، Xray آن را از متغیر محیطی
    /// XRAY_TUN_FD می‌خواند (تنها راه پشتیبانی‌شده روی اندروید/آی‌او‌اس).
    int? tunFd,
  }) {
    final cfg = <String, dynamic>{
      'log': {'loglevel': settings.logLevel.name},

      // آمار
      'stats': <String, dynamic>{},
      'api': {
        'tag': 'api',
        'listen': '127.0.0.1:${settings.xrayApiPort}',
        'services': const [
          'StatsService',
          'RoutingService',
          'LoggerService',
          'ReflectionService',
        ],
      },
      'policy': {
        'levels': {
          '0': {
            'statsUserUplink': true,
            'statsUserDownlink': true,
          },
        },
        'system': {
          'statsInboundUplink': true,
          'statsInboundDownlink': true,
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },

      'dns': _dns(settings),
      'inbounds': _inbounds(settings, tunFd: tunFd),
      'outbounds': [
        _outbound(profile, settings),
        {'tag': 'direct', 'protocol': 'freedom', 'settings': <String, dynamic>{}},
        {'tag': 'block', 'protocol': 'blackhole', 'settings': <String, dynamic>{}},
        // مقصدِ ترافیکِ خودِ API
        {'tag': 'api', 'protocol': 'blackhole', 'settings': <String, dynamic>{}},
      ],
      'routing': _routing(settings),
    };

    return const JsonEncoder.withIndent('  ').convert(cfg);
  }

  // ------------------------------------------------------------------- dns

  static Map<String, dynamic> _dns(AppSettings s) => {
        'servers': [
          s.remoteDns,
          s.localDns,
          'localhost',
        ],
        'queryStrategy': s.ipv6 ? 'UseIP' : 'UseIPv4',
        'disableCache': false,
        'disableFallback': false,
      };

  // ---------------------------------------------------------------- inbounds

  static List<Map<String, dynamic>> _inbounds(AppSettings s, {int? tunFd}) {
    final list = <Map<String, dynamic>>[
      {
        'tag': 'socks-in',
        'listen': '127.0.0.1',
        'port': s.mixedPort,
        'protocol': 'socks',
        'settings': {
          'udp': true,
          'auth': 'noauth',
          if (s.sniffing) 'ip': '127.0.0.1',
        },
        if (s.sniffing)
          'sniffing': {
            'enabled': true,
            'destOverride': const ['http', 'tls', 'quic'],
            'routeOnly': true,
          },
      },
      {
        'tag': 'http-in',
        'listen': '127.0.0.1',
        'port': s.mixedPort + 1,
        'protocol': 'http',
        'settings': {'allowTransparent': false},
        if (s.sniffing)
          'sniffing': {
            'enabled': true,
            'destOverride': const ['http', 'tls'],
            'routeOnly': true,
          },
      },
    ];

    // TUN: روی اندروید fd از env می‌آید و مسیریابی را VpnService انجام می‌دهد؛
    // روی لینوکس خود Xray جدول مسیریابی را می‌سازد.
    final tunWanted = s.tunMode && (tunFd != null || Platform.isLinux);

    if (tunWanted) {
      list.add({
        'tag': 'tun-in',
        'protocol': 'tun',
        'settings': tunFd != null
            ? <String, dynamic>{
                'name': 'tun0',
                'mtu': 1500,
              }
            : <String, dynamic>{
                'name': 'tun0',
                'mtu': 1500,
                'gateway': const ['172.19.0.1/30'],
                'autoSystemRoutingTable': const ['0.0.0.0/0'],
                'autoOutboundsInterface': 'auto',
              },
        'sniffing': {
          'enabled': s.sniffing,
          'destOverride': const ['http', 'tls', 'quic'],
          'routeOnly': true,
        },
        'streamSettings': const {
          'sockopt': {'tcpNoDelay': true},
        },
      });
    }

    return list;
  }

  // ---------------------------------------------------------------- outbounds

  static Map<String, dynamic> _outbound(Profile p, AppSettings s) {
    final protocol = p.protocol.xrayProtocol ?? 'vless';
    final out = <String, dynamic>{
      'tag': 'proxy',
      'protocol': protocol,
      'settings': _settings(p),
      'streamSettings': _streamSettings(p),
      'mux': {
        'enabled': s.mux,
        'concurrency': 8,
        'xudpConcurrency': 16,
        'xudpProxyUDP443': 'reject',
      },
    };
    return out;
  }

  static Map<String, dynamic> _settings(Profile p) => switch (p.protocol) {
        ProfileProtocol.vless => {
            'vnext': [
              {
                'address': p.address,
                'port': p.port,
                'users': [
                  {
                    'id': p.uuid ?? '',
                    'encryption': 'none',
                    if (p.flow != null) 'flow': p.flow,
                    'level': 0,
                  },
                ],
              },
            ],
          },

        ProfileProtocol.vmess => {
            'vnext': [
              {
                'address': p.address,
                'port': p.port,
                'users': [
                  {
                    'id': p.uuid ?? '',
                    'security': p.method ?? 'auto',
                    'alterId': 0,
                    'level': 0,
                  },
                ],
              },
            ],
          },

        ProfileProtocol.trojan => {
            'servers': [
              {
                'address': p.address,
                'port': p.port,
                'password': p.password ?? '',
                'level': 0,
              },
            ],
          },

        ProfileProtocol.shadowsocks => {
            'servers': [
              {
                'address': p.address,
                'port': p.port,
                'method': p.method ?? '2022-blake3-aes-128-gcm',
                'password': p.password ?? '',
                'level': 0,
              },
            ],
          },

        // Hysteria2 / TUIC در Xray-core پشتیبانی نمی‌شوند.
        _ => throw UnsupportedError(
            '${p.protocol.label} is not supported by Xray-core. '
            'Use sing-box, or pick a VLESS/VMess/Trojan/Shadowsocks profile.'),
      };

  static Map<String, dynamic> _streamSettings(Profile p) {
    var net = p.network ?? 'tcp';
    final sec = p.security ?? 'tls';

    // Xray محدودیت دارد: REALITY فقط با raw / xhttp / grpc کار می‌کند و
    // ترکیب‌های دیگر (مثلاً reality + ws) هنگامِ اجرا رد می‌شود:
    //   "REALITY only supports RAW, XHTTP and gRPC for now."
    // به‌جای تولیدِ کانفیگی که بالا نمی‌آید، به raw برمی‌گردیم.
    const realityNetworks = <String>{'tcp', 'raw', 'xhttp', 'grpc'};
    if (sec == 'reality' && !realityNetworks.contains(net)) {
      net = 'tcp';
    }

    final ss = <String, dynamic>{
      'network': net,
      'security': sec,
      if (sec == 'tls')
        'tlsSettings': {
          if (p.sni != null) 'serverName': p.sni,
          if (p.alpn != null) 'alpn': p.alpn!.split(','),
          'fingerprint': p.fingerprint ?? 'chrome',
          'allowInsecure': false,
        },
      if (sec == 'reality')
        'realitySettings': {
          if (p.sni != null) 'serverName': p.sni,
          if (p.publicKey != null) 'publicKey': p.publicKey,
          if (p.shortId != null) 'shortId': p.shortId,
          'fingerprint': p.fingerprint ?? 'chrome',
        },
      'sockopt': {
        'dialerProxy': '',
        'tcpKeepAliveIdle': 100,
        'tcpNoDelay': true,
      },
    };

    switch (net) {
      case 'ws':
        ss['wsSettings'] = {
          if (p.path != null) 'path': p.path,
          if (p.host != null)
            'headers': {'Host': p.host},
        };
      case 'grpc':
        ss['grpcSettings'] = {
          'serviceName': p.serviceName ?? p.path ?? '',
          'multiMode': false,
          'idle_timeout': 60,
        };
      case 'http' || 'h2':
        ss['network'] = 'http';
        ss['httpSettings'] = {
          if (p.path != null) 'path': p.path,
          if (p.host != null) 'host': p.host!.split(','),
        };
      case 'quic':
        ss['quicSettings'] = {
          'security': 'none',
          if (p.host != null) 'key': p.host,
          'header': {'type': 'none'},
        };
      default:
        ss['tcpSettings'] = {
          'header': {'type': 'none'},
        };
    }

    return ss;
  }

  // ---------------------------------------------------------------- routing

  static Map<String, dynamic> _routing(AppSettings s) => {
        'domainStrategy': 'AsIs',
        'rules': [
          // ترافیک خودِ API نباید از خروجیِ اصلی رد شود
          {
            'type': 'field',
            'inboundTag': const ['api'],
            'outboundTag': 'api',
          },
          if (s.bypassLan) ...[
            {
              'type': 'field',
              'ip': const ['geoip:private'],
              'outboundTag': 'direct',
            },
          ],
          if (s.routeMode == RouteMode.direct)
            {
              'type': 'field',
              'network': 'tcp,udp',
              'outboundTag': 'direct',
            },
        ],
      };
}
