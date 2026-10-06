import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:overx/core/models/app_package.dart';
import 'package:overx/core/config/link_parser.dart';
import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/settings.dart';
import 'package:overx/core/models/subscription.dart';
import 'package:overx/core/models/traffic.dart';
import 'package:overx/core/net/latency.dart';
import 'package:overx/core/net/sub_fetcher.dart';
import 'package:overx/core/process/binary_locator.dart';
import 'package:overx/core/process/core_process.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:overx/core/stats/stats_source.dart';
import 'package:overx/theme/app_theme.dart';
import 'package:overx/core/engine/core_adapter.dart';
import 'package:overx/core/engine/core_type.dart';
import 'package:overx/core/storage/repositories.dart';
import 'package:overx/l10n/strings.dart';

// ============================================================================
// State
// ============================================================================

class EngineState {
  const EngineState({
    this.status = ConnectionState2.disconnected,
    this.core = CoreType.singbox,
    this.profile,
    this.connectedAt,
    this.error,
    this.singboxVersion,
    this.xrayVersion,
    this.singboxPath,
    this.xrayPath,
  });

  final ConnectionState2 status;
  final CoreType core;
  final Profile? profile;
  final DateTime? connectedAt;
  final String? error;

  final String? singboxVersion;
  final String? xrayVersion;
  final String? singboxPath;
  final String? xrayPath;

  bool get isBusy => status == ConnectionState2.connecting;
  bool get isConnected => status == ConnectionState2.connected;

  Duration get uptime =>
      connectedAt == null ? Duration.zero : DateTime.now().difference(connectedAt!);

  EngineState copyWith({
    ConnectionState2? status,
    CoreType? core,
    Profile? profile,
    DateTime? connectedAt,
    String? error,
    String? singboxVersion,
    String? xrayVersion,
    String? singboxPath,
    String? xrayPath,
    bool clearError = false,
    bool clearUptime = false,
  }) =>
      EngineState(
        status: status ?? this.status,
        core: core ?? this.core,
        profile: profile ?? this.profile,
        connectedAt: clearUptime ? null : (connectedAt ?? this.connectedAt),
        error: clearError ? null : (error ?? this.error),
        singboxVersion: singboxVersion ?? this.singboxVersion,
        xrayVersion: xrayVersion ?? this.xrayVersion,
        singboxPath: singboxPath ?? this.singboxPath,
        xrayPath: xrayPath ?? this.xrayPath,
      );
}

// ============================================================================
// Controller
// ============================================================================

/// مغزِ برنامه: انتخاب هسته، تولید کانفیگ، اجرا/توقف، آمار و لاگ.
class EngineController extends Notifier<EngineState> {
  CoreProcess? _process;
  StatsSource? _stats;
  StreamSubscription? _logSub;
  Timer? _uptimeTicker;

  /// دسته‌ی TUN گرفته‌شده از پلتفرم (فقط اندروید).
  TunHandle? _tun;

  /// آیا پروکسی سیستم توسط ما تنظیم شده؟ (برای بازگردانی درست)
  bool _systemProxySet = false;

  /// آیا هسته از طریق libbox (درون‌فرآیندی) اجرا شده؟
  StreamSubscription<LibboxLogLine>? _libboxSub;
  StreamSubscription<void>? _libboxLogsClearedSub;
  bool _libboxStarted = false;

  /// بعد از dispose شدن کانتینر، هیچ کاری با ref انجام نمی‌دهیم
  /// (وگرنه Riverpod خطای «ProviderContainer disposed» می‌دهد).
  bool _disposed = false;

  /// اگر dispose شده باشیم، ref قابل استفاده نیست.
  bool get _alive => !_disposed;

  CoreAdapter get _adapter => CoreAdapter.of(state.core);

