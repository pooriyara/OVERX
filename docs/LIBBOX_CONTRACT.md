# قراردادِ libbox — چه چیزی تأیید شده و چه چیزی نه

این سند پاسخِ این سؤال است: **آیا gRPC روی `command.sock` واقعاً زیرِ
`VpnService` بالا می‌آید، و آیا کاتلینِ ما با اینترفیسِ واقعیِ libbox جور است؟**

دستگاه نداریم و `libbox.aar` هم نساخته‌ایم، پس «اجرا» ممکن نیست. به‌جایش
**سورسِ sing-box v1.14.2** و **مولّدِ کدِ gobind** را خوانده‌ایم و پیاده‌سازیِ
خودمان را با آن‌ها سنجیده‌ایم. هر ادعای این سند به یک فایلِ مشخص ارجاع دارد و
خلاصه‌ی قابل‌اجرایش در `test/libbox_contract_test.dart` است (۱۳ تست).

نسخه‌ی مرجع: **sing-box v1.14.2**، شاخه‌ی `v1.14.2`.

---

## ۱. آیا سوکت قبل از نیاز ساخته می‌شود؟ — بله

`experimental/libbox/command_server.go`:

```go
func (s *CommandServer) Start() error {
	if sCommandServerListenPort == 0 {
		sockPath := filepath.Join(sBasePath, "command.sock")
		os.Remove(sockPath)
		… net.ListenUnix(…) …
	}
	s.listener = listener
	…
	go s.grpcServer.Serve(listener)     // ← شنونده همین‌جا بالا می‌آید
	return nil
}
```

یعنی `Start()` **هم‌زمان** (نه در گوروتینِ جدا) سوکت را می‌سازد و پیش از
برگشتن، gRPC روی آن سرو می‌دهد. سپس:

```go
func (s *CommandServer) StartOrReloadService(configContent string, options *OverrideOptions) error
```

هسته را بالا می‌آورد — که در میانه‌اش ممکن است به عقب صدا بزند
(`PlatformInterface.OpenTun` و غیره).

سمتِ ما (`LibboxVpnService.startLibbox`) دقیقاً همین ترتیب را دارد:

```kotlin
val server = CommandServer(this, platformInterface)
server.start()                                              // ← سوکت اینجا ساخته می‌شود
server.startOrReloadService(config, buildOverrideOptions())
…
CoreCommandClient.start()                                   // ← کلاینت آخرِ کار وصل می‌شود
```

**نتیجه:** کلاینت هیچ‌وقت به سوکتی که هنوز ساخته نشده وصل نمی‌شود؛ حتی مهلتِ
تلاشِ دوباره هم مصرف نمی‌شود. این ترتیب با یک تست قفل شده
(«سوکت قبل از startOrReloadService گوش می‌دهد»).

مسیرِ سوکت دو طرف یکی است و هیچ پورتی پیکربندی نشده (اگر
`CommandServerListenPort` صفر نباشد، هر دو طرف به TCP روی `127.0.0.1`
سوئیچ می‌کنند و نیاز به `protect()` پیدا می‌شود — ما این کار را نکرده‌ایم،
که درست است):

| طرف | مسیر |
|---|---|
| سرور (`command_server.go`) | `filepath.Join(sBasePath, "command.sock")` |
| کلاینت (`command_client.go`) | `filepath.Join(sBasePath, "command.sock")` |
| ما (`LibboxSetup`) | `basePath = context.filesDir.path` |

---

## ۲. اگر دیر وصل شویم چه می‌شود؟ — ۱۰ تلاش، حدود ۳/۲ ثانیه

`experimental/libbox/command_client.go`:

```go
const (
	commandClientDialAttempts  = 10
	commandClientDialBaseDelay = 100 * time.Millisecond
	commandClientDialStepDelay = 50 * time.Millisecond
)
```

`NewCommandClient` کلاینت را `standalone=false` می‌سازد و برای چنین کلاینتی
`dialWithRetry` با `WaitForReady(true)` تلاش می‌کند (مهلتِ هر تلاش همان تأخیرِ
همان تلاش است: ۱۰۰ + ۱۵۰ + … + ۵۵۰ میلی‌ثانیه ≈ ۳/۲ ثانیه در مجموع).

