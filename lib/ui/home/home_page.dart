import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/core_type.dart';
import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/traffic.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';
import 'package:overx/ui/profiles/profiles_page.dart';
import 'package:overx/ui/widgets/connect_button.dart';
import 'package:overx/ui/widgets/core_switcher.dart';
import 'package:overx/ui/widgets/traffic_meter.dart';

/// صفحه‌ی اصلی — تنها صفحه‌ای که در نوار پایین/منو به صورت پیش‌فرض باز است.
///
/// ترکیب: وضعیت → دکمه اتصال → ترافیک → پروفایل فعال.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final engine = ref.watch(engineProvider);
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(activeProfileProvider);

    return LayoutBuilder(
      builder: (context, c) {
        final horizontal = c.maxWidth >= 640 ? 26.0 : 16.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusHeader(engine: engine, settings: settings),
                  const SizedBox(height: 16),
                  _ConnectCard(engine: engine, s: s),
                  const SizedBox(height: 14),
                  const TrafficMeter(),
                  const SizedBox(height: 14),
                  _ActiveProfileCard(profile: profile, s: s),
                  if (engine.error != null) ...[
                    const SizedBox(height: 14),
                    _ErrorCard(message: engine.error!),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusHeader extends ConsumerWidget {
  const _StatusHeader({required this.engine, required this.settings});

  final EngineState engine;

  final dynamic settings; // AppSettings

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final scheme = Theme.of(context).colorScheme;
    final color = StatusColors.of(engine.status);

    final version = engine.core == CoreType.singbox
        ? engine.singboxVersion
        : engine.xrayVersion;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // وضعیت
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  s.t(engine.status.name),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),

          // انتخاب هسته
          CoreSwitcher(
            selected: engine.core,
            enabled: !engine.isBusy,
            onChanged: (next) async {
              final ok =
                  await ref.read(engineProvider.notifier).switchCore(next);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(content: Text(s.t('switchBlocked'))),
                  );
              }
            },
          ),

          // نشان‌ها
          AppChip(
            label: settings.tunMode as bool ? 'TUN' : 'PROXY',
            color: scheme.outline,
          ),
          if (version != null) AppChip(label: 'v$version', color: scheme.outline),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConnectCard extends ConsumerWidget {
  const _ConnectCard({required this.engine, required this.s});

  final EngineState engine;
  final Strings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    final size = MediaQuery.sizeOf(context).width >= 640 ? 200.0 : 168.0;
    final status = engine.status;

    return AppCard(
      padding: EdgeInsets.fromLTRB(20, 26, 20, 22),
      child: Column(
        children: [
          ConnectButton(
            size: size,
            status: status,
            label: status == ConnectionState2.connected
                ? s.t('disconnect')
                : s.t('connect'),
            hint: '',
            onTap: () => ref.read(engineProvider.notifier).toggle(),
          ),
          const SizedBox(height: 16),
          // زمان اتصال
          AnimatedOpacity(
            opacity: status == ConnectionState2.disconnected ? 0.55 : 1,
            duration: const Duration(milliseconds: 250),
            child: Text(
              formatDuration(engine.uptime),
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 1.4,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status == ConnectionState2.disconnected
                ? s.t('startHint')
                : engine.profile?.name ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ActiveProfileCard extends ConsumerWidget {
  const _ActiveProfileCard({required this.profile, required this.s});

  final Profile? profile;
  final Strings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ProfilesPage()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(s.t('activeProfile')),
          if (profile == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.add_link_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.t('emptyProfilesHint'),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
                    size: 21,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppChip(label: profile!.protocol.label),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${profile!.address}:${profile!.port}',
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.outline,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (profile!.latencyMs != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${profile!.latencyMs} ms',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: profile!.latencyMs! < 80
                              ? StatusColors.connected
                              : profile!.latencyMs! < 160
                                  ? StatusColors.connecting
                                  : StatusColors.error,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.t('latency'),
                        style:
                            TextStyle(fontSize: 10.5, color: scheme.outline),
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StatusColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: StatusColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: StatusColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
