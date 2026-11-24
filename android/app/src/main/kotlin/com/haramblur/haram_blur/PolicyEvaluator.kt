package com.haramblur.haram_blur

/**
 * The decision layer for protection modes, Device Owner restrictions and the
 * power controls.
 *
 * Nothing here touches Android: every function takes the facts an Android
 * wrapper read and returns the state the UI may show. That keeps Basirah's
 * honesty rules testable on the JVM (`PolicyEvaluatorTest`) instead of only on
 * a provisioned device, and it puts the "never claim more than Android
 * confirmed" rule in one place instead of in each screen.
 */
object PolicyEvaluator {

    /** The two protection modes. Hardened is only ever effective when verified. */
    enum class Tier(val wire: String) {
        STANDARD("standard"),
        HARDENED("hardened");

        companion object {
            /** Unknown or missing values fall back to the safe, default mode. */
            fun fromWire(value: String?): Tier =
                entries.firstOrNull { it.wire == value } ?: STANDARD
        }
    }

    /**
     * Per-feature state. [REQUIRES_PROVISIONING] and [REQUIRES_PRIVILEGE] are
     * deliberately distinct from [INACTIVE]: a feature the device cannot grant
     * must never look like one the user simply has not switched on.
     */
    enum class State(val wire: String) {
        ACTIVE("active"),
        INACTIVE("inactive"),
        DEGRADED("degraded"),
        UNAVAILABLE("temporarily_unavailable"),
        DISABLED("disabled"),
        UNSUPPORTED("unsupported"),
        REQUIRES_PRIVILEGE("requires_privilege"),
        REQUIRES_PROVISIONING("requires_provisioning"),
    }

    /** The five protection-health answers the dashboard is allowed to give. */
    enum class Health(val wire: String) {
        ACTIVE("active"),
        TEMPORARILY_UNAVAILABLE("temporarily_unavailable"),
        DEGRADED("degraded"),
        DISABLED("disabled"),
        UNSUPPORTED("unsupported"),
    }

    /**
     * Hardened protection is a claim about Android's state, so the requested
     * tier only becomes the effective tier when Basirah is genuinely Device
     * Owner. Storing the request lets the choice survive provisioning; showing
     * it as active before that would be a lie.
     */
    fun effectiveTier(requested: Tier, deviceOwner: Boolean): Tier =
        if (requested == Tier.HARDENED && deviceOwner) Tier.HARDENED else Tier.STANDARD

    data class HealthFacts(
        val supported: Boolean,
        val protectionEnabled: Boolean,
        val accessibilityEnabled: Boolean,
        val serviceConnected: Boolean,
        val detectorReady: Boolean,
        val detectorFailure: String?,
        val requestedTier: Tier,
        val deviceOwner: Boolean,
        /** Restriction keys that are applied-but-not-verified, wire names only. */
        val missingRestrictions: List<String> = emptyList(),
    )

    data class HealthResult(val health: Health, val detail: String)

