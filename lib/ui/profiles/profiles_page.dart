import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/profile.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';

/// صفحه‌ی پروفایل‌ها.
class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(settingsProvider).activeProfileId;
    final engine = ref.watch(engineProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(s.t('add')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
            child: Text(
              s.t('profilesSub'),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (profiles.isEmpty)
            _EmptyState(s: s)
          else
            ...profiles.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProfileCard(
                  profile: p,
                  active: p.id == activeId,
                  onTap: () {
                    ref.read(profilesProvider.notifier).select(p.id);
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(content: Text(s.t('profileActivated'))),
                      );
                    // اگر متصل هستیم، با پروفایل جدید دوباره وصل شو
                    if (engine.isConnected) {
                      ref.read(engineProvider.notifier).connect(p);
                    }
                  },
                  onDelete: () async {
                    final ok = await _confirmDelete(context, s, p);
                    if (ok == true) {
                      await ref.read(profilesProvider.notifier).remove(p.id);
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('addLink')),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            maxLines: 5,
            minLines: 3,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'vless://…\nvmess://…\ntrojan://…\nss://…',
              hintStyle: const TextStyle(fontSize: 11),
              suffixIcon: IconButton(
                tooltip: s.t('importClip'),
                icon: const Icon(Icons.content_paste_go_rounded, size: 19),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text ?? '';
                  controller.text = text;
                  controller.selection = TextSelection.collapsed(
                    offset: controller.text.length,
                  );
                },
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(s.t('add')),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty || !context.mounted) return;

    final count = await ref
        .read(profilesProvider.notifier)
        .addFromText(result);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(count == 0 ? s.t('invalidLink') : '${s.t('added')} ($count)'),
          backgroundColor: count == 0 ? StatusColors.error : null,
        ),
      );
  }

  Future<bool?> _confirmDelete(
          BuildContext context, Strings s, Profile p) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.t('remove')),
          content: Text(p.name),
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
              child: Text(s.t('remove')),
            ),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.link_off_rounded, size: 34, color: scheme.outline),
          const SizedBox(height: 14),
          Text(
            s.t('emptyProfiles'),
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.t('emptyProfilesHint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.onTap,
    required this.onDelete,
  });

  final Profile profile;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      highlight: active,
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (active ? scheme.primary : scheme.outline).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.bolt_rounded,
              size: 20,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
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
                        profile.name,
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
                    AppChip(
                      label: profile.protocol.label,
                      color: scheme.outline,
                    ),
                    if (profile.network != null) ...[
                      const SizedBox(width: 5),
                      AppChip(
                        label: profile.network!,
                        color: scheme.outline,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.address}:${profile.port}',
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
          if (profile.latencyMs != null) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${profile.latencyMs} ms',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: profile.latencyMs! < 80
                        ? StatusColors.connected
                        : profile.latencyMs! < 160
                            ? StatusColors.connecting
                            : StatusColors.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ping',
                  style: TextStyle(fontSize: 10, color: scheme.outline),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                size: 19, color: scheme.onSurfaceVariant),
            tooltip: 'delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
