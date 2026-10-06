import 'package:overx/l10n/strings.dart';
import 'package:overx/core/models/settings.dart';
import 'package:overx/core/models/traffic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatting', () {
    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), startsWith('1 KB'));
      expect(formatBytes(1048576), startsWith('1 MB'));
      expect(formatBytes(1073741824), startsWith('1 GB'));
    });

    test('formatSpeed', () {
      expect(formatSpeed(2048), contains('/s'));
    });

    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 5)), '00:00:05');
      expect(formatDuration(const Duration(minutes: 3, seconds: 4)), '00:03:04');
      expect(formatDuration(const Duration(hours: 2)), '02:00:00');
    });
  });

  group('AppSettings', () {
    test('پیش‌فرض‌ها', () {
      const s = AppSettings();
      expect(s.activeCore, CoreTypePref.singbox);
      expect(s.tunMode, true);
      expect(s.mixedPort, 2080);
      expect(s.singboxApiPort, 9090);
      expect(s.xrayApiPort, 8080);
    });

    test('رفت‌وبرگشت JSON همه فیلدها را حفظ می‌کند', () {
      final s = const AppSettings().copyWith(
        lang: AppLang.en,
        themeMode: ThemeModePref.light,
        activeCore: CoreTypePref.xray,
        mixedPort: 3090,
        routeMode: RouteMode.global,
        dnsMode: DnsMode.local,
        logLevel: LogLevel.debug,
        mux: true,
        ipv6: true,
        bypassLan: false,
        sniffing: false,
        xrayApiPort: 18080,
        activeProfileId: 'abc',
      );
      final back = AppSettings.fromJson(s.toJson());

      expect(back.lang, AppLang.en);
      expect(back.themeMode, ThemeModePref.light);
      expect(back.activeCore, CoreTypePref.xray);
      expect(back.mixedPort, 3090);
      expect(back.routeMode, RouteMode.global);
      expect(back.dnsMode, DnsMode.local);
      expect(back.logLevel, LogLevel.debug);
      expect(back.mux, true);
      expect(back.ipv6, true);
      expect(back.bypassLan, false);
      expect(back.sniffing, false);
      expect(back.xrayApiPort, 18080);
      expect(back.activeProfileId, 'abc');
    });

    test('JSON خراب → پیش‌فرض', () {
      final s = AppSettings.fromJson(<String, dynamic>{});
      expect(s.mixedPort, 2080);
      expect(s.activeCore, CoreTypePref.singbox);
    });

    test('copyWith فقط فیلد مورد نظر را تغییر می‌دهد', () {
      const s = AppSettings();
      final next = s.copyWith(mux: true);
      expect(next.mux, true);
      expect(next.tunMode, s.tunMode);
      expect(next.dnsMode, s.dnsMode);
    });
  });
}
