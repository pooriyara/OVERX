package com.overx.overx

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import java.io.ByteArrayOutputStream
import java.util.Collections
import java.util.LinkedHashMap

/**
 * فهرست‌کردن برنامه‌های نصب‌شده برای «مسیریابیِ هر برنامه».
 *
 * خروجی برای دارت: لیستی از Map با کلیدهای
 * `packageName`، `label` و `isSystem`.
 */
object AppLister {

    private const val TAG = "AppLister"

    /** بسته‌هایی که نباید هرگز از VPN حذف شوند — حذفشان ارتباط را می‌بُرد. */
    private val PROTECTED = setOf(
        "com.overx.overx",
        "com.android.vending",   // Play Store
        "com.android.shell",
        "android",
    )

    fun list(context: Context, includeSystem: Boolean): List<Map<String, Any?>> {
        val pm = context.packageManager
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(0)
        }

        val result = ArrayList<Map<String, Any?>>(packages.size)
        for (info in packages) {
            val name = info.packageName ?: continue
            if (name in PROTECTED) continue

            val appInfo = info.applicationInfo
            val isSystem = appInfo != null &&
                (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (isSystem && !includeSystem) continue

            // برنامه‌هایی که آیکون/برچسب ندارند ارزش نمایش ندارند
            val label = try {
                appInfo?.loadLabel(pm)?.toString().orEmpty()
            } catch (e: Throwable) {
                ""
            }

            result.add(
                hashMapOf(
                    "packageName" to name,
                    "label" to if (label.isBlank()) name else label,
                    "isSystem" to isSystem,
                )
            )
        }

        // مرتب‌سازی بر اساس برچسب (بی‌توجه به بزرگی/کوچکی حروف)
        result.sortWith(compareBy(String.CASE_INSENSITIVE_ORDER) {
            it["label"] as? String ?: it["packageName"] as? String ?: ""
        })

        android.util.Log.d(TAG, "listing ${result.size} packages")
        return result
    }

    // ------------------------------------------------------------------ آیکون

    /**
     * حافظه‌ی نهانِ آیکون‌ها (کلید: «بسته@اندازه»).
     *
     * LRU یِ ساده با سقف ۱۹۲ ورودی؛ آیکونِ هر برنامه حدود ۲–۴ کیلوبایت PNG
     * است، یعنی سقفِ کش در بدترین حالت کمتر از یک مگابایت.
     */
    private val iconCache = Collections.synchronizedMap(
        object : LinkedHashMap<String, ByteArray>(64, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ByteArray>?): Boolean =
                size > 192
        }
    )

    /**
     * آیکونِ یک برنامه را به صورت PNG برمی‌گرداند، یا null اگر در دسترس نبود.
     *
     * [sizePx] اندازه‌ی مربعِ خروجی است (معمولاً ۶۴ برای کاشی‌های ۳۴dp).
     * خواندن از PackageManager شامل I/O است ← همیشه خارج از تردِ اصلی صدا
     * زده شود (نگاه کن به MainActivity).
     */
    fun icon(context: Context, packageName: String, sizePx: Int): ByteArray? {
        val key = "$packageName@$sizePx"
        iconCache[key]?.let { return it }

        val bytes = try {
            renderIcon(context, packageName, sizePx)
        } catch (e: Throwable) {
            android.util.Log.w(TAG, "icon failed for $packageName: ${e.message}")
            null
        }
        if (bytes != null) iconCache[key] = bytes
        return bytes
    }

    private fun renderIcon(context: Context, packageName: String, sizePx: Int): ByteArray? {
        val size = sizePx.coerceIn(16, 256)
        val drawable = try {
            context.packageManager.getApplicationIcon(packageName)
        } catch (e: Throwable) {
            null
        } ?: return null

        val bitmap = rasterize(drawable, size)
        val out = ByteArrayOutputStream(4096)
        val ok = bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return if (ok) out.toByteArray() else null
    }

    /**
     * Drawable را روی یک بیت‌مپِ شفاف می‌کشد.
     *
     * اگر خودش BitmapDrawable باشد، فقط تغییر اندازه می‌دهیم — وگرنه
     * (AdaptiveIconDrawable و غیره) روی Canvas رسم می‌کنیم. بیت‌مپِ مبدأ را
     * recycle نمی‌کنیم: ممکن است متعلق به کشِ خودِ PackageManager باشد.
     */
    private fun rasterize(drawable: Drawable, size: Int): Bitmap {
        if (drawable is BitmapDrawable) {
            val src = drawable.bitmap
            if (src.width == size && src.height == size) return src
            return Bitmap.createScaledBitmap(src, size, size, true)
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        return bitmap
    }
}
