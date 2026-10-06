# سازگاریِ کانفیگ با هسته‌های واقعی

این فایل فهرستِ تغییراتِ «شکننده» در sing-box/Xray است که مستقیماً روی
کانفیگی که OVERX تولید می‌کند اثر می‌گذارد، به همراهِ نگاشتِ قدیم→جدید.

**چرا این فایل وجود دارد؟** چون این اشتباهات در هیچ تستِ واحدی دیده نمی‌شوند:
تست فقط بررسی می‌کند که کلیدِ مورد انتظارِ خودمان سرجایش است. اینکه هسته‌ی
واقعی همان کلید را اصلاً می‌شناسد یا نه، فقط با اجرای خودش معلوم می‌شود —
برای همین `tool/validate_configs.sh` را داریم.

---

## چه شد که این فایل نوشته شد

تا پیش از این، کانفیگِ sing-box روی **sing-box 1.14.2 واقعی** کاملاً رد می‌شد:
`sing-box check` برای **هیچ‌کدام** از ۷ پروفایل موفق نبود. یعنی برنامه
عملاً نمی‌توانست هسته را بالا بیاورد، در حالی که ۱۴۸ تست سبز بود.

پنج اشتباه، یکی‌یکی (هر کدام فقط بعد از رفعِ قبلی آشکار می‌شد):

| # | پیامِ هسته | علت | اصلاح |
|---|---|---|---|
| ۱ | `legacy DNS fakeip options are deprecated in 1.12.0 and removed in 1.14.0` | بلوکِ `dns.fakeip` | fakeip به یک **سرورِ DNS** تبدیل شد |
| ۲ | `dns.servers[2]: unknown transport type: block` | سرورِ DNS از نوعِ `block` حذف شد | قانون با `action: reject` |
| ۳ | `inbounds[1]: legacy inbound fields … removed in 1.13.0` | `sniff` روی inbound | قانونِ مسیریابی با `action: sniff` |
| ۴ | `outbounds[3]: dns outbound is deprecated … removed in 1.13.0` | outbound ویژه‌ی `dns` | حذف؛ `hijack-dns` کافی است |
| ۵ | `experimental.cache_file.store: unknown field` | کلیدِ `store` | `store_fakeip` |

دو موردِ دیگر هم در ادامه پیدا شد:

| # | پیام | اصلاح |
|---|---|---|
| ۶ | `dns rule[3]: rule-set not found: geosite-ir` | قانونِ DNS به rule-set ی ارجاع می‌داد که در `route.rule_set` **اعلان نشده بود** |
| ۷ | `missing route.default_domain_resolver … will be removed in 1.14.0` | افزودنِ `default_domain_resolver` |

و یک موردِ مربوط به Xray:

| # | پیام | اصلاح |
|---|---|---|
| ۸ | `REALITY only supports RAW, XHTTP and gRPC for now` | VLESS+Reality همراهِ ترانسپورتِ `ws` تولید می‌شد؛ به `tcp` برمی‌گردیم |

---

## نگاشتِ قدیم → جدید (sing-box)

### fakeip

```jsonc
// قدیمی (حذف در 1.14)
"dns": {
  "servers": [ ... ],
  "fakeip": { "enabled": true, "inet4_range": "198.18.0.0/15" }
}

// جدید
"dns": {
  "servers": [
    ...,
    { "tag": "dns-fakeip", "type": "fakeip",
      "inet4_range": "198.18.0.0/15", "inet6_range": "fc00::/18" }
  ],
  "rules": [
    ...,
    // سرورِ fakeip نمی‌تواند خودِ پیش‌فرض باشد
    { "query_type": ["A", "AAAA"], "action": "route", "server": "dns-fakeip" }
  ],
  "final": "dns-remote"
}
```

### sniff

```jsonc
// قدیمی (حذف در 1.13)
"inbounds": [{ "type": "mixed", "sniff": true, "sniff_override_destination": true }]

// جدید
"inbounds": [{ "type": "mixed", "tag": "mixed-in" }],
"route": { "rules": [{ "action": "sniff" }, ...] }
```

> `sniff_override_destination` در فرمتِ جدید معادلی ندارد؛ sniffing حالا
> همیشه دامنه را در اختیارِ مسیریابی می‌گذارد.

### outbound‌های ویژه

| قدیمی | جدید |
|---|---|
| `{"type":"block"}` + `"outbound":"block"` | `{"action":"reject"}` |
| `{"type":"dns"}` + `{"protocol":"dns","outbound":"dns"}` | `{"protocol":"dns","action":"hijack-dns"}` |

### سایر

- `dns.independent_cache` در 1.14 منسوخ است → حذف شود.
- `route.default_domain_resolver` باید تنظیم شود، وگرنه sing-box هشدار
  می‌دهد که `domain_resolver` در dial fields حذف خواهد شد.
- هر rule-set ی که در قانونِ DNS ارجاع می‌شود **باید** در `route.rule_set`
  هم اعلان شود، وگرنه startup با `rule-set not found` شکست می‌خورد.

---

## محدودیتِ Xray

**REALITY فقط با `raw` / `xhttp` / `grpc` کار می‌کند.** اگر پروفایلی
VLESS+Reality همراهِ WebSocket (یا http/h2/quic) باشد، Xray کانفیگ را رد
می‌کند. `XrayConfigBuilder` در این حالت به `tcp` برمی‌گردد تا کانفیگ بالا
بیاید — نه اینکه از کار بیفتد.

ترکیب‌های دیگر (TLS+WS و مانندش) دست‌نخورده می‌مانند و تست دارد.

---

## نسخه‌هایی که با آن‌ها اعتبارسنجی شده

| هسته | نسخه | وضعیت |
|---|---|---|
| sing-box | 1.14.2 | ۷/۷ (شاملِ TUN) |
| Xray-core | 26.3.27 | ۵/۵ (بدون TUN؛ TUN به root نیاز دارد) |

sing-box **1.15.0** یک تغییرِ دیگر دارد که هنوز اعمال نشده: گزینه‌ی `stack`
در inboundِ TUN منسوخ شده و در 1.17 حذف می‌شود. چون فعلاً روی 1.14 اعتبارسنجی
می‌کنیم، `stack: mixed` را نگه داشته‌ایم.

---

## اجرای دوباره

```bash
flutter test tool/emit_configs_test.dart
./tool/validate_configs.sh
```

اگر نسخه‌ی هسته را بالا بردید، `SINGBOX_VERSION` را هم تغییر دهید:

```bash
SINGBOX_VERSION=1.15.0 ./tool/validate_configs.sh
```
