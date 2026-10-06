import 'dart:io';

import 'package:flutter/material.dart';

/// دو هسته‌ی پشتیبانی‌شده.
enum CoreType {
  singbox,
  xray;

  String get id => name;

  String get displayName => switch (this) {
        CoreType.singbox => 'sing-box',
        CoreType.xray => 'Xray',
      };

  String get shortName => switch (this) {
        CoreType.singbox => 'SB',
        CoreType.xray => 'XR',
      };

  String get descriptionKey => switch (this) {
        CoreType.singbox => 'sbDesc',
        CoreType.xray => 'xrDesc',
      };

  /// نام فایل باینری روی هر پلتفرم.
  String get binaryName {
    if (this == CoreType.singbox) {
      return Platform.isWindows ? 'sing-box.exe' : 'sing-box';
    }
    return Platform.isWindows ? 'xray.exe' : 'xray';
  }

  /// نام فایل کانفیگی که برای این هسته می‌نویسیم.
  String get configFileName => '${name}_config.json';

  /// آرگومان‌های اجرای هسته.
  List<String> get runArgs => switch (this) {
        CoreType.singbox => const ['run', '-D', r'$APPDIR', '-c', r'$CONFIG'],
        // xray: `xray run -c config.json`
        CoreType.xray => const ['run', '-c', r'$CONFIG'],
      };

  /// آرگومانِ گرفتن نسخه.
  List<String> get versionArgs => const ['version'];

  /// رنگِ برندِ هسته (برای نشان‌ها).
  Color get brandColor => switch (this) {
        CoreType.singbox => const Color(0xFF14B8A6),
        CoreType.xray => const Color(0xFF6366F1),
      };

  /// منبعِ آمارِ پیش‌فرض این هسته.
  StatsBackend get statsBackend => switch (this) {
        CoreType.singbox => StatsBackend.clashRest,
        CoreType.xray => StatsBackend.xrayGrpcCli,
      };
}

/// روشِ خواندن آمار از هسته.
enum StatsBackend {
  /// sing-box → Clash-compatible API (WebSocket روی /traffic).
  clashRest,

  /// Xray → gRPC StatsService از طریق زیرفرمان `xray api statsquery`.
  /// (برای استفاده‌ی مستقیم از gRPC بدون CLI، به docs/GRPC_STATS.md مراجعه کن)
  xrayGrpcCli,
}