  @override
  EngineState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_teardown());
    });

    // تشخیص نسخه هسته‌ها در پس‌زمینه
    Future.microtask(probeVersions);

    return EngineState(core: _initialCore());
  }

  CoreType _initialCore() {
    final pref = ref.read(settingsProvider).activeCore;
    return switch (pref) {
      CoreTypePref.singbox => CoreType.singbox,
      CoreTypePref.xray => CoreType.xray,
    };
  }

  // ------------------------------------------------------------- lifecycle

  /// اتصال با پروفایل مشخص (یا پروفایل فعال).
  /// تبدیل تنظیماتِ «مسیریابیِ هر برنامه» به دو فهرستِ include/exclude.
  ///
  /// اگر قابلیت خاموش یا فهرست خالی باشد، هر دو خالی برمی‌گردند (یعنی همه).
  static (List<String>, List<String>) perAppLists(AppSettings s) {
    if (!s.perAppProxyEnabled || s.perAppPackages.isEmpty) {
      return (const <String>[], const <String>[]);
    }
    return s.perAppProxyMode.isInclude
        ? (s.perAppPackages, const <String>[])
        : (const <String>[], s.perAppPackages);
  }

  Future<void> connect([Profile? profile]) async {
    if (state.isBusy || state.isConnected) return;

    final settings = ref.read(settingsProvider);
    final target = profile ?? ref.read(activeProfileProvider);

    if (target == null) {
      state = state.copyWith(
        status: ConnectionState2.error,
        error: 'no profile selected',
      );
      return;
    }

    if (!_adapter.supports(target)) {
      state = state.copyWith(
        status: ConnectionState2.error,
        error: _adapter.unsupportedReason(target),
      );
      ref.read(logsProvider.notifier).add(
            LogLine(
              time: DateTime.now(),
              level: LogLevel.error,
              text: '${state.core.displayName}: '
                  '${_adapter.unsupportedReason(target)}',
            ),
          );
      return;
    }

    state = state.copyWith(
      status: ConnectionState2.connecting,
      profile: target,
      clearError: true,
    );

    final logs = ref.read(logsProvider.notifier);
    logs.add(LogLine(
      time: DateTime.now(),
      level: LogLevel.info,
      text: 'starting ${state.core.displayName} → ${target.name}',
    ));

    final bridge = ref.read(platformBridgeProvider);
    final libbox = ref.read(libboxServiceProvider);

    // روی اندروید، sing-box را فقط با libbox می‌توان با TUNِ کل دستگاه اجرا کرد:
    // باینری CLI آن fd را از فایل کانفیگ نمی‌پذیرد.
    final useLibbox =
        state.core == CoreType.singbox && settings.tunMode && libbox.available;

    try {
      // 0) آماده‌سازی پلتفرم (اندروید: مجوز VPN)
      if (settings.tunMode && bridge.features.has(PlatformFeature.vpnService)) {
        final ready = await bridge.prepare();
        if (_disposed) return;
        if (!ready) {
          throw CoreException(
            bridge.lastError ?? 'VPN permission was not granted',
          );
        }
        // در حالت libbox خودِ کتابخانه با صدا زدن openTun() اینترفیس را
        // می‌سازد و fd را از ما می‌گیرد؛ پیشاپیش چیزی نمی‌سازیم.
        if (!useLibbox) {
          _tun = await bridge.acquireTun();
          if (_tun != null) {
            logs.add(LogLine(
              time: DateTime.now(),
              level: LogLevel.info,
              text: 'tun fd acquired: ${_tun!.fd}',
            ));
          }
        }
      }

      // 1) باینری (در حالت libbox هسته داخلِ خودِ برنامه است)
      final String binary;
      if (useLibbox) {
        binary = 'libbox';
      } else {
        // اندروید: باینری همراه برنامه باید ابتدا executable شود
        final preinstalled = (await bridge.installedBinaries())[state.core.name];
        final resolved = preinstalled ??
            await _adapter.resolveBinary(
              settings,
              nativeLibraryDir: await bridge.nativeLibraryDir(),
            );
        if (_disposed) return;
        if (resolved == null) {
          throw CoreException(
            '${state.core.binaryName} not found. '
            'Set the path in Settings → Cores.',
          );
        }
        binary = resolved;
      }
      logs.add(LogLine(
        time: DateTime.now(),
        level: LogLevel.debug,
        text: 'binary: $binary',
      ));

      // 2) کانفیگ
      final dir = await BinaryLocator.dataDirectory();
      final configPath = p.join(dir.path, state.core.configFileName);
      final json = _adapter.buildConfig(
        profile: target,
        settings: settings,
        tunFd: _tun?.fd,
      );
      await File(configPath).writeAsString(json);
      if (_disposed) return;
      logs.add(LogLine(
        time: DateTime.now(),
        level: LogLevel.debug,
        text: 'config written: $configPath',
      ));
      if (state.core == CoreType.singbox && settings.tunMode && !useLibbox) {
        logs.add(LogLine(
          time: DateTime.now(),
          level: LogLevel.warning,
          text: 'sing-box CLI cannot receive a TUN fd from the config file. '
              'For full-device routing on Android use the libbox build '
              '(or a tun2socks helper) — see docs/ANDROID_TUN.md',
        ));
      }

      // 3) اجرا
      if (useLibbox) {
        _libboxSub?.cancel();
        _libboxSub = libbox.logs.listen((line) {
          logs.add(LogLine(
            time: DateTime.now(),
            level: line.level,
            text: line.message,
          ));
        });

        // هسته بعد از هر بارگذاریِ دوباره لاگ‌هایش را پاک می‌کند؛ ما هم
        // نمای کاربر را پاک می‌کنیم تا خطوطِ کهنه با خطوطِ تازه قاطی نشوند.
        _libboxLogsClearedSub = libbox.logsCleared.listen((_) => logs.clear());

        final lists = perAppLists(settings);
        await libbox.start(
          config: json,
          includePackages: lists.$1,
          excludePackages: lists.$2,
        );
        if (_disposed) return;
        _libboxStarted = true;

        logs.add(LogLine(
          time: DateTime.now(),
          level: LogLevel.info,
          text: 'sing-box started via libbox (in-process, tun owned by libbox)',
        ));
        // لاگ‌های زنده از `CoreCommandClient` (gRPCِ SubscribeLog) می‌رسند؛
        // سطح هر خط هم از sing-box می‌آید، نه از حدس روی متن.
        logs.add(LogLine(
          time: DateTime.now(),
          level: LogLevel.debug,
          text: 'live core logs are streamed from the libbox command server',
        ));
      } else {
        final proc = await CoreProcess.start(
          type: state.core,
          executable: binary,
          args: _adapter.runArgs(configPath),
          workingDirectory: dir.path,
          // Xray روی اندروید fd اینترفیس را از XRAY_TUN_FD می‌خواند
          environment: _tun?.env,
        );
        _process = proc;
        if (_disposed) {
          unawaited(proc.stop());
          return;
        }

        _logSub?.cancel();
        _logSub = proc.logs.listen((line) {
          logs.add(line);
          // هسته‌ای که بلافاصله با خطا خارج می‌شود
          if (line.level == LogLevel.error && state.isBusy) {
            // صبر می‌کنیم؛ اگر فرآیند مرد، exitCode مدیریت می‌کند
          }
        });

        unawaited(proc.process.exitCode.then(_onExit));

        logs.add(LogLine(
          time: DateTime.now(),
          level: LogLevel.info,
          text: '${state.core.displayName} started (pid ${proc.pid})',
        ));
      }

      // 4) آمار
      _stats = _adapter.createStats(settings: settings, binaryPath: binary);
      ref.read(trafficProvider.notifier).listen(_stats!);
      await _stats!.start();
      if (_disposed) return;

      // تنظیم پروکسی سیستم (اگر پلتفرم اجاره بدهد و کاربر خواسته باشد)
      if (settings.systemProxy &&
          bridge.features.has(PlatformFeature.systemProxy)) {
        final ok = await bridge.setSystemProxy(
          host: '127.0.0.1',
          port: settings.mixedPort,
        );
        if (_disposed) return;
        _systemProxySet = ok;
        logs.add(LogLine(
          time: DateTime.now(),
          level: ok ? LogLevel.info : LogLevel.warning,
          text: ok
              ? 'system proxy → 127.0.0.1:${settings.mixedPort}'
              : 'system proxy failed: ${bridge.lastError ?? 'unknown'}',
        ));
      }

      state = state.copyWith(
        status: ConnectionState2.connected,
        connectedAt: DateTime.now(),
      );
      _startUptimeTicker();
    } catch (e, st) {
      logs.add(LogLine(
        time: DateTime.now(),
        level: LogLevel.error,
        text: 'failed to start: $e',
      ));
      if (e is! CoreException) {
        logs.add(LogLine(
          time: DateTime.now(),
          level: LogLevel.debug,
          text: '$st',
        ));
      }
      if (_disposed) return;
      await _teardown();

      // تلاش با هسته‌ی دیگر اگر فعال باشد
      final other = state.core == CoreType.singbox ? CoreType.xray : CoreType.singbox;
      if (settings.autoSwitchCore && CoreAdapter.of(other).supports(target)) {
        logs.add(LogLine(
          time: DateTime.now(),
          level: LogLevel.warning,
          text: 'falling back to ${other.displayName}',
        ));
        state = state.copyWith(core: other);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await connect(target);
        return;
      }

      state = state.copyWith(
        status: ConnectionState2.error,
        error: '$e',
        clearUptime: true,
      );
    }
  }

  Future<void> disconnect() async {
    if (state.status == ConnectionState2.disconnected) return;
    await _teardown();
    state = state.copyWith(
      status: ConnectionState2.disconnected,
      clearUptime: true,
      clearError: true,
    );
    ref.read(logsProvider.notifier).add(
          LogLine(
            time: DateTime.now(),
            level: LogLevel.info,
            text: '${state.core.displayName} stopped',
          ),
        );
  }

  Future<void> toggle() async =>
      state.isConnected ? disconnect() : connect();

  /// تغییر هسته — فقط وقتی متصل نباشیم.
  Future<bool> switchCore(CoreType next) async {
    if (state.core == next) return true;
    if (state.isConnected || state.isBusy) return false;

    state = state.copyWith(core: next, clearError: true);
    ref.read(settingsProvider.notifier).setCore(next);
    ref.read(logsProvider.notifier).add(
          LogLine(
            time: DateTime.now(),
            level: LogLevel.info,
            text: 'active core → ${next.displayName}',
          ),
        );
    return true;
  }

  void _onExit(int code) {
    if (_disposed) return;
    if (!state.isConnected && !state.isBusy) return;

    final wasConnected = state.isConnected;
    final settings = ref.read(settingsProvider);
    final core = state.core;

    ref.read(logsProvider.notifier).add(
          LogLine(
            time: DateTime.now(),
            level: code == 0 ? LogLevel.info : LogLevel.error,
            text: '${core.displayName} exited with code $code',
          ),
        );

    // فرآیند به دستور خودمان متوقف شده — nothing to do.
    if (_process == null) return;

    if (wasConnected && settings.keepAlive && code != 0) {
      ref.read(logsProvider.notifier).add(
            LogLine(
              time: DateTime.now(),
              level: LogLevel.warning,
              text: 'keep-alive: restarting ${core.displayName} in 2s',
            ),
          );
      state = state.copyWith(
        status: ConnectionState2.disconnected,
        clearUptime: true,
      );
      Future<void>.delayed(const Duration(seconds: 2), () async {
        if (_disposed) return;
        await _teardown();
        await connect(state.profile);
      });
      return;
    }

    state = state.copyWith(
      status: ConnectionState2.disconnected,
      clearUptime: true,
      error: code == 0 ? null : 'core exited with code $code',
    );
  }

  void _startUptimeTicker() {
    _uptimeTicker?.cancel();
    _uptimeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.isConnected) {
        // صرفاً برای اینکه UI هر ثانیه بازسازی شود و زمان اتصال به‌روز شود
        state = state.copyWith();
      }
    });
  }

  Future<void> _teardown() async {
    // بازگردانی پروکسی سیستم و آزادسازی fd پیش از توقف فرآیند
    if (_alive && _systemProxySet) {
      _systemProxySet = false;
      final bridge = ref.read(platformBridgeProvider);
      if (bridge.features.has(PlatformFeature.systemProxy)) {
        await bridge.clearSystemProxy();
      }
    }
    if (_tun != null) {
      final bridge = ref.read(platformBridgeProvider);
      await bridge.releaseTun();
      _tun = null;
    }

    _uptimeTicker?.cancel();
    _uptimeTicker = null;

    if (_libboxStarted) {
      _libboxStarted = false;
      await ref.read(libboxServiceProvider).stop();
    }
    await _libboxSub?.cancel();
    _libboxSub = null;
    await _libboxLogsClearedSub?.cancel();
    _libboxLogsClearedSub = null;

    await _logSub?.cancel();
    _logSub = null;
    final stats = _stats;
    _stats = null;
    await stats?.dispose();
    final proc = _process;
    _process = null;
    await proc?.stop();
    if (_alive) ref.read(trafficProvider.notifier).reset();
  }

  // ------------------------------------------------------------- versions

  /// گرفتن نسخه‌ی هر دو هسته و ثبت در state.
  Future<void> probeVersions() async {
    final settings = ref.read(settingsProvider);

    for (final type in CoreType.values) {
      final path = await BinaryLocator.locate(
        type,
        overridePath: type == CoreType.singbox
            ? settings.singboxPath
            : settings.xrayPath,
      );
      if (_disposed) return;
      if (path == null) continue;
      final ver = await BinaryLocator.check(path, type);
      if (_disposed) return;
      state = switch (type) {
        CoreType.singbox => state.copyWith(singboxVersion: ver, singboxPath: path),
        CoreType.xray => state.copyWith(xrayVersion: ver, xrayPath: path),
      };
    }
  }

  /// بررسی دستی یک هسته (دکمه‌ی «بررسی» در صفحه هسته‌ها).
  Future<String?> checkCore(CoreType type) async {
    final settings = ref.read(settingsProvider);
    final path = await BinaryLocator.locate(
      type,
      overridePath: type == CoreType.singbox ? settings.singboxPath : settings.xrayPath,
    );
    if (path == null) return null;
    final ver = await BinaryLocator.check(path, type);
    if (_disposed) return ver;
    state = switch (type) {
      CoreType.singbox => state.copyWith(singboxVersion: ver, singboxPath: path),
      CoreType.xray => state.copyWith(xrayVersion: ver, xrayPath: path),
    };
    return ver;
  }
}