ما از `Libbox.newCommandClient(...)` استفاده می‌کنیم (نگاشتِ gobind از
`NewCommandClient`)، **نه** `NewStandaloneCommandClient` که فقط یک تلاشِ
fail-fast دارد و برای رابطی که خودش مالکِ چرخه‌ی حیاتِ سرویس نیست مناسب است.

> نکته‌ی فرعی: چون `CoreCommandClient.start()` بعد از `startOrReloadService`
> صدا زده می‌شود، این تلاشِ دوباره در عمل حتی لازم نیست — سوکت از قبل گوش
> می‌دهد. شکستِ اتصال هم کشنده نیست: `CoreCommandClient.start()` استثنا را
> می‌گیرد و فقط یک لاگ می‌نویسد (لاگ، آمار، گروه‌ها و اتصال‌ها را نخواهیم داشت).

---

## ۳. باگ‌هایی که فقط با کامپایل دیده می‌شوند

برای اینکه این‌ها اصلاً دیده شوند، یک دروازه‌ی کامپایل ساخته‌ایم:
`tool/check_android.sh` — اندروید SDK و kotlinc را می‌آورد، استابِ libbox را
(بخش ۳.۲) می‌سازد و کلِ `android/app/src/main/kotlin` را کامپایل می‌کند.

```
$ ./tool/check_android.sh
  تعداد خطاها: ۰
```

**۱۰ باگ واقعی** تا امروز با همین دروازه بیرون کشیده شده — یعنی لایه‌ی
اندروید پیش از این، نه‌تنها اجرا نشده بود، که حتی **کامپایل هم نمی‌شد**.

کدِ ما تا پیش از این با هیچ AAR ی کامپایل نشده بود (نداشتیمش)، برای همین این
سه تا زنده مانده بودند. همه اصلاح شدند و تست‌شان هم نوشته شده:

| # | اشتباه | حقیقتِ مستند | وضعیت |
|---|---|---|---|
| ۱ | `class StringArray(...) : StringIterator()` | gobind اینترفیسِ Go را به **`public interface`** جاوا تبدیل می‌کند (`bind/genjava.go` → `g.Printf("public interface %s", …)`)؛ اینترفیس سازنده ندارد | اصلاح شد |
| ۲ | `StringIterator` فقط `next`/`hasNext` پیاده شده بود | در ۱.۱۴.۲ سه متد دارد: `Len() int32`, `HasNext() bool`, `Next() string` (`experimental/libbox/iterator.go`). نبودِ `len()` یعنی «abstract member not implemented» | `len()` اضافه شد؛ ورودی حالا متریالیزه می‌شود تا اندازه معلوم باشد |
| ۳ | `override fun checkPlatformShell(): Boolean` | در Go امضا `CheckPlatformShell() error` است و خروجیِ `error` در gobind به `void` تبدیل می‌شود (`genFuncSignature`: یک خروجی از نوع error ⇒ `ret = "void"`). پس امضای جاوا `void` است | به `Unit` تغییر کرد |

### ۳.۱ هفت باگِ دیگر (از جنسِ کامپایل، نه از جنسِ libbox)

این‌ها ربطی به قراردادِ libbox ندارند و هر کامپایلرِ کاتلینی آن‌ها را می‌گرفت؛
فقط هیچ‌وقت کامپایلر اجرا نشده بود:

| # | کدِ قبلی | مشکل | اصلاح |
|---|---|---|---|
| ۴ | `VpnService.Builder(service)` | `VpnService.Builder` کلاسِ **درونیِ غیراستاتیک** است (`VpnService$Builder` فیلدِ `this$0` دارد)؛ در کاتلین باید با نمونه ساخته شود | `service.Builder()` |
| ۵ | `HandlerThread(...).apply { it.start() }` | `apply` پارامتر ندارد؛ `it` وجود ندارد (و توضیحِ کد هم برعکس بود) | `apply { start() }` |
| ۶ | `registerBestMatchingNetworkCallback(..., callbackHandler)` | `callbackHandler` از نوع `Handler?` است و این API غیر‌تهی می‌خواهد | گرفتنِ مقدارِ محلی و برگشتن اگر تهی است |
| ۷ | `options.httpProxyBypassDomain.toList()` | `StringIterator` ی libbox یک `Iterable` ی جاوا نیست، پس `toList()` ندارد | پیمایشِ دستی در یک `ArrayList` |
| ۸ | `override fun triggerNativeCrash(): Boolean = false` | Go: `TriggerNativeCrash() error` ⇒ امضای جاوا `void` | بدون نوعِ خروجی |
| ۹ | `pfd.file?.name` در `TunVpnService` | `ParcelFileDescriptor` چنین ویژگی‌ای ندارد و اندروید نامِ اینترفیس را نمی‌دهد | ثابتِ `tun0` (همان مقدارِ پیش‌فرضِ سمتِ دارت) |
| ۱۰ | `builder.excludeRoute(address, prefix)` | برعکسِ `addRoute`، این متد فقط یک `IpPrefix` می‌گیرد | ساختِ `IpPrefix` از آدرس و طولِ پیشوند |

نکته‌ی تاریخی: در نسخه‌های قدیمی‌ترِ libbox اینترفیس فقط `Len` و `Next` داشت و
پایانِ پیمایش با `nil` مشخص می‌شد (به‌همین دلیل در کدِ خودمان از
`iterator.next() ?: break` استفاده کرده‌ایم که همچنان درست است). در ۱.۱۴.۲
`HasNext` **اضافه** شده، نه جایگزین؛ پس هر سه متد باید باشند.

---

### ۳.۲ استابِ libbox — چرا و چگونه

چون `libbox.aar` نداریم، `tool/libbox_stub/` همان چیزی را تولید می‌کند که
gobind از سورسِ Go می‌سازد: **۴۴ کلاس/اینترفیس جاوا**. چرا جاوا و نه کاتلین؟
چون فقط نوع‌های جاوا در کاتلین «پلتفرم‌تایپ» (`String!`) می‌سازند — یعنی هم
`x.foo()` روی آن‌ها مجاز است و هم override با نسخه‌ی تهی‌پذیر. استابِ کاتلین
نمی‌توانست این را نشان بدهد و خطایِ کاذب می‌داد.

این استاب‌ها فقط برای کامپایل‌اند و وارد APK نمی‌شوند (بیرون از `android/`).
اگر نسخه‌ی sing-box را بالا بردید، آن‌ها را هم به‌روز کنید — وگرنه دروازه به‌جای
واقعیت، استاب را تأیید می‌کند.

## ۴. تطبیقِ متد به متد (همه درست از آب درآمد)

هر سه اینترفیس سطر‌به‌سطر مقایسه شدند. تعداد و نام‌ها دقیقاً یکی است:

| اینترفیسِ Go | پیاده‌سازیِ ما | تعداد | نتیجه |
|---|---|---|---|
| `CommandClientHandler` (`command_client.go`) | `CoreCommandClient` | ۱۱ | ✅ |
| `CommandServerHandler` (`command_server.go`) | `LibboxVpnService` | ۷ | ✅ |
| `PlatformInterface` (`platform.go`) | `LibboxPlatformInterface` | ۲۷ | ✅ |

شماره‌ی فرمان‌ها هم با `experimental/libbox/command.go` یکی است:

```go
const ( CommandLog int32 = iota; CommandStatus; CommandGroup;
        CommandClashMode; CommandConnections; CommandOutbounds )
```

ما `Log=0`, `Status=1`, `Group=2`, `Connections=4` را subscribe می‌کنیم و
`ClashMode` و `Outbounds` را (عمداً) نه.

دیگر چیزهایی که تأیید شدند:

* **`SetupOptions`**: همه‌ی فیلدهایی که ست می‌کنیم (`basePath`, `workingPath`,
  `tempPath`, `fixAndroidStack`, `logMaxLines`, `debug`, `crashReportSource`)
  در ۱.۱۴.۲ وجود دارند (`experimental/libbox/setup.go`).
* **`OverrideOptions`**: فقط `AutoRedirect`, `IncludePackage`, `ExcludePackage`
  دارد؛ ما دوتای آخر را پر می‌کنیم.
