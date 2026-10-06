import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:overx/core/models/app_package.dart';

import 'platform_bridge.dart';

/// محیط دسکتاپ لینوکس — برای انتخاب روشِ تنظیم پروکسی.
enum LinuxDesktopEnv { gnome, kde, unknown }

/// سازنده‌های دستور. **توابع خالص** هستند تا بدون اجرای واقعی
/// بشه تست‌شان کرد (نگاه کن به test/desktop_bridge_test.dart).
abstract class DesktopCommands {
  static const String winKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const String winRunKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _linuxAutostartId = 'com.overx.app.desktop';
  static const String _macLaunchAgentId = 'com.overx.app.plist';
  static const String _macLabel = 'com.overx.app';

  /// تشخیص محیط از روی متغیرهای محیطی.
  static LinuxDesktopEnv detectLinuxDesktop(Map<String, String> env) {
    final current = (env['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
    final desktop = (env['DESKTOP_SESSION'] ?? '').toLowerCase();

    if (current.contains('gnome') ||
        current.contains('ubuntu') ||
        current.contains('pop') ||
        desktop.contains('gnome') ||
        desktop.contains('ubuntu') ||
        desktop.contains('pop')) {
      return LinuxDesktopEnv.gnome;
    }
    if (current.contains('kde') ||
        current.contains('plasma') ||
        desktop.contains('plasma') ||
        desktop.contains('kde')) {
      return LinuxDesktopEnv.kde;
    }
    return LinuxDesktopEnv.unknown;
  }

  /// دستورات تنظیم/پاک کردن پروکسی روی لینوکس.
  static List<List<String>> linuxProxy(
    String host,
    int port, {
    required bool enable,
    required LinuxDesktopEnv env,
  }) {
    if (!enable) {
      return switch (env) {
        LinuxDesktopEnv.gnome => [
            ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'none'],
          ],
        LinuxDesktopEnv.kde => [
            [
              'kwriteconfig5',
              '--file',
              'kioslaverc',
              '--group',
              'Proxy Settings',
              '--key',
              'ProxyType',
              '0',
            ],
            // تلاش با kwriteconfig6 اگر نسخه‌ی ۵ نباشد
            [
              'kwriteconfig6',
              '--file',
              'kioslaverc',
              '--group',
              'Proxy Settings',
              '--key',
              'ProxyType',
              '0',
            ],
          ],
        LinuxDesktopEnv.unknown => const [],
      };
    }

    final socks = '$host:$port';
    return switch (env) {
      LinuxDesktopEnv.gnome => [
          ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'manual'],
          [
            'gsettings',
            'set',
            'org.gnome.system.proxy.http',
            'host',
            host,
          ],
          ['gsettings', 'set', 'org.gnome.system.proxy.http', 'port', '$port'],
          [
            'gsettings',
            'set',
            'org.gnome.system.proxy.https',
            'host',
            host,
          ],
          ['gsettings', 'set', 'org.gnome.system.proxy.https', 'port', '$port'],
          [
            'gsettings',
            'set',
            'org.gnome.system.proxy.socks',
            'host',
            host,
          ],
          ['gsettings', 'set', 'org.gnome.system.proxy.socks', 'port', '$port'],
          [
            'gsettings',
            'set',
            'org.gnome.system.proxy',
            'ignore-hosts',
            "['localhost', '127.0.0.1', '::1']",
          ],
        ],
      LinuxDesktopEnv.kde => [
          for (final bin in const ['kwriteconfig5', 'kwriteconfig6']) ...[
            [
              bin,
              '--file',
              'kioslaverc',
              '--group',
              'Proxy Settings',
              '--key',
              'ProxyType',
              '1',
            ],
            [
              bin,
              '--file',
              'kioslaverc',
              '--group',
              'Proxy Settings',
              '--key',
              'httpProxy',
              'http://$socks',
            ],
            [
              bin,
              '--file',
              'kioslaverc',
              '--group',
              'Proxy Settings',
              '--key',
              'httpsProxy',
              'http://$socks',
            ],
            [
              bin,
              '--file',
              'kioslaverc',
              '--group',
              'Proxy Settings',
              '--key',
              'socksProxy',
              socks,
            ],
          ],
        ],
      LinuxDesktopEnv.unknown => const [],
    };
  }

