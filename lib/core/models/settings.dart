import 'package:overx/core/models/app_package.dart';
import 'package:overx/l10n/strings.dart';

/// حالت مسیریابی.
enum RouteMode { rule, global, direct }

/// حالت DNS.
enum DnsMode { fakeIp, remote, local }

/// تم.
enum ThemeModePref { system, light, dark }

/// سطح لاگ.
enum LogLevel { debug, info, warning, error }

/// همه تنظیمات قابل‌ذخیره برنامه.
class AppSettings {
  const AppSettings({
    this.lang = AppLang.fa,
    this.themeMode = ThemeModePref.dark,
    this.activeCore = CoreTypePref.singbox,
    this.autoStart = false,
    this.autoConnect = false,
    this.minimizeToTray = true,
    this.tunMode = true,
    this.systemProxy = true,
    this.mixedPort = 2080,
    this.routeMode = RouteMode.rule,
    this.bypassLan = true,
    this.sniffing = true,
    this.mux = false,
    this.ipv6 = false,
    this.dnsMode = DnsMode.fakeIp,
    this.remoteDns = 'https://1.1.1.1/dns-query',
    this.localDns = '8.8.8.8',
    this.logLevel = LogLevel.info,
    this.singboxApiPort = 9090,
    this.xrayApiPort = 8080,
    this.autoSwitchCore = false,
    this.keepAlive = true,
    this.coreBeta = false,
    this.perAppProxyEnabled = false,
    this.perAppProxyMode = PerAppProxyMode.exclude,
    this.perAppPackages = const <String>[],
    this.singboxPath,
    this.xrayPath,
    this.activeProfileId,
  });

  final AppLang lang;
  final ThemeModePref themeMode;

  /// هسته‌ی فعال (ترجیح کاربر).
  final CoreTypePref activeCore;

  final bool autoStart;
  final bool autoConnect;
  final bool minimizeToTray;

  final bool tunMode;
  final bool systemProxy;

  // ------------------------------------------- مسیریابیِ هر برنامه (اندروید)
  /// آیا فقط بعضی برنامه‌ها (یا همه به‌جز بعضی) از VPN عبور کنند؟
  final bool perAppProxyEnabled;
  final PerAppProxyMode perAppProxyMode;

  /// نام بسته‌های انتخاب‌شده.
  final List<String> perAppPackages;
  final int mixedPort;
  final RouteMode routeMode;
  final bool bypassLan;
  final bool sniffing;
  final bool mux;
  final bool ipv6;

  final DnsMode dnsMode;
  final String remoteDns;
  final String localDns;

  final LogLevel logLevel;
  final int singboxApiPort;
  final int xrayApiPort;

  final bool autoSwitchCore;
  final bool keepAlive;

  /// بررسیِ نسخه‌های بتا/پیش‌انتشار هسته‌ها.
  final bool coreBeta;

  /// مسیرِ دستیِ باینری (اگر null باشه، خودکار پیدا می‌شه).
  final String? singboxPath;
  final String? xrayPath;

  final String? activeProfileId;

  AppSettings copyWith({
    AppLang? lang,
    ThemeModePref? themeMode,
    CoreTypePref? activeCore,
    bool? autoStart,
    bool? autoConnect,
    bool? minimizeToTray,
    bool? tunMode,
    bool? systemProxy,
    int? mixedPort,
    RouteMode? routeMode,
    bool? bypassLan,
    bool? sniffing,
    bool? mux,
    bool? ipv6,
    DnsMode? dnsMode,
    String? remoteDns,
    String? localDns,
    LogLevel? logLevel,
    int? singboxApiPort,
    int? xrayApiPort,
    bool? autoSwitchCore,
    bool? keepAlive,
    bool? coreBeta,
    String? singboxPath,
    String? xrayPath,
    String? activeProfileId,
    bool? perAppProxyEnabled,
    PerAppProxyMode? perAppProxyMode,
    List<String>? perAppPackages,
  }) =>
      AppSettings(
        lang: lang ?? this.lang,
        themeMode: themeMode ?? this.themeMode,
        activeCore: activeCore ?? this.activeCore,
        autoStart: autoStart ?? this.autoStart,
        autoConnect: autoConnect ?? this.autoConnect,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
        tunMode: tunMode ?? this.tunMode,
        systemProxy: systemProxy ?? this.systemProxy,
        mixedPort: mixedPort ?? this.mixedPort,
        routeMode: routeMode ?? this.routeMode,
        bypassLan: bypassLan ?? this.bypassLan,
        sniffing: sniffing ?? this.sniffing,
        mux: mux ?? this.mux,
        ipv6: ipv6 ?? this.ipv6,
        dnsMode: dnsMode ?? this.dnsMode,
        remoteDns: remoteDns ?? this.remoteDns,
        localDns: localDns ?? this.localDns,
        logLevel: logLevel ?? this.logLevel,
        singboxApiPort: singboxApiPort ?? this.singboxApiPort,
        xrayApiPort: xrayApiPort ?? this.xrayApiPort,
        autoSwitchCore: autoSwitchCore ?? this.autoSwitchCore,
        keepAlive: keepAlive ?? this.keepAlive,
        coreBeta: coreBeta ?? this.coreBeta,
        singboxPath: singboxPath ?? this.singboxPath,
        xrayPath: xrayPath ?? this.xrayPath,
        activeProfileId: activeProfileId ?? this.activeProfileId,
        perAppProxyEnabled: perAppProxyEnabled ?? this.perAppProxyEnabled,
        perAppProxyMode: perAppProxyMode ?? this.perAppProxyMode,
        perAppPackages: perAppPackages ?? this.perAppPackages,
      );

