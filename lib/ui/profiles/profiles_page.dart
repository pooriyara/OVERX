import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/subscription.dart';
import 'package:overx/core/net/sub_fetcher.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';

enum _Menu { clip, addSub, updateSub, realPing, sortPing }

/// صفحه‌ی پروفایل‌ها / اشتراک‌ها.
class ProfilesPage extends ConsumerStatefulWidget {
  const ProfilesPage({super.key});

  @override
  ConsumerState<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends ConsumerState<ProfilesPage> {
  String? _selectedGroup; // null = همه
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final profiles = ref.watch(profilesProvider);
    final subs = ref.watch(subscriptionsProvider);
    final activeId = ref.watch(settingsProvider).activeProfileId;
    final engine = ref.watch(engineProvider);

    final shown = _selectedGroup == null
        ? profiles
        : profiles.where((p) => p.groupId == _selectedGroup).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(s.t('add')),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopBar(
            s: s,
            subs: subs,
            selected: _selectedGroup,
            busy: _busy,
            onSelect: (id) => setState(() => _selectedGroup = id),
            onMenu: (m) => _onMenu(m, ref, shown),
          ),
          Expanded(
            child: shown.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [_EmptyState(s: s)],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    children: [
                      ...shown.map(
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
                                  SnackBar(
                                      content: Text(s.t('profileActivated'))),
                                );
                              if (engine.isConnected) {
                                ref
                                    .read(engineProvider.notifier)
                                    .connect(p);
                              }
                            },
                            onDelete: () async {
                              final ok = await _confirmDelete(context, s, p);
                              if (ok == true) {
                                await ref
                                    .read(profilesProvider.notifier)
                                    .remove(p.id);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(_Menu m, WidgetRef ref, List<Profile> shown) async {
    final s = ref.read(stringsProvider);
    switch (m) {
      case _Menu.clip:
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (!mounted) return;
        _showAddDialog(context, ref, initial: data?.text ?? '');
      case _Menu.addSub:
        _showAddDialog(context, ref, isSubscription: true);
      case _Menu.updateSub:
        await _updateSubs(ref, s);
      case _Menu.realPing:
        setState(() => _busy = true);
        await ref.read(profilesProvider.notifier).realPingAll(shown);
        if (mounted) setState(() => _busy = false);
      case _Menu.sortPing:
        await ref.read(profilesProvider.notifier).sortByPing();
    }
  }

  Future<void> _updateSubs(WidgetRef ref, Strings s) async {
    final subs = ref.read(subscriptionsProvider);
    final targets = _selectedGroup == null
        ? subs.where((e) => e.url != null).toList()
        : subs
            .where((e) => e.id == _selectedGroup && e.url != null)
            .toList();
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    var total = 0;
    String? error;
    for (final t in targets) {
      try {
        total += await ref.read(subscriptionsProvider.notifier).update(t.id);
      } on SubscriptionFetchException catch (e) {
        error = e.message;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(error ?? '${s.t('subUpdated')} ($total)'),
        backgroundColor: error != null ? StatusColors.error : null,
      ));
  }

  Future<void> _showAddDialog(
    BuildContext context,
    WidgetRef ref, {
    String initial = '',
    bool isSubscription = false,
  }) async {
    final s = ref.read(stringsProvider);
    final content = TextEditingController(text: initial);
    final name = TextEditingController();
    var sub = isSubscription || _looksLikeUrl(initial);

    final result = await showDialog<_AddResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(s.t('addLink'))),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: sub,
                    title: Text(s.t('isSubscription'),
                        style: const TextStyle(fontSize: 13)),
                    onChanged: (v) => setSt(() => sub = v ?? false),
                  ),
                  if (sub)
                    TextField(
                      controller: name,
                      decoration: InputDecoration(
                        hintText: s.t('subName'),
                        hintStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: content,
                    maxLines: 5,
                    minLines: 3,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 12,
                        fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: sub
                          ? 'https://example.com/sub?token=…'
                          : 'vless://…\nvmess://…\ntrojan://…\nss://…',
                      hintStyle: const TextStyle(fontSize: 11),
                      suffixIcon: IconButton(
                        tooltip: s.t('importClip'),
                        icon: const Icon(Icons.content_paste_go_rounded,
                            size: 19),
                        onPressed: () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          setSt(() {
                            content.text = data?.text ?? '';
                            if (_looksLikeUrl(content.text)) sub = true;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, _AddResult(sub: sub, name: name.text,
                      content: content.text)),
              child: Text(s.t('add')),
            ),
          ],
        ),
      ),
    );

    if (result == null ||
        result.content.trim().isEmpty ||
        !context.mounted) return;

    setState(() => _busy = true);
    String? error;
    var count = 0;
    try {
      if (result.sub) {
        count = await ref
            .read(subscriptionsProvider.notifier)
            .addFromUrl(result.name, result.content);
      } else {
        count = await ref
            .read(profilesProvider.notifier)
            .addFromText(result.content);
      }
    } on SubscriptionFetchException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(error ??
            (count == 0 ? s.t('invalidLink') : '${s.t('added')} ($count)')),
        backgroundColor:
            (error != null || count == 0) ? StatusColors.error : null,
      ));
  }

  bool _looksLikeUrl(String t) {
    final s = t.trim();
    return s.startsWith('http://') || s.startsWith('https://');
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

class _AddResult {
  const _AddResult({required this.sub, required this.name,
      required this.content});
  final bool sub;
  final String name;
  final String content;
}

/// نوارِ بالا: فهرستِ افقیِ اشتراک‌ها (با «همه» اول) + منوی سه‌نقطه.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.s,
    required this.subs,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onMenu,
  });

  final Strings s;
  final List<Subscription> subs;
  final String? selected;
  final bool busy;
  final ValueChanged<String?> onSelect;
  final void Function(_Menu) onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip(context, null, s.t('all'), selected == null),
                  ...subs.map(
                    (e) => _chip(context, e.id, e.name, selected == e.id),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<_Menu>(
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.more_vert_rounded),
            onSelected: onMenu,
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: _Menu.clip,
                child: _item(Icons.content_paste_rounded, s.t('importClip')),
              ),
              PopupMenuItem(
                value: _Menu.addSub,
                child: _item(Icons.add_link_rounded, s.t('addSubscription')),
              ),
              PopupMenuItem(
                value: _Menu.updateSub,
                child: _item(Icons.sync_rounded, s.t('updateSub')),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _Menu.realPing,
                child: _item(Icons.network_ping_rounded, s.t('realPing')),
              ),
              PopupMenuItem(
                value: _Menu.sortPing,
                child: _item(Icons.sort_rounded, s.t('sortPing')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label) => Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      );

  Widget _chip(
          BuildContext context, String? id, String label, bool isSel) =>
      Padding(
        padding: const EdgeInsets.only(right: 6, left: 2),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: isSel,
          onSelected: (_) => onSelect(id),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              color: (active ? scheme.primary : scheme.outline)
                  .withValues(alpha: 0.14),
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