class CoreException implements Exception {
  const CoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ============================================================================
// Providers
// ============================================================================

final engineProvider =
    NotifierProvider<EngineController, EngineState>(EngineController.new);

/// نمونه‌ی لحظه‌ای ترافیک.
final trafficProvider = NotifierProvider<TrafficNotifier, TrafficSample>(
    TrafficNotifier.new);

class TrafficNotifier extends Notifier<TrafficSample> {
  StreamSubscription<TrafficSample>? _sub;

  @override
  TrafficSample build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _sub = null;
    });
    return TrafficSample.zero;
  }

  void listen(StatsSource source) {
    unawaited(_sub?.cancel());
    _sub = source.stream.listen((s) => state = s);
  }

  void reset() {
    state = TrafficSample.zero;
  }
}

/// آیا ثبت لاگ موقتاً متوقف است؟
final logsPausedProvider = StateProvider<bool>((ref) => false);

/// حلقه‌ی لاگ (حداکثر ۶۰۰ خط).
final logsProvider = NotifierProvider<LogsNotifier, List<LogLine>>(
    LogsNotifier.new);

class LogsNotifier extends Notifier<List<LogLine>> {
  static const max = 600;

  @override
  List<LogLine> build() => const [];

  bool get paused => ref.read(logsPausedProvider);

