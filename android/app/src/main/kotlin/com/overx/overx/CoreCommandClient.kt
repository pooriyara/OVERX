package com.overx.overx

import android.util.Log
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.Connections
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupItemIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator

/**
 * کلاینتِ فرمانِ libbox: **لاگ‌های زنده‌ی هسته**، **آمارِ ترافیک**،
 * **گروه‌های خروجی** و **اتصال‌ها**.
 *
 * چرا لازم است؟ در حالت libbox، کلیدِ `log.output` در کانفیگ نادیده گرفته
 * می‌شود: لاگ‌ها فقط در یک حلقه‌ی درون‌حافظه‌ای (`logRing`) نگه داشته
 * می‌شوند. به همین ترتیب، تنها راهِ رسیدن به گروه‌ها و اتصال‌ها، جریانِ
 * gRPCِ سرورِ فرمان است — نه API ی Clash (که در AAR حذف شده).
 *
 * جریانِ داده:
 * ```
 * Go:    daemon.StartedService.SubscribeLog / SubscribeStatus / SubscribeGroups /
 *        SubscribeConnections
 *          ↓ gRPC
 * Go:    libbox.CommandClient → CommandClientHandler
 *          ↓ gomobile
 * اینجا:  writeLogs()      → LibboxChannel.emitLogLine  → Dart logsProvider
 *         writeStatus()    → TrafficListener            → اعلان
 *         writeGroups()    → snapshotGroups()           → صفحه‌ی «شبکه»
 *         writeConnectionEvents() → snapshotConnections() → صفحه‌ی «شبکه»
 * ```
 *
 * اتصال از طریق سوکتِ یونیکسِ `<basePath>/command.sock` است (درون‌فرآیندی)،
 * پس هیچ پورتی باز نمی‌شود و نیازی به `protect()` نیست.
 */
object CoreCommandClient : CommandClientHandler {

    private const val TAG = "CoreCommandClient"

    /**
     * شماره‌ی فرمان‌ها — باید با `experimental/libbox/command.go` یکی باشد:
     * `CommandLog=0`، `CommandStatus=1`، `CommandGroup=2`،
     * `CommandClashMode=3`، `CommandConnections=4`، `CommandOutbounds=5`.
     *
     * از ثابت‌های تولیدشده‌ی gomobile استفاده نمی‌کنیم چون بسته به نسخه ممکن
     * است نامشان متفاوت باشد؛ مقدارِ عددیِ این enum از ابتدای libbox ثابت بوده.
     */
    private const val COMMAND_LOG = 0
    private const val COMMAND_STATUS = 1
    private const val COMMAND_GROUP = 2
    private const val COMMAND_CONNECTIONS = 4

    /**
     * فاصله‌ی ارسالِ آمار — **واحد نانوثانیه**.
     *
     * سمت Go این مقدار مستقیماً به `time.Duration(request.Interval)` تبدیل
     * می‌شود (نگاه کن به `daemon.SubscribeStatus`)؛ مقدارِ صفر هم همان
     * پیش‌فرضِ یک ثانیه است، امّا صریح می‌نویسیم تا به پیش‌فرض وابسته نباشیم.
     */
    private const val STATUS_INTERVAL_NANOS = 1_000_000_000L

    /** سطحِ لاگِ پیش‌فرضِ هسته؛ `log.LevelInfo` برابر ۴ است. */
    private const val DEFAULT_LOG_LEVEL_INFO = 4

    /** شنونده‌ی آمارِ ترافیک — اعلان از همین استفاده می‌کند. */
    fun interface TrafficListener {
        /**
         * [uplink] و [downlink] **دلتا** از پیام قبلی‌اند (با فاصله‌ی یک
         * ثانیه، پس عملاً بایت‌برثانیه)؛ [uplinkTotal] و [downlinkTotal]
         * تجمعی‌اند.
         */
        fun onTraffic(uplink: Long, downlink: Long, uplinkTotal: Long, downlinkTotal: Long)
    }

