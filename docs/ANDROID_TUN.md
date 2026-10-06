# مسیریابیِ کل دستگاه روی اندروید (TUN)

روی دسکتاپ، خودِ هسته اینترفیس TUN را می‌سازد (نیاز به دسترسی مدیر).
روی اندروید اما فقط یک `VpnService` می‌تواند اینترفیس بسازد، و هر هسته
روش متفاوتی برای گرفتنِ fd دارد:

| هسته | روش تحویل fd | وضعیت |
|---|---|---|
| **Xray-core** | متغیر محیطی `XRAY_TUN_FD` | ✅ کامل پیاده‌سازی شده |
| **sing-box** | `libbox` — کتابخانه‌ی بومی که fd را از callback می‌گیرد | ✅ کامل پیاده‌سازی شده |

---

## ۱. Xray — مسیرِ «fd خام»

مستندات رسمی:
<https://xtls.github.io/en/config/inbounds/tun.html>

> On Android and iOS, the TUN FD must be passed in from an external app via the
> **`XRAY_TUN_FD`** environment variable.

در این مسیر **ما** اینترفیس را می‌سازیم و fd را به هسته می‌دهیم:

```
Dart: EngineController.connect()
  → AndroidBridge.prepare()           // VpnService.prepare() → دیالوگ مجوز
  → AndroidBridge.acquireTun(mtu)     // TunVpnService
        ↳ Builder().establish() → ParcelFileDescriptor → fd
  → TunHandle(fd).env  ==  {'XRAY_TUN_FD': '42', 'XRAY_TUN_MTU': '9000'}
  → CoreProcess.start(..., environment: env)
  → XrayConfigBuilder.build(tunFd: fd)
```

وقتی fd از بیرون می‌آید، Xray نباید خودش جدول مسیریابی را دست بزند —
`VpnService.Builder.addRoute()` این کار را کرده است. برای همین در
`xray_config_builder.dart` هنگام `tunFd != null` کلیدهای
`autoSystemRoutingTable` و `gateway` را نمی‌فرستیم.

## ۲. sing-box — مسیرِ libbox (برعکسِ مسیر قبل)

### چرا؟

بررسیِ شِمای رسمی sing-box (`sing-box.sagernet.org/schema.json`) نشان می‌دهد
که کانفیگ JSON آن **هیچ فیلد `file_descriptor` ندارد** — این فقط در کتابخانه‌ی
`sing-tun` وجود دارد. پس باینری CLI هرگز نمی‌تواند fd را بگیرد.

`libbox` این مشکل را با وارونه کردن جریان حل می‌کند:
**خودِ کتابخانه با صدا زدن `PlatformInterface.openTun(options)` از ما
می‌خواهد اینترفیس را بسازیم و fd را برگردانیم.**

زمینه در کد sing-box (`experimental/libbox/service.go`):

```go
func (w *platformInterfaceWrapper) OpenInterface(
    options *tun.Options, platformOptions option.TunPlatformOptions,
) (tun.Tun, error) {
    tunFd, err := w.iif.OpenTun(&tunOptions{options, routeRanges, platformOptions})
    ...
    options.Name, err = getTunnelName(tunFd)
    dupFd, err := dup(int(tunFd))
    options.FileDescriptor = dupFd     // ← fd ما اینجا می‌نشیند
    return tun.New(*options)
}
```

### جریان در OVERX

```
Dart:  EngineController.connect()
         └─ libbox.available && sing-box && tunMode  →  libbox.start(config)
              ↓ MethodChannel('com.overx/libbox')
Kotlin: MainActivity.startLibbox()
          → LibboxVpnService (یک VpnService پیش‌زمینه)
              → Libbox.setup(SetupOptions)
              → CommandServer(this, platformInterface).start()
              → commandServer.startOrReloadService(config, OverrideOptions)
                   ↓
Go:      libbox کانفیگ را می‌خواند، به TUN می‌رسد و صدا می‌زند:
              ↓
Kotlin:  LibboxPlatformInterface.openTun(options)
           ├─ address/mtu/route/dns/بسته‌ها را از options می‌خواند
           ├─ VpnService.Builder().establish()
           └─ return pfd.fd          ← fd تحویل داده می‌شود
```

