package com.haramblur.haram_blur

import android.content.Context
import android.preference.PreferenceManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Small persistent log of blurs produced by the accessibility service.
 *
 * Stored as a JSON array under a single SharedPreferences key (newest last,
 * capped at [MAX_EVENTS]) and read back by [MainActivity] for the Flutter
 * history. Keys are short (`t`, `p`, `r`, `c`) to keep the stored blob small.
 */
object EventLog {
    private const val KEY = "hb_events"
    private const val MAX_EVENTS = 200

    private fun prefs(context: Context) =
        PreferenceManager.getDefaultSharedPreferences(context)

    @Synchronized
    fun append(
        context: Context,
        packageName: String,
        reason: String,
        confidence: Double,
        metric: Double? = null,
    ) {
        val array = load(context)
        val entry = JSONObject()
            .put("t", System.currentTimeMillis())
            .put("p", packageName)
            .put("r", reason)
            .put("c", confidence.coerceIn(0.0, 1.0))
        if (metric != null) entry.put("m", metric)
        array.put(entry)
        while (array.length() > MAX_EVENTS) {
            array.remove(0)
        }
        prefs(context).edit().putString(KEY, array.toString()).apply()
    }

    /** Newest last, at most [limit] entries, in the map shape Dart decodes. */
    @Synchronized
    fun read(context: Context, limit: Int): List<Map<String, Any?>> {
        val array = load(context)
        val start = maxOf(0, array.length() - limit)
        val out = ArrayList<Map<String, Any?>>(array.length() - start)
        for (i in start until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "t" to obj.optLong("t"),
                    "p" to obj.optString("p", "unknown"),
                    "r" to obj.optString("r", "nsfw"),
                    "c" to obj.optDouble("c", 0.0),
                    "m" to if (obj.has("m")) obj.optDouble("m", 0.0) else null,
                )
            )
        }
        return out
    }

    @Synchronized
    fun countToday(context: Context): Int {
        val array = load(context)
        var count = 0
        for (i in 0 until array.length()) {
            val timestamp = array.optJSONObject(i)?.optLong("t") ?: continue
            if (isToday(timestamp)) count++
        }
        return count
    }

    @Synchronized
    fun countTotal(context: Context): Int = load(context).length()

    @Synchronized
    fun clear(context: Context) {
        prefs(context).edit().remove(KEY).apply()
    }

    private fun load(context: Context): JSONArray {
        val raw = prefs(context).getString(KEY, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            // A truncated write must not break the capture loop.
            JSONArray()
        }
    }

    private fun isToday(timestamp: Long): Boolean {
        val then = Calendar.getInstance().apply { timeInMillis = timestamp }
        val now = Calendar.getInstance()
        return then.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
            then.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
    }
}
