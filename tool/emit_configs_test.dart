// ابزار: تولیدِ کانفیگ‌های واقعی از لینک‌های اشتراک، برای اینکه بتوان آن‌ها را
// با **باینری اصلیِ sing-box / xray** اعتبارسنجی کرد (`check` / `-test`).
//
// چرا این ابزار وجود دارد؟ چون سازنده‌ی کانفیگ تا امروز فقط در برابرِ انتظارهای
// خودِ تست‌ها سنجیده می‌شد؛ هیچ هسته‌ی واقعی‌ای این JSONها را ندیده بود. این
// ابزار خروجی را می‌نویسد تا `tool/validate_configs.sh` آن را به هسته بدهد.
//
// اجرا:
//   dart run tool/emit_configs.dart [مسیرِ خروجی]

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:overx/core/config/link_parser.dart';
import 'package:overx/core/config/singbox_config_builder.dart';
import 'package:overx/core/config/xray_config_builder.dart';
import 'package:overx/core/models/settings.dart';

/// لینک‌های نمونه برای همه‌ی پروتکل‌های پشتیبانی‌شده.
///
/// کلیدها و مقادیرشان کاملاً ساختگی‌اند و فقط برای این است که شکلِ
/// کانفیگِ تولیدشده درست باشد — قرار نیست واقعاً وصل شوند.
const List<(String, String)> kSampleLinks = <(String, String)>[
  (
    'vless-reality',
    'vless://11111111-2222-3333-4444-555555555555@fra1.example.net:443'
        '?encryption=none&security=reality&flow=xtls-rprx-vision'
        '&sni=www.microsoft.com&fp=chrome&pbk=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&sid=abcd1234'
        '&type=ws&path=%2Fws&host=www.microsoft.com#VLESS-Reality'
  ),
  (
    'vless-tls',
    'vless://11111111-2222-3333-4444-555555555555@ams2.example.net:443'
        '?encryption=none&security=tls&sni=ams2.example.net&type=tcp'
        '#VLESS-TLS'
  ),
  (
    'vmess',
    'vmess://eyJ2IjoiMiIsInBzIjoiVk1lc3MtV1MiLCJhZGQiOiJ2bS5leGFtcGxlLm5ldCIs'
        'InBvcnQiOiI0NDMiLCJpZCI6IjExMTExMTExLTIyMjItMzMzMy00NDQ0LTU1NTU1NTU1'
        'NTU1NSIsImFpZCI6IjAiLCJuZXQiOiJ3cyIsInR5cGUiOiJub25lIiwiaG9zdCI6InZt'
        'LmV4YW1wbGUubmV0IiwicGF0aCI6Ii93cyIsInRscyI6InRscyIsInNuaSI6InZtLmV4'
        'YW1wbGUubmV0In0='
  ),
  (
    'trojan',
    'trojan://password123@tr1.example.net:443?security=tls&sni=tr1.example.net'
        '&type=ws&path=%2Ftrojan#Trojan-WS'
  ),
  (
    'shadowsocks',
    'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@ss1.example.net:8388#Shadowsocks'
  ),
  (
    'hysteria2',
    'hysteria2://password123@hy2.example.net:443?sni=hy2.example.net'
        '&obfs=salamander&obfs-password=obfspass#Hysteria2'
  ),
  (
    'tuic',
    'tuic://11111111-2222-3333-4444-555555555555:password123@tu1.example.net:443'
        '?sni=tu1.example.net&congestion_control=bbr#TUIC'
  ),
];

void main() {
  test('کانفیگ همه‌ی پروتکل‌ها نوشته می‌شود', () async {
    await _emit(Directory('/tmp/overx-configs'));
  });
}

Future<void> _emit(Directory outDir) async {
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  const settings = AppSettings();
  final report = <String, Object?>{
    'generatedAt': DateTime.now().toIso8601String(),
    'profiles': <Object?>[],
  };

  var failures = 0;

  for (final (name, link) in kSampleLinks) {
    final profile = LinkParser.parse(link);
    if (profile == null) {
      stderr.writeln('XX  $name -> لینک پارس نشد');
      failures++;
      continue;
    }

    final entry = <String, Object?>{
      'name': name,
      'protocol': profile.protocol.name,
      'files': <Object?>[],
    };

    // sing-box
    final sbPath = '${outDir.path}/$name.singbox.json';
    File(sbPath).writeAsStringSync(
      SingboxConfigBuilder.build(profile: profile, settings: settings),
    );

    (entry['files'] as List<Object?>)
        .add(<String, Object?>{'core': 'singbox', 'path': sbPath});

    // Xray پروتکل‌های مدرن (Hysteria2 / TUIC) را ندارد؛ سازنده درست خطا
    // می‌دهد. این را به عنوانِ «پشتیبانی نمی‌شود» ثبت می‌کنیم، نه شکست.
    String? xrayError;
    // دو نسخه: بدونِ TUN (قابلِ اعتبارسنجی بدونِ root) و با TUN
    for (final (suffix, tun) in <(String, bool)>[('', false), ('.tun', true)]) {
      final xrayPath = '${outDir.path}/$name.xray$suffix.json';
      try {
        File(xrayPath).writeAsStringSync(
          XrayConfigBuilder.build(
            profile: profile,
            settings: settings.copyWith(tunMode: tun),
          ),
        );
        final file = <String, Object?>{
          'core': 'xray',
          'path': xrayPath,
          if (tun) 'needsRoot': true,
        };
        (entry['files'] as List<Object?>).add(file);
      } catch (e) {
        xrayError = '$e'.split('\n').first;
        if (File(xrayPath).existsSync()) File(xrayPath).deleteSync();
      }
    }
    entry['xrayUnsupported'] = xrayError;

    final xrayNote = xrayError == null ? '' : '  [Xray: پشتیبانی نمی‌شود]';
    stdout.writeln('OK  $name (${profile.protocol.name})$xrayNote');
    (report['profiles'] as List<Object?>).add(entry);
  }

  report['failures'] = failures;
  File('${outDir.path}/manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));

  stdout.writeln('\n${kSampleLinks.length - failures} پروفایل در ${outDir.path}');
  if (failures > 0) exit(1);
}
