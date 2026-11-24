package com.haramblur.haram_blur

import android.content.ComponentName
import android.content.Context
import android.preference.PreferenceManager
import android.provider.Settings
import android.util.Log

/**
 * Anti-tamper monitoring and the honest protection report.
 *
 * The report is built from observable state only: the accessibility grant,
 * whether Android has the service bound, detector readiness, the last rule
 * scan, and every Device Owner policy read back from Android. Anything Android
 * does not expose to an ordinary application is absent rather than guessed.
 *
 * State transitions are recorded once, in [SecurityAudit], so the audit trail
 * shows real changes instead of one entry per poll. Everything stays in this
 * app's private preferences: no telemetry, no network.
 */
object ProtectionHealth {

    private const val TAG = "HaramBlur"

    private const val KEY_REQUESTED_TIER = "hb_protection_tier"
    private const val KEY_LAST_SCAN = "hb_last_scan_at"
    private const val KEY_LAST_CONNECT = "hb_last_service_connect_at"
    private const val KEY_LAST_BOOT = "hb_last_boot_at"
    private const val KEY_BOOT_RECOVERED = "hb_boot_recovered_at"
    private const val KEY_MATCHER_READY = "hb_matcher_ready"
    private const val KEY_LAST_HEALTH = "hb_last_health"
    private const val KEY_POLICY_SIGNATURE = "hb_policy_signature"
    private const val KEY_ACCESSIBILITY = "hb_accessibility_granted"
    private const val KEY_OWNER = "hb_device_owner"
    private const val KEY_DETECTOR_ERROR = "hb_detector_error"
    private const val KEY_LAST_INTERRUPT = "hb_last_service_interrupt_at"

    /** Scans happen about once a second; the timestamp is not rewritten that often. */
    private const val SCAN_STAMP_INTERVAL_MS = 10_000L

    /** A reconnect within this window of a boot counts as reboot recovery. */
    private const val BOOT_RECOVERY_WINDOW_MS = 10 * 60_000L

    /** A rebind storm must not fill the audit with identical entries. */
    private const val INTERRUPT_QUIET_MS = 60_000L

    private fun prefs(context: Context) =
        PreferenceManager.getDefaultSharedPreferences(context)

    // ------------------------------------------------------------------
    // Protection mode
    // ------------------------------------------------------------------

    /** The tier the user asked for; it is not necessarily the effective one. */
    fun requestedTier(context: Context): PolicyEvaluator.Tier =
        PolicyEvaluator.Tier.fromWire(prefs(context).getString(KEY_REQUESTED_TIER, null))

    fun setRequestedTier(context: Context, tier: PolicyEvaluator.Tier) {
        prefs(context).edit().putString(KEY_REQUESTED_TIER, tier.wire).apply()
    }

    /** Hardened only when Android reports the Device Owner; never inferred. */
    fun effectiveTier(context: Context): PolicyEvaluator.Tier =
        PolicyEvaluator.effectiveTier(
            requestedTier(context),
            DeviceOwner.isDeviceOwner(context),
        )

    // ------------------------------------------------------------------
    // Observable state, also used by BootReceiver and MainActivity
    // ------------------------------------------------------------------

    /**
     * Android exposes enabled accessibility services as a `:`-separated list of
     * flattened component names. Compare both forms so this works across OEMs.
     */
    fun isAccessibilityEnabled(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val component = ComponentName(context, SystemWideBlurService::class.java)
        return enabled.split(':').any {
            it.equals(component.flattenToString(), true) ||
                it.equals(component.flattenToShortString(), true)
        }
    }

    // ------------------------------------------------------------------
    // Lifecycle hooks called by the service, the receiver and the activity
    // ------------------------------------------------------------------

    fun onBoot(context: Context) {
        val store = prefs(context)
        val previousBoot = store.getLong(KEY_LAST_BOOT, 0L)
        store.edit()
            .putLong(KEY_LAST_BOOT, System.currentTimeMillis())
            .putBoolean(KEY_MATCHER_READY, false)
            .apply()
        if (previousBoot > 0) {
            Log.i(TAG, "Lifecycle: BOOT_RECEIVED previous_boot=$previousBoot")
        }
        SecurityAudit.record(context, "reboot", "device started; protection re-arms on unlock")
    }

    fun onServiceConnected(context: Context) {
        val now = System.currentTimeMillis()
        val store = prefs(context)
        val bootAt = store.getLong(KEY_LAST_BOOT, 0L)
        val recoveredFor = store.getLong(KEY_BOOT_RECOVERED, 0L)
        store.edit()
            .putLong(KEY_LAST_CONNECT, now)
            .putBoolean(KEY_MATCHER_READY, true)
            .apply()
        SecurityAudit.check(context, "service-connected")
        // The service only starts after the user unlocks, so a reconnect inside
        // this window is what "protection came back after a restart" looks like.
        if (bootAt > 0 &&
            recoveredFor != bootAt &&
            now - bootAt in 1..BOOT_RECOVERY_WINDOW_MS
        ) {
            store.edit().putLong(KEY_BOOT_RECOVERED, bootAt).apply()
            SecurityAudit.record(
                context,
                "reboot_recovery",
                "accessibility service connected after a restart",
            )
        }
    }

