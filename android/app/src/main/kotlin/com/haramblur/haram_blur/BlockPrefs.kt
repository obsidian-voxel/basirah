package com.haramblur.haram_blur

import android.content.Context
import android.preference.PreferenceManager
import org.json.JSONObject
import java.util.Calendar

/**
 * Persistence for the non-visual filters, written by Flutter and read by the
 * accessibility service on every window change.
 *
 * The service must keep blocking when the Flutter engine is dead, so nothing
 * here goes through Dart at runtime. Keys mirror `FilterStore` in Dart.
 */
object BlockPrefs {
    const val KEY_BLOCKED_APPS = "filter_blocked_apps"
    const val KEY_BLOCKED_DOMAINS = "filter_blocked_domains"
    const val KEY_URL_PATTERNS = "filter_blocked_url_patterns"
    const val KEY_KEYWORDS = "filter_blocked_keywords"
    const val KEY_BLOCK_NEW_APPS = "advanced_block_new_apps"
    const val KEY_BLOCK_NEW_BROWSERS = "advanced_block_new_browsers"
    const val KEY_BLOCK_UNSUPPORTED_BROWSERS = "advanced_block_unsupported_browsers"
    const val KEY_DAILY_AFFIRMATIONS = "advanced_daily_affirmations"
    private const val KEY_NEW_APPS_BASELINE = "advanced_new_apps_baseline"
    const val KEY_SCHEDULES = "filter_schedules"
    const val KEY_LIMITS = "filter_daily_limits"
    private const val KEY_USAGE_DATE = "filter_usage_date"
    private const val KEY_USAGE_SECONDS = "filter_usage_seconds"
    const val KEY_BLOCK_SPLIT_SCREEN = "advanced_block_split_screen"
    const val KEY_BLOCK_INCOGNITO = "advanced_block_incognito"
    const val KEY_BLOCK_INAPP_BROWSERS = "advanced_block_inapp_browsers"
    const val KEY_CROSS_BLOCK_LIMIT = "advanced_cross_block_limit"
    const val KEY_BLOCK_SCREEN_TITLE = "block_screen_title"
    const val KEY_BLOCK_SCREEN_MESSAGE = "block_screen_message"
    const val KEY_WHITELIST = "filter_whitelisted_apps"
    const val KEY_FOCUS_UNTIL = "focus_active_until"
    const val KEY_FOCUS_ALLOWED = "focus_allowed_apps"
    const val KEY_FOCUS_PREVENT_EXIT = "focus_prevent_exit"

    /** Domains that must never be blocked, checked before every site list. */
    const val KEY_ALLOWLISTED_DOMAINS = "filter_allowlisted_domains"

    /** Keywords matched only as whole words, never inside a longer word. */
    const val KEY_WHOLEWORD_KEYWORDS = "filter_blocked_keywords_wholeword"

    /** Apps where the in-app browser rule applies; empty means every app. */
    const val KEY_INAPP_BROWSER_APPS = "advanced_inapp_browser_apps"

    /** Leave Android's Settings screens that would disable protection. */
    const val KEY_GUARD_SETTINGS = "advanced_guard_settings"

    const val KEY_PRAYER_ENABLED = "advanced_prayer_blocking"
    const val KEY_PRAYER_LATITUDE = "prayer_latitude"
    const val KEY_PRAYER_LONGITUDE = "prayer_longitude"
    const val KEY_PRAYER_MINUTES = "prayer_minutes_after"
    const val KEY_PRAYER_METHOD = "prayer_method"

    /** Browsers installed when "block new browsers" was switched on. */
    private const val KEY_NEW_BROWSERS_BASELINE = "advanced_new_browsers_baseline"

    private fun prefs(context: Context) =
        PreferenceManager.getDefaultSharedPreferences(context)

    fun blockedApps(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_BLOCKED_APPS, null) ?: emptySet()

    fun keywords(context: Context): List<String> = lines(context, KEY_KEYWORDS)

    /** Domains the user added themselves; the bundled list is in [AdultDomainIndex]. */
    fun domains(context: Context): List<String> = lines(context, KEY_BLOCKED_DOMAINS)

    /** Bundled adult URL patterns; matched against the URL only. */
    fun urlPatterns(context: Context): List<String> = lines(context, KEY_URL_PATTERNS)

