package com.overx.overx

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/**
 * مدیریت «اجرا در شروع سیستم».
 *
 * با فعال شدن، کامپوننتِ BroadcastReceiver در مانیفست فعال می‌شود تا
 * پس از بوت شدن دستگاه برنامه اجرا شود.
 */
object BootReceiver {

    private const val PREFS = "overx_prefs"
    private const val KEY_AUTOSTART = "auto_start"

    fun setEnabled(context: Context, enable: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_AUTOSTART, enable)
            .apply()

        val component = ComponentName(context, StartOnBootReceiver::class.java)
        val state = if (enable) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        context.packageManager.setComponentEnabledSetting(
            component,
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_AUTOSTART, false)
}

/** واقعاً بعد از بوت صدا زده می‌شود (فقط وقتی فعال باشد). */
class StartOnBootReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!BootReceiver.isEnabled(context)) return

        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(launch)
    }
}