    /**
     * Classifies the whole protection stack. Order matters: a switched-off
     * protection is *disabled*, not degraded, and a missing accessibility grant
     * is *temporarily unavailable* because the user can restore it in Settings.
     */
    fun health(facts: HealthFacts): HealthResult {
        if (!facts.supported) {
            return HealthResult(
                Health.UNSUPPORTED,
                "Screen protection needs Android 11 or newer.",
            )
        }
        if (!facts.protectionEnabled) {
            return HealthResult(
                Health.DISABLED,
                "Protection is switched off in Basirah. Nothing is being blocked.",
            )
        }
        if (!facts.accessibilityEnabled) {
            return HealthResult(
                Health.TEMPORARILY_UNAVAILABLE,
                "Android has accessibility off, so Basirah cannot see the screen. " +
                    "Turn it back on in Android settings.",
            )
        }
        if (!facts.serviceConnected) {
            return HealthResult(
                Health.TEMPORARILY_UNAVAILABLE,
                "Accessibility is enabled but the service is not connected right " +
                    "now. Basirah is not blocking anything until it reconnects.",
            )
        }
        if (facts.requestedTier == Tier.HARDENED && !facts.deviceOwner) {
            return HealthResult(
                Health.DEGRADED,
                "Hardened protection is requested, but this device has no verified " +
                    "Device Owner, so only Standard protection is running.",
            )
        }
        if (facts.requestedTier == Tier.HARDENED &&
            facts.deviceOwner &&
            facts.missingRestrictions.isNotEmpty()
        ) {
            return HealthResult(
                Health.DEGRADED,
                "Hardened protection is missing or could not verify: " +
                    facts.missingRestrictions.joinToString(", ") + ".",
            )
        }
        if (facts.detectorFailure != null) {
            return HealthResult(
                Health.DEGRADED,
                "The visual detector is not running, so exposed frames are not " +
                    "blurred. App, site and keyword blocking still work.",
            )
        }
        if (!facts.detectorReady) {
            return HealthResult(
                Health.DEGRADED,
                "The visual detector is still starting. Blocking rules already work.",
            )
        }
        return HealthResult(
            Health.ACTIVE,
            "Accessibility, the rule matcher and the visual detector are all running.",
        )
    }

    /**
     * Facts for one Device Owner policy. [readError] means Android would not
     * report the state, which is not the same as "off": the UI shows degraded.
     */
    data class RestrictionFacts(
        val apiAvailable: Boolean,
        val deviceOwner: Boolean,
        val isSet: Boolean,
        val readError: String? = null,
    )

    fun restrictionState(facts: RestrictionFacts): State = when {
        !facts.apiAvailable -> State.UNSUPPORTED
        !facts.deviceOwner -> State.REQUIRES_PROVISIONING
        facts.readError != null -> State.DEGRADED
        facts.isSet -> State.ACTIVE
        else -> State.INACTIVE
    }

    /** Device-policy user restrictions exist from API 21 (Android 5.0). */
    fun apiAvailable(sdkInt: Int): Boolean = sdkInt >= 21

    enum class PowerAction(val wire: String) {
        RESTART("restart"),
        POWER_OFF("power_off"),
    }

    enum class PowerRoute(val wire: String) {
        /** `GLOBAL_ACTION_POWER_DIALOG`; the user finishes the action. */
        SYSTEM_POWER_DIALOG("system_power_dialog"),

        /** `DevicePolicyManager.reboot()`, Device Owner only. */
        DEVICE_OWNER_REBOOT("device_owner_reboot"),

        UNAVAILABLE("unavailable"),
    }

    /**
     * Chooses the mechanism for a power action.
     *
     * There is no public shutdown API, not even for a Device Owner, so
     * [PowerAction.POWER_OFF] never routes to `DEVICE_OWNER_REBOOT`; both
     * actions fall back to Android's own power dialog when accessibility is
     * connected, and report unavailable (with a manual instruction) when it is
     * not. The direct restart is only offered on a genuinely verified Device
     * Owner in Hardened mode.
     */
    fun powerRoute(
        action: PowerAction,
        tier: Tier,
        deviceOwner: Boolean,
        accessibilityConnected: Boolean,
    ): PowerRoute = when {
        action == PowerAction.RESTART &&
            tier == Tier.HARDENED &&
            deviceOwner -> PowerRoute.DEVICE_OWNER_REBOOT
        accessibilityConnected -> PowerRoute.SYSTEM_POWER_DIALOG
        else -> PowerRoute.UNAVAILABLE
    }

    /** Policies that were applied earlier and are no longer set, or newly set. */
    data class PolicyTransitions(
        val lost: List<String>,
        val added: List<String>,
    ) {
        val isEmpty: Boolean get() = lost.isEmpty() && added.isEmpty()
    }

    /**
     * Compares two verified policy signatures. Used by the anti-tamper monitor:
     * a restriction that disappears without the user removing it is the one
     * policy change Android lets an ordinary app observe.
     */
    fun policyTransitions(previous: Set<String>, current: Set<String>) =
        PolicyTransitions(
            lost = (previous - current).sorted(),
            added = (current - previous).sorted(),
        )
}