    /** True when Android took the service away while protection was on. */
    fun onServiceUnbound(context: Context) {
        val store = prefs(context)
        if (!store.getBoolean(MainActivity.KEY_PROTECTION_ENABLED, false)) return
        val now = System.currentTimeMillis()
        if (now - store.getLong(KEY_LAST_INTERRUPT, 0L) < INTERRUPT_QUIET_MS) return
        store.edit().putLong(KEY_LAST_INTERRUPT, now).apply()
        SecurityAudit.record(
            context,
            "service_interrupted",
            "Android unbound the accessibility service",
        )
    }

    /** Records the first scan of every edit without one entry per window event. */
    fun markScan(context: Context) {
        val store = prefs(context)
        val now = System.currentTimeMillis()
        if (now - store.getLong(KEY_LAST_SCAN, 0L) < SCAN_STAMP_INTERVAL_MS) return
        store.edit().putLong(KEY_LAST_SCAN, now).apply()
    }

    /** A detector that never starts is degraded protection, not silence. */
    fun onDetectorState(context: Context, ready: Boolean, error: String?) {
        val store = prefs(context)
        val stored = store.getString(KEY_DETECTOR_ERROR, null)
        if (error == null) {
            if (stored != null) {
                store.edit().remove(KEY_DETECTOR_ERROR).apply()
                SecurityAudit.record(context, "detector_recovered", "the visual detector is running")
            }
            return
        }
        if (stored == error) return
        store.edit().putString(KEY_DETECTOR_ERROR, error).apply()
        SecurityAudit.record(context, "detector_failed", error.take(120))
        if (!ready) Log.w(TAG, "Protection: visual detector degraded")
    }

    /** The stored detector failure, for the report (null when healthy). */
    fun detectorFailure(context: Context): String? =
        prefs(context).getString(KEY_DETECTOR_ERROR, null)

    // ------------------------------------------------------------------
    // The report shown by the protection dashboard
    // ------------------------------------------------------------------

    fun report(context: Context, service: SystemWideBlurService?): Map<String, Any?> {
        val store = prefs(context)
        val requested = requestedTier(context)
        val owner = DeviceOwner.isDeviceOwner(context)
        val adminActive = DeviceOwner.isAdminActive(context)
        val tier = PolicyEvaluator.effectiveTier(requested, owner)
        val accessibility = isAccessibilityEnabled(context)
        val connected = service != null
        val protectionEnabled = store.getBoolean(MainActivity.KEY_PROTECTION_ENABLED, false)
        val detectorReady = service?.isDetectorReady() == true
        val detectorError = service?.detectorError() ?: detectorFailure(context)
        val matcherReady = store.getBoolean(KEY_MATCHER_READY, false)
        val lastScan = store.getLong(KEY_LAST_SCAN, 0L)
        val lastConnect = store.getLong(KEY_LAST_CONNECT, 0L)
        val lastBoot = store.getLong(KEY_LAST_BOOT, 0L)

        val policies = DeviceOwner.snapshot(context)
        val applied = policies.filter { it.facts.isSet }.map { it.key }.toSet()
        val missing = if (requested == PolicyEvaluator.Tier.HARDENED) {
            DeviceOwner.ALL.filter { it !in applied }
        } else {
            emptyList()
        }

        val health = PolicyEvaluator.health(
            PolicyEvaluator.HealthFacts(
                supported = true,
                protectionEnabled = protectionEnabled,
                accessibilityEnabled = accessibility,
                serviceConnected = connected,
                detectorReady = detectorReady,
                detectorFailure = detectorError,
                requestedTier = requested,
                deviceOwner = owner,
                missingRestrictions = missing,
            ),
        )

        auditTransitions(
            context = context,
            health = health.health.wire,
            accessibility = accessibility,
            owner = owner,
            activePolicies = applied,
        )

        return mapOf(
            "tier" to tier.wire,
            "tierRequested" to requested.wire,
            "deviceOwner" to mapOf(
                "isOwner" to owner,
                "adminActive" to adminActive,
                "component" to DeviceOwner.component(context).flattenToString(),
                "apiSupported" to PolicyEvaluator.apiAvailable(android.os.Build.VERSION.SDK_INT),
                "packageName" to context.packageName,
            ),
            "health" to health.health.wire,
            "healthDetail" to health.detail,
            "components" to components(
                protectionEnabled = protectionEnabled,
                accessibility = accessibility,
                connected = connected,
                detectorReady = detectorReady,
                detectorError = detectorError,
                matcherReady = matcherReady,
                lastScan = lastScan,
                lastConnect = lastConnect,
                lastBoot = lastBoot,
            ),
            "restrictions" to policies.map {
                mapOf(
                    "key" to it.key,
                    "state" to it.state.wire,
                    "detail" to it.detail,
                )
            },
            "controls" to controls(tier, owner, connected),
            "lastScanAt" to lastScan,
            "lastConnectAt" to lastConnect,
            "lastBootAt" to lastBoot,
            "samsung" to samsungNote(),
            "audit" to SecurityAudit.read(context, 20),
        )
    }

