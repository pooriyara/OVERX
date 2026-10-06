import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/core_type.dart';
import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';
import 'package:overx/ui/widgets/setting_tile.dart';
import 'package:overx/core/process/core_installer.dart';

/// صفحه‌ی مدیریت هسته‌ها.
class CoresPage extends ConsumerWidget {
  const CoresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final engine = ref.watch(engineProvider);
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
          child: Text(
            s.t('coresSub'),
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        // کارت‌های هسته
        LayoutBuilder(
          builder: (context, c) {
            final twoCols = c.maxWidth >= 700;
            final cards = CoreType.values
                .map((t) => _CoreCard(type: t, engine: engine, s: s))
                .toList();
            return twoCols
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 14),
                      Expanded(child: cards[1]),
                    ],
                  )
                : Column(
                    children: [
                      cards[0],
                      const SizedBox(height: 14),
                      cards[1],
                    ],
                  );
          },
        ),

        const SizedBox(height: 16),

        // گزینه‌ها
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SectionTitle(s.t('coreOptions')),
              ),
              SwitchSetting(
                title: s.t('autoSwitchCore'),
                subtitle: s.t('autoSwitchCoreSub'),
                value: settings.autoSwitchCore,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .setAutoSwitchCore(v),
              ),
              const SettingDivider(),
              SwitchSetting(
                title: s.t('keepAlive'),
                subtitle: s.t('keepAliveSub'),
                value: settings.keepAlive,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setKeepAlive(v),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // مسیر باینری‌ها
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SectionTitle('Binaries'),
              ),
              ActionSetting(
                title: 'sing-box',
                subtitle: engine.singboxPath ??
                    '${CoreType.singbox.binaryName} — ${s.t('notFound')}',
                icon: Icons.article_outlined,
                onTap: () => _pickPath(context, ref, CoreType.singbox),
                trailing: engine.singboxVersion != null
                    ? AppChip(
                        label: 'v${engine.singboxVersion}',
                        color: StatusColors.connected,
                      )
                    : AppChip(label: s.t('notFound'), color: StatusColors.idle),
              ),
              const SettingDivider(),
              ActionSetting(
                title: 'Xray',
                subtitle: engine.xrayPath ??
                    '${CoreType.xray.binaryName} — ${s.t('notFound')}',
                icon: Icons.article_outlined,
                onTap: () => _pickPath(context, ref, CoreType.xray),
                trailing: engine.xrayVersion != null
                    ? AppChip(
                        label: 'v${engine.xrayVersion}',
                        color: StatusColors.connected,
                      )
                    : AppChip(label: s.t('notFound'), color: StatusColors.idle),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickPath(
    BuildContext context,
    WidgetRef ref,
    CoreType type,
  ) async {
    final controller = TextEditingController(
      text: type == CoreType.singbox
          ? ref.read(engineProvider).singboxPath ?? ''
          : ref.read(engineProvider).xrayPath ?? '',
    );

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s(context, ref)} — ${type.displayName}'),
        content: TextField(
          controller: controller,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: '/usr/local/bin/sing-box',
            hintStyle: TextStyle(fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(s(context, ref).t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final path = result.isEmpty ? null : result;
    if (type == CoreType.singbox) {
      await ref.read(settingsProvider.notifier).setSingboxPath(path);
    } else {
      await ref.read(settingsProvider.notifier).setXrayPath(path);
    }
    await ref.read(engineProvider.notifier).checkCore(type);
  }

  Strings s(BuildContext context, WidgetRef ref) => ref.read(stringsProvider);
}

// ---------------------------------------------------------------------------

class _CoreCard extends ConsumerStatefulWidget {
  const _CoreCard({
    required this.type,
    required this.engine,
    required this.s,
  });

  final CoreType type;
  final EngineState engine;
  final Strings s;

  @override
  ConsumerState<_CoreCard> createState() => _CoreCardState();
}

class _CoreCardState extends ConsumerState<_CoreCard> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    var v = await ref.read(engineProvider.notifier).checkCore(widget.type);

    // اگر پیدا نشد و دسکتاپ هستیم، خودکار دانلود/نصب کن و دوباره بررسی کن.
    String? installError;
    if (v == null && CoreInstaller.supported) {
      try {
        await CoreInstaller.install(widget.type);
        v = await ref.read(engineProvider.notifier).checkCore(widget.type);
      } on CoreInstallException catch (e) {
        installError = e.message;
      } catch (e) {
        installError = '$e';
      }
    }

    if (mounted) setState(() => _checking = false);
    if (!mounted) return;
    final ok = v != null;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${widget.type.displayName} v$v'
                : installError ??
                    '${widget.type.displayName} — ${widget.s.t('notFound')}',
          ),
          backgroundColor: ok ? null : StatusColors.error,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.engine.core == widget.type;

    final version = widget.type == CoreType.singbox
        ? widget.engine.singboxVersion
        : widget.engine.xrayVersion;

    final busy = widget.engine.isBusy || widget.engine.isConnected;

    return AppCard(
      highlight: selected,
      onTap: busy
          ? null
          : () async {
              final ok = await ref
                  .read(engineProvider.notifier)
                  .switchCore(widget.type);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(content: Text(widget.s.t('switchBlocked'))),
                  );
              }
            },
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      widget.type.brandColor,
                      widget.type.brandColor.withValues(alpha: 0.62),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.type.shortName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (selected)
                AppChip(
                  label: widget.s.t('active'),
                  color: scheme.primary,
                  onBackground: true,
                ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            widget.type.displayName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            version != null
                ? 'v$version · ${widget.type.binaryName}'
                : '${widget.type.binaryName} · ${widget.s.t('notFound')}',
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.outline,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.s.t(widget.type.descriptionKey),
            style: TextStyle(
              fontSize: 12,
              height: 1.65,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(widget.s.t('check')),
          ),
        ],
      ),
    );
  }
}
