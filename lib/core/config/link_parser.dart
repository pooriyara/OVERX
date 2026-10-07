import 'dart:convert';

import 'package:overx/core/models/profile.dart';

/// پارس کردن لینک‌های اشتراک‌گذاری به [Profile].
///
/// پشتیبانی: vless:// · vmess:// · trojan:// · ss:// · hysteria2:// · tuic://
class LinkParser {
  const LinkParser._();

  /// لینک را به [Profile] تبدیل می‌کند؛ اگر نشد null.
  static Profile? parse(String raw) {
    final link = raw.trim();
    if (link.isEmpty) return null;

    final scheme = _schemeOf(link);
    return switch (scheme) {
      'vless' => _vless(link),
      'vmess' => _vmess(link),
      'trojan' => _trojan(link),
      'ss' => _shadowsocks(link),
      'hysteria2' || 'hy2' => _hysteria2(link),
      'tuic' => _tuic(link),
      'anytls' => _anytls(link),
      _ => null,
    };
  }

  /// پارس کردن چند لینک (هر خط یکی). لینک‌های خراب رد می‌شن.
  static List<Profile> parseMany(String raw) {
    final out = <Profile>[];
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      final p = parse(line);
      if (p != null) out.add(p);
    }
    return out;
  }

  // ------------------------------------------------------------------ utils

  static String _schemeOf(String link) {
    final i = link.indexOf('://');
    if (i <= 0) return '';
    return link.substring(0, i).toLowerCase();
  }

  static String _decodeName(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  static Map<String, String> _query(String link) {
    final qIndex = link.indexOf('?');
    if (qIndex < 0) return const {};
    var end = link.indexOf('#');
    if (end < 0) end = link.length;
    final q = link.substring(qIndex + 1, end);
    final map = <String, String>{};
    for (final pair in q.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      map[pair.substring(0, eq).toLowerCase()] =
          Uri.decodeQueryComponent(pair.substring(eq + 1));
    }
    return map;
  }

  static String _fragment(String link) {
    final i = link.indexOf('#');
    if (i < 0) return '';
    return _decodeName(link.substring(i + 1));
  }

  /// userinfo@host:port
  static (String, String, int)? _splitAuthority(String link) {
    final schemeEnd = link.indexOf('://');
    if (schemeEnd < 0) return null;
    var rest = link.substring(schemeEnd + 3);
    final hash = rest.indexOf('#');
    if (hash >= 0) rest = rest.substring(0, hash);
    final q = rest.indexOf('?');
    if (q >= 0) rest = rest.substring(0, q);

    final at = rest.lastIndexOf('@');
    if (at < 0) return null;
    final userinfo = rest.substring(0, at);
    final hostPort = rest.substring(at + 1);

    String host;
    int port;
    if (hostPort.startsWith('[')) {
      final close = hostPort.indexOf(']');
      if (close < 0) return null;
      host = hostPort.substring(1, close);
      final restPort = hostPort.substring(close + 1);
      port = restPort.startsWith(':')
          ? int.tryParse(restPort.substring(1)) ?? 443
          : 443;
    } else {
      final colon = hostPort.lastIndexOf(':');
      if (colon < 0) {
        host = hostPort;
        port = 443;
      } else {
        host = hostPort.substring(0, colon);
        port = int.tryParse(hostPort.substring(colon + 1)) ?? 443;
      }
    }
    return (userinfo, host, port);
  }

  static String _base64Pad(String s) {
    var v = s.replaceAll('-', '+').replaceAll('_', '/');
    while (v.length % 4 != 0) {
      v += '=';
    }
    return v;
  }

  static String? _b64(String s) {
    try {
      return utf8.decode(base64.decode(_base64Pad(s)));
    } catch (_) {
      return null;
    }
  }

  static String _id() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  // ---------------------------------------------------------------- vless

  static Profile? _vless(String link) {
    final a = _splitAuthority(link);
    if (a == null) return null;
    final (uuid, host, port) = a;
    final q = _query(link);

    return Profile(
      id: _id(),
      name: _fragment(link).isEmpty ? '$host:$port' : _fragment(link),
      protocol: ProfileProtocol.vless,
      address: host,
      port: port,
      rawLink: link,
      fields: {
        'uuid': uuid,
        'security': q['security'] ?? (q.containsKey('pbk') ? 'reality' : 'tls'),
        if (q['sni'] != null) 'sni': q['sni'],
        if (q['flow'] != null) 'flow': q['flow'],
        if (q['type'] != null) 'network': _normalizeNetwork(q['type']!),
        if (q['path'] != null) 'path': q['path'],
        if (q['host'] != null) 'host': q['host'],
        if (q['serviceName'] != null) 'serviceName': q['serviceName'],
        if (q['alpn'] != null) 'alpn': q['alpn'],
        if (q['fp'] != null) 'fingerprint': q['fp'],
        if (q['pbk'] != null) 'publicKey': q['pbk'],
        if (q['sid'] != null) 'shortId': q['sid'],
      },
    );
  }

  // ---------------------------------------------------------------- vmess

  static Profile? _vmess(String link) {
    final body = link.substring('vmess://'.length);
    final hash = body.indexOf('#');
    final b64 = hash >= 0 ? body.substring(0, hash) : body;
    final decoded = _b64(b64);
    if (decoded == null) return null;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final host = (j['add'] ?? '').toString();
    if (host.isEmpty) return null;

    final net = (j['net'] ?? 'tcp').toString();

    return Profile(
      id: _id(),
      name: (j['ps'] as String?)?.isNotEmpty == true
          ? j['ps'] as String
          : '$host:${j['port']}',
      protocol: ProfileProtocol.vmess,
      address: host,
      port: int.tryParse('${j['port']}') ?? 443,
      rawLink: link,
      fields: {
        'uuid': '${j['id'] ?? ''}',
        'security': (j['tls'] ?? '').toString() == 'tls' ? 'tls' : 'none',
        if (j['sni'] != null) 'sni': '${j['sni']}',
        if (j['host'] != null) 'host': '${j['host']}',
        if (j['path'] != null) 'path': '${j['path']}',
        if (j['alpn'] != null) 'alpn': '${j['alpn']}',
        if (j['scy'] != null) 'method': '${j['scy']}',
        'network': _normalizeNetwork(net),
        if (_normalizeNetwork(net) == 'grpc' && j['path'] != null)
          'serviceName': '${j['path']}',
      },
    );
  }

  // ---------------------------------------------------------------- trojan

  static Profile? _trojan(String link) {
    final a = _splitAuthority(link);
    if (a == null) return null;
    final (password, host, port) = a;
    final q = _query(link);

    return Profile(
      id: _id(),
      name: _fragment(link).isEmpty ? '$host:$port' : _fragment(link),
      protocol: ProfileProtocol.trojan,
      address: host,
      port: port,
      rawLink: link,
      fields: {
        'password': password,
        'security': q['security'] ?? 'tls',
        if (q['sni'] != null) 'sni': q['sni'],
        if (q['type'] != null) 'network': _normalizeNetwork(q['type']!),
        if (q['path'] != null) 'path': q['path'],
        if (q['host'] != null) 'host': q['host'],
        if (q['serviceName'] != null) 'serviceName': q['serviceName'],
        if (q['alpn'] != null) 'alpn': q['alpn'],
        if (q['fp'] != null) 'fingerprint': q['fp'],
      },
    );
  }

  // ---------------------------------------------------------------- shadowsocks

  static Profile? _shadowsocks(String link) {
    final body = link.substring('ss://'.length);
    final hash = body.indexOf('#');
    final name = hash >= 0 ? _decodeName(body.substring(hash + 1)) : '';
    var main = hash >= 0 ? body.substring(0, hash) : body;
    final qIndex = main.indexOf('?');
    if (qIndex >= 0) main = main.substring(0, qIndex);

    String userinfo;
    String hostPort;

    final at = main.lastIndexOf('@');
    if (at >= 0) {
      userinfo = main.substring(0, at);
      hostPort = main.substring(at + 1);
    } else {
      final decoded = _b64(main);
      if (decoded == null) return null;
      final at2 = decoded.lastIndexOf('@');
      if (at2 < 0) return null;
      userinfo = decoded.substring(0, at2);
      hostPort = decoded.substring(at2 + 1);
    }

    final methodPass = _b64(userinfo) ?? userinfo;
    final sep = methodPass.indexOf(':');
    if (sep <= 0) return null;
    final method = methodPass.substring(0, sep);
    final password = methodPass.substring(sep + 1);

    final colon = hostPort.lastIndexOf(':');
    final host = colon < 0 ? hostPort : hostPort.substring(0, colon);
    final port = colon < 0 ? 8388 : int.tryParse(hostPort.substring(colon + 1)) ?? 8388;

    return Profile(
      id: _id(),
      name: name.isEmpty ? '$host:$port' : name,
      protocol: ProfileProtocol.shadowsocks,
      address: host,
      port: port,
      rawLink: link,
      fields: {'method': method, 'password': password},
    );
  }

  // ---------------------------------------------------------------- hysteria2

  static Profile? _hysteria2(String link) {
    final a = _splitAuthority(link);
    if (a == null) return null;
    final (password, host, port) = a;
    final q = _query(link);

    return Profile(
      id: _id(),
      name: _fragment(link).isEmpty ? '$host:$port' : _fragment(link),
      protocol: ProfileProtocol.hysteria2,
      address: host,
      port: port,
      rawLink: link,
      fields: {
        'password': password,
        if (q['sni'] != null) 'sni': q['sni'],
        if (q['obfs-password'] != null) 'obfsPassword': q['obfs-password'],
        if (q['up'] != null) 'upMbps': int.tryParse(q['up']!),
        if (q['down'] != null) 'downMbps': int.tryParse(q['down']!),
      },
    );
  }

  // ---------------------------------------------------------------- tuic

  static Profile? _tuic(String link) {
    final a = _splitAuthority(link);
    if (a == null) return null;
    final (userinfo, host, port) = a;
    final q = _query(link);
    final colon = userinfo.indexOf(':');
    final uuid = colon < 0 ? userinfo : userinfo.substring(0, colon);
    final password = colon < 0 ? '' : userinfo.substring(colon + 1);

    return Profile(
      id: _id(),
      name: _fragment(link).isEmpty ? '$host:$port' : _fragment(link),
      protocol: ProfileProtocol.tuic,
      address: host,
      port: port,
      rawLink: link,
      fields: {
        'uuid': uuid,
        'password': password,
        if (q['sni'] != null) 'sni': q['sni'],
        if (q['alpn'] != null) 'alpn': q['alpn'],
      },
    );
  }

  // ---------------------------------------------------------------- anytls

  static Profile? _anytls(String link) {
    final a = _splitAuthority(link);
    if (a == null) return null;
    final (password, host, port) = a;
    final q = _query(link);

    return Profile(
      id: _id(),
      name: _fragment(link).isEmpty ? '$host:$port' : _fragment(link),
      protocol: ProfileProtocol.anytls,
      address: host,
      port: port,
      rawLink: link,
      fields: {
        'password': password,
        if (q['sni'] != null) 'sni': q['sni'],
        if (q['security'] != null) 'security': q['security'],
      },
    );
  }

  /// نرمال‌سازی نام transport بین دو هسته.
  static String _normalizeNetwork(String v) => switch (v.toLowerCase()) {
        'ws' || 'websocket' => 'ws',
        'grpc' || 'gun' => 'grpc',
        'h2' || 'http' => 'http',
        'quic' => 'quic',
        _ => 'tcp',
      };
}