    /** یک خروجی درون یک گروه (بدونِ تأخیر — نگاه کن به یادداشتِ زیر). */
    /**
     * يک خروجي درونِ گروه.
     *
     * `urlTestTime` صفر يعني «تأخير تست نشده» (مطابقِ [OutboundItem.tested]
     * سمت دارت).
     */
    private class GroupItem(
        val tag: String,
        val type: String,
        val urlTestDelay: Int,
        val urlTestTime: Long,
    )

    private class GroupSnapshot(
        val tag: String,
        val type: String,
        val selectable: Boolean,
        val selected: String,
        val isExpand: Boolean,
        val items: List<GroupItem>,
    )

    /** قفلِ چرخه‌ی حيات: start و stop نبايد هم‌زمان اجرا شوند. */
    private val lifecycleLock = Any()

    /** قفلِ وضعیت: هم نوشتن از تردِ Go و هم خواندن از تردِ اصلی. */
    private val stateLock = Any()

    @Volatile
    private var client: CommandClient? = null

    @Volatile
    private var defaultLogLevel: Int = DEFAULT_LOG_LEVEL_INFO

    /** تنها یک شنونده داریم (سرویسِ VPN)؛ با `stop()` صفر می‌شود. */
    @Volatile
    var trafficListener: TrafficListener? = null

    private var groups: List<GroupSnapshot> = emptyList()

    /**
     * اتصال‌ها — شیءِ خودِ libbox را نگه می‌داریم تا فیلتر و مرتب‌سازی را
     * همان سمت Go انجام دهد.
     */
    private var connections: Connections? = null

    /** آیا جریان وصل است؟ برای اینکه دوبار وصل نشویم. */
    val isConnected: Boolean get() = client != null

    /**
     * وصل‌شدن به سرورِ فرمان.
     *
     * چون کلاینت «handler-bound» است، حلقه‌ی اتصال تا بالا آمدنِ سرور صبر
     * می‌کند (۱۰ تلاش)؛ بنابراین می‌توان بلافاصله بعد از
     * `startOrReloadService` صدا زد.
     */
    fun start(): Boolean {
        if (client != null) return true
        synchronized(lifecycleLock) {
            if (client != null) return true
            return try {
                val options = CommandClientOptions().apply {
                    addCommand(COMMAND_LOG)
                    addCommand(COMMAND_STATUS)
                    addCommand(COMMAND_GROUP)
                    addCommand(COMMAND_CONNECTIONS)
                    statusInterval = STATUS_INTERVAL_NANOS
                }
                val newClient = Libbox.newCommandClient(this, options)
                newClient.connect()
                synchronized(stateLock) { connections = Libbox.newConnections() }
                client = newClient
                LibboxChannel.emitLog("libbox: command client connected (log + status + groups)")
                true
            } catch (e: Throwable) {
                // شکستِ این اتصال به معنای شکستِ کل اتصال نیست — فقط لاگ،
                // آمار، گروه‌ها و اتصال‌ها را نخواهیم داشت.
                Log.w(TAG, "connect failed", e)
                LibboxChannel.emitLog("libbox: command client unavailable: ${e.message}")
                false
            }
        }
    }

    fun stop() {
        val previous: CommandClient?
        synchronized(lifecycleLock) {
            previous = client
            client = null
        }
        trafficListener = null
        synchronized(stateLock) {
            groups = emptyList()
            connections = null
        }
        try {
            previous?.disconnect()
        } catch (e: Throwable) {
            Log.w(TAG, "disconnect", e)
        }
    }

    // -------------------------------------------------------------- عکسِ وضعیت

    /** گروه‌های خروجی برای ارسال روی کانال (مدلِ دارت: `OutboundGroup`). */
    fun snapshotGroups(): List<Map<String, Any?>> {
        val snapshot = synchronized(stateLock) { groups }
        val out = ArrayList<Map<String, Any?>>(snapshot.size)
        var i = 0
        while (i < snapshot.size) {
            val group = snapshot[i]
            val items = ArrayList<Map<String, Any?>>(group.items.size)
            var k = 0
            while (k < group.items.size) {
                val item = group.items[k]
                items.add(
                    hashMapOf<String, Any?>(
                        "tag" to item.tag,
                        "type" to item.type,
                        "urlTestDelay" to item.urlTestDelay,
                        "urlTestTime" to item.urlTestTime,
                    ),
                )
                k++
            }
            out.add(
                hashMapOf<String, Any?>(
                    "tag" to group.tag,
                    "type" to group.type,
                    "selectable" to group.selectable,
                    "selected" to group.selected,
                    "isExpand" to group.isExpand,
                    "items" to items,
                ),
            )
            i++
        }
        return out
    }

