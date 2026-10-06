package com.overx.overx

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.SystemProxyStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.io.File

/**
 * سرویسی که هسته‌ی sing-box را از طریق **libbox** درون فرآیند خودش اجرا می‌کند.
 *
 * تفاوت این مسیر با حالت عادی:
 *  - ما اینترفیس TUN را پیشاپیش نمی‌سازیم؛ libbox هنگام نیاز متد
 *    [LibboxPlatformInterface.openTun] را صدا می‌زند و fd را تحویل می‌گیرد.
 *  - هیچ فرآیند جداگانه‌ای spawn نمی‌شود؛ هسته داخل همین سرویس است.
 *
 * برای Xray این سرویس استفاده نمی‌شود (آن یکی fd را از متغیر محیطی
 * `XRAY_TUN_FD` می‌گیرد و با `TunVpnService` کار می‌کند).
 */
class LibboxVpnService : android.net.VpnService(), CommandServerHandler {

    companion object {
        private const val TAG = "LibboxVpnService"
        private const val NOTIFICATION_ID = 2
        const val CHANNEL_ID = "overx_libbox"
        const val ACTION_STOP = "com.overx.overx.LIBBOX_STOP"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_INCLUDE = "include_packages"
        const val EXTRA_EXCLUDE = "exclude_packages"

        /** کمینه‌ی فاصله‌ی بین دو به‌روزرسانیِ اعلان (میلی‌ثانیه). */
        private const val NOTIFICATION_MIN_INTERVAL = 1000L

        @Volatile
        var running: Boolean = false
            private set
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val binder = LocalBinder()

    private var commandServer: CommandServer? = null
    private var platformInterface: LibboxPlatformInterface? = null

    /** به‌روزرسانیِ اعلان فقط از تردِ اصلی مجاز است. */
    private val mainHandler = Handler(Looper.getMainLooper())

    /** اعلان را بیش از یک بار در ثانیه به‌روز نمی‌کنیم. */
    @Volatile
    private var lastNotificationAt = 0L

    /** آخرین آماری که از هسته رسیده — برای اعلان. */
    private val trafficListener = CoreCommandClient.TrafficListener {
            uplink, downlink, uplinkTotal, downlinkTotal ->
        onTraffic(uplink, downlink, uplinkTotal, downlinkTotal)
    }

    /** fd اینترفیس — توسط [LibboxPlatformInterface.openTun] پر می‌شود. */
    var fileDescriptor: ParcelFileDescriptor? = null

    /** نام جلسه‌ای که در اعلان و لاگ اندروید دیده می‌شود. */
    val sessionName: String get() = "OVERX (sing-box)"

    @Volatile
    private var lastConfig: String = ""

    @Volatile
    private var lastIncludePackages: List<String> = emptyList()

    @Volatile
    private var lastExcludePackages: List<String> = emptyList()

    inner class LocalBinder : Binder() {
        fun getService(): LibboxVpnService = this@LibboxVpnService
    }

    override fun onCreate() {
        super.onCreate()
        LibboxSetup.ensure(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopLibbox()
                return START_NOT_STICKY
            }
        }

        val config = intent?.getStringExtra(EXTRA_CONFIG)
        if (config.isNullOrBlank()) {
            Log.w(TAG, "no config supplied; stopping")
            stopSelf()
            return START_NOT_STICKY
        }
        lastConfig = config
        lastIncludePackages = intent.getStringArrayListExtra(EXTRA_INCLUDE) ?: emptyList()
        lastExcludePackages = intent.getStringArrayListExtra(EXTRA_EXCLUDE) ?: emptyList()

        startForeground(NOTIFICATION_ID, buildNotification(getString(R.string.libbox_starting)))

        scope.launch {
            try {
                startLibbox(config)
            } catch (e: Throwable) {
                Log.e(TAG, "failed to start libbox", e)
                LibboxChannel.emitStatus("error", e.message)
                stopSelf()
            }
        }
        return START_STICKY
    }

