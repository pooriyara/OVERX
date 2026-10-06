import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/app_package.dart';
import 'package:overx/core/platform/app_icon_service.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';

/// انتخابِ اینکه کدام برنامه‌ها از VPN عبور کنند.
///
/// این قابلیت فقط روی اندروید و فقط وقتی sing-box از طریق libbox اجرا می‌شود
/// معنا دارد: libbox از طریق `OverrideOptions.includePackage` /
/// `excludePackage` فهرست را به هسته می‌دهد و `openTun()` آن‌ها را به
/// `addAllowedApplication` / `addDisallowedApplication` تبدیل می‌کند.
class PerAppPage extends ConsumerStatefulWidget {
  const PerAppPage({super.key});

  @override
  ConsumerState<PerAppPage> createState() => _PerAppPageState();
}

class _PerAppPageState extends ConsumerState<PerAppPage> {
  final _search = TextEditingController();
  final _packages = <AppPackage>[];

  bool _loading = true;
  String? _error;
  bool _showSystem = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(platformBridgeProvider)
          .listInstalledPackages(includeSystem: _showSystem);
      if (!mounted) return;
      setState(() {
        _packages
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<AppPackage> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _packages;
    return _packages
        .where((p) =>
            p.displayName.toLowerCase().contains(q) ||
            p.packageName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _toggle(String packageName, bool selected) async {
    final current = ref.read(settingsProvider).perAppPackages.toList();
    if (selected) {
      if (!current.contains(packageName)) current.add(packageName);
    } else {
      current.remove(packageName);
    }
    await ref.read(settingsProvider.notifier).setPerAppPackages(current);
  }

  Future<void> _selectAll(bool select) async {
    final next = <String>{
      ...ref.read(settingsProvider).perAppPackages,
    };
    for (final p in _visible) {
      if (select) {
        next.add(p.packageName);
      } else {
        next.remove(p.packageName);
      }
    }
    await ref.read(settingsProvider.notifier).setPerAppPackages(next.toList());
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final selected = settings.perAppPackages.toSet();
    final enabled = settings.perAppProxyEnabled;
    final libboxAvailable = ref.watch(libboxServiceProvider).available;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('perAppTitle'))),
      body: !libboxAvailable
          ? _Unsupported(body: s.t('perAppNeedsLibbox'))
          : Column(
              children: [
                // ---------------------------------------------- فعال‌سازی
                SwitchListTile(
                  title: Text(s.t('perAppEnable')),
                  subtitle: Text(s.t('perAppEnableSub')),
                  value: enabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setPerAppProxyEnabled(v),
                ),

                if (enabled) ...[
                  // ------------------------------------------------ حالت
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SegmentedButton<PerAppProxyMode>(
                      segments: [
                        ButtonSegment(
                          value: PerAppProxyMode.exclude,
                          label: Text(s.t('perAppExclude')),
                        ),
                        ButtonSegment(
                          value: PerAppProxyMode.include,
                          label: Text(s.t('perAppInclude')),
                        ),
                      ],
                      selected: <PerAppProxyMode>{settings.perAppProxyMode},
                      onSelectionChanged: (v) => ref
                          .read(settingsProvider.notifier)
                          .setPerAppProxyMode(v.first),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      settings.perAppProxyMode.isInclude
                          ? s.t('perAppIncludeHint')
                          : s.t('perAppExcludeHint'),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  // --------------------------------------------- جستجو
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: s.t('perAppSearch'),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                              ),
                      ),
                    ),
                  ),

                  // --------------------------------- انتخاب همه / سیستمی
                  // روی صفحه‌ی باریک یک ردیفِ واحد سرریز می‌کند،
                  // برای همین کنترل‌ها را در دو ردیف می‌گذاریم.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => _selectAll(true),
                          child: Text(s.t('perAppSelectAll')),
                        ),
                        TextButton(
                          onPressed: () => _selectAll(false),
                          child: Text(s.t('perAppClear')),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            '${selected.length} ${s.t('perAppSelectedCount')}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.t('perAppShowSystem'),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Switch(
                          value: _showSystem,
                          onChanged: (v) {
                            setState(() => _showSystem = v);
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],

                // ------------------------------------------------- فهرست
                Expanded(child: _buildList(s, selected, enabled, scheme)),
              ],
            ),
    );
  }

  Widget _buildList(
    Strings s,
    Set<String> selected,
    bool enabled,
    ColorScheme scheme,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: StatusColors.error),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _load,
                child: Text(s.t('retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (_visible.isEmpty) {
      return Center(
        child: Text(
          s.t('perAppEmpty'),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: _visible.length,
      itemBuilder: (context, i) {
        final p = _visible[i];
        final isSelected = selected.contains(p.packageName);
        return CheckboxListTile(
          dense: true,
          value: isSelected,
          enabled: enabled,
          onChanged: (v) => _toggle(p.packageName, v ?? false),
          // CheckboxListTile پارامترِ leading ندارد؛ `secondary` همیشه
          // سمتِ مخالفِ چک‌باکس می‌نشیند، پس affinity را صریح می‌گذاریم
          // تا در RTL آیکون در ابتدا و چک‌باکس در انتها باشد.
          controlAffinity: ListTileControlAffinity.trailing,
          secondary: _AppIcon(package: p, colorScheme: scheme),
          title: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  p.displayName,
                  style: const TextStyle(fontSize: 13.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (p.isSystem) ...<Widget>[
                const SizedBox(width: 6),
                Tooltip(
                  message: s.t('perAppSystemApp'),
                  child: Icon(
                    Icons.settings_applications,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            p.packageName,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smartphone_outlined,
              size: 40,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// آیکونِ یک برنامه.
///
/// آیکون به صورت تنبل (lazy) و فقط برای کاشی‌هایی که واقعاً روی صفحه
/// می‌آیند درخواست می‌شود؛ روی دسکتاپ/وب پاسخ `null` است و حرفِ اولِ نام
/// نشان داده می‌شود.
class _AppIcon extends ConsumerStatefulWidget {
  const _AppIcon({required this.package, required this.colorScheme});

  final AppPackage package;
  final ColorScheme colorScheme;

  @override
  ConsumerState<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends ConsumerState<_AppIcon> {
  static const double size = 34;

  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    final service = ref.read(appIconServiceProvider);
    // اگر از قبل کش شده باشد، این Future همان فریم کامل می‌شود.
    _future = service
        .load(widget.package.packageName)
        .then((_) => service.peek(widget.package.packageName));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return _fallback();
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        );
      },
    );
  }

  Widget _fallback() {
    final name = widget.package.displayName.trim();
    final initial = name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: widget.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