    /**
     * اتصال‌های جاری برای ارسال روی کانال (مدلِ دارت: `ConnectionEntry`).
     *
     * مرتب‌سازی بر اساسِ زمان است (جدیدترین اول). باید زیرِ [stateLock]
     * باشد: شیءِ `Connections` سمت Go قفل ندارد و نوشتنِ هم‌زمان روی نگاشتش
     * می‌تواند فرآیند را بترکاند.
     */
    fun snapshotConnections(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        synchronized(stateLock) {
            val holder = connections ?: return out
            runCatching { holder.sortByDate() }
                .onFailure { Log.w(TAG, "sortByDate", it) }
            val iterator = runCatching { holder.iterator() }.getOrNull() ?: return out
            try {
                while (true) {
                    // پايانِ پيمایش با nil مشخص مي‌شود
                    val connection = iterator.next() ?: break
                out.add(
                    hashMapOf<String, Any?>(
                        "id" to connection.id,
                        "outbound" to connection.outbound,
                        "protocol" to connection.protocol,
                        "network" to connection.network,
                        "destination" to runCatching { connection.displayDestination() }
                            .getOrNull(),
                        "domain" to connection.domain,
                        "source" to connection.source,
                        "uplinkTotal" to connection.uplinkTotal,
                        "downlinkTotal" to connection.downlinkTotal,
                        "createdAt" to connection.createdAt,
                        "closedAt" to connection.closedAt,
                        "processPath" to runCatching { connection.processInfo?.processPath }
                            .getOrNull(),
                        ),
                    )
                }
            } catch (e: Throwable) {
                Log.w(TAG, "snapshotConnections", e)
            }
        }
        return out
    }

    // ------------------------------------------------------------- فرمان‌ها

    fun selectOutbound(groupTag: String, outboundTag: String): Boolean =
        onClient { it.selectOutbound(groupTag, outboundTag) }

    fun urlTest(outboundTag: String): Boolean =
        onClient { it.urlTest(outboundTag) }

    fun closeConnection(id: String): Boolean =
        onClient { it.closeConnection(id) }

    fun closeConnections(): Boolean =
        onClient { it.closeConnections() }

    private inline fun onClient(block: (CommandClient) -> Unit): Boolean {
        val current = client
        if (current == null) {
            LibboxChannel.emitLog("libbox: command client is not connected")
            return false
        }
        return try {
            block(current)
            true
        } catch (e: Throwable) {
            Log.w(TAG, "command failed", e)
            LibboxChannel.emitLog("libbox: command failed: ${e.message}")
            false
        }
    }

    // --------------------------------------------- پیاده‌سازی CommandClientHandler
    //
    // این متدها از تردهای Go صدا زده می‌شوند، نه تردِ اصلیِ اندروید.

    override fun connected() {
        LibboxChannel.emitLog("libbox: command stream connected")
    }

    override fun disconnected(message: String?) {
        LibboxChannel.emitLog("libbox: command stream disconnected: $message")
    }

    override fun setDefaultLogLevel(level: Int) {
        defaultLogLevel = level
    }

    /** هسته لاگ‌ها را پاک کرده — معمولاً بعد از بارگذاریِ دوباره‌ی کانفیگ. */
    override fun clearLogs() {
        LibboxChannel.emitLogsCleared()
    }

    override fun writeLogs(messageList: LogIterator?) {
        val iterator = messageList ?: return
        try {
            while (true) {
                val entry = iterator.next() ?: break
                val text = entry.message ?: continue
                LibboxChannel.emitLogLine(entry.level, text)
            }
        } catch (e: Throwable) {
            Log.w(TAG, "writeLogs", e)
        }
    }

    override fun writeStatus(message: StatusMessage?) {
        val status = message ?: return
        trafficListener?.onTraffic(
            status.uplink,
            status.downlink,
            status.uplinkTotal,
            status.downlinkTotal,
        )
    }

