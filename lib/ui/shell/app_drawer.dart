import 'package:overx/core/engine/core_type.dart';
import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// منوی برنامه — یک کامپوننت، دو حالت:
///
/// * [overlay] = true  → داخل `Drawer`، با دکمه‌ی همبرگری در AppBar (موبایل)
/// * [overlay] = false → منوی ثابت در کنار محتوا (دسکتاپ)
///
/// نکته: از `NavigationDrawer` آماده استفاده نمی‌کنیم چون فرزندانش داخل
/// یک اسکرولView هستند و نمی‌توان فوتر را با `Spacer` به پایین چسباند.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.overlay = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = _DrawerContent(
      selectedIndex: selectedIndex,
      onSelect: onSelect,
    );

    if (!overlay) return content;

    return Drawer(
      width: 300,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------

class _DrawerContent extends ConsumerWidget {
  const _DrawerContent({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final engine = ref.watch(engineProvider);
    final profiles = ref.watch(profilesProvider);
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BrandHeader(subtitle: s.t('tagline')),
            const SizedBox(height: 6),

            // بخش‌های قابل اسکرول (اگر صفحه کوتاه باشد)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel(s.t('grpMain')),
                    _NavItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: s.t('home'),
                      selected: selectedIndex == 0,
                      onTap: () => onSelect(0),
                    ),
                    _NavItem(
                      icon: Icons.list_alt_outlined,
                      activeIcon: Icons.list_alt_rounded,
                      label: s.t('profiles'),
                      selected: selectedIndex == 1,
                      badge: profiles.isEmpty ? null : '${profiles.length}',
                      onTap: () => onSelect(1),
                    ),
                    _NavItem(
                      icon: Icons.terminal_outlined,
                      activeIcon: Icons.terminal_rounded,
                      label: s.t('logs'),
                      selected: selectedIndex == 2,
                      onTap: () => onSelect(2),
                    ),
                    const SizedBox(height: 8),
                    const _ThinDivider(),
                    const SizedBox(height: 8),
                    _SectionLabel(s.t('grpConfig')),
                    _NavItem(
                      icon: Icons.hub_outlined,
                      activeIcon: Icons.hub_rounded,
                      label: s.t('network'),
                      selected: selectedIndex == 3,
                      onTap: () => onSelect(3),
                    ),
                    const SizedBox(height: 8),
                    const _ThinDivider(),
                    const SizedBox(height: 8),
                    _SectionLabel(s.t('grpConfig')),
                    _NavItem(
                      icon: Icons.layers_outlined,
                      activeIcon: Icons.layers_rounded,
                      label: s.t('cores'),
                      selected: selectedIndex == 4,
                      onTap: () => onSelect(4),
                    ),
                    _NavItem(
                      icon: Icons.tune_outlined,
                      activeIcon: Icons.tune_rounded,
                      label: s.t('settings'),
                      selected: selectedIndex == 5,
                      onTap: () => onSelect(5),
                    ),
                    _NavItem(
                      icon: Icons.info_outline_rounded,
                      activeIcon: Icons.info_rounded,
                      label: s.t('about'),
                      selected: selectedIndex == 6,
                      onTap: () => onSelect(6),
                    ),
                  ],
                ),
              ),
            ),

            const _ThinDivider(),
            _CoreStatusFooter(engine: engine, s: s),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: 20,
        endIndent: 20,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .7),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
}

/// آیتمِ منو با نشانگرِ قرصیِ Material 3.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(selected ? activeIcon : icon, size: 22, color: fg),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 22, 20, 12),
      child: Row(
        children: [
          // نشانه‌ی واقعیِ برنامه (ساخته‌شده با tool/gen_icons.py)؛
          // در زمینه‌ی تیره نسخه‌ی سفید استفاده می‌شود
          Image.asset(
            Theme.of(context).brightness == Brightness.dark
                ? 'assets/icon_white.png'
                : 'assets/icon.png',
            width: 40,
            height: 40,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'OVERX',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoreStatusFooter extends ConsumerWidget {
  const _CoreStatusFooter({required this.engine, required this.s});

  final EngineState engine;
  final Strings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = StatusColors.of(engine.status);
    final version = engine.core == CoreType.singbox
        ? engine.singboxVersion
        : engine.xrayVersion;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _PulseDot(color: statusColor, active: engine.isConnected),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${engine.core.displayName}'
                    '${version != null ? ' · v$version' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.t(engine.status.name),
                    style: TextStyle(fontSize: 10.5, color: scheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: .15 + .35 * _c.value),
              blurRadius: 4 + 6 * _c.value,
              spreadRadius: _c.value * 2,
            ),
          ],
        ),
      ),
    );
  }
}
