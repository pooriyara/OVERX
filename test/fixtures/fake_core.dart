// هسته‌ی قلابی — فقط برای تستِ سرتاسریِ EngineController.
//
// رفتار واقعیِ دو هسته را شبیه‌سازی می‌کند:
//   `<bin> version`      → چاپِ نسخه (BinaryLocator آن را صدا می‌زند)
//   `<bin> run -c <cfg>` → چند خط لاگ + میزبانیِ Clash API روی /traffic
//
// این فایل مستقیماً اجرا نمی‌شود؛ تست یک wrapperِ شل می‌سازد که آن را با
// مفسرِ dart اجرا کند.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('fake-core: no arguments');
    exit(64);
  }

  // ---------------------------------------------------------------- version
  if (args.first == 'version') {
    stdout.writeln('sing-box version 1.14.2 (fake-core)');
    return;
  }

  // -------------------------------------------------------------------- run
  final configIndex = args.indexOf('-c');
  if (args.first != 'run' || configIndex == -1 || configIndex + 1 >= args.length) {
    stderr.writeln('fake-core: expected `run -c <config>`');
    exit(64);
  }

  final configFile = File(args[configIndex + 1]);
  if (!configFile.existsSync()) {
    stderr.writeln('fake-core: config not found: ${configFile.path}');
    exit(66);
  }

  final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final port = _clashPort(config);

  stdout.writeln('INFO[0000] fake-core: configuration loaded');
  stdout.writeln('INFO[0000] inbound/mixed[0] listening at 127.0.0.1:2080');
  await stdout.flush();

  if (port == null) {
    stdout.writeln('WARN[0000] fake-core: no clash api in config');
    await stdout.flush();
    await _serveForever(null);
    return;
  }

  stdout.writeln('INFO[0000] clash api listening at 127.0.0.1:$port');
  await stdout.flush();
  await _serveForever(port);
}

/// پورت را از `experimental.clash_api.external_controller` می‌خواند.
int? _clashPort(Map<String, dynamic> config) {
  final experimental = config['experimental'];
  if (experimental is! Map<String, dynamic>) return null;
  final clash = experimental['clash_api'];
  if (clash is! Map<String, dynamic>) return null;
  final controller = clash['external_controller'];
  if (controller is! String) return null;
  final parts = controller.split(':');
  if (parts.length < 2) return null;
  return int.tryParse(parts.last.trim());
}

Future<void> _serveForever(int? port) async {
  HttpServer? server;
  if (port != null) {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    stdout.writeln('INFO[0000] fake-core: started');
    await stdout.flush();

    var up = 0;
    var down = 0;
    server.transform(WebSocketTransformer()).listen((WebSocket socket) {
      Timer.periodic(const Duration(milliseconds: 200), (timer) {
        // مقادیر تجمعی — دقیقاً مثل خروجیِ واقعیِ sing-box
        up += 1500;
        down += 6000;
        try {
          socket.add(jsonEncode(<String, int>{'up': up, 'down': down}));
        } catch (_) {
          timer.cancel();
        }
      });
    });
  } else {
    stdout.writeln('INFO[0000] fake-core: started');
    await stdout.flush();
  }

  final done = Completer<void>();
  ProcessSignal.sigterm.watch().listen((_) {
    if (!done.isCompleted) done.complete();
  });
  ProcessSignal.sigint.watch().listen((_) {
    if (!done.isCompleted) done.complete();
  });
  stdin.listen((_) {}, onDone: () {
    if (!done.isCompleted) done.complete();
  });

  await done.future;
  await server?.close(force: true);
  stdout.writeln('INFO[0000] fake-core: stopped');
}
