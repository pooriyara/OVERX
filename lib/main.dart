import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:overx/app.dart';
import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:overx/core/platform/platform_bridge.dart';
import 'package:overx/core/storage/repositories.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // جهتِ عمودیِ ثابت روی موبایل؛ روی دسکتاپ محدود نمی‌کنیم.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final prefs = await SharedPreferences.getInstance();

  // libbox فقط روی اندروید معنا دارد (کتابخانه همان‌جا همراه برنامه است)
  final LibboxService libbox = Platform.isAndroid
      ? MethodChannelLibboxService(defaultAvailable: true)
      : const UnavailableLibboxService();
  if (libbox is MethodChannelLibboxService) {
    // دسترسی‌بودن را در پس‌زمینه دقیق می‌کنیم
    unawaited(libbox.probe());
  }

  runApp(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider
            .overrideWithValue(SettingsRepository(prefs)),
        profileRepositoryProvider.overrideWithValue(ProfileRepository(prefs)),
        platformBridgeProvider.overrideWithValue(createPlatformBridge()),
        libboxServiceProvider.overrideWithValue(libbox),
      ],
      child: const OverxApp(),
    ),
  );
}