  Map<String, dynamic> toJson() => {
        'lang': lang.name,
        'themeMode': themeMode.name,
        'activeCore': activeCore.name,
        'autoStart': autoStart,
        'autoConnect': autoConnect,
        'minimizeToTray': minimizeToTray,
        'tunMode': tunMode,
        'systemProxy': systemProxy,
        'mixedPort': mixedPort,
        'routeMode': routeMode.name,
        'bypassLan': bypassLan,
        'sniffing': sniffing,
        'mux': mux,
        'ipv6': ipv6,
        'dnsMode': dnsMode.name,
        'remoteDns': remoteDns,
        'localDns': localDns,
        'logLevel': logLevel.name,
        'singboxApiPort': singboxApiPort,
        'xrayApiPort': xrayApiPort,
        'autoSwitchCore': autoSwitchCore,
        'keepAlive': keepAlive,
        'coreBeta': coreBeta,
        'perAppProxyEnabled': perAppProxyEnabled,
        'perAppProxyMode': perAppProxyMode.name,
        'perAppPackages': perAppPackages,
        if (singboxPath != null) 'singboxPath': singboxPath,
        if (xrayPath != null) 'xrayPath': xrayPath,
        if (activeProfileId != null) 'activeProfileId': activeProfileId,
      };

  static AppSettings fromJson(Map<String, dynamic> j) {
    T enumOf<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.firstWhere((e) => e.name == name, orElse: () => fallback);

    return AppSettings(
      lang: enumOf(AppLang.values, j['lang'] as String?, AppLang.fa),
      themeMode: enumOf(
          ThemeModePref.values, j['themeMode'] as String?, ThemeModePref.dark),
      activeCore: enumOf(CoreTypePref.values, j['activeCore'] as String?,
          CoreTypePref.singbox),
      autoStart: j['autoStart'] as bool? ?? false,
      autoConnect: j['autoConnect'] as bool? ?? false,
      minimizeToTray: j['minimizeToTray'] as bool? ?? true,
      tunMode: j['tunMode'] as bool? ?? true,
      systemProxy: j['systemProxy'] as bool? ?? true,
      mixedPort: (j['mixedPort'] as num?)?.toInt() ?? 2080,
      routeMode:
          enumOf(RouteMode.values, j['routeMode'] as String?, RouteMode.rule),
      bypassLan: j['bypassLan'] as bool? ?? true,
      sniffing: j['sniffing'] as bool? ?? true,
      mux: j['mux'] as bool? ?? false,
      ipv6: j['ipv6'] as bool? ?? false,
      dnsMode:
          enumOf(DnsMode.values, j['dnsMode'] as String?, DnsMode.fakeIp),
      remoteDns: j['remoteDns'] as String? ?? 'https://1.1.1.1/dns-query',
      localDns: j['localDns'] as String? ?? '8.8.8.8',
      logLevel:
          enumOf(LogLevel.values, j['logLevel'] as String?, LogLevel.info),
      singboxApiPort: (j['singboxApiPort'] as num?)?.toInt() ?? 9090,
      xrayApiPort: (j['xrayApiPort'] as num?)?.toInt() ?? 8080,
      autoSwitchCore: j['autoSwitchCore'] as bool? ?? false,
      keepAlive: j['keepAlive'] as bool? ?? true,
      coreBeta: j['coreBeta'] as bool? ?? false,
      singboxPath: j['singboxPath'] as String?,
      xrayPath: j['xrayPath'] as String?,
      activeProfileId: j['activeProfileId'] as String?,
      perAppProxyEnabled: j['perAppProxyEnabled'] as bool? ?? false,
      perAppProxyMode: enumOf(PerAppProxyMode.values,
          j['perAppProxyMode'] as String?, PerAppProxyMode.exclude),
      perAppPackages: (j['perAppPackages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
    );
  }
}

/// هسته — در لایه تنظیمات (قابل سریال‌سازی).
enum CoreTypePref { singbox, xray }