    /**
     * Sites the user trusts. Checked before the custom list, the bundled
     * 952k index and the URL patterns, because a hash index has no way to
     * express "except this one".
     */
    fun allowlistedDomains(context: Context): List<String> =
        lines(context, KEY_ALLOWLISTED_DOMAINS)

    fun writeAllowlistedDomains(context: Context, domains: Collection<String>) =
        writeLines(context, KEY_ALLOWLISTED_DOMAINS, domains.map { it.trim().lowercase() })

    /** Keywords that only match as whole words. */
    fun wholeWordKeywords(context: Context): List<String> =
        lines(context, KEY_WHOLEWORD_KEYWORDS)

    fun writeWholeWordKeywords(context: Context, keywords: Collection<String>) =
        writeLines(context, KEY_WHOLEWORD_KEYWORDS, keywords.map { it.trim() })

    /** Apps where in-app browsers are blocked; empty means all of them. */
    fun inAppBrowserApps(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_INAPP_BROWSER_APPS, null) ?: emptySet()

    fun writeInAppBrowserApps(context: Context, packages: Collection<String>) {
        prefs(context).edit()
            .putStringSet(
                KEY_INAPP_BROWSER_APPS,
                packages.map { it.trim() }.filter { it.isNotEmpty() }.toSet(),
            )
            .apply()
    }

    /** Snapshot of the browsers present when the guard was switched on. */
    fun browserBaseline(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_NEW_BROWSERS_BASELINE, null) ?: emptySet()

    fun captureBrowserBaseline(context: Context, packages: Collection<String>) {
        prefs(context).edit()
            .putStringSet(KEY_NEW_BROWSERS_BASELINE, packages.toSet())
            .apply()
    }

    /** Add one app to both baselines, so the user can vouch for an app. */
    fun trustPackage(context: Context, packageName: String) {
        val launchable = baseline(context).toMutableSet()
        launchable.add(packageName)
        prefs(context).edit()
            .putStringSet(KEY_NEW_APPS_BASELINE, launchable)
            .apply()
        val browsers = browserBaseline(context).toMutableSet()
        browsers.add(packageName)
        prefs(context).edit()
            .putStringSet(KEY_NEW_BROWSERS_BASELINE, browsers)
            .apply()
    }

    /** True when leaving Android's own app/accessibility screens is guarded. */
    fun guardSettings(context: Context): Boolean =
        prefs(context).getBoolean(KEY_GUARD_SETTINGS, true)