    override fun writeGroups(message: OutboundGroupIterator?) {
        val iterator = message ?: return
        val parsed = ArrayList<GroupSnapshot>()
        try {
            while (true) {
                val group = iterator.next() ?: break
                val items = ArrayList<GroupItem>()
                val itemIterator = group.getItems()
                while (true) {
                    val item = itemIterator.next() ?: break
                    // gobind نامِ فيلدِ Go را دست‌نخورده مي‌گذارد:
                    //   URLTestDelay -> getURLTestDelay()
                    // (bind/genjava.go: public final native <T> get<Field>();)
                    // پس حتماً با حروفِ بزرگِ URL است، نه Url.
                    //
                    // هر کدام را جداگانه مي‌پوشانيم: اگر نام عوض شده باشد،
                    // تأخير از دست مي‌رود نه کلِ گروه.
                    val delay = runCatching { item.getURLTestDelay() }.getOrDefault(0)
                    val testedAt = runCatching { item.getURLTestTime() }.getOrDefault(0L)
                    items.add(
                        GroupItem(
                            item.tag ?: "",
                            item.type ?: "",
                            delay,
                            testedAt,
                        ),
                    )
                }
                parsed.add(
                    GroupSnapshot(
                        group.tag ?: "",
                        group.type ?: "",
                        group.selectable,
                        group.selected ?: "",
                        group.isExpand,
                        items,
                    ),
                )
            }
        } catch (e: Throwable) {
            Log.w(TAG, "writeGroups", e)
            return
        }
        synchronized(stateLock) { groups = parsed }
    }

    /**
     * رویدادهای اتصال.
     *
     * `Connections.ApplyEvents` خودش `reset` را هم مدیریت می‌کند (وقتی هسته
     * کانفیگ را دوباره بارگذاری کرده باشد).
     */
    override fun writeConnectionEvents(events: ConnectionEvents?) {
        val incoming = events ?: return
        synchronized(stateLock) {
            val holder = connections ?: return
            runCatching { holder.applyEvents(incoming) }
                .onFailure { Log.w(TAG, "applyEvents", it) }
        }
    }

    // ------------------------------------------- فرمانی که فعلاً استفاده نمی‌شود
    //
    // اینترفیسِ gomobile همه‌ی متدها را می‌خواهد، حتی اگر کاری نکنند.
    // `writeOutbounds` فهرستِ تختِ خروجی‌هاست؛ فعلاً به آن نیاز نداریم چون
    // گروه‌ها خودشان ایتم‌هایشان را دارند (با تأخیرِ تست).

    override fun writeOutbounds(message: OutboundGroupItemIterator?) = Unit

    override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) = Unit

    override fun updateClashMode(newMode: String?) = Unit
}

/**
 * قالب‌بندیِ اعدادِ ترافیک برای اعلان.
 *
 * یکاها با توانِ ۱۰۰۰ (نه ۱۰۲۴) — همان قراردادی که sing-box در API ی Clash
 * و اکثر کلاینت‌ها به کار می‌برند.
 */
object TrafficFormat {

    private const val K = 1000L
    private val UNITS = arrayOf("B", "KB", "MB", "GB", "TB")

    /** حجمِ تجمعی: «۱.۲ MB». */
    fun bytes(value: Long): String {
        if (value < 0) return "—"
        var amount = value.toDouble()
        var unit = 0
        while (amount >= K && unit < UNITS.lastIndex) {
            amount /= K.toDouble()
            unit++
        }
        val text = if (unit == 0 || amount >= 100) {
            amount.toStringAsFixed(0)
        } else {
            amount.toStringAsFixed(1)
        }
        return "$text ${UNITS[unit]}"
    }

    /** نرخ: «۱۲.۴ KB/s». */
    fun speed(bytesPerSecond: Long): String {
        if (bytesPerSecond <= 0) return "0 B/s"
        return "${bytes(bytesPerSecond)}/s"
    }

    private fun Double.toStringAsFixed(digits: Int): String =
        String.format(java.util.Locale.US, "%.${digits}f", this)
}
