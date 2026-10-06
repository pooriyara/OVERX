import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:overx/core/models/settings.dart';
import 'package:overx/core/engine/core_type.dart';

/// یک خطِ لاگ.
class LogLine {
  const LogLine({required this.time, required this.level, required this.text});

  final DateTime time;
  final LogLevel level;
  final String text;

  @override
  String toString() =>
      '[${time.toIso8601String().substring(11, 19)}] ${level.name.toUpperCase().padRight(7)} $text';
}

/// فرآیندِ در حال اجرای یک هسته.
///
/// مسئولیت‌ها: اجرا، خواندن خروجی (stdout/stderr) به صورت خط‌به‌خط،
/// نگه‌داشتنِ pid و توقفِ تمیز.
class CoreProcess {
  CoreProcess._({
    required this.process,
    required this.type,
    required this.logs,
  });

  final Process process;
  final CoreType? type;

  /// جریانِ یکپارچه‌ی لاگ‌ها (stdout + stderr).
  final Stream<LogLine> logs;

  int get pid => process.pid;

  bool _killed = false;

  Future<bool> get exited async => _killed;

  /// اجرای یک هسته.
  static Future<CoreProcess> start({
    required CoreType type,
    required String executable,
    required List<String> args,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final proc = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );

    final controller = StreamController<LogLine>();
    var refCount = 2;
    void maybeClose() {
      if (--refCount == 0) {
        unawaited(controller.close());
      }
    }

    void pipe(Stream<List<int>> source) {
      source
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (!controller.isClosed && line.trim().isNotEmpty) {
                controller.add(_parseLine(line));
              }
            },
            onError: (_) {},
            onDone: maybeClose,
            cancelOnError: false,
          );
    }

    pipe(proc.stdout);
    pipe(proc.stderr);

    return CoreProcess._(process: proc, type: type, logs: controller.stream);
  }

  /// توقفِ تمیز: ابتدا SIGINT/SIGTERM، بعد از timeout کشتن اجباری.
  Future<int> stop({Duration grace = const Duration(seconds: 3)}) async {
    if (_killed) return -1;
    _killed = true;
    try {
      if (!Platform.isWindows) {
        process.kill(ProcessSignal.sigterm);
        final code = await process.exitCode.timeout(
          grace,
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -9;
          },
        );
        return code;
      } else {
        process.kill();
        return await process.exitCode.timeout(
          grace,
          onTimeout: () => -9,
        );
      }
    } catch (_) {
      return -1;
    }
  }

  /// حدس زدنِ سطح لاگ از متن خروجی.
  static LogLine _parseLine(String raw) {
    final trimmed = raw.trimRight();
    final lower = trimmed.toLowerCase();

    LogLevel level = LogLevel.info;
    if (lower.contains('fatal') || lower.contains('panic')) {
      level = LogLevel.error;
    } else if (RegExp(r'\berror\b').hasMatch(lower)) {
      level = LogLevel.error;
    } else if (RegExp(r'\b(warn|warning)\b').hasMatch(lower)) {
      level = LogLevel.warning;
    } else if (RegExp(r'\bdebug\b|\btrace\b').hasMatch(lower)) {
      level = LogLevel.debug;
    }

    return LogLine(time: DateTime.now(), level: level, text: trimmed);
  }
}