  void setPaused(bool v) => ref.read(logsPausedProvider.notifier).state = v;

  void togglePaused() =>
      ref.read(logsPausedProvider.notifier).state = !paused;

  void add(LogLine line) {
    if (paused) return;
    final next = [...state, line];
    if (next.length > max) next.removeRange(0, next.length - max);
    state = next;
  }

  void clear() => state = const [];
}

// ---------------------------------------------------------------- settings

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final repo = ref.watch(settingsRepositoryProvider);
    return repo.load();
  }

  Future<void> _save(AppSettings s) async {
    state = s;
    await ref.read(settingsRepositoryProvider).save(s);
  }

  Future<void> setLang(AppLang v) async => _save(state.copyWith(lang: v));
  Future<void> setThemeMode(ThemeModePref v) async => _save(state.copyWith(themeMode: v));
  Future<void> setCore(CoreType v) async => _save(state.copyWith(
        activeCore: v == CoreType.singbox ? CoreTypePref.singbox : CoreTypePref.xray,
      ));
  Future<void> setAutoStart(bool v) async => _save(state.copyWith(autoStart: v));
  Future<void> setAutoConnect(bool v) async => _save(state.copyWith(autoConnect: v));
  Future<void> setMinimizeToTray(bool v) async => _save(state.copyWith(minimizeToTray: v));
  Future<void> setTunMode(bool v) async => _save(state.copyWith(tunMode: v));
  Future<void> setSystemProxy(bool v) async => _save(state.copyWith(systemProxy: v));
  Future<void> setMixedPort(int v) async => _save(state.copyWith(mixedPort: v));
  Future<void> setRouteMode(RouteMode v) async => _save(state.copyWith(routeMode: v));
  Future<void> setBypassLan(bool v) async => _save(state.copyWith(bypassLan: v));
  Future<void> setSniffing(bool v) async => _save(state.copyWith(sniffing: v));
  Future<void> setMux(bool v) async => _save(state.copyWith(mux: v));
  Future<void> setIpv6(bool v) async => _save(state.copyWith(ipv6: v));
  Future<void> setDnsMode(DnsMode v) async => _save(state.copyWith(dnsMode: v));
  Future<void> setRemoteDns(String v) async => _save(state.copyWith(remoteDns: v));
  Future<void> setLocalDns(String v) async => _save(state.copyWith(localDns: v));
  Future<void> setLogLevel(LogLevel v) async => _save(state.copyWith(logLevel: v));
  Future<void> setSingboxApiPort(int v) async => _save(state.copyWith(singboxApiPort: v));
  Future<void> setXrayApiPort(int v) async => _save(state.copyWith(xrayApiPort: v));
  Future<void> setAutoSwitchCore(bool v) async => _save(state.copyWith(autoSwitchCore: v));
  Future<void> setKeepAlive(bool v) async => _save(state.copyWith(keepAlive: v));
  Future<void> setPerAppProxyEnabled(bool v) async =>
      _save(state.copyWith(perAppProxyEnabled: v));
  Future<void> setPerAppProxyMode(PerAppProxyMode v) async =>
      _save(state.copyWith(perAppProxyMode: v));
  Future<void> setPerAppPackages(List<String> v) async =>
      _save(state.copyWith(perAppPackages: v));

  Future<void> setSingboxPath(String? v) async => _save(state.copyWith(singboxPath: v));
  Future<void> setXrayPath(String? v) async => _save(state.copyWith(xrayPath: v));
  Future<void> setActiveProfileId(String? v) async => _save(state.copyWith(activeProfileId: v));

  Future<void> reset() =>
      _save(ref.read(settingsRepositoryProvider).defaults());

  /// مقداردهیِ یک‌جای چند فیلد — برای ابزار تولید تصویر و تست‌ها.
  Future<void> prime({ThemeModePref? theme, AppLang? lang}) =>
      _save(state.copyWith(
        themeMode: theme,
        lang: lang,
      ));
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError('override in main() after SharedPreferences init');
});

