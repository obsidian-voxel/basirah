package com.haramblur.haram_blur

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Device administration receiver (anti-bypass).
 *
 * Prevents easy uninstall / tampering while device admin is active. The user
 * must activate it in Settings → Security → Device admin apps.
 */
class DeviceAdmin : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        // Audited, not assumed: the UI and the log both show the transition
        // Android just performed.
        SecurityAudit.check(context, "device-admin-enabled")
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Basirah can be uninstalled in one step without device admin, " +
            "which turns screen protection off. Keep it active unless you are " +
            "removing the app."

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        // App can't re-enable itself; the audit entry plus the UI warning are
        // how the user learns removal protection is gone.
        SecurityAudit.check(context, "device-admin-disabled")
    }
}
