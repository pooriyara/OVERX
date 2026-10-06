package com.overx.overx

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * آماده‌سازی باینری‌های هسته در اولین اجرا.
 *
 * چرا لازم است؟
 * فایل‌های `.so` داخل APK توسط سیستم **غیرقابل‌اجرا** extract می‌شوند
 * (extractNativeLibs). پس نمی‌توان مستقیماً `libxray.so` را اجرا کرد؛
 * باید آن را به حافظه‌ی داخلی کپی و `chmod +x` کرد.
 *
 * خروجی: نگاشتی از نام هسته به مسیر فایلِ آمادهٔ اجرا، مثلاً
 * `{ "xray": "/data/data/com.overx.overx/files/bin/xray" }`.
 */
object BinaryInstaller {

    private const val TAG = "BinaryInstaller"
    private const val DIR = "bin"

    /** فایل‌هایی که همراه برنامه در jniLibs می‌آیند. */
    private val CORES = mapOf(
        "xray" to "libxray.so",
        "singbox" to "libsingbox.so",
    )

    fun install(context: Context): Map<String, String> {
        val nativeDir = File(context.applicationInfo.nativeLibraryDir)
        val outDir = File(context.filesDir, DIR)
        if (!outDir.exists() && !outDir.mkdirs()) {
            Log.e(TAG, "cannot create ${outDir.path}")
            return emptyMap()
        }

        val installed = LinkedHashMap<String, String>()

        for ((coreName, libName) in CORES) {
            val source = File(nativeDir, libName)
            if (!source.exists()) {
                Log.d(TAG, "$libName not bundled — skipping")
                continue
            }
            val target = File(outDir, coreName)
            try {
                // کپیِ دوباره در هر اتصال یعنی جابه‌جاییِ ده‌ها مگابایت
                // بی‌دلیل؛ اگر قبلاً نصب شده و اندازه یکی است، رد می‌شویم.
                if (target.exists() &&
                    target.canExecute() &&
                    target.length() == source.length()
                ) {
                    installed[coreName] = target.absolutePath
                    Log.d(TAG, "$coreName already installed")
                    continue
                }
                copy(source, target)
                if (!target.setExecutable(true, true)) {
                    Log.w(TAG, "could not chmod +x ${target.path}")
                }
                installed[coreName] = target.absolutePath
                Log.i(TAG, "installed $coreName → ${target.absolutePath}")
            } catch (e: Throwable) {
                Log.e(TAG, "failed to install $coreName", e)
            }
        }
        return installed
    }

    private fun copy(source: File, target: File) {
        // ابتدا کنار یک فایل موقت می‌نویسیم تا نیمه‌کاره نماند
        val tmp = File(target.parentFile, "${target.name}.tmp")
        source.inputStream().use { input ->
            FileOutputStream(tmp).use { output ->
                input.copyTo(output, bufferSize = 128 * 1024)
            }
        }
        if (target.exists()) target.delete()
        if (!tmp.renameTo(target)) {
            tmp.copyTo(target, overwrite = true)
            tmp.delete()
        }
    }
}