// ---------------------------------------------------------------- profiles

final profilesProvider =
    NotifierProvider<ProfilesController, List<Profile>>(ProfilesController.new);

class ProfilesController extends Notifier<List<Profile>> {
  @override
  List<Profile> build() => ref.watch(profileRepositoryProvider).load();

  Future<void> _commit(List<Profile> next) async {
    state = next;
    await ref.read(profileRepositoryProvider).save(next);
  }

  Future<void> add(Profile p) => _commit([...state, p]);

  Future<void> remove(String id) =>
      _commit(state.where((e) => e.id != id).toList());

  Future<void> update(Profile p) => _commit(
        state.map((e) => e.id == p.id ? p : e).toList(),
      );

  /// افزودن از یک یا چند لینک.
  /// برگشت: تعداد پروفایل‌هایی که با موفقیت اضافه شدند.
  Future<int> addFromText(String text, {String? groupId}) async {
    var parsed = LinkParser.parseMany(text);
    if (groupId != null) {
      parsed = [for (final e in parsed) e.copyWith(groupId: groupId)];
    }
    if (parsed.isEmpty) return 0;
    await _commit([...state, ...parsed]);
    return parsed.length;
  }

  /// افزودنِ چند پروفایلِ آماده (مثلاً خروجیِ پارسِ یک اشتراک).
  Future<int> addMany(List<Profile> items) async {
    if (items.isEmpty) return 0;
    await _commit([...state, ...items]);
    return items.length;
  }

