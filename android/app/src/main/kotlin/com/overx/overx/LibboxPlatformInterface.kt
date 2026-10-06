package com.overx.overx

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.IpPrefix
import android.net.VpnService
import android.os.Build
import android.os.Process
import android.system.OsConstants
import android.util.Log
import io.nekohasekai.libbox.BridgeOptions
import io.nekohasekai.libbox.BridgeSession
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.NetworkInterface as JavaNetworkInterface

/**
 * پیاده‌سازیِ [PlatformInterface] برای اندروید.
 *
 * این همان رابطی است که کتابخانه‌ی libbox صدا می‌زند تا از سیستم‌عامل چیزی
 * بخواهد. مهم‌ترین متد آن [openTun] است: وقتی هسته به اینترفیس TUN نیاز پیدا
 * می‌کند، libbox این متد را با گزینه‌هایی که خودش از کانفیگ استخراج کرده فرا
 * می‌خواند و ما باید اینترفیس را بسازیم و **فقط یک fd برگردانیم**.
 *
 * نکته‌ی مهم: ما آدرس‌ها و مسیرها را خودمان انتخاب نمی‌کنیم — هرچه libbox در
 * [TunOptions] فرستاده همان چیزی است که کاربر در کانفیگ نوشته است، بنابراین
 * باید دقیقاً همان‌ها را به [VpnService.Builder] بدهیم.
 */