    // ------------------------------------------------------------- چرخه‌ی حیات

    private fun startLibbox(config: String) {
        if (commandServer != null) {
            // قبلاً اجرا شده — فقط کانفیگ را بارگذاریِ دوباره می‌کنیم
            reload(config)
            return
        }

        LibboxChannel.emitStatus("starting")
        LibboxChannel.emitLog("libbox: starting sing-box in-process")

        val platformInterface = LibboxPlatformInterface(this, this)
        this.platformInterface = platformInterface

        val server = CommandServer(this, platformInterface)
        server.start()
        commandServer = server

        server.startOrReloadService(config, buildOverrideOptions())
        running = true
        LibboxChannel.emitStatus("started")
        LibboxChannel.emitLog("libbox: sing-box started")
        updateNotification(getString(R.string.libbox_running))

        // لاگِ زنده و آمارِ ترافیک — بعد از بالا آمدنِ هسته وصل می‌شویم
        CoreCommandClient.trafficListener = trafficListener
        CoreCommandClient.start()
    }

    private fun reload(config: String) {
        val server = commandServer ?: return
        LibboxChannel.emitLog("libbox: reloading configuration")
        server.startOrReloadService(config, buildOverrideOptions())
    }

    private fun buildOverrideOptions(): OverrideOptions = OverrideOptions().apply {
        // نکته: برنامه‌ی خودمان را در هر دو حالت لحاظ می‌کنیم.
        //  - حالت include: باید خودمان هم در فهرست باشیم، وگرنه ترافیکمان
        //    (مثلاً درخواست‌های بروزرسانی پروفایل) از تونل بیرون می‌ماند.
        //    سوکت‌هایمان با autoDetectInterfaceControl → protect() محافظت می‌شوند
        //    پس حلقه ایجاد نمی‌شود.
        //  - حالت exclude: نباید خودمان را حذف کنیم، چون آن‌وقت ترافیکمان
        //    مستقیم می‌رود و اتصالِ کنترلی قطع می‌شود.
        if (lastIncludePackages.isNotEmpty()) {
            includePackage = LibboxPlatformInterface.StringArray(
                (lastIncludePackages + packageName).distinct().iterator()
            )
        }
        if (lastExcludePackages.isNotEmpty()) {
            excludePackage = LibboxPlatformInterface.StringArray(
                (lastExcludePackages - packageName).distinct().iterator()
            )
        }
    }