  /// جایگزینیِ پروفایل‌های یک گروه (برای «آپدیت اشتراک»).
  Future<void> replaceGroup(String groupId, List<Profile> next) async {
    final kept = state.where((e) => e.groupId != groupId).toList();
    await _commit([...kept, ...next]);
  }

  /// حذفِ پروفایل‌های یک گروه.
  Future<void> removeGroup(String groupId) async =>
      _commit(state.where((e) => e.groupId != groupId).toList());

  Future<void> select(String id) =>
      ref.read(settingsProvider.notifier).setActiveProfileId(id);

  /// مرتب‌سازی بر اساس پینگ (بدون پینگ آخر لیست).
  Future<void> sortByPing() async {
    final next = [...state]..sort((a, b) {
        final la = a.latencyMs;
        final lb = b.latencyMs;
        if (la == null && lb == null) return 0;
        if (la == null) return 1;
        if (lb == null) return -1;
        return la.compareTo(lb);
      });
    await _commit(next);
  }

  /// پینگِ واقعی گرفتن برای یک پروفایل و ذخیره‌ی آن.
  Future<int?> realPing(Profile p) async {
    final ms = await LatencyTester.tcpPing(p.address, p.port);
    await update(p.copyWith(latencyMs: ms));
    return ms;
  }

