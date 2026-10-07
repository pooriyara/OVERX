import 'dart:convert';

import 'package:overx/core/config/link_parser.dart';
import 'package:overx/core/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkParser', () {
    test('vless + reality', () {
      final p = LinkParser.parse(
        'vless://11111111-2222-3333-4444-555555555555@fra1.example.net:443'
        '?security=reality&sni=www.microsoft.com&fp=chrome&pbk=abc&sid=deadbeef'
        '&type=ws&path=%2Fws&host=www.microsoft.com&flow=xtls-rprx-vision'
        '#DE-Fra-01',
      );
      expect(p, isNotNull);
      expect(p!.protocol, ProfileProtocol.vless);
      expect(p.name, 'DE-Fra-01');
      expect(p.address, 'fra1.example.net');
      expect(p.port, 443);
      expect(p.uuid, '11111111-2222-3333-4444-555555555555');
      expect(p.security, 'reality');
      expect(p.sni, 'www.microsoft.com');
      expect(p.publicKey, 'abc');
      expect(p.shortId, 'deadbeef');
      expect(p.network, 'ws');
      expect(p.path, '/ws');
      expect(p.flow, 'xtls-rprx-vision');
    });

    test('trojan', () {
      final p = LinkParser.parse(
        'trojan://pa55word@ams.example.net:443?sni=example.com#NL',
      );
      expect(p, isNotNull);
      expect(p!.protocol, ProfileProtocol.trojan);
      expect(p.password, 'pa55word');
      expect(p.sni, 'example.com');
      expect(p.name, 'NL');
    });

    test('anytls', () {
      final p = LinkParser.parse(
        'anytls://pa55word@any.example.net:443?sni=example.com&security=tls#ANY',
      );
      expect(p, isNotNull);
      expect(p!.protocol, ProfileProtocol.anytls);
      expect(p.address, 'any.example.net');
      expect(p.port, 443);
      expect(p.password, 'pa55word');
      expect(p.sni, 'example.com');
      expect(p.security, 'tls');
      expect(p.name, 'ANY');
      // anytls با Xray پشتیبانی نمی‌شود.
      expect(p.protocol.supportedByXray, isFalse);
      expect(p.protocol.singboxType, 'anytls');
    });

    test('shadowsocks (base64 userinfo)', () {
      // "aes-256-gcm:hunter2" به صورت base64
      final p = LinkParser.parse(
        'ss://YWVzLTI1Ni1nY206aHVudGVyMg==@par.example.net:8388#Paris',
      );
      expect(p, isNotNull);
      expect(p!.protocol, ProfileProtocol.shadowsocks);
      expect(p.method, 'aes-256-gcm');
      expect(p.password, 'hunter2');
      expect(p.port, 8388);
      expect(p.name, 'Paris');
    });

    test('shadowsocks (whole body base64)', () {
      final p = LinkParser.parse(
        'ss://YWVzLTI1Ni1nY206aHVudGVyMkBwYXIuZXhhbXBsZS5uZXQ6ODM4OA==',
      );
      expect(p, isNotNull);
      expect(p!.method, 'aes-256-gcm');
      expect(p.address, 'par.example.net');
    });

    test('vmess (base64 json)', () {
      final json = '{"v":"2","ps":"SG","add":"sin.example.net","port":"443",'
          '"id":"uuid-123","aid":"0","net":"ws","path":"/vm","tls":"tls",'
          '"sni":"sin.example.net","host":"sin.example.net"}';
      final encoded = base64.encode(utf8.encode(json));
      final p = LinkParser.parse('vmess://$encoded');
      expect(p, isNotNull);
      expect(p!.protocol, ProfileProtocol.vmess);
      expect(p.address, 'sin.example.net');
      expect(p.uuid, 'uuid-123');
      expect(p.network, 'ws');
      expect(p.path, '/vm');
      expect(p.security, 'tls');
    });

    test('hysteria2', () {
      final p = LinkParser.parse(
        'hy2://pw@h2.example.net:443?sni=h2.example.net&obfs-password=xyz&up=100&down=200#H2',
      );
      expect(p, isNotNull);
      expect(p!.protocol, ProfileProtocol.hysteria2);
      expect(p.password, 'pw');
      expect(p.obfsPassword, 'xyz');
      expect(p.upMbps, 100);
      expect(p.downMbps, 200);
    });

    test('tuic', () {
      final p = LinkParser.parse(
        'tuic://uuid:pass@t.example.net:443?sni=t.example.net&alpn=h3#T',
      );
      expect(p, isNotNull);
      expect(p!.protocol, ProfileProtocol.tuic);
      expect(p.uuid, 'uuid');
      expect(p.password, 'pass');
    });

    test('لینک اشتباه → null', () {
      expect(LinkParser.parse(''), isNull);
      expect(LinkParser.parse('http://example.com'), isNull);
      expect(LinkParser.parse('not a link at all'), isNull);
    });

    test('چند لینک همزمان', () {
      const blob = '''
vless://11111111-1111-1111-1111-111111111111@a.example.net:443#a
junk line
trojan://pw@b.example.net:443#b
''';
      final list = LinkParser.parseMany(blob);
      expect(list.length, 2);
      expect(list.first.protocol, ProfileProtocol.vless);
      expect(list.last.protocol, ProfileProtocol.trojan);
    });

    test('Profile رفت‌وبرگشتی JSON', () {
      final p = LinkParser.parse('trojan://pw@x.example.net:443#X')!;
      final round = Profile.decode(p.encode());
      expect(round, isNotNull);
      expect(round!.name, p.name);
      expect(round.address, p.address);
      expect(round.port, p.port);
    });

    test('IPv6 authority', () {
      final p = LinkParser.parse(
        'vless://uuid@[2001:db8::1]:443?security=tls#v6',
      );
      expect(p, isNotNull);
      expect(p!.address, '2001:db8::1');
      expect(p.port, 443);
    });
  });
}
