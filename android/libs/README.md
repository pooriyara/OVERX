# خروجی‌های libbox

`scripts/build_libbox.sh` فایل `libbox.aar` را اینجا می‌گذارد.
اگر این فایل نباشد، ساختِ اندروید شکست می‌خورد (چون
`LibboxVpnService` و `LibboxPlatformInterface` به کلاس‌های
`io.nekohasekai.libbox.*` نیاز دارند).

برای غیرفعال کردن موقت: فایل‌های
`LibboxVpnService.kt` و `LibboxPlatformInterface.kt` را حذف و
بخش libbox از `MainActivity` را بردارید.
