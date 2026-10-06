# آمار Xray از طریق gRPC مستقیم (بدون CLI)

پیاده‌سازی فعلی (`XrayCliStats` در `lib/core/stats/stats_source.dart`) هر ثانیه
یک فرآیند کوتاه اجرا می‌کند:

```bash
xray api statsquery --server=127.0.0.1:8080 -pattern ""
# {"stat":[{"name":"outbound>>>proxy>>>traffic>>>uplink","value":12345}, …]}
```

این روش ساده و بدون وابستگی است، اما برای تولید بهتر است مستقیم با
**gRPC StatsService** صحبت کنی. مراحل:

## ۱. وابستگی‌ها

```yaml
dependencies:
  grpc: ^4.0.0
  protobuf: ^4.0.0

dev_dependencies:
  protoc_plugin: ^21.1.2
```

## ۲. فایل‌های proto

از مخزن Xray-core بردار:

- `app/stats/command/command.proto`
- `app/stats/config.proto`

و وابستگی‌هایشان (`common/serial/*.proto`, `common/net/*.proto`, …) را کنار آن‌ها بگذار.

## ۳. تولید کد دارت

```bash
mkdir -p lib/core/stats/generated
protoc \
  --dart_out=grpc:lib/core/stats/generated \
  -I protos \
  protos/app/stats/command/command.proto
```

## ۴. کلاینت

```dart
import 'package:grpc/grpc.dart';
import 'generated/app/stats/command/command.pbgrpc.dart';

final channel = ClientChannel(
  '127.0.0.1',
  port: settings.xrayApiPort,
  options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
);
final client = StatsServiceClient(channel);

final resp = await client.queryStats(
  QueryStatsRequest()..reset = false,
);
// resp.stat: [ {name: "outbound>>>proxy>>>traffic>>>uplink", value: 12345} ]
```

سپس کلاس را جایگزین `XrayCliStats` کن — قراردادِ `StatsSource` ثابت است:

```dart
class XrayGrpcStats extends StatsSource {
  @override Future<void> onStart() { /* stream یا polling */ }
  @override Future<void> onStop()  { /* channel.shutdown() */ }
}
```

و در `XrayAdapter.createStats`:

```dart
return XrayGrpcStats(port: settings.xrayApiPort);
```

## ۵. نکته امنیتی

پورت API باید **فقط روی 127.0.0.1** گوش بدهد (در کانفیگ ما همین است) و
هیچ احراز هویتی ندارد؛ آن را از فایروال/شبکه باز نکن.
