package com.overx.overx

import android.annotation.TargetApi
import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface

/**
 * زیر نظر گرفتنِ اینترفیس پیش‌فرضِ شبکه برای libbox.
 *
 * چرا لازم است؟
 * وقتی کاربر از وای‌فای به داده‌ی همراه (یا برعکس) می‌رود، هسته باید بداند که
 * مسیر خروجی عوض شده تا جداول مسیریابی‌اش را به‌روز کند. libbox این را از
 * طریق [InterfaceUpdateListener] می‌پرسد و ما اینجا پاسخش را می‌دهیم.
 *
 * دو نکته‌ی مهم:
 *
 * ۱. از `registerDefaultNetworkCallback` روی اندروید ۹ به بعد، اینترفیسِ
 *    **خودِ VPN** برگردانده می‌شود (تغییر رفتار گوگل در Android P DP1)،
 *    که برای ما بی‌فایده است. برای همین روی آن نسخه‌ها از `requestNetwork`
 *    با درخواستِ REQUEST استفاده می‌کنیم. این نیازمند مجوز
 *    `CHANGE_NETWORK_STATE` است که در مانیفست هست.
 *
 * ۲. ممکن است هم‌زمان چند شبکه در دسترس باشد (مثلاً وای‌فای و داده‌ی همراه).
 *    اندروید لزوماً همانی را برنمی‌گزیند که ما می‌خواهیم، پس خودمان به نوعِ
 *    ترابرد امتیاز می‌دهیم و بهترین را انتخاب می‌کنیم (نگاه کن به
 *    [transportScore] و [preferWifi]).
 */
object DefaultNetworkMonitor {

    private const val TAG = "DefaultNetworkMonitor"

    private val lock = Any()

    @Volatile
    private var listener: InterfaceUpdateListener? = null

    @Volatile
    private var currentNetwork: Network? = null

    /**
     * وای‌فای را به داده‌ی همراه ترجیح بده؟
     *
     * پیش‌فرض «بله» است: روی موبایل معمولاً وای‌فای ارزان‌تر و پایدارتر است.
     * بعداً می‌توان این را به یک تنظیم در UI وصل کرد.
     */
    @Volatile
    var preferWifi: Boolean = true

    private var connectivity: ConnectivityManager? = null
    private var callbackThread: HandlerThread? = null
    private var callbackHandler: Handler? = null

    /** همه‌ی شبکه‌های در دسترس به همراه قابلیت‌هایشان. */
    private val candidates = LinkedHashMap<Network, NetworkCapabilities>()