    private fun components(
        protectionEnabled: Boolean,
        accessibility: Boolean,
        connected: Boolean,
        detectorReady: Boolean,
        detectorError: String?,
        matcherReady: Boolean,
        lastScan: Long,
        lastConnect: Long,
        lastBoot: Long,
    ): List<Map<String, Any?>> {
        val accessibilityState = when {
            accessibility && connected -> PolicyEvaluator.State.ACTIVE
            else -> PolicyEvaluator.State.UNAVAILABLE
        }
        val accessibilityDetail = when {
            accessibility && connected -> "Granted and connected to Android."
            accessibility -> "Granted, but Android has not connected the service yet."
            else -> "Not granted. Only Android settings can grant it; it is revocable there at any time."
        }

        val detectorState = when {
            !connected -> PolicyEvaluator.State.INACTIVE
            detectorError != null -> PolicyEvaluator.State.DEGRADED
            detectorReady -> PolicyEvaluator.State.ACTIVE
            else -> PolicyEvaluator.State.DEGRADED
        }
        val detectorDetail = when {
            !connected -> "Starts with the accessibility service."
            detectorError != null ->
                "Not running. Blocking rules still work; exposed frames are not blurred."
            detectorReady -> "The on-device model is loaded and scoring frames."
            else -> "Still starting; this can take up to half a minute after a reboot."
        }

        val matcherState = when {
            !connected -> PolicyEvaluator.State.INACTIVE
            matcherReady -> PolicyEvaluator.State.ACTIVE
            else -> PolicyEvaluator.State.DEGRADED
        }
        val matcherDetail = when {
            !connected -> "Block lists load when the accessibility service connects."
            matcherReady -> "Block lists are loaded and matching."
            else -> "Waiting for the first screen scan after connecting."
        }

        val rebootState =
            if (lastBoot == 0L) PolicyEvaluator.State.INACTIVE
            else if (lastConnect >= lastBoot) PolicyEvaluator.State.ACTIVE
            else PolicyEvaluator.State.DEGRADED
        val rebootDetail = when {
            lastBoot == 0L -> "No restart recorded since Basirah was installed."
            lastConnect >= lastBoot -> "The service reconnected after the last restart."
            else -> "Protection has not reconnected since the last restart."
        }

        val scanState =
            if (lastScan > 0L) PolicyEvaluator.State.ACTIVE else PolicyEvaluator.State.INACTIVE
        val scanDetail =
            if (lastScan > 0L) "Last screen scan ${relative(lastScan)}." else "No screen scan recorded yet."

        return listOf(
            map("preferences", if (protectionEnabled) {
                PolicyEvaluator.State.ACTIVE
            } else {
                PolicyEvaluator.State.DISABLED
            }, if (protectionEnabled) {
                "Protection is switched on and stored on this device."
            } else {
                "Protection is switched off in Basirah."
            }),
            map("accessibility", accessibilityState, accessibilityDetail),
            map("detection_engine", detectorState, detectorDetail),
            map("matcher", matcherState, matcherDetail),
            map("last_scan", scanState, scanDetail),
            map("reboot_recovery", rebootState, rebootDetail),
            map(
                "anti_tamper",
                if (connected) PolicyEvaluator.State.ACTIVE else PolicyEvaluator.State.INACTIVE,
                if (connected) {
                    "Recording accessibility, policy and Settings changes in this app's " +
                        "private audit log."
                } else {
                    "Monitoring pauses while the accessibility service is disconnected."
                },
            ),
        )
    }

    private fun controls(
        tier: PolicyEvaluator.Tier,
        owner: Boolean,
        connected: Boolean,
    ): List<Map<String, Any?>> {
        val restart = PolicyEvaluator.powerRoute(
            PolicyEvaluator.PowerAction.RESTART,
            tier,
            owner,
            connected,
        )
        val powerOff = PolicyEvaluator.powerRoute(
            PolicyEvaluator.PowerAction.POWER_OFF,
            tier,
            owner,
            connected,
        )
        return listOf(
            control("restart", restart),
            control("power_off", powerOff),
        )
    }