  /// پینگِ واقعی برای چند پروفایل به‌صورت هم‌زمان (محدود).
  Future<void> realPingAll(List<Profile> targets) async {
    const conc = 8;
    for (var i = 0; i < targets.length; i += conc) {
      final chunk = targets.sublist(i, (i + conc).clamp(0, targets.length));
      await Future.wait(chunk.map(realPing));
    }
  }

  /// جایگزینیِ کامل لیست — برای ابزار تولید تصویر و تست‌ها.
  Future<void> seed(List<Profile> items) => _commit(items);
}

// ------------------------------------------------------------- subscriptions

final subscriptionsProvider =
    NotifierProvider<SubscriptionsController, List<Subscription>>(
        SubscriptionsController.new);

class SubscriptionsController extends Notifier<List<Subscription>> {
  @override
  List<Subscription> build() =>
      ref.watch(profileRepositoryProvider).loadSubscriptions();

  Future<void> _commit(List<Subscription> next) async {
    state = next;
    await ref.read(profileRepositoryProvider).saveSubscriptions(next);
  }

  /// افزودنِ یک اشتراک از URL: دریافت، پارس، و ساختِ گروه.
  /// برگشت: تعداد پروفایل‌های افزوده‌شده؛ خطاها را می‌اندازد.
  Future<int> addFromUrl(String name, String url) async {
    final body = await SubscriptionFetcher.fetchBody(url);
    final parsed = LinkParser.parseMany(body);
    if (parsed.isEmpty) {
      throw const SubscriptionFetchException('اشتراکی لینکی برنگرداند');
    }
    final sub = Subscription(
      id: 'sub-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? Uri.parse(url).host : name.trim(),
      url: url.trim(),
      updatedAt: DateTime.now(),
    );
    final withGroup = [for (final e in parsed) e.copyWith(groupId: sub.id)];
    await ref.read(profilesProvider.notifier).addMany(withGroup);
    await _commit([...state, sub]);
    return withGroup.length;
  }