    private fun stopLibbox() {
        LibboxChannel.emitStatus("stopping")
        running = false
        CoreCommandClient.stop()
        lastNotificationAt = 0L
        try {
            commandServer?.closeService()
        } catch (e: Throwable) {
            Log.w(TAG, "closeService", e)
        }
        try {
            commandServer?.close()
        } catch (e: Throwable) {
            Log.w(TAG, "close", e)
        }
        commandServer = null
        platformInterface = null
        try {
            fileDescriptor?.close()
        } catch (e: Throwable) {
            Log.w(TAG, "close tun fd", e)
        }
        fileDescriptor = null
        LibboxChannel.emitStatus("stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (running) stopLibbox()
        scope.cancel()
        super.onDestroy()
    }

    /** کاربر VPN را از تنظیمات سیستم قطع کرده. */
    override fun onRevoke() {
        Log.w(TAG, "vpn revoked by the system")
        stopLibbox()
        super.onRevoke()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return if (intent?.action == android.net.VpnService.SERVICE_INTERFACE ||
            intent?.action == ACTION_STOP
        ) {
            super.onBind(intent)
        } else {
            binder
        }
    }

    // -------------------------------------------- پیاده‌سازی CommandServerHandler

    override fun serviceStop() {
        stopLibbox()
    }

    override fun serviceReload() {
        runBlocking { reload(lastConfig) }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus? =
        SystemProxyStatus().apply {
            available = false
            enabled = false
        }

    override fun setSystemProxyEnabled(p0: Boolean) {
        serviceReload()
    }

    /**
     * Go: `TriggerNativeCrash() error` ⇒ امضای جاوا `void` است (خروجیِ تنهای
     * error در gobind به `void` + throws ترجمه می‌شود).
     */
    override fun triggerNativeCrash() {
        // عمداً کاری نمی‌کند: خرابیِ عمدی فقط در ساختِ دیباگ معنا دارد.
    }

    override fun writeDebugMessage(message: String?) {
        if (!message.isNullOrBlank()) LibboxChannel.emitLog("debug: $message")
    }

    override fun connectSSHAgent(): Int = -1

    // ------------------------------------------------------------ اعلان

    fun sendLibboxNotification(notification: Notification) {
        val channelId = "notification-${notification.typeID}"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(channelId, notification.typeName, NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val builder = NotificationCompat.Builder(this, channelId)
            .setContentTitle(notification.title)
            .setContentText(notification.body)
            // نشانه‌ی تک‌رنگِ برنامه — آیکنِ لانچر برای نوارِ وضعیت مناسب نیست
            .setSmallIcon(R.drawable.ic_stat_overx)
            .setAutoCancel(true)
        if (!notification.subtitle.isNullOrBlank()) builder.setContentInfo(notification.subtitle)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(notification.identifier, notification.typeID, builder.build())
    }

    fun cancelLibboxNotification(identifier: String, typeID: Int) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(identifier, typeID)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.libbox_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
    }

    private fun buildNotification(text: String) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("OVERX")
            .setContentText(text)
            // نشانه‌ی تک‌رنگِ برنامه — آیکنِ لانچر برای نوارِ وضعیت مناسب نیست
            .setSmallIcon(R.drawable.ic_stat_overx)
            .setOngoing(true)
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            ).build()

    private fun updateNotification(text: String) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification(text))
    }

    /**
     * آمارِ تازه از هسته رسیده (از تردِ Go صدا زده می‌شود).
     *
     * [uplink] و [downlink] دلتای یک‌ثانیه‌ای‌اند، پس عملاً همان بایت‌برثانیه.
     */
    private fun onTraffic(
        uplink: Long,
        downlink: Long,
        uplinkTotal: Long,
        downlinkTotal: Long,
    ) {
        // از ساعتِ دیواری استفاده می‌کنیم (نه SystemClock): برای یک گامِ
        // یک‌ثانیه‌ای تفاوتی ندارد و وابسته به android.jar هم نیست.
        val now = System.currentTimeMillis()
        if (now - lastNotificationAt < NOTIFICATION_MIN_INTERVAL) return
        lastNotificationAt = now

        val text = "↑ ${TrafficFormat.speed(uplink)}   ↓ ${TrafficFormat.speed(downlink)}" +
            "   ·   ${TrafficFormat.bytes(uplinkTotal + downlinkTotal)}"
        mainHandler.post { updateNotification(text) }
    }

}

/**
 * تنظیمِ اولیه‌ی libbox — فقط یک بار انجام می‌شود.
 */
object LibboxSetup {

    @Volatile
    private var done = false

    fun ensure(context: Context) {
        if (done) return
        synchronized(this) {
            if (done) return
            val baseDir = context.filesDir
            val workingDir = context.getExternalFilesDir(null) ?: baseDir
            val tempDir = context.cacheDir
            workingDir.mkdirs()
            Libbox.setup(
                SetupOptions().apply {
                    basePath = baseDir.path
                    workingPath = workingDir.path
                    tempPath = tempDir.path
                    fixAndroidStack = true
                    logMaxLines = 3000
                    debug = false
                    crashReportSource = "OVERX"
                }
            )
            try {
                Libbox.setLocale(java.util.Locale.getDefault().toLanguageTag())
            } catch (e: Throwable) {
                Log.w("LibboxSetup", "setLocale", e)
            }
            done = true
            Log.i("LibboxSetup", "libbox ${Libbox.version()} ready (base=${baseDir.path})")
        }
    }

    private fun File.ensureDir(): File = apply { mkdirs() }
}