* **`StatusMessage`**: `Uplink/Downlink/UplinkTotal/DownlinkTotal` درست‌اند؛
  `StatusInterval` مستقیماً `time.Duration` می‌شود، پس مقدارش باید **نانوثانیه**
  باشد (`1_000_000_000L`).
* **`OutboundGroup` / `OutboundGroupItem`**: `GetItems()` و
  `getURLTestDelay()/getURLTestTime()` — gobind نامِ فیلدِ Go را دست‌نخورده
  می‌گذارد، پس `URL` با حروف بزرگ است.
* **`Connections`**: `Libbox.newConnections()` وجود دارد
  (`func NewConnections() *Connections`) و متدهای `ApplyEvents`, `SortByDate`,
  `Iterator` با همین نام‌ها در جاوا هستند. فیلدهایی که در
  `snapshotConnections()` می‌خوانیم، همه در ساختارِ `Connection` هستند.
* **`TunOptions`** یک اینترفیس است (`GetMTU`, `GetInet4Address`, …) و دسترسیِ
  ملکیِ کاتلین (`options.mtu`) به `getMTU()` وصل می‌شود — درست است.

---

## ۵. چه چیزی هنوز تأیید نشده

این سند «هماهنگیِ دو طرف» را ثابت می‌کند، نه رفتارِ زمانِ اجرا را. مواردِ زیر
**نیاز به دستگاه** دارند و هیچ تضمینی برایشان نداریم:

1. **`openTun` روی دستگاه واقعی.** آدرس‌ها و مسیرها از `TunOptions` خوانده
   می‌شوند و به `VpnService.Builder` داده می‌شوند، ولی این که اندرویدِ نسخه‌ی
   مختلف همان‌ها را بپذیرد، فقط با اجرا معلوم می‌شود.
2. **`protect()` و حلقه.** `usePlatformAutoDetectInterfaceControl()` را `true`
   برگردانده‌ایم تا libbox برای هر سوکت `protect()` را صدا بزند. درستیِ این
   تصمیم روی دستگاه باید دید.
3. **`serviceReload()` از تردِ Go وقتی خودِ Go منتظر جواب است.**
   پیاده‌سازیِ ما `runBlocking { reload(lastConfig) }` است و این فراخوانی از
   درونِ گوروتینِ gRPC می‌آید. روی کاغذ بن‌بست نیست (فراخوانیِ بازگشتی به جاوا
   روی همان ترد انجام می‌شود)، ولی این دقیقاً همان چیزی است که فقط اجرا
   نشانش می‌دهد.
4. **نشتِ fd در `stopLibbox`**: بستنِ `fileDescriptor` انجام می‌شود، ولی
   اینکه fd ی که libbox گرفته در زمانِ `closeService` آزاد شود یا نه را نخوانده‌ایم.
5. **خودِ `libbox.aar`**: تا ساخته نشود (`scripts/build_libbox.sh`)، هیچ‌کدام
   از این‌ها کامپایل نمی‌شود و این سند هم فقط روی کاغذ است.

---

## ۶. اگر نسخه‌ی sing-box را بالا ببرید

پرونده‌هایی که باید دوباره بخوانید (همان‌هایی که این سند از آن‌ها نقل کرده):

```
experimental/libbox/command.go             شماره‌ی فرمان‌ها
experimental/libbox/command_client.go      CommandClientHandler + تلاشِ اتصال
experimental/libbox/command_server.go      CommandServerHandler + ساختِ سوکت
experimental/libbox/command_types.go       StatusMessage / گروه‌ها / اتصال‌ها
experimental/libbox/iterator.go            StringIterator (تعدادِ متدها!)
experimental/libbox/platform.go            PlatformInterface + WIFIState و …
experimental/libbox/setup.go               SetupOptions
experimental/libbox/tun.go                 TunOptions
```

بعد از تغییرِ نسخه، `flutter test test/libbox_contract_test.dart` اولین چیزی
است که باید اجرا شود؛ اگر مجموعه‌ی متدها عوض شده باشد، همان‌جا خطا می‌دهد.