    /**
     * یک شبکه‌ی نامزد به همراه امتیازش.
     *
     * به‌جای `Pair` استفاده می‌شود: `first`/`second` و destructuring روی
     * نوع‌های حل‌نشده (بدون `android.jar`) برای کامپایلر مبهم می‌شوند.
     */
    private class Candidate(val network: Network, val score: Int)

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            track(network)
            applyBest()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            capabilities: NetworkCapabilities,
        ) {
            synchronized(lock) { candidates[network] = capabilities }
            applyBest()
        }

        override fun onLinkPropertiesChanged(network: Network, props: LinkProperties) {
            // نامِ اینترفیس ممکن است همین الان آماده شده باشد
            if (synchronized(lock) { currentNetwork } == network) reportUpdate(network)
        }

        override fun onLost(network: Network) {
            synchronized(lock) { candidates.remove(network) }
            applyBest()
        }
    }

    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .build()

    fun setListener(context: Context, newListener: InterfaceUpdateListener?) {
        listener = newListener
        if (newListener == null) return
        val current = synchronized(lock) { currentNetwork }
        if (current == null) applyBest() else reportUpdate(current)
    }

    fun start(context: Context) {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return
        synchronized(lock) {
            if (connectivity != null) return   // قبلاً شروع شده
            connectivity = cm

            // `apply` پارامتر ندارد و فقط `this` را می‌دهد؛ `it` اینجا اصلاً
            // وجود ندارد (و کامپایل نمی‌شد). منظور این بود: این ترد را start کن.
            val thread = HandlerThread("overx-network").apply { start() }
            callbackThread = thread
            callbackHandler = Handler(thread.looper)

            // شبکه‌هایی که همین حالا هم برقرارند
            seedCandidates(cm)

            runCatching { register(cm) }
                .onFailure { Log.e(TAG, "register network callback", it) }
        }
        applyBest()
    }

    fun stop() {
        synchronized(lock) {
            val cm = connectivity ?: return
            runCatching { cm.unregisterNetworkCallback(callback) }
                .onFailure { Log.w(TAG, "unregister", it) }
            connectivity = null
            candidates.clear()
            currentNetwork = null
        }
        callbackThread?.quitSafely()
        callbackThread = null
        callbackHandler = null
        listener = null
    }

    /** شبکه‌های از پیش موجود را وارد فهرست می‌کند (مثلاً وای‌فایِ وصل از قبل). */
    private fun seedCandidates(cm: ConnectivityManager) {
        val networks = runCatching { cm.allNetworks }.getOrNull() ?: return
        // حلقه با اندیس (نه for-in): تکرارگرِ آرایه‌ی برگشتی بدون android.jar
        // مبهم است و کامپایلرِ ما را به خطا می‌اندازد.
        var i = 0
        while (i < networks.size) {
            val network = networks[i]
            val capabilities = runCatching { cm.getNetworkCapabilities(network) }.getOrNull()
            if (capabilities != null && isUsable(capabilities)) {
                candidates[network] = capabilities
            }
            i++
        }
    }

    /** یک شبکه را (اگر ارزش داشت) به فهرستِ نامزدها اضافه می‌کند. */
    private fun track(network: Network) {
        val cm = synchronized(lock) { connectivity } ?: return
        val capabilities = runCatching { cm.getNetworkCapabilities(network) }.getOrNull()
            ?: return
        synchronized(lock) {
            if (isUsable(capabilities)) candidates[network] = capabilities
        }
    }

    /**
     * آیا این شبکه را به عنوانِ اینترفیسِ خروجی می‌پذیریم؟
     *
     * `TRANSPORT_VPN` را حذف می‌کنیم: آن اینترفیسِ خودمان است و گرفتنش دقیقاً
     * همان دوری است که کل این کلاس برای پرهیز از آن نوشته شده.
     */
    private fun isUsable(capabilities: NetworkCapabilities): Boolean {
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }

    /**
     * امتیازِ نوعِ ترابرد — عددِ بزرگ‌تر یعنی اولویتِ بیشتر.
     *
     * ترتیب (وقتی [preferWifi] روشن باشد):
     * وای‌فای > اترنت > بلوتوث/داده‌ی همراه > بقیه > VPN
     */
    private fun transportScore(capabilities: NetworkCapabilities): Int {
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return -100
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
            return if (preferWifi) 100 else 40
        }
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) return 90
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)) return 50
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) return 40
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI_AWARE)) return 30
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_LOWPAN)) return 20
        return 10
    }

    /** بهترین شبکه‌ی در دسترس را برمی‌گزیند و تغییر را به libbox گزارش می‌دهد. */
    private fun applyBest() {
        val snapshot = synchronized(lock) {
            val keys = ArrayList(candidates.keys)
            val out = ArrayList<Candidate>(keys.size)
            var i = 0
            while (i < keys.size) {
                val network = keys[i]
                val capabilities = candidates[network]
                if (capabilities != null) {
                    out.add(Candidate(network, transportScore(capabilities)))
                }
                i++
            }
            out
        }

        var best: Network? = null
        var bestScore = Int.MIN_VALUE
        var j = 0
        while (j < snapshot.size) {
            val candidate = snapshot[j]
            if (candidate.score > bestScore) {
                best = candidate.network
                bestScore = candidate.score
            }
            j++
        }

        val previous = synchronized(lock) {
            val old = currentNetwork
            currentNetwork = best
            old
        }

        if (best == null) {
            // هیچ شبکه‌ای نیست: اینترفیسِ پیش‌فرضی هم وجود ندارد
            val target = listener ?: return
            runCatching { target.updateDefaultInterface("", -1, false, false) }
                .onFailure { Log.w(TAG, "updateDefaultInterface(empty)", it) }
            return
        }
        if (best != previous) {
            Log.d(TAG, "default network changed → $best (score $bestScore)")
        }
        reportUpdate(best)
    }

    @Suppress("DEPRECATION")
    @TargetApi(Build.VERSION_CODES.O)
    private fun register(cm: ConnectivityManager) {
        // این متدها Handlerِ غیر‌تهی می‌خواهند؛ اگر تردِ مانیتور هنوز بالا
        // نیامده، اصلاً ثبت‌نام نمی‌کنیم (به‌جای فرستادنِ null که امضا ندارد).
        val handler = callbackHandler ?: return
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                cm.registerBestMatchingNetworkCallback(request, callback, handler)

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ->
                // اینجا REQUEST می‌خواهیم، نه LISTEN — وگرنه اینترفیس VPN برمی‌گردد
                cm.requestNetwork(request, callback, handler)

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                cm.registerDefaultNetworkCallback(callback, handler)

            else ->
                cm.registerDefaultNetworkCallback(callback)
        }
    }

    /**
     * نام و ایندکسِ اینترفیس را پیدا و به libbox گزارش می‌دهد.
     *
     * اندکی پس از تغییر شبکه، `LinkProperties` ممکن است هنوز آماده نباشد؛
     * برای همین چند بار با فاصله‌ی کوتاه تلاش می‌کنیم (همان الگوی SFA).
     */
    private fun reportUpdate(network: Network?) {
        val target = listener ?: return
        val cm = synchronized(lock) { connectivity } ?: return

        if (network == null) {
            runCatching { target.updateDefaultInterface("", -1, false, false) }
                .onFailure { Log.w(TAG, "updateDefaultInterface(empty)", it) }
            return
        }

        for (attempt in 0 until 10) {
            val interfaceName = runCatching {
                cm.getLinkProperties(network)?.interfaceName?.toString()
            }.getOrNull()
            if (interfaceName.isNullOrBlank()) {
                sleepBriefly()
                continue
            }
            val index = runCatching { NetworkInterface.getByName(interfaceName)?.index }
                .getOrNull()
            if (index == null) {
                sleepBriefly()
                continue
            }
            runCatching { target.updateDefaultInterface(interfaceName, index, false, false) }
                .onFailure { Log.w(TAG, "updateDefaultInterface", it) }
            return
        }
        Log.w(TAG, "could not resolve interface for the default network")
    }

    private fun sleepBriefly() {
        runCatching { Thread.sleep(100) }
    }
}