  /// دستورات تنظیم/پاک کردن پروکسی روی ویندوز (رجیستری).
  static List<List<String>> windowsProxy(
    String host,
    int port, {
    required bool enable,
  }) {
    if (!enable) {
      return [
        ['reg', 'add', winKey, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f'],
      ];
    }
    return [
      ['reg', 'add', winKey, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f'],
      ['reg', 'add', winKey, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', '$host:$port', '/f'],
      [
        'reg',
        'add',
        winKey,
        '/v',
        'ProxyOverride',
        '/t',
        'REG_SZ',
        '/d',
        'localhost;127.0.0.1;<local>',
        '/f',
      ],
    ];
  }

  /// دستورات تنظیم/پاک کردن پروکسی روی macOS.
  static List<List<String>> macProxy(
    String host,
    int port, {
    required bool enable,
    List<String> services = const ['Wi-Fi', 'Ethernet'],
  }) {
    final cmds = <List<String>>[];
    for (final s in services) {
      if (enable) {
        cmds.addAll([
          ['networksetup', '-setwebproxy', s, host, '$port'],
          ['networksetup', '-setsecurewebproxy', s, host, '$port'],
          ['networksetup', '-setsocksfirewallproxy', s, host, '$port'],
        ]);
      } else {
        cmds.addAll([
          ['networksetup', '-setwebproxystate', s, 'off'],
          ['networksetup', '-setsecurewebproxystate', s, 'off'],
          ['networksetup', '-setsocksfirewallproxystate', s, 'off'],
        ]);
      }
    }
    return cmds;
  }

  // ---------------------------------------------------------------- autostart

  static String linuxAutostartPath(String home) =>
      p.join(home, '.config', 'autostart', _linuxAutostartId);

  static String linuxAutostartContent(String execPath) => '''
[Desktop Entry]
Type=Application
Version=1.0
Name=OVERX
Comment=OVERX — sing-box & Xray
Exec=$execPath --minimized
Icon=overx
Terminal=false
Categories=Network;
X-GNOME-Autostart-enabled=true
Hidden=false
''';

  static List<List<String>> windowsAutostart(
    String exePath, {
    required bool enable,
  }) =>
      enable
          ? [
              [
                'reg',
                'add',
                winRunKey,
                '/v',
                'OVERX',
                '/t',
                'REG_SZ',
                '/d',
                exePath,
                '/f',
              ],
            ]
          : [
              ['reg', 'delete', winRunKey, '/v', 'OVERX', '/f'],
            ];

  static String macAutostartPath(String home) =>
      p.join(home, 'Library', 'LaunchAgents', _macLaunchAgentId);

  static String macAutostartContent(String executable) => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_macLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>$executable</string>
    <string>--minimized</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
''';
}

/// پیاده‌سازی دسکتاپ (لینوکس / ویندوز / macOS).
class DesktopBridge implements PlatformBridge {
  DesktopBridge({ProcessRunner? runner})
      : _runner = runner ?? const ProcessRunner(),
        _env = Platform.environment;

  final ProcessRunner _runner;
  final Map<String, String> _env;

  LinuxDesktopEnv? _linuxEnv;

  @override
  PlatformFeatures get features => PlatformFeatures(<PlatformFeature>{
        PlatformFeature.systemProxy,
        PlatformFeature.autoStart,
        // TUN بومی روی لینوکس/ویندوز/مک توسط خود هسته ساخته می‌شود
        if (!Platform.isWindows) PlatformFeature.tunFd,
      });

  @override
  String? lastError;

  LinuxDesktopEnv get linuxEnv =>
      _linuxEnv ??= DesktopCommands.detectLinuxDesktop(_env);

  String get _home =>
      _env['HOME'] ?? _env['USERPROFILE'] ?? Directory.current.path;

  @override
  Future<bool> prepare() async => true;

  @override
  Future<TunHandle?> acquireTun({int mtu = 9000}) async => null;

  @override
  Future<void> releaseTun() async {}

  @override
  Future<bool> setSystemProxy({required String host, required int port}) =>
      _applyProxy(host, port, enable: true);

  @override
  Future<bool> clearSystemProxy() => _applyProxy('127.0.0.1', 0, enable: false);

  Future<bool> _applyProxy(
    String host,
    int port, {
    required bool enable,
  }) async {
    final cmds = _proxyCommands(host, port, enable: enable);
    if (cmds.isEmpty) {
      lastError = Platform.isLinux
          ? 'محیط دسکتاپ شناخته نشد (فقط GNOME و KDE پشتیبانی می‌شوند)'
          : 'تنظیم پروکسی روی این پلتفرم پشتیبانی نمی‌شود';
      return false;
    }

    var ok = false;
    for (final c in cmds) {
      final r = await _runner.run(c.first, c.sublist(1));
      // روی KDE هر دو kwriteconfig تلاش می‌شود؛ موفقیتِ یکی کافی است
      if (r.exitCode == 0) ok = true;
    }
    if (!ok) lastError = 'اجرای دستورات پروکسی ناموفق بود';
    return ok;
  }

  /// ساخت دستورات متناسب با سیستم‌عامل فعلی.
  List<List<String>> _proxyCommands(
    String host,
    int port, {
    required bool enable,
  }) {
    if (Platform.isLinux) {
      return DesktopCommands.linuxProxy(host, port,
          enable: enable, env: linuxEnv);
    }
    if (Platform.isWindows) {
      return DesktopCommands.windowsProxy(host, port, enable: enable);
    }
    if (Platform.isMacOS) {
      return DesktopCommands.macProxy(host, port, enable: enable);
    }
    return const [];
  }

  @override
  Future<bool> setAutoStart(bool enable) async {
    try {
      if (Platform.isLinux) {
        final file = File(DesktopCommands.linuxAutostartPath(_home));
        if (!enable) {
          if (await file.exists()) await file.delete();
          return true;
        }
        await file.parent.create(recursive: true);
        await file.writeAsString(
          DesktopCommands.linuxAutostartContent(Platform.resolvedExecutable),
        );
        return true;
      }

      if (Platform.isWindows) {
        var ok = false;
        for (final c in DesktopCommands.windowsAutostart(
          Platform.resolvedExecutable,
          enable: enable,
        )) {
          final r = await _runner.run(c.first, c.sublist(1));
          if (r.exitCode == 0) ok = true;
        }
        return ok;
      }

      if (Platform.isMacOS) {
        final file = File(DesktopCommands.macAutostartPath(_home));
        if (!enable) {
          if (await file.exists()) await file.delete();
          return true;
        }
        await file.parent.create(recursive: true);
        await file.writeAsString(
          DesktopCommands.macAutostartContent(Platform.resolvedExecutable),
        );
        return true;
      }
    } catch (e) {
      lastError = '$e';
      return false;
    }
    return false;
  }

  @override
  Future<bool> isAutoStartEnabled() async {
    try {
      if (Platform.isLinux) {
        return File(DesktopCommands.linuxAutostartPath(_home)).existsSync();
      }
      if (Platform.isMacOS) {
        return File(DesktopCommands.macAutostartPath(_home)).existsSync();
      }
      if (Platform.isWindows) {
        final r = await _runner.run('reg', [
          'query',
          DesktopCommands.winRunKey,
          '/v',
          'OVERX',
        ]);
        return r.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  @override
  Future<String?> nativeLibraryDir() async => null;

  @override
  Future<List<AppPackage>> listInstalledPackages({
    bool includeSystem = false,
  }) async =>
      const <AppPackage>[];

  /// روی دسکتاپ آیکونی نداریم (فهرستِ برنامه‌ها هم اصلاً خالی است).
  @override
  Future<Uint8List?> appIcon(String packageName, {int size = 64}) async => null;

  @override
  Future<Map<String, String>> installedBinaries() async => const <String, String>{};


  @override
  Future<void> dispose() async {}
}

/// لایه‌ی نازک روی Process.run — برای جایگزینی در تست‌ها.
class ProcessRunner {
  const ProcessRunner();

  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    bool runInShell = false,
  }) =>
      Process.run(executable, args, runInShell: runInShell);

  Future<ProcessResult> runShell(String command) =>
      Process.run('/bin/sh', ['-c', command]);
}