    fun prayerEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_PRAYER_ENABLED, false)

    fun prayerLatitude(context: Context): Double =
        prefs(context).getFloat(KEY_PRAYER_LATITUDE, Float.NaN).toDouble()

    fun prayerLongitude(context: Context): Double =
        prefs(context).getFloat(KEY_PRAYER_LONGITUDE, Float.NaN).toDouble()

    /** Minutes the block lasts after each prayer begins. */
    fun prayerMinutesAfter(context: Context): Int =
        prefs(context).getInt(KEY_PRAYER_MINUTES, 15)

    fun prayerMethod(context: Context): String? =
        prefs(context).getString(KEY_PRAYER_METHOD, null)

    fun writePrayer(
        context: Context,
        enabled: Boolean,
        latitude: Double?,
        longitude: Double?,
        minutesAfter: Int,
        method: String?,
    ) {
        val editor = prefs(context).edit()
        editor.putBoolean(KEY_PRAYER_ENABLED, enabled)
        if (latitude != null && !latitude.isNaN()) {
            editor.putFloat(KEY_PRAYER_LATITUDE, latitude.toFloat())
        }
        if (longitude != null && !longitude.isNaN()) {
            editor.putFloat(KEY_PRAYER_LONGITUDE, longitude.toFloat())
        }
        editor.putInt(KEY_PRAYER_MINUTES, minutesAfter.coerceIn(1, 120))
        if (method.isNullOrBlank()) {
            editor.remove(KEY_PRAYER_METHOD)
        } else {
            editor.putString(KEY_PRAYER_METHOD, method)
        }
        editor.apply()
    }

    private fun lines(context: Context, key: String): List<String> {
        val raw = prefs(context).getString(key, null) ?: return emptyList()
        if (raw.isEmpty()) return emptyList()
        return raw.split('\n').filter { it.isNotBlank() }
    }

    fun writeDomains(context: Context, domains: Collection<String>) =
        writeLines(context, KEY_BLOCKED_DOMAINS, domains.map { it.trim().lowercase() })

    fun writeUrlPatterns(context: Context, patterns: Collection<String>) =
        writeLines(context, KEY_URL_PATTERNS, patterns.map { it.trim().lowercase() })

    /** One entry per line; duplicates dropped so the encoding stays compact. */
    private fun writeLines(context: Context, key: String, entries: Collection<String>) {
        val encoded = entries
            .map { it.replace('\n', ' ') }
            .filter { it.isNotEmpty() }
            .toSet()
            .joinToString("\n")
        prefs(context).edit().putString(key, encoded).apply()
    }

    /**
     * Returns the configured domain that owns [url]'s host, or null. Suffix
     * matching means `pornhub.com` also blocks `de.pornhub.com` without each
     * subdomain having to be listed.
     */
    fun matchingDomain(domains: List<String>, url: String): String? {
        if (url.isEmpty() || domains.isEmpty()) return null
        val host = hostOf(url)
        if (host.isEmpty()) return null
        for (domain in domains) {
            if (host == domain || host.endsWith(".$domain")) return domain
        }
        return null
    }

    /** Host of [url], or '' when it has none. Mirrors `hostOf` in Dart. */
    fun hostOf(url: String): String {
        var value = url.trim().lowercase()
        val scheme = value.indexOf("://")
        if (scheme >= 0) value = value.substring(scheme + 3)
        value = value.substringBefore('/').substringBefore('?').substringBefore('#')
        val at = value.lastIndexOf('@')
        if (at >= 0) value = value.substring(at + 1)
        val colon = value.lastIndexOf(':')
        if (colon >= 0) value = value.substring(0, colon)
        return normalizeHost(value)
    }

    /**
     * Canonical host form, so one site cannot dodge the list with spelling:
     *  - a trailing dot (`pornhub.com.`) is a valid absolute name;
     *  - percent escapes (`porn%68ub.com`) reach the server as plain bytes;
     *  - a Unicode host is stored in the index as punycode (`xn--...`).
     *
     * A numeric IPv4 host is left alone: it is an address, not a domain, and
     * no entry in a domain list can ever match it.
     */
    fun normalizeHost(raw: String): String {
        var value = raw.trim().trim('.').lowercase()
        if (value.isEmpty()) return ""
        if (value.contains('%')) {
            value = try {
                // URLDecoder turns '+' into a space; a host never contains one.
                java.net.URLDecoder.decode(value.replace("+", "%2B"), "UTF-8")
            } catch (_: Throwable) {
                value
            }
        }
        value = value.trimEnd('.')
        if (value.isEmpty()) return ""
        if (value.any { it.code > 0x7f }) {
            value = try {
                java.net.IDN.toASCII(value, java.net.IDN.ALLOW_UNASSIGNED)
                    .lowercase()
            } catch (_: Throwable) {
                value
            }
        }
        return value
    }

    /** True when [host] is an IPv4 literal, including one-part numeric forms. */
    fun isIpLiteral(host: String): Boolean {
        if (host.isEmpty()) return false
        val parts = host.split('.')
        if (parts.size > 4) return false
        return parts.all { part ->
            part.isNotEmpty() && (
                part.all { it.isDigit() } ||
                    (part.startsWith("0x", true) && part.length > 2 &&
                        part.drop(2).all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' })
                )
        }
    }

    fun flag(context: Context, key: String, fallback: Boolean = false): Boolean =
        prefs(context).getBoolean(key, fallback)

    /** Baseline of packages installed when "block new apps" was switched on. */
    fun baseline(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_NEW_APPS_BASELINE, null) ?: emptySet()

    fun writeAdvanced(context: Context, raw: Map<*, *>?) {
        if (raw == null) return
        val editor = prefs(context).edit()
        fun bool(key: String, arg: String) {
            val value = raw[arg] as? Boolean ?: return
            editor.putBoolean(key, value)
        }
        bool(KEY_BLOCK_NEW_APPS, "blockNewApps")
        bool(KEY_BLOCK_NEW_BROWSERS, "blockNewBrowsers")
        bool(KEY_BLOCK_UNSUPPORTED_BROWSERS, "blockUnsupportedBrowsers")
        bool(KEY_DAILY_AFFIRMATIONS, "dailyAffirmations")
        bool(KEY_BLOCK_SPLIT_SCREEN, "blockSplitScreen")
        bool(KEY_BLOCK_INCOGNITO, "blockIncognito")
        bool(KEY_BLOCK_INAPP_BROWSERS, "blockInAppBrowsers")
        bool(KEY_CROSS_BLOCK_LIMIT, "crossBlockLimit")
        editor.apply()
    }

    /**
     * User copy for the block screen. Blank values fall back to the shipped
     * wording, so clearing the field restores it.
     */
    fun screenTitle(context: Context): String? =
        prefs(context).getString(KEY_BLOCK_SCREEN_TITLE, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

    fun screenMessage(context: Context): String? =
        prefs(context).getString(KEY_BLOCK_SCREEN_MESSAGE, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

    fun writeScreen(context: Context, title: String?, message: String?) {
        val editor = prefs(context).edit()
        val cleanTitle = title?.trim().orEmpty()
        val cleanMessage = message?.trim().orEmpty()
        if (cleanTitle.isEmpty()) {
            editor.remove(KEY_BLOCK_SCREEN_TITLE)
        } else {
            editor.putString(KEY_BLOCK_SCREEN_TITLE, cleanTitle.take(80))
        }
        if (cleanMessage.isEmpty()) {
            editor.remove(KEY_BLOCK_SCREEN_MESSAGE)
        } else {
            editor.putString(KEY_BLOCK_SCREEN_MESSAGE, cleanMessage.take(280))
        }
        editor.apply()
    }

    /** Apps the user allows even though they are on the blocklist. */
    fun whitelist(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_WHITELIST, null) ?: emptySet()

    fun writeWhitelist(context: Context, packages: Collection<String>) {
        prefs(context).edit()
            .putStringSet(KEY_WHITELIST, packages.map { it.trim() }.filter { it.isNotEmpty() }.toSet())
            .apply()
    }

    /** Epoch milliseconds until which focus mode runs; 0 when idle. */
    fun focusActiveUntil(context: Context): Long =
        prefs(context).getLong(KEY_FOCUS_UNTIL, 0L)

    /** Apps that stay reachable during a focus session. */
    fun focusAllowedApps(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_FOCUS_ALLOWED, null) ?: emptySet()

    fun focusPreventExit(context: Context): Boolean =
        prefs(context).getBoolean(KEY_FOCUS_PREVENT_EXIT, false)

    fun writeFocus(
        context: Context,
        activeUntil: Long,
        allowedApps: Collection<String>,
        preventExit: Boolean,
    ) {
        prefs(context).edit()
            .putLong(KEY_FOCUS_UNTIL, activeUntil)
            .putStringSet(
                KEY_FOCUS_ALLOWED,
                allowedApps.map { it.trim() }.filter { it.isNotEmpty() }.toSet(),
            )
            .putBoolean(KEY_FOCUS_PREVENT_EXIT, preventExit)
            .apply()
    }

    /** True while a focus session is running. */
    fun focusActive(context: Context, now: Long = System.currentTimeMillis()): Boolean =
        focusActiveUntil(context) > now

    /**
     * Snapshots today's launcher apps so anything installed later can be
     * recognised. Called when the user switches "block new apps" on.
     */
    fun captureBaseline(context: Context, packages: Collection<String>) {
        prefs(context).edit()
            .putStringSet(KEY_NEW_APPS_BASELINE, packages.toSet())
            .apply()
    }

    fun writeBlockedApps(context: Context, packages: Collection<String>) {
        prefs(context).edit()
            .putStringSet(KEY_BLOCKED_APPS, packages.map { it.trim() }.toSet())
            .apply()
    }

    /** One keyword per line; newlines are stripped so the encoding is stable. */
    fun writeKeywords(context: Context, keywords: Collection<String>) =
        writeLines(context, KEY_KEYWORDS, keywords.map { it.trim() })

    /** `package -> [startMinute, endMinute]`. */
    fun schedules(context: Context): Map<String, IntArray> {
        val raw = prefs(context).getString(KEY_SCHEDULES, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            val out = HashMap<String, IntArray>()
            for (key in json.keys()) {
                val window = json.optJSONObject(key) ?: continue
                if (!window.has("start") || !window.has("end")) continue
                out[key] = intArrayOf(window.optInt("start"), window.optInt("end"))
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun writeSchedules(context: Context, raw: Map<*, *>?) {
        val json = JSONObject()
        raw?.forEach { entry, value ->
            val packageName = entry as? String ?: return@forEach
            if (value !is List<*> || value.size < 2) return@forEach
            val start = (value[0] as? Number)?.toInt() ?: return@forEach
            val end = (value[1] as? Number)?.toInt() ?: return@forEach
            json.put(
                packageName,
                JSONObject().put("start", start.coerceIn(0, 1439))
                    .put("end", end.coerceIn(0, 1439)),
            )
        }
        prefs(context).edit().putString(KEY_SCHEDULES, json.toString()).apply()
    }

    /** `package -> minutes per day`. */
    fun limits(context: Context): Map<String, Int> {
        val raw = prefs(context).getString(KEY_LIMITS, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            val out = HashMap<String, Int>()
            for (key in json.keys()) {
                val minutes = json.optInt(key, 0)
                if (minutes > 0) out[key] = minutes
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun writeLimits(context: Context, raw: Map<*, *>?) {
        val json = JSONObject()
        raw?.forEach { entry, value ->
            val packageName = entry as? String ?: return@forEach
            val minutes = (value as? Number)?.toInt() ?: return@forEach
            if (minutes > 0) json.put(packageName, minutes)
        }
        prefs(context).edit().putString(KEY_LIMITS, json.toString()).apply()
    }

    /**
     * True when [now] is inside the allowed window. Equal endpoints mean "no
     * restriction"; start > end wraps midnight (mirrors `ScheduleWindow` in
     * Dart, which the unit tests pin).
     */
    fun withinWindow(window: IntArray, now: Calendar = Calendar.getInstance()): Boolean {
        if (window.size < 2) return true
        val start = window[0]
        val end = window[1]
        if (start == end) return true
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return if (start < end) {
            minute in start until end
        } else {
            minute >= start || minute < end
        }
    }

    fun windowLabel(window: IntArray): String {
        fun clock(minute: Int) =
            "%02d:%02d".format(minute / 60, minute % 60)
        return "${clock(window[0])}–${clock(window[1])}"
    }

    // ------------------------------------------------------------------
    // Daily usage (resets at midnight because the date key changes)
    // ------------------------------------------------------------------

    fun usedSeconds(context: Context, packageName: String): Int {
        val usage = todayUsage(context, Calendar.getInstance())
        return usage.optInt(packageName, 0)
    }

    fun usageToday(context: Context): Map<String, Int> {
        val usage = todayUsage(context, Calendar.getInstance())
        val out = HashMap<String, Int>()
        for (key in usage.keys()) out[key] = usage.optInt(key, 0)
        return out
    }

    /** Adds foreground seconds and writes the counter back. */
    @Synchronized
    fun addUsage(context: Context, packageName: String, seconds: Int) {
        if (seconds <= 0) return
        val now = Calendar.getInstance()
        val usage = todayUsage(context, now)
        usage.put(packageName, usage.optInt(packageName, 0) + seconds)
        prefs(context).edit()
            .putString(KEY_USAGE_DATE, dayKey(now))
            .putString(KEY_USAGE_SECONDS, usage.toString())
            .apply()
    }

    /**
     * Usage for today. A counter written on another day is discarded here, so
     * the reset needs no scheduled job.
     */
    private fun todayUsage(context: Context, now: Calendar): JSONObject {
        val storedDate = prefs(context).getString(KEY_USAGE_DATE, null)
        if (storedDate != dayKey(now)) return JSONObject()
        val raw = prefs(context).getString(KEY_USAGE_SECONDS, null) ?: return JSONObject()
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            JSONObject()
        }
    }

    /** `YYYY-MM-DD` for [now]; the key that makes usage reset at midnight. */
    fun dayKey(now: Calendar = Calendar.getInstance()): String =
        "%04d-%02d-%02d".format(
            now.get(Calendar.YEAR),
            now.get(Calendar.MONTH) + 1,
            now.get(Calendar.DAY_OF_MONTH),
        )
}
