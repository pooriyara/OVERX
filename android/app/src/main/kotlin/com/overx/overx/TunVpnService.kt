package com.overx.overx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * اینترفیس TUN برنامه.
 *
 * جریان کار:
 *   1. دارت → `acquireTun` روی MethodChannel
 *   2. این سرویس با `Builder()` یک اینترفیس TUN می‌سازد و fd آن را نگه می‌دارد
 *   3. fd را به دارت برمی‌گرداند
 *   4. دارت آن را در متغیر محیطی `XRAY_TUN_FD` به فرآیند هسته می‌دهد
 *      (برای sing-box به libbox یا tun2socks نیاز است — نگاه کن به docs/ANDROID_TUN.md)
 *   5. هنگام توقف، `releaseTun` سرویس را می‌بندد و fd بسته می‌شود
 */
class TunVpnService : VpnService() {

    data class TunHandle(val fd: Int, val mtu: Int, val interfaceName: String)

    companion object {
        const val TAG = "TunVpnService"
        const val ACTION_START = "com.overx.app.START"
        const val ACTION_STOP = "com.overx.app.STOP"
        const val EXTRA_MTU = "mtu"

        private const val CHANNEL_ID = "overx_vpn"
        private const val NOTIFICATION_ID = 1

        // آدرس‌های اینترفیس — با تنظیمات DNS برنامه هماهنگ است
        private const val TUN_IPV4 = "172.19.0.2"
        private const val TUN_IPV4_PREFIX = 32
        private const val TUN_ROUTE = "0.0.0.0"
        private const val TUN_ROUTE_PREFIX = 0

        /** نامِ قراردادیِ اینترفیس (اندروید نامِ واقعی را نمی‌دهد). */
        private const val TUN_INTERFACE_NAME = "tun0"

        private val latch = CountDownLatch(1)
        private val handleRef = AtomicReference<TunHandle?>(null)

        @Volatile
        private var instance: TunVpnService? = null

        @Volatile
        private var descriptor: ParcelFileDescriptor? = null

        /** منتظر ساخته شدن fd می‌ماند (از MainActivity صدا زده می‌شود). */
        fun awaitTun(timeoutMs: Long, cb: (TunHandle?) -> Unit) {
            Thread {
                val ok = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
                cb(if (ok) handleRef.get() else null)
            }.start()
        }

        fun stop(context: android.content.Context) {
            val intent = Intent(context, TunVpnService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        fun release() {
            latch.countDown()
            handleRef.set(null)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_STOP -> {
                teardown()
                stopForeground(true)
                stopSelf()
                START_NOT_STICKY
            }
            else -> {
                instance = this
                startForeground(NOTIFICATION_ID, buildNotification())
                val mtu = intent?.getIntExtra(EXTRA_MTU, 9000) ?: 9000
                val handle = establish(mtu)
                handleRef.set(handle)
                if (handle == null) Log.e(TAG, "Builder.establish() returned null")
                latch.countDown()
                START_STICKY
            }
        }
    }

    /**
     * ساخت اینترفیس و برگرداندن fd.
     *
     * نکته: `Builder()` را می‌توان برای مسیریابیِ هر برنامه
     * (`addAllowedApplication` / `addDisallowedApplication`) تنظیم کرد —
     * این قابلیت بعداً به تنظیمات اضافه می‌شود.
     */
    private fun establish(mtu: Int): TunHandle? {
        val builder = Builder()
            .setSession("OVERX")
            .setMtu(mtu)
            .addAddress(TUN_IPV4, TUN_IPV4_PREFIX)
            .addRoute(TUN_ROUTE, TUN_ROUTE_PREFIX)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .setBlocking(false)
            .setMetered(false)

        val pfd: ParcelFileDescriptor? = runCatching { builder.establish() }
            .onFailure { Log.e(TAG, "establish failed", it) }
            .getOrNull()

        descriptor = pfd ?: return null

        return TunHandle(
            fd = pfd!!.fd,
            mtu = mtu,
            // اندروید نامِ اینترفیس را از روی ParcelFileDescriptor نمی‌دهد
            // (تنها راهش خواندنِ /proc/net/dev یا رابطِ پنهانِ سیستم است).
            // قراردادِ رایج در ابزارهای TUN همین tun0 است و سمتِ دارت هم
            // همین مقدارِ پیش‌فرض را دارد (platform_bridge.dart).
            interfaceName = TUN_INTERFACE_NAME,
        )
    }

    private fun teardown() {
        runCatching {
            descriptor?.close()
        }.onFailure { Log.w(TAG, "closing descriptor", it) }
        descriptor = null
        instance = null
        release()
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    override fun onRevoke() {
        // کاربر VPN را از تنظیمات سیستم قطع کرده
        teardown()
        stopSelf()
        super.onRevoke()
    }

    private fun buildNotification(): Notification {
        createChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0),
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("OVERX")
            .setContentText("اتصال برقرار است")
            // همان نشانه‌ی برنامه؛ باید تک‌رنگ باشد چون اندروید آن را
            // در نوارِ وضعیت به رنگِ سفید درمی‌آورد (ic_stat_overx)
            .setSmallIcon(R.drawable.ic_stat_overx)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "وضعیت اتصال OVERX",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "نمایش وضعیت اتصال در نوار اعلان‌ها"
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }
}
