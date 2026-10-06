import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/ui/about/about_page.dart';
import 'package:overx/ui/cores/cores_page.dart';
import 'package:overx/ui/home/home_page.dart';
import 'package:overx/ui/logs/logs_page.dart';
import 'package:overx/ui/network/network_page.dart';
import 'package:overx/ui/profiles/profiles_page.dart';
import 'package:overx/ui/settings/settings_page.dart';
import 'package:overx/ui/shell/app_drawer.dart';
import 'package:overx/core/models/settings.dart';

/// نقطه‌ی بریک‌پوینت: از این عرض به بالا منو به صورت ثابت نمایش داده می‌شود
/// و از این به پایین به صورت منوی همبرگری (Drawer) باز می‌شود.
const double kWideBreakpoint = 960;

/// شِل برنامه.
///
/// یک چیدمان برای دو حالت:
///  - عریض (دسکتاپ/تبلت): منو همیشه باز است در سمت راستِ متن.
///  - باریک (موبایل/پنجره کوچک): منو به Drawer تبدیل می‌شود
///    و فلاتر به‌طور خودکار دکمه‌ی همبرگری را در AppBar می‌گذارد.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _pages = <Widget>[
    HomePage(),
    ProfilesPage(),
    LogsPage(),
    NetworkPage(),
    CoresPage(),
    SettingsPage(),
    AboutPage(),
  ];

  void _select(int i) {
    if (_index == i) return;
    setState(() => _index = i);
  }

  String _title(Strings s) => switch (_index) {
        0 => s.t('home'),
        1 => s.t('profiles'),
        2 => s.t('logs'),
        3 => s.t('network'),
        4 => s.t('cores'),
        5 => s.t('settings'),
        _ => s.t('about'),
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kWideBreakpoint;

    final drawer = AppDrawer(
      selectedIndex: _index,
      overlay: !wide,
      onSelect: (i) {
        _select(i);
        if (!wide) Navigator.of(context).maybePop();
      },
    );

    final content = Scaffold(
      appBar: AppBar(
        title: Text(_title(s)),
        actions: const [
          _LanguageButton(),
          _ThemeButton(),
          SizedBox(width: 6),
        ],
      ),
      // نبودن drawer در حالت عریض یعنی خبری از همبرگری نیست (منو ثابت است)
      drawer: wide ? null : drawer,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: _pages[_index],
        ),
      ),
    );

    if (!wide) return content;

    return Scaffold(
      body: Row(
        textDirection: Directionality.of(context),
        children: [
          SizedBox(width: 268, child: drawer),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ThemeButton extends ConsumerWidget {
  const _ThemeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider).themeMode;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IconButton(
      tooltip: 'Theme',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
      onPressed: () {
        final next = switch (mode) {
          ThemeModePref.system => isDark ? ThemeModePref.light : ThemeModePref.dark,
          ThemeModePref.light => ThemeModePref.dark,
          ThemeModePref.dark => ThemeModePref.light,
        };
        ref.read(settingsProvider.notifier).setThemeMode(next);
      },
    );
  }
}

class _LanguageButton extends ConsumerWidget {
  const _LanguageButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(settingsProvider).lang;
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: 'Language',
      icon: Icon(
        Icons.translate_rounded,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
      onPressed: () => ref.read(settingsProvider.notifier).setLang(
            lang == AppLang.fa ? AppLang.en : AppLang.fa,
          ),
    );
  }
}
