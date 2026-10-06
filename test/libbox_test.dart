import 'package:overx/core/models/settings.dart';
import 'package:overx/core/platform/libbox.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.overx/libbox');

/// شبیه‌سازیِ یک فراخوانیِ Kotlin → Dart روی کانالِ libbox.
Future<void> _send(MethodCall call) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _channel.name,
    const StandardMethodCodec().encodeMethodCall(call),
    (data) {},
  );
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnavailableLibboxService', () {
    test('همیشه unavailable است و start خطا می‌دهد', () async {
      const svc = UnavailableLibboxService();
      expect(svc.available, false);
      expect(svc.status, LibboxStatus.unavailable);
      expect(svc.lastError, isNotNull);
      expect(svc.start(config: '{}'), throwsA(isA<LibboxException>()));
      await expectLater(svc.stop(), completes);
    });
  });

  group('MethodChannelLibboxService', () {
    late List<MethodCall> calls;
    late bool startResult;

    setUp(() {
      calls = <MethodCall>[];
      startResult = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'available' => true,
          'start' => startResult,
          'stop' => null,
          _ => null,
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('start کانفیگ و فهرست بسته‌ها را می‌فرستد', () async {
      final svc = MethodChannelLibboxService();
      await svc.start(
        config: '{"log":{}}',
        includePackages: const ['org.telegram.messenger'],
        excludePackages: const ['com.android.chrome'],
      );

      expect(calls.length, 1);
      expect(calls.first.method, 'start');

      final args = calls.first.arguments as Map<Object?, Object?>;
      expect(args['config'], '{"log":{}}');
      expect(args['includePackages'], ['org.telegram.messenger']);
      expect(args['excludePackages'], ['com.android.chrome']);

      expect(svc.status, LibboxStatus.started);
      expect(svc.lastError, isNull);
    });

    test('وقتی بومی false برمی‌گرداند، وضعیت error و خطا پرتاب می‌شود',
        () async {
      startResult = false;
      final svc = MethodChannelLibboxService();

      await expectLater(svc.start(config: '{}'), throwsA(isA<LibboxException>()));
      expect(svc.status, LibboxStatus.error);
    });

    test('stop کانال را صدا می‌زند و وضعیت stopped می‌شود', () async {
      final svc = MethodChannelLibboxService();
      await svc.start(config: '{}');
      await svc.stop();

      expect(calls.map((c) => c.method), contains('stop'));
      expect(svc.status, LibboxStatus.stopped);
    });

    test('probe مقدار available را از بومی می‌گیرد', () async {
      final svc = MethodChannelLibboxService();
      expect(svc.available, false, reason: 'تا پیش از probe مقدار پیش‌فرض است');

      expect(await svc.probe(), true);
      expect(svc.available, true);
    });

    test('defaultAvailable روی اندروید پیش‌فرض را true می‌کند', () {
      // main() این را برای اندروید می‌فرستد تا پیش از آمدنِ جوابِ probe
      // بلوک نشویم
      expect(MethodChannelLibboxService(defaultAvailable: true).available, true);
    });

    test('لاگِ ساده (رشته) در سطحِ info پخش می‌شود', () async {
      final svc = MethodChannelLibboxService();
      final received = <LibboxLogLine>[];
      svc.logs.listen(received.add);

      await _send(const MethodCall('onLog', 'libbox: started'));

      expect(received.single.message, 'libbox: started');
      expect(received.single.level, LogLevel.info);
    });

    test('لاگِ همراه با سطح، سطحش را حفظ می‌کند', () async {
      final svc = MethodChannelLibboxService();
      final received = <LibboxLogLine>[];
      svc.logs.listen(received.add);

      await _send(
        const MethodCall(
          'onLog',
          <String, Object?>{'level': 2, 'message': 'bad config'},
        ),
      );

      expect(received.single.message, 'bad config');
      expect(received.single.level, LogLevel.error);
    });

    test('سطحِ گم‌شده یا نامعلوم به info می‌افتد', () async {
      final svc = MethodChannelLibboxService();
      final received = <LibboxLogLine>[];
      svc.logs.listen(received.add);

      await _send(
        const MethodCall('onLog', <String, Object?>{'message': 'hello'}),
      );
      await _send(
        const MethodCall(
          'onLog',
          <String, Object?>{'level': 99, 'message': 'x'},
        ),
      );

      expect(received.map((l) => l.level), [LogLevel.info, LogLevel.info]);
    });

    test('رویدادِ پاک‌شدنِ لاگ‌ها پخش می‌شود', () async {
      final svc = MethodChannelLibboxService();
      var cleared = 0;
      svc.logsCleared.listen((_) => cleared++);

      await _send(const MethodCall('onLogsCleared', null));
      await _send(const MethodCall('onLogsCleared', null));

      expect(cleared, 2);
    });

    test('تغییر وضعیت از سمت بومی اعمال می‌شود', () async {
      final svc = MethodChannelLibboxService();

      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onStatus', {
            'status': 'error',
            'error': 'vpn permission not granted',
          }),
        ),
        (data) {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(svc.status, LibboxStatus.error);
      expect(svc.lastError, 'vpn permission not granted');
    });
  });

  group('نگاشتِ سطحِ لاگِ sing-box', () {
    test('ترتیبِ سطوح برعکسِ ترتیبِ حروفِ الفباست', () {
      // log/level.go: panic=0، fatal=1، error=2، warn=3، info=4، debug=5، trace=6
      expect(libboxLevelToLogLevel(0), LogLevel.error);
      expect(libboxLevelToLogLevel(1), LogLevel.error);
      expect(libboxLevelToLogLevel(2), LogLevel.error);
      expect(libboxLevelToLogLevel(3), LogLevel.warning);
      expect(libboxLevelToLogLevel(4), LogLevel.info);
      expect(libboxLevelToLogLevel(5), LogLevel.debug);
      expect(libboxLevelToLogLevel(6), LogLevel.debug);
    });

    test('مقدارِ نال و نامعلوم به info می‌افتد', () {
      expect(libboxLevelToLogLevel(null), LogLevel.info);
      expect(libboxLevelToLogLevel(-1), LogLevel.info);
      expect(libboxLevelToLogLevel(42), LogLevel.info);
    });
  });

}