  /// افزودنِ دستی/کلیپ‌برد به‌صورت یک گروهِ بدون URL.
  Future<int> addFromTextAsGroup(String name, String text) async {
    final sub = Subscription(
      id: 'sub-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'دستی' : name.trim(),
      updatedAt: DateTime.now(),
    );
    final count = await ref
        .read(profilesProvider.notifier)
        .addFromText(text, groupId: sub.id);
    if (count == 0) return 0;
    await _commit([...state, sub]);
    return count;
  }

  /// به‌روزرسانیِ یک اشتراک از URL اش.
  Future<int> update(String id) async {
    final sub = state.where((e) => e.id == id).firstOrNull;
    if (sub == null || sub.url == null) return 0;
    final body = await SubscriptionFetcher.fetchBody(sub.url!);
    final parsed = LinkParser.parseMany(body);
    if (parsed.isEmpty) {
      throw const SubscriptionFetchException('اشتراکی لینکی برنگرداند');
    }
    // نگه‌داشتنِ پینگِ قبلی برای پروفایل‌های هم‌نام تا مرتب‌سازی معنا داشته باشد.
    final old = ref
        .read(profilesProvider)
        .where((e) => e.groupId == id)
        .toList();
    final oldByName = {for (final e in old) e.rawLink ?? e.id: e.latencyMs};
    final withGroup = [
      for (final e in parsed)
        e.copyWith(
          groupId: id,
          latencyMs: oldByName[e.rawLink ?? e.id],
        ),
    ];
    await ref.read(profilesProvider.notifier).replaceGroup(id, withGroup);
    await _commit([
      for (final e in state)
        if (e.id == id) e.copyWith(updatedAt: DateTime.now()) else e,
    ]);
    return withGroup.length;
  }

  Future<void> remove(String id) async {
    await ref.read(profilesProvider.notifier).removeGroup(id);
    await _commit(state.where((e) => e.id != id).toList());
  }

  Future<void> rename(String id, String name) => _commit([
        for (final e in state) if (e.id == id) e.copyWith(name: name) else e,
      ]);
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  throw UnimplementedError('override in main() after SharedPreferences init');
});

/// پروفایل فعال.
final activeProfileProvider = Provider<Profile?>((ref) {
  final all = ref.watch(profilesProvider);
  if (all.isEmpty) return null;
  final id = ref.watch(settingsProvider).activeProfileId;
  return all.where((e) => e.id == id).firstOrNull ?? all.first;
});