class LibboxPlatformInterface(
    private val service: VpnService,
    private val host: LibboxVpnService,
) : PlatformInterface {

    companion object {
        private const val TAG = "LibboxPlatformInterface"
    }

    // ------------------------------------------------------------------ TUN

    override fun openTun(options: TunOptions): Int {
        // اگر هنوز مجوز VPN نگرفته‌ایم، گرفتنِ اینترفیس با خطا روبه‌رو می‌شود
        if (VpnService.prepare(service) != null) {
            error("android: missing vpn permission")
        }

        // `VpnService.Builder` یک کلاسِ **درونیِ غیراستاتیک** است
        // (android.jar: `VpnService$Builder` فیلدِ this$0 دارد و سازنده‌اش
        // خودِ سرویس را می‌گیرد)، پس در کاتلین باید با نمونه ساخته شود:
        // `service.Builder()` — نوشتنِ `VpnService.Builder(service)` کامپایل نمی‌شود.
        val builder = service.Builder()
            .setSession(host.sessionName)
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
        // اجازه می‌دهیم برنامه‌هایی که خودشان را مستثنی کرده‌اند از VPN بگذرند
        builder.allowBypass()

        // آدرس‌هایی که libbox از کانفیگ استخراج کرده
        val inet4Address = options.inet4Address
        while (inet4Address.hasNext()) {
            val address = inet4Address.next()
            builder.addAddress(address.address(), address.prefix())
        }
        val inet6Address = options.inet6Address
        while (inet6Address.hasNext()) {
            val address = inet6Address.next()
            builder.addAddress(address.address(), address.prefix())
        }

        if (options.autoRoute) {
            // DNS — فقط وقتی هسته قرار است خودش DNS را مدیریت کند
            if (options.dnsMode.value != Libbox.DNSModeDisabled) {
                val dnsServerAddress = options.dnsServerAddress
                while (dnsServerAddress.hasNext()) {
                    builder.addDnsServer(dnsServerAddress.next())
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // اندروید ۱۳ به بعد: مسیرها را با دقتِ بیشتری می‌توان داد
                val inet4RouteAddress = options.inet4RouteAddress
                if (inet4RouteAddress.hasNext()) {
                    while (inet4RouteAddress.hasNext()) {
                        val address = inet4RouteAddress.next()
                        builder.addRoute(address.address(), address.prefix())
                    }
                } else if (options.inet4Address.hasNext()) {
                    builder.addRoute("0.0.0.0", 0)
                }

                val inet6RouteAddress = options.inet6RouteAddress
                if (inet6RouteAddress.hasNext()) {
                    while (inet6RouteAddress.hasNext()) {
                        val address = inet6RouteAddress.next()
                        builder.addRoute(address.address(), address.prefix())
                    }
                } else if (options.inet6Address.hasNext()) {
                    builder.addRoute("::", 0)
                }

                // برعکسِ addRoute، متدِ excludeRoute هیچ نسخه‌ی
                // «آدرس + طولِ پیشوند» ندارد: فقط یک IpPrefix می‌گیرد
                // (اندروید ۱۳ به بعد — که دقیقاً همین شاخه است).
                val inet4Exclude = options.inet4RouteExcludeAddress
                while (inet4Exclude.hasNext()) {
                    inet4Exclude.next().toIpPrefix()?.let { builder.excludeRoute(it) }
                }
                val inet6Exclude = options.inet6RouteExcludeAddress
                while (inet6Exclude.hasNext()) {
                    inet6Exclude.next().toIpPrefix()?.let { builder.excludeRoute(it) }
                }
            } else {
                // اندروید ۱۲ و پایین‌تر: از بازه‌های مسیر استفاده می‌کنیم
                val inet4Range = options.inet4RouteRange
                if (inet4Range.hasNext()) {
                    while (inet4Range.hasNext()) {
                        val address = inet4Range.next()
                        builder.addRoute(address.address(), address.prefix())
                    }
                }
                val inet6Range = options.inet6RouteRange
                if (inet6Range.hasNext()) {
                    while (inet6Range.hasNext()) {
                        val address = inet6Range.next()
                        builder.addRoute(address.address(), address.prefix())
                    }
                }
            }

            // مسیریابیِ هر برنامه (per-app proxy)
            val includePackage = options.includePackage
            if (includePackage.hasNext()) {
                while (includePackage.hasNext()) {
                    try {
                        builder.addAllowedApplication(includePackage.next())
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.w(TAG, "addAllowedApplication failed", e)
                    }
                }
            }
            val excludePackage = options.excludePackage
            if (excludePackage.hasNext()) {
                while (excludePackage.hasNext()) {
                    try {
                        builder.addDisallowedApplication(excludePackage.next())
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.w(TAG, "addDisallowedApplication failed", e)
                    }
                }
            }
        }

        // پروکسی HTTPِ سیستمی (اندروید ۱۰ به بعد)
        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // `StringIterator` ی libbox یک Iterable جاوا نیست، پس `toList()`
            // روی آن وجود ندارد — باید دستی پیمایش شود.
            val bypass = ArrayList<String>().apply {
                val iterator = options.httpProxyBypassDomain
                while (iterator.hasNext()) add(iterator.next())
            }
            builder.setHttpProxy(
                android.net.ProxyInfo.buildDirectProxy(
                    options.httpProxyServer,
                    options.httpProxyServerPort,
                    bypass,
                )
            )
        }

        val pfd = builder.establish()
            ?: error("android: the application is not prepared or is revoked")

        // fd را نگه می‌داریم تا هنگام توقف بتوانیم ببندیمش
        host.fileDescriptor = pfd
        Log.i(TAG, "openTun: established (fd=${pfd.fd}, mtu=${options.mtu})")
        return pfd.fd
    }

    // ------------------------------------------------------- سوکت‌های محافظت‌شده

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        // سوکتِ هسته نباید دوباره وارد تونل شود
        service.protect(fd)
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    private fun connectivity() =
        service.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        val uid = connectivity().getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == Process.INVALID_UID) error("android: connection owner not found")
        val packages = service.packageManager.getPackagesForUid(uid)
        return ConnectionOwner().apply {
            userId = uid
            userName = packages?.firstOrNull() ?: ""
            setAndroidPackageNames(StringArray(packages?.toList()?.iterator()))
        }
    }

    // ------------------------------------------------------------- شبکه

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        if (listener == null) return
        DefaultNetworkMonitor.start(service)
        DefaultNetworkMonitor.setListener(service, listener)
        Log.i(TAG, "default interface monitor started")
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        DefaultNetworkMonitor.setListener(service, null)
        DefaultNetworkMonitor.stop()
        Log.i(TAG, "default interface monitor stopped")
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val connectivity = connectivity()
        val networks = connectivity.allNetworks
        val javaInterfaces = java.util.Collections.list(JavaNetworkInterface.getNetworkInterfaces())
        val result = mutableListOf<NetworkInterface>()

        for (network in networks) {
            val linkProperties =
                connectivity.getLinkProperties(network) ?: continue
            val capabilities =
                connectivity.getNetworkCapabilities(network) ?: continue

            val boxInterface = NetworkInterface()
            boxInterface.name = linkProperties.interfaceName
            val javaInterface =
                javaInterfaces.firstOrNull { it.name == boxInterface.name } ?: continue

            boxInterface.dnsServer =
                StringArray(linkProperties.dnsServers.mapNotNull { it.hostAddress }.iterator())
            boxInterface.gateway = StringArray(
                linkProperties.routes
                    .filter { it.destination.prefixLength == 0 }
                    .mapNotNull { it.gateway }
                    .filterNot { it.isAnyLocalAddress }
                    .mapNotNull { it.hostAddress }
                    .iterator()
            )
            boxInterface.type = when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ->
                    Libbox.InterfaceTypeWIFI

                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
                    Libbox.InterfaceTypeCellular

                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ->
                    Libbox.InterfaceTypeEthernet

                else -> Libbox.InterfaceTypeOther
            }
            boxInterface.index = javaInterface.index
            runCatching { boxInterface.mtu = javaInterface.mtu }
            boxInterface.addresses =
                StringArray(javaInterface.interfaceAddresses.map { it.toPrefix() }.iterator())

            var flags = 0
            if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (javaInterface.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (javaInterface.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (javaInterface.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
            boxInterface.flags = flags
            boxInterface.metered =
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)

            result.add(boxInterface)
        }
        return InterfaceArray(result.iterator())
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun clearDNSCache() {}

    override fun readWIFIState(): WIFIState? {
        @Suppress("DEPRECATION")
        val wifiInfo = service.applicationContext
            .getSystemService(android.content.Context.WIFI_SERVICE)
            .let { it as? android.net.wifi.WifiManager }?.connectionInfo ?: return null
        var ssid = wifiInfo.ssid
        if (ssid == "<unknown ssid>") return WIFIState("", "")
        if (ssid.startsWith("\"") && ssid.endsWith("\"")) {
            ssid = ssid.substring(1, ssid.length - 1)
        }
        return WIFIState(ssid, wifiInfo.bssid)
    }

    // ------------------------------------------------------------ متفرقه

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun startNeighborMonitor(listener: NeighborUpdateListener?) {}

    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) {}

    override fun registerMyInterface(name: String?) {}

    override fun usePlatformShell(): Boolean = false

    /**
     * Go: `CheckPlatformShell() error`.
     *
     * خروجیِ `error` در gobind به `throws` ترجمه می‌شود و نوعِ بازگشتیِ جاوا
     * `void` می‌ماند (`bind/genjava.go` → `genFuncSignature`: یک خروجی از نوع
     * error ⇒ `ret = "void"`). بنابراین امضایِ جاوا `void checkPlatformShell()`
     * است و پیاده‌سازیِ کاتلین باید `Unit` برگرداند؛ برگرداندنِ `Boolean`
     * «return type is not a subtype of the overridden member» می‌دهد و تنها
     * وقتی کامپایل می‌کنیم که AAR حاضر باشد دیده می‌شد.
     */
    override fun checkPlatformShell() {
        // پوسته‌ی پلتفرم پشتیبانی نمی‌شود؛ «در دسترس نیست» همان خطاست.
        error("android: platform shell not supported")
    }

    override fun openShellSession(
        user: PlatformUser?,
        command: String?,
        environ: StringIterator?,
        term: String?,
        rows: Int,
        cols: Int,
    ): ShellSession? = null

    override fun lookupUser(username: String?): PlatformUser? = null

    override fun lookupSFTPServer(): String? = null

    override fun readSystemSSHHostKey(): String? = null

    override fun tailscaleHostname(): String? = null

    override fun usePlatformBridge(): Boolean = false

    override fun createBridge(options: BridgeOptions?): BridgeSession? = null

    override fun sendNotification(notification: Notification?) {
        notification ?: return
        host.sendLibboxNotification(notification)
    }

    override fun cancelNotification(identifier: String?, typeID: Int) {
        identifier ?: return
        host.cancelLibboxNotification(identifier, typeID)
    }

    // ------------------------------------------------------- ابزارهای کمکی

    /**
     * تبدیل یک لیست به [StringIterator] که libbox می‌فهمد.
     *
     * اینترفیسِ Go در sing-box 1.14.2 (`experimental/libbox/iterator.go`) سه
     * متد دارد:
     * ```go
     * type StringIterator interface {
     *     Len() int32
     *     HasNext() bool
     *     Next() string
     * }
     * ```
     * و gobind آن را به **interface جاوا** تبدیل می‌کند
     * (`bind/genjava.go`: `public interface %s`)، نه یک کلاسِ abstract —
     * برای همین در کاتلین بدون پرانتز پیاده می‌شود.
     *
     * دو نکته که قبلاً اینجا اشتباه بود و فقط هنگامِ کامپایل با AARِ واقعی
     * خودش را نشان می‌داد:
     *  1. `: StringIterator()` — اینترفیس سازنده ندارد.
     *  2. `len()` پیاده نشده بود (در نسخه‌های قدیمی‌تر libbox نبود).
     *
     * چون `Iterator` ی جاوا اندازه ندارد، ورودی را همان اول متریالیزه می‌کنیم
     * تا `len()` عددِ درستی برگرداند.
     */
    class StringArray(values: Iterator<String>?) : StringIterator {
        private val items: List<String> = values?.let { source ->
            buildList { while (source.hasNext()) add(source.next()) }
        } ?: emptyList()

        private var cursor = 0

        override fun len(): Int = items.size

        override fun hasNext(): Boolean = cursor < items.size

        /** پایانِ پیمایش: مانند خودِ Go مقدارِ صفر («») برمی‌گردد. */
        override fun next(): String = if (cursor < items.size) items[cursor++] else ""
    }

    /**
     * همان [StringArray] برای اینترفیسِ شبکه.
     *
     * `NetworkInterfaceIterator` در `experimental/libbox/platform.go` فقط دو
     * متد دارد (`Next` و `HasNext`) و `len()` ندارد. پایانِ پیمایش در Go با
     * `nil` است، پس اینجا هم `null` برمی‌گردانیم تا اگر مصرف‌کننده‌ای به
     * `hasNext()` توجه نکرد، حلقه بی‌انتها نشود.
     */
    class InterfaceArray(private val values: Iterator<NetworkInterface>) :
        NetworkInterfaceIterator {

        override fun hasNext(): Boolean = values.hasNext()

        /** پایانِ پیمایش در Go با `nil` است، نه استثنا. */
        override fun next(): NetworkInterface? =
            if (values.hasNext()) values.next() else null
    }

    /**
     * تبدیلِ یک مسیرِ libbox به [IpPrefix] ی اندروید.
     *
     * [RoutePrefix.address] رشته است، پس باید解析 شود؛ اگر آدرس نامعتبر
     * باشد (یا دستگاه نسخه‌ی قدیمی‌تری داشته باشد) با null برمی‌گردیم تا
     * کلِ ساختِ اینترفیس به‌خاطر یک مسیر شکست نخورد.
     */
    private fun io.nekohasekai.libbox.RoutePrefix.toIpPrefix(): IpPrefix? =
        runCatching {
            IpPrefix(java.net.InetAddress.getByName(address()), prefix())
        }.onFailure {
            Log.w(TAG, "toIpPrefix: رد کردنِ مسیرِ نامعتبر ${address()}", it)
        }.getOrNull()

    private fun java.net.InterfaceAddress.toPrefix(): String {
        val address = address
        val prefix = networkPrefixLength
        return if (address is Inet6Address) {
            "${address.hostAddress}/$prefix"
        } else {
            "${address.hostAddress}/$prefix"
        }
    }
}
