package com.overx.overx

import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * کانال ارتباطی بین سرویس libbox و لایه‌ی Dart.
 *
 * `MethodChannel` به یک `BinaryMessenger` نیاز دارد که معمولاً از موتور فلاترِ
 * اکتیویتی می‌آید. سرویس ممکن است زمانی پیام بفرستد که اکتیویتی مرده است؛
 * در این صورت پیام‌ها بی‌صدا دور ریخته می‌شوند (برای لاگ مشکلی نیست).
 *
 * ارتقای بعدی: استفاده از `FlutterEngineCache` برای داشتنِ یک موتور پس‌زمینه
 * که حتی پس از بسته‌شدن اکتیویتی هم زنده بماند.
 */
object LibboxChannel {

    private const val TAG = "LibboxChannel"
    const val NAME = "com.overx/libbox"

    @Volatile
    private var channel: MethodChannel? = null

    /** از `MainActivity.configureFlutterEngine` صدا زده می‌شود. */
    @JvmStatic
    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, NAME)
        Log.d(TAG, "attached")
    }

    @JvmStatic
    fun detach() {
        channel = null
    }

    /**
     * ارسال یک خطِ لاگ به Dart.
     *
     * برای سازگاری با نسخه‌های قدیمی، پیامِ ساده به صورت رشته فرستاده می‌شود
     * و Dart آن را در سطحِ info می‌گیرد.
     */
    @JvmStatic
    fun emitLog(message: String) {
        send("onLog", message)
    }

    /**
     * ارسال یک خطِ لاگ **همراه با سطح**.
     *
     * [level] همان `log.Level` ی sing-box است (نگاه کن به
     * `log/level.go`): `panic=0`، `fatal=1`، `error=2`، `warn=3`،
     * `info=4`، `debug=5`، `trace=6`.
     */
    @JvmStatic
    fun emitLogLine(level: Int, message: String) {
        send(
            "onLog",
            hashMapOf<String, Any?>("level" to level, "message" to message),
        )
    }

    /** هسته لاگ‌هایش را پاک کرده (بعد از بارگذاریِ دوباره‌ی کانفیگ). */
    @JvmStatic
    fun emitLogsCleared() {
        send("onLogsCleared", null)
    }

    /** ارسال تغییر وضعیت به Dart. */
    @JvmStatic
    fun emitStatus(status: String, error: String? = null) {
        send(
            "onStatus",
            hashMapOf<String, Any?>("status" to status, "error" to error),
        )
    }

    /**
     * فرستادنِ یک فراخوانی به Dart.
     *
     * اگر اکتیویتی مرده باشد کانال null است و پیام بی‌صدا دور ریخته می‌شود؛
     * خطاهای واقعی را هم با بلعیدن به سقوطِ سرویس تبدیل نمی‌کنیم.
     */
    private fun send(method: String, arguments: Any?) {
        try {
            channel?.invokeMethod(method, arguments)
        } catch (e: Throwable) {
            Log.w(TAG, "send $method failed", e)
            channel = null
        }
    }
}
