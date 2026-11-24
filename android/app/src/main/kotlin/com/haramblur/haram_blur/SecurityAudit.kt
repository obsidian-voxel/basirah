package com.haramblur.haram_blur

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.preference.PreferenceManager
import org.json.JSONArray
import org.json.JSONObject

/**
 * Security audit trail: device-admin transitions, Settings escapes and
 * package installs.
 *
 * Uninstall protection is only worth claiming if its state is observable, so
 * every change is recorded once (not on every poll) and the log is readable
 * from Settings and from the Flutter bridge. Stored locally, newest last, and
 * capped like [EventLog].
 */
object SecurityAudit {
    private const val KEY = "hb_security_audit"
    private const val KEY_ADMIN_STATE = "hb_security_admin_state"
    private const val MAX_EVENTS = 100

    private fun prefs(context: Context) =
        PreferenceManager.getDefaultSharedPreferences(context)

    /**
     * Appends one entry. [event] is a stable wire name (`device_admin`,
     * `settings_escape`, `package_installed`); [detail] is short context.
     */
    @Synchronized
    fun record(context: Context, event: String, detail: String = "") {
        val array = load(context)
        array.put(
            JSONObject()
                .put("t", System.currentTimeMillis())
                .put("e", event)
                .put("d", detail.take(160)),
        )
        while (array.length() > MAX_EVENTS) array.remove(0)
        prefs(context).edit().putString(KEY, array.toString()).apply()
    }

    /** True when Android reports Basirah as an active device admin. */
    fun isAdminActive(context: Context): Boolean = try {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        dpm.isAdminActive(ComponentName(context, DeviceAdmin::class.java))
    } catch (_: Throwable) {
        false
    }

    /**
     * Records the current admin state only when it differs from the last known
     * one. Called on service connect and from the UI, so the log shows real
     * transitions instead of one entry per poll.
     */
    @Synchronized
    fun check(context: Context, source: String) {
        val active = isAdminActive(context)
        val stored = prefs(context).getString(KEY_ADMIN_STATE, null)
        val current = if (active) "on" else "off"
        if (stored == current) return
        prefs(context).edit().putString(KEY_ADMIN_STATE, current).apply()
        record(
            context,
            "device_admin",
            if (active) "enabled ($source)" else "not active ($source)",
        )
    }

    /** Newest last, at most [limit] entries, in the map shape Dart decodes. */
    @Synchronized
    fun read(context: Context, limit: Int = 20): List<Map<String, Any?>> {
        val array = load(context)
        val start = maxOf(0, array.length() - limit)
        val out = ArrayList<Map<String, Any?>>(array.length() - start)
        for (i in start until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "t" to obj.optLong("t"),
                    "event" to obj.optString("e", "unknown"),
                    "detail" to obj.optString("d", ""),
                ),
            )
        }
        return out
    }

    @Synchronized
    fun clear(context: Context) {
        prefs(context).edit().remove(KEY).apply()
    }

    private fun load(context: Context): JSONArray {
        val raw = prefs(context).getString(KEY, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }
}