    private fun control(
        key: String,
        route: PolicyEvaluator.PowerRoute,
    ): Map<String, Any?> {
        val detail = when (route) {
            PolicyEvaluator.PowerRoute.DEVICE_OWNER_REBOOT ->
                "Restarts directly through the Device Owner API after you confirm."
            PolicyEvaluator.PowerRoute.SYSTEM_POWER_DIALOG ->
                "Opens Android's own power menu; you choose the action there."
            PolicyEvaluator.PowerRoute.UNAVAILABLE ->
                "Needs the accessibility service. Hold the phone's side button to " +
                    "open the power menu yourself."
        }
        return mapOf(
            "key" to key,
            "state" to if (route == PolicyEvaluator.PowerRoute.UNAVAILABLE) {
                PolicyEvaluator.State.INACTIVE.wire
            } else {
                PolicyEvaluator.State.ACTIVE.wire
            },
            "route" to route.wire,
            "detail" to detail,
        )
    }

    private fun map(
        key: String,
        state: PolicyEvaluator.State,
        detail: String,
    ): Map<String, Any?> = mapOf(
        "key" to key,
        "state" to state.wire,
        "detail" to detail,
    )

    /**
     * Records what changed since the last observation. Only transitions are
     * written, so the audit names real events (accessibility revoked, a policy
     * removed, protection degraded) instead of repeating the current state.
     */
    private fun auditTransitions(
        context: Context,
        health: String,
        accessibility: Boolean,
        owner: Boolean,
        activePolicies: Set<String>,
    ) {
        val store = prefs(context)
        val editor = store.edit()

        val storedAccessibility = store.getBoolean(KEY_ACCESSIBILITY, accessibility)
        if (storedAccessibility != accessibility) {
            SecurityAudit.record(
                context,
                if (accessibility) "accessibility_granted" else "accessibility_revoked",
                if (accessibility) {
                    "Android reports the accessibility service enabled"
                } else {
                    "Android no longer lists the accessibility service as enabled"
                },
            )
            editor.putBoolean(KEY_ACCESSIBILITY, accessibility)
        }

        val ownerValue = if (owner) "owner" else "standard"
        val storedOwner = store.getString(KEY_OWNER, null)
        if (storedOwner != null && storedOwner != ownerValue) {
            SecurityAudit.record(
                context,
                "device_owner",
                if (owner) {
                    "Android reports Basirah as Device Owner"
                } else {
                    "Android no longer reports Basirah as Device Owner"
                },
            )
        }
        if (storedOwner != ownerValue) editor.putString(KEY_OWNER, ownerValue)

        val signature = activePolicies.sorted().joinToString(",")
        val previous = store.getString(KEY_POLICY_SIGNATURE, null)
        if (previous != null && previous != signature) {
            val transitions = PolicyEvaluator.policyTransitions(
                previous.split(',').filter { it.isNotBlank() }.toSet(),
                activePolicies,
            )
            if (!transitions.isEmpty) {
                SecurityAudit.record(
                    context,
                    "policy_changed",
                    "lost=" + (transitions.lost.joinToString(",").ifEmpty { "-" }) +
                        " added=" + (transitions.added.joinToString(",").ifEmpty { "-" }),
                )
            }
        }
        if (previous != signature) editor.putString(KEY_POLICY_SIGNATURE, signature)

        editor.apply()

        // Health transitions are recorded from the same observation the report
        // shows, so the audit and the dashboard cannot disagree.
        val storedHealth = store.getString(KEY_LAST_HEALTH, null)
        if (storedHealth != null && storedHealth != health) {
            SecurityAudit.record(context, "protection_health", "$storedHealth -> $health")
        }
        if (storedHealth != health) store.edit().putString(KEY_LAST_HEALTH, health).apply()
    }

    /**
     * Samsung One UI note shown next to the device restrictions. Kept here so
     * the text the app displays and the documentation cannot drift apart.
     */
    fun samsungNote(): Map<String, Any?> = mapOf(
        "device" to "Samsung Galaxy A56 (One UI)",
        "validated" to false,
        "detail" to "Android enterprise Device Owner policy is documented by Google " +
            "and used by managed-device products, but Basirah has not been run on a " +
            "physical Galaxy A56 in this workspace. Emulator results do not prove " +
            "One UI behaviour.",
    )

    private fun relative(timestamp: Long): String {
        val age = System.currentTimeMillis() - timestamp
        if (age < 0) return "just now"
        val minutes = age / 60_000L
        return when {
            minutes < 1 -> "just now"
            minutes < 60 -> "$minutes min ago"
            minutes < 24 * 60 -> "${minutes / 60} h ago"
            else -> "${minutes / (24 * 60)} d ago"
        }
    }
}
