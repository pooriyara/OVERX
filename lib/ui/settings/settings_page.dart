import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/config/singbox_config_builder.dart';
import 'package:overx/core/config/xray_config_builder.dart';
import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:overx/ui/settings/per_app_page.dart';
import 'package:overx/core/models/settings.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';
import 'package:overx/ui/widgets/setting_tile.dart';

/// صفحه‌ی تنظیمات — همه چیز به جز صفحه‌ی اصلی.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final active = ref.watch(activeProfileProvider);
    final set = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
          child: Text(
            s.t('settingsSub'),
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        // ---------------------------------------------------------- عمومی
        _Group(
          title: s.t('grpGeneral'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OptionSetting<ThemeModePref>(
                title: s.t('theme'),
                subtitle: s.t('themeSub'),
                value: settings.themeMode,
                options: ThemeModePref.values,
                labelOf: (v) => s.t(v.name),
                onChanged: (v) => set.setThemeMode(v!),
                icon: Icons.palette_outlined,
              ),
            ),
            const SettingDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OptionSetting<AppLang>(
                title: s.t('language'),
                subtitle: s.t('languageSub'),
                value: settings.lang,
                options: AppLang.values,
                labelOf: (v) => v.label,
                onChanged: (v) => set.setLang(v!),
                icon: Icons.translate_rounded,
              ),
            ),
            const SettingDivider(),
            SwitchSetting(
              title: s.t('autoStart'),
              subtitle: _autoStartSubtitle(context, ref, s),
              value: settings.autoStart,
              icon: Icons.rocket_launch_outlined,
              onChanged: (v) async {
                final bridge = ref.read(platformBridgeProvider);
                if (!bridge.features.has(PlatformFeature.autoStart)) {
                  _snack(context, bridge.lastError ?? s.t('notSupported'));
                  return;
                }
                final ok = await bridge.setAutoStart(v);
                if (ok) {
                  await set.setAutoStart(v);
                } else if (context.mounted) {
                  _snack(context, bridge.lastError ?? s.t('notSupported'));
                }
              },
            ),
            const SettingDivider(),
            SwitchSetting(
              title: s.t('autoConnect'),
              subtitle: s.t('autoConnectSub'),
              value: settings.autoConnect,
              icon: Icons.auto_mode_outlined,
              onChanged: set.setAutoConnect,
            ),
            const SettingDivider(),
            ActionSetting(
              title: s.t('perAppTile'),
              subtitle: s.t('perAppTileSub'),
              icon: Icons.apps_outlined,
              enabled: ref.watch(libboxServiceProvider).available,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PerAppPage()),
              ),
            ),
            const SettingDivider(),
            SwitchSetting(
              title: s.t('minTray'),
              subtitle: ref.watch(platformBridgeProvider) is AndroidBridge
                  ? s.t('minTraySubAndroid')
                  : s.t('minTraySub'),
              value: settings.minimizeToTray,
              icon: Icons.remove_from_queue_outlined,
              onChanged: set.setMinimizeToTray,
            ),
          ],
        ),

        // ---------------------------------------------------------- شبکه
        _Group(
          title: s.t('grpNetwork'),
          children: [
            SwitchSetting(
              title: s.t('tunMode'),
              subtitle: s.t('tunModeSub'),
              value: settings.tunMode,
              onChanged: set.setTunMode,
              icon: Icons.settings_input_antenna_outlined,
            ),
            const SettingDivider(),
            SwitchSetting(
              title: s.t('sysProxy'),
              subtitle: ref.read(platformBridgeProvider).features
                      .has(PlatformFeature.systemProxy)
                  ? s.t('sysProxySub')
                  : '${s.t('sysProxySub')} — ${s.t('notSupported')}',
              value: settings.systemProxy,
              onChanged: set.setSystemProxy,
              icon: Icons.lan_outlined,
            ),
            const SettingDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OptionSetting<RouteMode>(
                title: s.t('routeMode'),
                value: settings.routeMode,
                options: RouteMode.values,
                labelOf: (v) => s.t('rm${v.name[0].toUpperCase()}${v.name.substring(1)}'),
                onChanged: (v) => set.setRouteMode(v!),
                icon: Icons.alt_route_rounded,
              ),
            ),
            const SettingDivider(),
            SwitchSetting(
              title: s.t('bypassLan'),
              subtitle: s.t('bypassLanSub'),
              value: settings.bypassLan,
              onChanged: set.setBypassLan,
              icon: Icons.home_work_outlined,
            ),
            const SettingDivider(),
            SwitchSetting(
              title: s.t('sniff'),
              subtitle: s.t('sniffSub'),
              value: settings.sniffing,
              onChanged: set.setSniffing,
              icon: Icons.search_outlined,
            ),
            const SettingDivider(),
            SwitchSetting(
              title: s.t('mux'),
              subtitle: s.t('muxSub'),
              value: settings.mux,
              onChanged: set.setMux,
              icon: Icons.call_split_outlined,
            ),
            const SettingDivider(),
            SwitchSetting(
              title: s.t('ipv6'),
              value: settings.ipv6,
              onChanged: set.setIpv6,
              icon: Icons.numbers_outlined,
            ),
            const SettingDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextSetting(
                title: s.t('mixedPort'),
                value: '${settings.mixedPort}',
                numeric: true,
                ltr: true,
                width: 110,
                icon: Icons.hub_outlined,
                onSubmit: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0 && n < 65536) set.setMixedPort(n);
                },
              ),
            ),
          ],
        ),

        // ---------------------------------------------------------- DNS
        _Group(
          title: s.t('grpDns'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OptionSetting<DnsMode>(
                title: s.t('dnsMode'),
                value: settings.dnsMode,
                options: DnsMode.values,
                labelOf: (v) => s.t('dns${v.name[0].toUpperCase()}${v.name.substring(1)}'),
                onChanged: (v) => set.setDnsMode(v!),
                icon: Icons.dns_outlined,
              ),
            ),
            const SettingDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextSetting(
                title: s.t('dnsRemoteAddr'),
                value: settings.remoteDns,
                ltr: true,
                icon: Icons.public_outlined,
                onSubmit: set.setRemoteDns,
              ),
            ),
            const SettingDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextSetting(
                title: s.t('dnsLocalAddr'),
                value: settings.localDns,
                ltr: true,
                width: 150,
                icon: Icons.router_outlined,
                onSubmit: set.setLocalDns,
              ),
            ),
          ],
        ),

        // ---------------------------------------------------------- پیشرفته
        _Group(
          title: s.t('grpAdvanced'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OptionSetting<LogLevel>(
                title: s.t('logLevel'),
                value: settings.logLevel,
                options: LogLevel.values,
                labelOf: (v) => v.name,
                onChanged: (v) => set.setLogLevel(v!),
                icon: Icons.terminal_outlined,
              ),
            ),
            const SettingDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextSetting(
                title: s.t('apiPort'),
                subtitle: s.t('apiPortSub'),
                value: '${settings.singboxApiPort}',
                numeric: true,
                ltr: true,
                width: 110,
                icon: Icons.api_outlined,
                onSubmit: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0 && n < 65536) set.setSingboxApiPort(n);
                },
              ),
            ),
            const SettingDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextSetting(
                title: 'Xray gRPC API port',
                value: '${settings.xrayApiPort}',
                numeric: true,
                ltr: true,
                width: 110,
                icon: Icons.api_outlined,
                onSubmit: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0 && n < 65536) set.setXrayApiPort(n);
                },
              ),
            ),
            const SettingDivider(),
            ActionSetting(
              title: s.t('exportCfg'),
              subtitle: s.t('exportCfgSub'),
              icon: Icons.data_object_outlined,
              onTap: active == null
                  ? null
                  : () => _showConfig(context, ref, active),
            ),
          ],
        ),

        // ---------------------------------------------------------- بازنشانی
        _Group(
          title: s.t('reset'),
          children: [
            ActionSetting(
              title: s.t('reset'),
              danger: true,
              icon: Icons.restart_alt_rounded,
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(s.t('reset')),
                    content: Text(s.t('resetConfirm')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(s.t('cancel')),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: StatusColors.error,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(s.t('resetBtn')),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await set.reset();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.t('settingsReset'))),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  static String _autoStartSubtitle(
    BuildContext context,
    WidgetRef ref,
    Strings s,
  ) {
    final supported =
        ref.read(platformBridgeProvider).features.has(PlatformFeature.autoStart);
    if (!supported) return '${s.t('autoStartSub')} — ${s.t('notSupported')}';
    return s.t('autoStartSub');
  }

  static void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _showConfig(
    BuildContext context,
    WidgetRef ref,
    dynamic profile,
  ) {
    final settings = ref.read(settingsProvider);
    String singbox, xray;
    try {
      singbox = SingboxConfigBuilder.build(
        profile: profile,
        settings: settings,
      );
    } catch (e) {
      singbox = '// error: $e';
    }
    try {
      xray = XrayConfigBuilder.build(profile: profile, settings: settings);
    } catch (e) {
      xray = '// error: $e';
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          title: Text(ref.read(stringsProvider).t('exportCfg')),
          content: SizedBox(
            width: 620,
            height: 420,
            child: Column(
              children: [
                TabBar(
                  tabs: [
                    const Tab(text: 'sing-box'),
                    const Tab(text: 'Xray'),
                  ],
                  labelStyle: const TextStyle(fontSize: 12.5),
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(
                    children: [_ConfigView(text: singbox), _ConfigView(text: xray)],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ref.read(stringsProvider).t('cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigView extends StatelessWidget {
  const _ConfigView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF07090D) : const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.6,
            color: Color(0xFFB9C6D6),
          ),
        ),
      ),
    );
  }
}

/// یک گروه از تنظیمات داخل یک کارت.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SectionTitle(title),
              ),
              ...children,
            ],
          ),
        ),
      );
}
