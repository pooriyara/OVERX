import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/subscription.dart';
import 'package:overx/core/net/sub_fetcher.dart';

void main() {
  group('بازکردنِ بدنه‌ی اشتراک', () {
    test('متنِ حاوی لینک دست‌نخورده می‌ماند', () {
      const body = 'vless://abc@1.2.3.4:443#A\nvmess://xx#B';
      expect(SubscriptionFetcher.decodeBody(utf8.encode(body)), body);
    });

    test('بدنه‌ی base64 باز می‌شود', () {
      const plain = 'vless://abc@1.2.3.4:443#A\ntrojan://pw@h:443#B';
      final b64 = base64.encode(utf8.encode(plain));
      final out = SubscriptionFetcher.decodeBody(utf8.encode(b64));
      expect(out, contains('vless://'));
      expect(out, contains('trojan://'));
    });
  });

  group('مدل اشتراک و گروه', () {
    test('پروفایل groupId را در JSON حفظ می‌کند', () {
      const p = Profile(
        id: '1',
        name: 'n',
        protocol: ProfileProtocol.vless,
        address: 'a',
        port: 443,
        groupId: 'g1',
      );
      final back = Profile.decode(p.encode())!;
      expect(back.groupId, 'g1');
    });

    test('پروفایلِ قدیمی بدون groupId می‌شکند نمی‌شود', () {
      const json =
          '{"id":"1","name":"n","protocol":"vless","address":"a","port":443}';
      final p = Profile.decode(json)!;
      expect(p.groupId, isNull);
    });

    test('رفت‌وبرگشت JSON اشتراک', () {
      final s = Subscription(
        id: 's1',
        name: 'my sub',
        url: 'https://x/sub',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final back = Subscription.decode(s.encode())!;
      expect(back.name, 'my sub');
      expect(back.url, 'https://x/sub');
      expect(back.updatedAt!.millisecondsSinceEpoch, 1000);
    });
  });
}
