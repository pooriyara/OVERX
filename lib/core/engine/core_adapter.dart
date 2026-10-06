import 'package:overx/core/config/singbox_config_builder.dart';
import 'package:overx/core/config/xray_config_builder.dart';
import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/settings.dart';
import 'package:overx/core/process/binary_locator.dart';
import 'package:overx/core/stats/stats_source.dart';
import 'package:overx/core/engine/core_type.dart';

/// تفاوت‌های دو هسته پشت یک رابط یکسان.
///
/// هر چیزی که بین sing-box و Xray فرق می‌کند اینجا می‌آید؛
/// بقیه‌ی برنامه فقط با این انتزاع کار می‌کند.
abstract class CoreAdapter {
  const CoreAdapter();

  CoreType get type;

  /// مسیر باینری را پیدا (یا اعتبارسنجی) می‌کند.
  Future<String?> resolveBinary(AppSettings settings, {String? nativeLibraryDir});

  /// کانفیگ نهایی این هسته را به صورت متن JSON تولید می‌کند.
  String buildConfig({
    required Profile profile,
    required AppSettings settings,
    int? tunFd,
  });

  /// آرگومان‌های اجرا.
  List<String> runArgs(String configPath) => type.runArgs
      .map((a) => a.replaceAll(r'$CONFIG', configPath))
      .toList();

  /// منبع آمار.
  StatsSource createStats({
    required AppSettings settings,
    required String binaryPath,
  });

  /// آیا این پروفایل روی این هسته قابل اجراست؟
  bool supports(Profile profile);

  /// اگر پشتیبانی نمی‌شود، دلیلش (برای نمایش به کاربر).
  String? unsupportedReason(Profile profile) => null;

  factory CoreAdapter.of(CoreType type) => switch (type) {
        CoreType.singbox => const SingboxAdapter(),
        CoreType.xray => const XrayAdapter(),
      };
}

// ---------------------------------------------------------------------------

class SingboxAdapter extends CoreAdapter {
  const SingboxAdapter();

  @override
  CoreType get type => CoreType.singbox;

  @override
  Future<String?> resolveBinary(AppSettings settings, {String? nativeLibraryDir}) =>
      BinaryLocator.locate(
        type,
        overridePath: settings.singboxPath,
        nativeLibraryDir: nativeLibraryDir,
      );

  @override
  String buildConfig({
    required Profile profile,
    required AppSettings settings,
    int? tunFd,
  }) =>
      SingboxConfigBuilder.build(
        profile: profile,
        settings: settings,
        tunFd: tunFd,
      );

  @override
  StatsSource createStats({
    required AppSettings settings,
    required String binaryPath,
  }) =>
      SingBoxClashStats(port: settings.singboxApiPort);

  @override
  bool supports(Profile profile) => true;
}

// ---------------------------------------------------------------------------

class XrayAdapter extends CoreAdapter {
  const XrayAdapter();

  @override
  CoreType get type => CoreType.xray;

  @override
  Future<String?> resolveBinary(AppSettings settings, {String? nativeLibraryDir}) =>
      BinaryLocator.locate(
        type,
        overridePath: settings.xrayPath,
        nativeLibraryDir: nativeLibraryDir,
      );

  @override
  String buildConfig({
    required Profile profile,
    required AppSettings settings,
    int? tunFd,
  }) =>
      XrayConfigBuilder.build(
        profile: profile,
        settings: settings,
        tunFd: tunFd,
      );

  @override
  StatsSource createStats({
    required AppSettings settings,
    required String binaryPath,
  }) =>
      XrayCliStats(
        binaryPath: binaryPath,
        port: settings.xrayApiPort,
      );

  @override
  bool supports(Profile profile) => profile.protocol.supportedByXray;

  @override
  String? unsupportedReason(Profile profile) =>
      '${profile.protocol.label} is not supported by Xray-core';
}
