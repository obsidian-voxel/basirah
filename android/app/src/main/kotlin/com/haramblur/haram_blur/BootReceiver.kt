package com.haramblur.haram_blur

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.preference.PreferenceManager
import android.util.Log

/**
 * Android cannot re-enable an accessibility service by itself after a reboot,
 * so instead of yanking the user into the app (which used to happen from the
 * background, a restricted and jarring behaviour) this posts a notification
 * when protection was left on but the service is no longer enabled.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        val protection = prefs.getBoolean(MainActivity.KEY_PROTECTION_ENABLED, false)
        // One shared implementation: the activity, the service and this
        // receiver must never disagree about whether accessibility is enabled.
        val accessibility = ProtectionHealth.isAccessibilityEnabled(context)
        // Anchors the reboot-recovery row on the dashboard and audits the boot.
        ProtectionHealth.onBoot(context)
        // Timeline anchor for the reboot path: this is the first code the app
        // runs after a boot, and it names both flags without any content.
        Log.i("HaramBlur", "Lifecycle: BOOT_RECEIVED protection=$protection accessibility=$accessibility")
        if (!protection) return
        if (accessibility) return

        notifyProtectionOff(context)
    }

    private fun notifyProtectionOff(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        val channelId = "protection_status"
        manager.createNotificationChannel(
            NotificationChannel(
                channelId,
                "Protection status",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Reminds you when screen protection needs re-enabling."
            }
        )

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = Notification.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Basirah is off")
            .setContentText("Android disabled screen protection after the restart. Tap to restore it.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()

        try {
            manager.notify(1001, notification)
        } catch (_: SecurityException) {
            // Notification permission not granted; nothing else to do here.
        }
    }
}
