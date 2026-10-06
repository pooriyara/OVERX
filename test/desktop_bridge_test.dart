import 'package:overx/core/platform/desktop_bridge.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopCommands — تشخیص محیط لینوکس', () {
    test('GNOME / Ubuntu', () {
      expect(
        DesktopCommands.detectLinuxDesktop({'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'}),
        LinuxDesktopEnv.gnome,
      );
      expect(
        DesktopCommands.detectLinuxDesktop({'XDG_CURRENT_DESKTOP': 'GNOME'}),
        LinuxDesktopEnv.gnome,
      );
      expect(
        DesktopCommands.detectLinuxDesktop({'DESKTOP_SESSION': 'pop'}),
        LinuxDesktopEnv.gnome,
      );
    });

    test('KDE Plasma', () {
      expect(
        DesktopCommands.detectLinuxDesktop({'XDG_CURRENT_DESKTOP': 'KDE'}),
        LinuxDesktopEnv.kde,
      );
      expect(
        DesktopCommands.detectLinuxDesktop(
            {'XDG_CURRENT_DESKTOP': 'plasma:wayland'}),
        LinuxDesktopEnv.kde,
      );
    });

    test('نامشخص', () {
      expect(DesktopCommands.detectLinuxDesktop({}), LinuxDesktopEnv.unknown);
      expect(
        DesktopCommands.detectLinuxDesktop({'XDG_CURRENT_DESKTOP': 'i3'}),
        LinuxDesktopEnv.unknown,
      );
    });
  });

  group('DesktopCommands — پروکسی لینوکس', () {
    test('فعال‌سازی روی GNOME', () {
      final cmds = DesktopCommands.linuxProxy('127.0.0.1', 2080,
          enable: true, env: LinuxDesktopEnv.gnome);

      expect(cmds.length, 8);
      expect(cmds.first,
          ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'manual']);
      expect(
        cmds.any((c) =>
            c.join(' ').contains('org.gnome.system.proxy.socks port 2080')),
        true,
      );
      expect(
        cmds.any((c) => c.join(' ').contains('127.0.0.1')),
        true,
      );
    });

    test('غیرفعال‌سازی روی GNOME', () {
      final cmds = DesktopCommands.linuxProxy('127.0.0.1', 0,
          enable: false, env: LinuxDesktopEnv.gnome);
      expect(cmds, [
        ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'none'],
      ]);
    });

    test('فعال‌سازی روی KDE هر دو نسخه kwriteconfig را امتحان می‌کند', () {
      final cmds = DesktopCommands.linuxProxy('127.0.0.1', 2080,
          enable: true, env: LinuxDesktopEnv.kde);
      final bins = cmds.map((c) => c.first).toSet();
      expect(bins, {'kwriteconfig5', 'kwriteconfig6'});
      expect(cmds.any((c) => c.contains('1')), true);
    });

    test('محیط نامشخص → دستوری تولید نمی‌شود', () {
      expect(
        DesktopCommands.linuxProxy('127.0.0.1', 2080,
            enable: true, env: LinuxDesktopEnv.unknown),
        isEmpty,
      );
    });
  });

  group('DesktopCommands — پروکسی ویندوز', () {
    test('فعال‌سازی', () {
      final cmds =
          DesktopCommands.windowsProxy('127.0.0.1', 2080, enable: true);
      expect(cmds.length, 3);
      expect(cmds[0].join(' '), contains('ProxyEnable'));
      expect(cmds[0], contains('REG_DWORD'));
      expect(cmds[0], contains('1'));
      // آخرین آرگومان reg همیشه /f است (بدون تأیید)
      expect(cmds[0].last, '/f');
      expect(cmds[1].join(' '), contains('127.0.0.1:2080'));
      expect(cmds[2].join(' '), contains('<local>'));
    });

    test('غیرفعال‌سازی', () {
      final cmds = DesktopCommands.windowsProxy('', 0, enable: false);
      expect(cmds.length, 1);
      expect(cmds[0], contains('ProxyEnable'));
      expect(cmds[0], contains('0'));
    });
  });

  group('DesktopCommands — پروکسی macOS', () {
    test('روی همه سرویس‌ها اعمال می‌شود', () {
      final cmds = DesktopCommands.macProxy('127.0.0.1', 2080,
          enable: true, services: const ['Wi-Fi', 'Ethernet']);
      expect(cmds.length, 6);
      expect(cmds.any((c) => c.contains('Wi-Fi')), true);
      expect(cmds.any((c) => c.contains('Ethernet')), true);
      expect(cmds.any((c) => c.contains('-setsocksfirewallproxy')), true);
    });

    test('غیرفعال‌سازی', () {
      final cmds = DesktopCommands.macProxy('127.0.0.1', 2080,
          enable: false, services: const ['Wi-Fi']);
      expect(cmds.length, 3);
      expect(cmds.every((c) => c.last == 'off'), true);
    });
  });

  group('DesktopCommands — اجرا در شروع', () {
    test('لینوکس: فایل .desktop', () {
      final path = DesktopCommands.linuxAutostartPath('/home/u');
      expect(path, endsWith('com.overx.app.desktop'));
      expect(path, contains('.config'));
      expect(path, contains('autostart'));

      final content = DesktopCommands.linuxAutostartContent('/opt/OVERX/overx');
      expect(content, contains('[Desktop Entry]'));
      expect(content, contains('Exec=/opt/OVERX/overx'));
      expect(content, contains('X-GNOME-Autostart-enabled=true'));
    });

    test('ویندوز: رجیستری', () {
      final on =
          DesktopCommands.windowsAutostart(r'C:\OVERX\overx.exe', enable: true);
      expect(on.first.first, 'reg');
      expect(on.first, contains('OVERX'));
      expect(on.first.join(' '), contains('C:\\OVERX\\overx.exe'));

      final off =
          DesktopCommands.windowsAutostart(r'C:\OVERX\overx.exe', enable: false);
      expect(off.first, contains('delete'));
    });

    test('macOS: LaunchAgent', () {
      final path = DesktopCommands.macAutostartPath('/Users/u');
      expect(path, endsWith('com.overx.app.plist'));
      expect(path, contains('LaunchAgents'));

      final content = DesktopCommands.macAutostartContent('/Applications/OVERX');
      expect(content, contains('com.overx.app'));
      expect(content, contains('<key>RunAtLoad</key>'));
      expect(content, contains('<true/>'));
    });
  });

  group('DesktopBridge', () {
    test('قابلیت‌ها: پروکسی و auto-start دارد', () {
      final bridge = DesktopBridge();
      expect(bridge.features.has(PlatformFeature.systemProxy), true);
      expect(bridge.features.has(PlatformFeature.autoStart), true);
    });

    test('prepare همیشه موفق است و TUN دستی ندارد', () async {
      final bridge = DesktopBridge();
      expect(await bridge.prepare(), true);
      expect(await bridge.acquireTun(), isNull);
      expect(await bridge.nativeLibraryDir(), isNull);
    });

    test('clearSystemProxy خطای کنترل‌شده می‌دهد (بدون crash)', () async {
      final bridge = DesktopBridge();
      final r = await bridge.clearSystemProxy();
      expect(r, isA<bool>());
    });
  });
}