نکته‌ی کلیدی: ما آدرس‌ها را انتخاب نمی‌کنیم. هرچه کاربر در کانفیگ sing-box
نوشته (مثلاً `inet4_address`, `mtu`, `auto_route`, `include_package`)
همان از طریق `TunOptions` به ما می‌رسد و باید عیناً به `Builder` داده شود.

### فایل‌ها

| فایل | نقش |
|---|---|
| `LibboxVpnService.kt` | سرویس VPN؛ میزبان `CommandServer`؛ پیاده‌سازی `CommandServerHandler` |
| `LibboxPlatformInterface.kt` | پیاده‌سازی `PlatformInterface` — از جمله `openTun` |
| `LibboxChannel.kt` | ارسال لاگ و وضعیت به Dart |
| `MainActivity.kt` | کانال `com.overx/libbox` (`available` / `start` / `stop`) |
| `lib/core/platform/libbox.dart` | رابط Dart + `MethodChannelLibboxService` |

### ساخت

```bash
./scripts/build_libbox.sh          # → android/libs/libbox.aar
flutter build apk --release
```

اسکریپت همان دستوری را اجرا می‌کند که مخزن sing-box خودش تعریف کرده:

```makefile
lib_android:
	go run ./cmd/internal/build_libbox -target android
```

پیکربندی در `experimental/libbox/ffi.json` است؛ بسته‌ی جاوا:
`io.nekohasekai.libbox`.

پیش‌نیاز: Go 1.24+، Android NDK r28+ (`ANDROID_NDK_HOME`)، JDK 17.

### تأییدِ API

همه‌ی نوع‌ها، ثابت‌ها و توابعی که کاتلین استفاده می‌کند در برابر منبع
sing-box **v1.14.2** بررسی شده‌اند (۲۱ مورد: `CommandServer`,
`CommandServerHandler`, `OverrideOptions`, `SetupOptions`, `TunOptions`,
`Libbox.DNSModeDisabled`, `Libbox.InterfaceTypeWIFI`, …).
نحو و ساختار کاتلین هم با `kotlinc` بررسی شده (بدون خطای نحو).

> با این حال کامپایل نهایی نیازمند android.jar و AAR واقعی است و در این
> محیط (نبود اندروید SDK/NDK) انجام نشده است.

## ۳. مسیریابیِ هر برنامه

گزینه‌های `include_package` / `exclude_package` در کانفیگ sing-box توسط
`OverrideOptions` به libbox می‌رسند و `openTun()` آن‌ها را به
`addAllowedApplication` / `addDisallowedApplication` تبدیل می‌کند.

```
تنظیمات → مسیریابیِ هر برنامه
   ↓ فعال + انتخاب حالت (فقط این‌ها / همه به‌جز این‌ها)
Dart:  settings.perAppPackages  →  EngineController.perAppLists()
   ↓ libbox.start(includePackages:, excludePackages:)
Kotlin: LibboxVpnService.buildOverrideOptions()
   ↓ OverrideOptions.includePackage / excludePackage
Go:     libbox → platformWrapper.OpenInterface
Kotlin: LibboxPlatformInterface.openTun(options)
          options.includePackage → builder.addAllowedApplication(...)
          options.excludePackage → builder.addDisallowedApplication(...)
```

نکته‌ی ظریف: برنامه‌ی خودمان در هر دو حالت لحاظ می‌شود.
در حالت include باید خودمان هم در فهرست باشیم (وگرنه درخواست‌هایمان از تونل
بیرون می‌ماند — سوکت‌ها با `protect()` محافظت می‌شوند پس حلقه‌ای پیش نمی‌آید)؛
در حالت exclude نباید خودمان را حذف کنیم. این منطق در
`LibboxVpnService.buildOverrideOptions()` است.

فهرست برنامه‌ها با `AppLister` و کانال `listPackages` گرفته می‌شود
(برنامه‌های سیستمی به‌طور پیش‌فرض پنهان‌اند).

### ۳.۱ آیکونِ برنامه‌ها

آیکون‌ها همراهِ فهرست نمی‌آیند: با صد برنامه باید چند مگابایت از کانالِ متد
رد می‌شد. به‌جایش هر کاشی هنگامِ نمایش، آیکونِ خودش را جداگانه می‌خواهد:

```
Dart:   _AppIcon.initState → AppIconService.load(packageName)
   ↓ آیکون در کش نیست
Dart:   PlatformBridge.appIcon(name, size: 64)
   ↓ MethodChannel "appIcon" {packageName, size}
Kotlin: MainActivity → Thread { AppLister.icon(this, pkg, size) }
          PackageManager.getApplicationIcon() → Drawable
          AdaptiveIconDrawable/VectorDrawable → Canvas → Bitmap 64×64
          Bitmap.compress(PNG) → ByteArray
   ↓ result.success(ByteArray)
Dart:   کش در AppIconService → Image.memory
```

نکته‌ها:

- خواندن از `PackageManager` شامل I/O است ← همیشه در `Thread` و بیرون از
  تردِ اصلی (`AppLister.icon` خودش ترد نمی‌سازد؛ صدا زننده مسئول است).
- `AdaptiveIconDrawable` (اندروید ۸+) را نمی‌توان مستقیماً به بیت‌مپ تبدیل
  کرد؛ باید روی `Canvas` رسم شود. `BitmapDrawable` فقط تغییر اندازه می‌گیرد.
- بیت‌مپِ مبدأ `recycle` نمی‌شود — ممکن است متعلق به کشِ خودِ
  `PackageManager` باشد.
- کشِ LRU با سقفِ ۱۹۲ ورودی در `AppIconCache` (هر آیکون ۲–۴ کیلوبایت).
- پاسخِ `null` هم کش می‌شود تا برای برنامه‌های بی‌آیکون هر بار درخواست
  نرود. در UI حرفِ اولِ نام جایگزین می‌شود.

## ۴. آماده‌سازی باینری روی اندروید

هسته‌ی Xray هم‌چنان باید به صورت کتابخانه‌ی بومی کنار برنامه باشد:

```
android/app/src/main/jniLibs/
├── arm64-v8a/libxray.so
├── armeabi-v7a/libxray.so
└── x86_64/libxray.so
```

`BinaryLocator` از طریق `AndroidBridge.nativeLibraryDir()` این پوشه را
پیدا می‌کند.

فایل‌های `.so` داخل APK توسط سیستم **غیرقابل‌اجرا** extract می‌شوند، بنابراین
`BinaryInstaller` در اولین اجرا آن‌ها را به `filesDir/bin` کپی و `chmod +x`
می‌کند و مسیر آماده را برمی‌گرداند:

```dart
final installed = await bridge.installedBinaries();
// {'xray': '/data/data/com.overx.overx/files/bin/xray'}
```

`EngineController` این مسیر را بر جستجوی خودکارِ باینری مقدم می‌دارد.

## ۵. مانیفست

`android/app/src/main/AndroidManifest.xml` دو سرویس VPN دارد:

```xml
<service android:name=".TunVpnService"      … />   <!-- مسیر fd خام (Xray) -->
<service android:name=".LibboxVpnService"   … />   <!-- مسیر libbox (sing-box) -->
```

هر دو `android:permission="android.permission.BIND_VPN_SERVICE"` و
فیلتر `android.net.VpnService` دارند. مجوزها:
`INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`,
`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`.

## ۶. مانیتورِ اینترفیس پیش‌فرض

وقتی کاربر از وای‌فای به داده‌ی همراه می‌رود، هسته باید بداند مسیر خروجی عوض
شده تا جداول مسیریابی‌اش را به‌روز کند. libbox این را از طریق
`PlatformInterface.StartDefaultInterfaceMonitor` می‌پرسد و
`DefaultNetworkMonitor` پاسخش را می‌دهد.

یک نکته‌ی مهم که اگر رعایت نشود این قابلیت بی‌اثر می‌ماند:

> از اندروید ۹ (API 28) به بعد، `registerDefaultNetworkCallback` اینترفیسِ
> **خودِ VPN** را برمی‌گرداند
> ([تغییر رفتار در Android P DP1](https://android.googlesource.com/platform/frameworks/base/+/dda156ab0c5d66ad82bdcf76cda07cbc0a9c8a2e)).

برای همین روی آن نسخه‌ها به‌جای LISTEN از `requestNetwork` استفاده می‌کنیم تا
فقط «شبکه‌ی واقعیِ پیش‌فرض» را بگیریم (نیازمند `CHANGE_NETWORK_STATE`):

| API | روش |
|---|---|
| ۳۱+ | `registerBestMatchingNetworkCallback(request, cb, handler)` |
| ۲۸–۳۰ | `requestNetwork(request, cb, handler)` |
| ۲۶–۲۷ | `registerDefaultNetworkCallback(cb, handler)` |
| ۲۴–۲۵ | `registerDefaultNetworkCallback(cb)` |

پس از تغییر شبکه، `LinkProperties` ممکن است هنوز آماده نباشد؛ مانیتور تا ۱۰ بار
با فاصله‌ی ۱۰۰ میلی‌ثانیه تلاش می‌کند (همان الگوی SFA). اگر شبکه قطع شود،
`updateDefaultInterface("", -1, false, false)` فرستاده می‌شود.


### ۶.۱ اولویتِ شبکه (وای‌فای در برابر داده‌ی همراه)

ممکن است هم‌زمان چند شبکه در دسترس باشد. اندروید لزوماً همانی را برنمی‌گزیند
که ما می‌خواهیم، پس `DefaultNetworkMonitor` همه‌ی شبکه‌های در دسترس را در یک
نگاشت نگه می‌دارد و به نوعِ ترابرد امتیاز می‌دهد:

| ترابرد | امتیاز (پیش‌فرض) |
|---|---|
| وای‌فای | ۱۰۰ (اگر `preferWifi` خاموش باشد: ۴۰) |
| اترنت | ۹۰ |
| بلوتوث | ۵۰ |
| داده‌ی همراه | ۴۰ |
| بقیه | ۱۰ |
| VPN | ۱۰۰- (هرگز انتخاب نمی‌شود) |

دو نکته:

- **`TRANSPORT_VPN` حذف می‌شود.** آن اینترفیسِ خودمان است و گرفتنش دقیقاً
  همان دوری است که کل این کلاس برای پرهیز از آن نوشته شده.
- هنگامِ `start()` شبکه‌های از پیش موجود با `allNetworks` واردِ فهرست
  می‌شوند، وگرنه تا اولین تغییرِ شبکه چیزی گزارش نمی‌شد.

`preferWifi` یک پرچمِ سراسری است (پیش‌فرض «روشن») که بعداً می‌توان به یک
تنظیم در UI وصل کرد.

## ۷. زنده‌ماندنِ کانال (FlutterEngineCache)

`MethodChannel` به یک `BinaryMessenger` نیاز دارد که معمولاً از موتور فلاترِ
اکتیویتی می‌آید. اگر اکتیویتی نابود شود، پیام‌های سرویس (لاگ و وضعیت) به دارت
نمی‌رسند.

برای همین `MainActivity` موتور را کش می‌کند:

```kotlin
override fun provideFlutterEngine(context: Context): FlutterEngine? =
    FlutterEngineCache.getInstance().get(ENGINE_ID)
        ?: FlutterEngine(context).also { FlutterEngineCache.getInstance().put(ENGINE_ID, it) }

override fun shouldDestroyEngineWithHost(): Boolean = false
override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) { /* عمداً خالی */ }
```

و کانال‌ها فقط یک بار بسته می‌شوند (`channelsAttached`) تا با هر اتصالِ مجددِ
اکتیویتی هندلرها تکرار نشوند.

## ۸. لاگ‌های زنده و آمار از طریق `CommandClient`

در حالت libbox کلیدِ `log.output` در کانفیگ **نادیده گرفته می‌شود**: لاگ‌ها
در یک حلقه‌ی درون‌حافظه‌ای (`logRing` در `daemon`) نگه داشته می‌شوند و تنها
راهِ خواندنشان جریانِ gRPCِ `SubscribeLog` است. بنابراین برای دیدنِ لاگِ زنده
باید یک «کلاینتِ فرمان» به سرورِ درون‌فرآیندی وصل کنیم.

`CoreCommandClient.kt` دقیقاً همین کار را می‌کند:

```
Go:     daemon.StartedService.SubscribeLog / SubscribeStatus
           ↓ gRPC روی <basePath>/command.sock (یونیکس، درون‌فرآیندی)
Go:     libbox.CommandClient → CommandClientHandler
           ↓ gomobile
Kotlin: CoreCommandClient.writeLogs() / writeStatus()
           ↓
         LibboxChannel.emitLogLine(level, message)  →  Dart logsProvider
         CoreCommandClient.TrafficListener          →  اعلان
```

### ثبت‌نامِ فرمان‌ها

فقط دو فرمان را می‌خواهیم (`experimental/libbox/command.go`):

| ثابت | مقدار | معنا |
|---|---|---|
| `CommandLog` | ۰ | جریانِ لاگ |
| `CommandStatus` | ۱ | آمارِ ترافیک |

### نکته‌هایی که از سورس گرفته شده (وگرنه به خطا می‌خورد)

- **`statusInterval` واحدش نانوثانیه است.** سمت Go مستقیماً به
  `time.Duration(request.Interval)` تبدیل می‌شود (`daemon.SubscribeStatus`)؛
  مقدارِ صفر هم همان پیش‌فرضِ یک ثانیه است.
- **ترتیبِ سطوحِ لاگ برعکسِ انتظار است** (`log/level.go`، نوعِ
  `Level = uint8`): `panic=0`، `fatal=1`، `error=2`، `warn=3`، `info=4`،
  `debug=5`، `trace=6`. نگاشت به `LogLevel` ی برنامه در
  `libboxLevelToLogLevel()` (در `lib/core/platform/libbox.dart`) انجام
  می‌شود و تست دارد.
- **`SubscribeStatus` دلتا می‌فرستد**: `Uplink`/`Downlink` تفاضلِ نسبت به
  پیامِ قبلی‌اند (با فاصله‌ی یک ثانیه، پس عملاً بایت‌برثانیه) و
  `UplinkTotal`/`DownlinkTotal` تجمعی. پیامِ اول دلتای صفر دارد.
- **`clearLogs()` بعد از هر بارگذاریِ دوباره صدا زده می‌شود**؛ سمت Dart
  با `onLogsCleared` فهرستِ نمایش‌داده‌شده خالی می‌شود.
- کلاینتِ «handler-bound» (برخلافِ standalone) تا ۱۰ بار برای بالا آمدنِ
  سرور صبر می‌کند، پس می‌توان بلافاصله بعد از `startOrReloadService` صدا زد.

### گروه‌های خروجی و اتصال‌ها (صفحه‌ی «شبکه»)

علاوه بر لاگ و آمار، دو فرمانِ دیگر را هم ثبت می‌کنیم تا صفحه‌ی شبکه داده‌ی
زنده داشته باشد:

| ثابت | مقدار | مصرف |
|---|---|---|
| `CommandGroup` | ۲ | گروه‌های خروجی (`writeGroups`) |
| `CommandConnections` | ۴ | اتصال‌های جاری (`writeConnectionEvents`) |

`CoreCommandClient` آخرین تصویر را نگه می‌دارد (نه جریان) و
`MainActivity` آن را روی درخواست برمی‌گرداند. قراردادِ کانال:

| متد | آرگومان‌ها | پاسخ |
|---|---|---|
| `getGroups` | — | `List<Map>` با کلیدهای `tag,type,selectable,selected,isExpand,items` |
| `getConnections` | — | `List<Map>` با کلیدهای `id,outbound,protocol,network,destination,domain,source,uplinkTotal,downlinkTotal,createdAt,closedAt,processPath` |
| `selectOutbound` | `{groupTag,outboundTag}` | — |
| `urlTest` | `{outboundTag}` | — |
| `closeConnection` | `{id}` | — |
| `closeConnections` | — | — |

#### نام‌های gobind — بررسی‌شده با سورسِ v1.14.2

این فهرست قبلاً «فرضِ تأییدنشده» بود. حالا با خواندنِ سورسِ واقعیِ
`sing-box v1.14.2` و مولّدِ `golang/mobile/bind/genjava.go` بررسی شده؛
جزئیات و ارجاعِ فایل‌به‌فایل در [LIBBOX_CONTRACT.md](LIBBOX_CONTRACT.md) و
تستِ قابل‌اجرا در `test/libbox_contract_test.dart` است. تنها چیزی که مانده،
اولین **کامپایل** با AAR واقعی است (که آن هم سه باگِ واقعی را بیرون کشید و
اصلاح شد — همان سند، بخش ۳):

| فراخوانی در کاتلین | فرض | ریسک |
|---|---|---|
| `holder.iterator()` | Go: `Connections.Iterator()` | متوسط |
| `iterator.next()` | Go: `Next()`؛ **پایانِ پیمایش با `nil`** | پرریسک‌ترین مورد |
| `group.getItems()` | Go: `OutboundGroup.GetItems()` | کم |
| `item.tag` / `item.type` | gobind برای فیلدِ exported getter می‌سازد | کم |
| `connection.displayDestination()` | Go: `Connection.DisplayDestination()` | متوسط |
| `item.getURLTestDelay()` | فیلدِ `URLTestDelay` — **تأییدشده از مولد** | ندارد |

> **اصلاحیه (مهم):** اینجا قبلاً نوشته بودیم «gobind متدِ `hasNext()`
> تولید نمی‌کند». این حرف درست نبود. در v1.14.2 تکرارگرها خودشان `HasNext`
> دارند (`experimental/libbox/iterator.go` و `command_types.go`)، بنابراین
> `hasNext()` در جاوا هم وجود دارد.
>
> با این حال الگویِ فعلیِ ما همچنان درست است و عمداً نگه داشته شده:
> `while (true) { val x = it.next() ?: break }`
> چون `iterator[T].Next()` در Go وقتی لیست تمام شود مقدارِ صفر (`nil`) برمی‌گرداند.
> خلاصه: **هر دو کار می‌کند**؛ `next() ?: break` وابسته به `HasNext` نیست و
> برای تکرارگرهایی که آن را ندارند (مثل `RoutePrefixIterator` در برخی نسخه‌ها)
> هم جواب می‌دهد.

#### قاعده‌ی قطعیِ نام‌گذاری در gobind (از روی مولد)

این دیگر حدس نیست — از `golang/mobile/bind/genjava.go` خوانده شده:

```go
// فيلدها: نامِ فيلدِ Go دست‌نخورده مي‌آيد
g.Printf("public final native %s get%s();\n", g.javaType(f.Type()), f.Name())
g.Printf("public final native void set%s(%s v);\n\n", f.Name(), ...)
```

| در Go | در جاوا/کاتلین |
|---|---|
| فیلدِ `URLTestDelay` | `getURLTestDelay()` / `setURLTestDelay(int)` |
| فیلدِ `URLTestTime` | `getURLTestTime()` / `setURLTestTime(long)` |
| متدِ `GetItems()` | `getItems()` |
| متدِ `Iterator()` | `iterator()` |
| متدِ `Next()` | `next()` |

**نکته‌ی عملی:** چون مخفف دست‌نخورده می‌ماند، `getURLTestDelay` است نه
`getUrlTestDelay`. و چون کاتلین طبقِ JavaBeans نامِ ویژگی را از
`getURLTestDelay` می‌سازد (`URLTestDelay` با حروفِ بزرگ)، در کاتلین
**حتماً getter را صریح صدا بزنید** و سراغِ ویژگیِ مصنوعی نروید.

#### یک اشتباه که اینجا ثبت می‌شود

`MethodChannel.setMethodCallHandler` هندلرِ قبلی را **جایگزین** می‌کند، نه
اینکه اضافه کند. یک بار در `MainActivity` بلوکِ libbox تکراری ثبت شد و نیمی
از متدها روی دستگاه بی‌صدا از کار می‌افتادند — در حالی که کامپایلر فقط چند
خطایِ بی‌ربطِ inference نشان می‌داد. برای همین `test/channel_contract_test.dart`
وجود دارد: متنِ دو سمت را می‌خواند و ناهماهنگیِ نام‌ها را می‌گیرد.

### اعلانِ ترافیک

`LibboxVpnService` خودش را به عنوانِ `TrafficListener` ثبت می‌کند و متنِ
اعلان را به صورت `↑ ۱۲ KB/s ↓ ۸۴ KB/s · مجموع ۱.۲ MB` به‌روز می‌کند.
به‌روزرسانیِ اعلان به تردِ اصلی فرستاده می‌شود و بیش از یک بار در ثانیه
انجام نمی‌گیرد (`NOTIFICATION_MIN_INTERVAL`).

## ۹. چک‌لیست باقی‌مانده اندروید

- [x] آیکون برای برنامه‌ها در صفحه‌ی per-app
- [x] لاگ‌های زنده‌ی هسته در حالت libbox (از طریق `CommandClient`)
- [x] نمایش ترافیک در اعلان (به‌روزرسانی دوره‌ای)
- [x] اولویت‌بندیِ شبکه (وای‌فای در برابر داده) در مانیتور
- [x] صفحه‌ی شبکه: گروه‌های خروجی + اتصال‌های زنده (فقط حالت libbox)
- [x] تستِ قراردادِ کانال (ایستا — جایگزینِ بخشی از تستِ روی دستگاه)
- [ ] **ساخت با `libbox.aar` واقعی و تأییدِ جدولِ فرض‌های gobind** ← گامِ بعدی
