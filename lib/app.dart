import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';
import 'package:overx/ui/shell/app_shell.dart';
import 'package:overx/core/models/settings.dart';

class OverxApp extends ConsumerWidget {
  const OverxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);

    final themeMode = switch (settings.themeMode) {
      ThemeModePref.system => ThemeMode.system,
      ThemeModePref.light => ThemeMode.light,
      ThemeModePref.dark => ThemeMode.dark,
    };

    return MaterialApp(
      title: 'OVERX',
      debugShowCheckedModeBanner: false,

      // ---- i18n ----
      locale: strings.locale,
      supportedLocales: AppLang.values.map((e) => e.locale).toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // ---- theme ----
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,

      // جهتِ متن را صریحاً اعمال می‌کنیم تا تعویض زبان آنی باشد
      builder: (context, child) => Directionality(
        textDirection: strings.direction,
        child: child ?? const SizedBox.shrink(),
      ),

      home: const AppShell(),
    );
  }
}
