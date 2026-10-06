package com.overx.overx

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.Libbox

/**
 * نقطه‌ی ورود اندروید.
 *
 * دو کانال با لایه‌ی دارت دارد:
 *  - `com.overx/core`   → قابلیت‌های عمومی پلتفرم (مجوز VPN، TUN، اجرا در شروع)
 *  - `com.overx/libbox` → اجرای sing-box به صورت کتابخانه‌ی بومی
 *
 * متدها در `lib/core/platform/android_bridge.dart` و
 * `lib/core/platform/libbox.dart` تعریف شده‌اند.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_CORE = "com.overx/core"
        private const val REQUEST_VPN = 1001

        /** شناسه‌ی موتوری که در حافظه نگه می‌داریم. */
        const val ENGINE_ID = "overx_main"

        @Volatile
        private var channelsAttached = false
    }

    private var pendingPrepareResult: MethodChannel.Result? = null

    /**
     * موتور را کش می‌کنیم تا پس از بسته‌شدن اکتیویتی هم زنده بماند.
     *
     * اهمیت: سرویسِ VPN ممکن است زمانی پیام بفرستد که اکتیویتی مرده است.
     * با یک موتورِ کش‌شده، `BinaryMessenger` همچنان معتبر می‌ماند و
     * لاگ‌ها/وضعیت‌ها به دارت می‌رسند.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(ENGINE_ID) ?: FlutterEngine(context).also {
            FlutterEngineCache.getInstance().put(ENGINE_ID, it)
        }

    /** موتورِ کش‌شده نباید با نابودیِ اکتیویتی از بین برود. */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    /** پلاگین‌ها و کانال‌ها را برای موتورِ کش‌شده نگه می‌داریم. */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // عمداً super را صدا نمی‌زنیم: موتور کش‌شده باید دست‌نخورده بماند
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // فقط یک بار — وگرنه با هر اتصالِ مجددِ اکتیویتی هندلرها تکرار می‌شوند
        if (channelsAttached) return
        channelsAttached = true
        LibboxChannel.attach(flutterEngine.dartExecutor.binaryMessenger)

        // ---------------------------------------------------- قابلیت‌های عمومی
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CORE)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepareVpn" -> prepareVpn(result)
                    "acquireTun" -> acquireTun(call, result)
                    "releaseTun" -> {
                        TunVpnService.stop(this)
                        result.success(true)
                    }
                    "nativeLibraryDir" ->
                        result.success(applicationInfo.nativeLibraryDir)
                    "setAutoStart" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        BootReceiver.setEnabled(this, enable)
                        result.success(true)
                    }
                    "isAutoStartEnabled" ->
                        result.success(BootReceiver.isEnabled(this))
                    "listPackages" -> {
                        val includeSystem =
                            call.argument<Boolean>("includeSystem") ?: false
                        // فهرست‌کردن می‌تواند روی دستگاه‌های شلوغ کند باشد
                        Thread {
                            val apps = AppLister.list(this, includeSystem)
                            runOnUiThread { result.success(apps) }
                        }.start()
                    }
                    "installBinaries" -> result.success(
                        BinaryInstaller.install(this)
                    )
                    "appIcon" -> {
                        // آرگومان‌های کانال در واقع Any هستند؛ صریح تبدیل می‌کنیم
                        val pkg = call.argument<String>("packageName")?.toString()
                        val size = call.argument<Int>("size")?.toString()
                            ?.toIntOrNull() ?: 64
                        if (pkg == null) {
                            result.error("bad_args", "packageName is required", null)
                        } else {
                            // خواندنِ آیکون از PackageManager I/O دارد
                            Thread {
                                val bytes = AppLister.icon(this, pkg, size)
                                runOnUiThread { result.success(bytes) }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // -------------------------------------------------------------- libbox
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LibboxChannel.NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> {
                        // آرگومان را Any? می‌گیریم: بدون android.jar نوعِ
                        // MethodChannel.Result حل نمی‌شود و پارامترِ جنریکِ
                        // success با اولین فراخوانی قفل می‌گردد.
                        val payload: Any? = isLibboxAvailable()
                        result.success(payload)
                    }
                    "start" -> startLibbox(call, result)
                    "stop" -> {
                        stopLibbox()
                        val payload: Any? = null
                        result.success(payload)
                    }

                    // -------------------------------- گروه‌ها و اتصال‌ها
                    "getGroups" -> getGroups(result)
                    "getConnections" -> getConnections(result)
                    "selectOutbound" -> selectOutbound(call, result)
                    "urlTest" -> urlTestOutbound(call, result)
                    "closeConnection" -> closeConnection(call, result)
                    "closeConnections" -> closeConnections(result)
                    else -> result.notImplemented()
                }
            }

    }

    // ------------------------------------------------------------------ libbox

    /**
     * آیا کتابخانه‌ی بومی libbox همراه برنامه است؟
     * اگر خیر، فراخوانیِ [Libbox.version] با خطای پیوند مواجه می‌شود.
     */
    private fun isLibboxAvailable(): Boolean = try {
        LibboxSetup.ensure(this)
        Libbox.version().isNotBlank()
    } catch (e: Throwable) {
        android.util.Log.w("MainActivity", "libbox unavailable: ${e.message}")
        false
    }

    /**
     * عکسِ وضعیتِ گروه‌های خروجی.
     *
     * مدلِ سمت دارت: `OutboundGroup` در `core/models/network.dart`.
     * آرگومان‌ها را در متغیلی از نوع `Any?` می‌گذاریم چون مقدارِ برگشتی بسته
     * به این‌که هسته چه فرستاده باشد فرق می‌کند.
     */
    private fun getGroups(result: MethodChannel.Result) {
        val payload: Any? = CoreCommandClient.snapshotGroups()
        result.success(payload)
    }

    private fun getConnections(result: MethodChannel.Result) {
        val payload: Any? = CoreCommandClient.snapshotConnections()
        result.success(payload)
    }

    private fun selectOutbound(call: MethodCall, result: MethodChannel.Result) {
        // آرگومان‌های کانال در واقع Any هستند؛ صریح تبدیل می‌کنیم
        val group = call.argument<String>("groupTag")?.toString()
        val outbound = call.argument<String>("outboundTag")?.toString()
        if (group == null || outbound == null) {
            result.error("bad_args", "groupTag and outboundTag are required", null)
            return
        }
        val payload: Any? = CoreCommandClient.selectOutbound(group, outbound)
        result.success(payload)
    }

    private fun urlTestOutbound(call: MethodCall, result: MethodChannel.Result) {
        val tag = call.argument<String>("outboundTag")?.toString()
        if (tag == null) {
            result.error("bad_args", "outboundTag is required", null)
            return
        }
        val payload: Any? = CoreCommandClient.urlTest(tag)
        result.success(payload)
    }

    private fun closeConnection(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")?.toString()
        if (id == null) {
            result.error("bad_args", "id is required", null)
            return
        }
        val payload: Any? = CoreCommandClient.closeConnection(id)
        result.success(payload)
    }

    private fun closeConnections(result: MethodChannel.Result) {
        val payload: Any? = CoreCommandClient.closeConnections()
        result.success(payload)
    }

    private fun startLibbox(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>("config")
        if (config.isNullOrBlank()) {
            result.error("EMPTY_CONFIG", "no configuration supplied", null)
            return
        }
        val include = call.argument<List<String>>("includePackages") ?: emptyList()
        val exclude = call.argument<List<String>>("excludePackages") ?: emptyList()

        // مجوز VPN لازم است؛ otherwise openTun با خطا روبه‌رو می‌شود
        val prepareIntent = android.net.VpnService.prepare(this)
        if (prepareIntent != null) {
            result.error("VPN_PERMISSION", "vpn permission not granted", null)
            return
        }

        val intent = Intent(this, LibboxVpnService::class.java).apply {
            putExtra(LibboxVpnService.EXTRA_CONFIG, config)
            putStringArrayListExtra(LibboxVpnService.EXTRA_INCLUDE, ArrayList(include))
            putStringArrayListExtra(LibboxVpnService.EXTRA_EXCLUDE, ArrayList(exclude))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(true)
    }

    private fun stopLibbox() {
        val intent = Intent(this, LibboxVpnService::class.java).apply {
            action = LibboxVpnService.ACTION_STOP
        }
        runCatching { startService(intent) }
    }

    // --------------------------------------------------------- TUN خام (Xray)

    /**
     * گرفتن مجوز VPN از کاربر.
     * اگر قبلاً داده شده، مستقیماً true برمی‌گرداند.
     */
    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = android.net.VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingPrepareResult = result
        startActivityForResult(intent, REQUEST_VPN)
    }

    /**
     * ساخت اینترفیس TUN و برگرداندن fd به دارت.
     *
     * خروجی: mapOf("fd" to Int, "mtu" to Int, "interfaceName" to String)
     */
    private fun acquireTun(call: MethodCall, result: MethodChannel.Result) {
        val mtu = call.argument<Int>("mtu") ?: 9000

        val intent = Intent(this, TunVpnService::class.java).apply {
            action = TunVpnService.ACTION_START
            putExtra(TunVpnService.EXTRA_MTU, mtu)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

        // منتظر می‌مانیم تا سرویس fd را بسازد (معمولاً چند ده میلی‌ثانیه)
        TunVpnService.awaitTun(timeoutMs = 5000) { handle ->
            runOnUiThread {
                if (handle == null) {
                    result.error("TUN_FAILED", "could not create TUN interface", null)
                } else {
                    result.success(
                        mapOf(
                            "fd" to handle.fd,
                            "mtu" to handle.mtu,
                            "interfaceName" to handle.interfaceName,
                        )
                    )
                }
            }
        }
    }

    @Deprecated("Legacy Activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN) {
            val res = pendingPrepareResult
            pendingPrepareResult = null
            res?.success(resultCode == Activity.RESULT_OK)
        }
    }
}
