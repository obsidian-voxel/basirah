package com.haramblur.haram_blur

import com.haramblur.haram_blur.PolicyEvaluator.Health
import com.haramblur.haram_blur.PolicyEvaluator.HealthFacts
import com.haramblur.haram_blur.PolicyEvaluator.PowerAction
import com.haramblur.haram_blur.PolicyEvaluator.PowerRoute
import com.haramblur.haram_blur.PolicyEvaluator.RestrictionFacts
import com.haramblur.haram_blur.PolicyEvaluator.State
import com.haramblur.haram_blur.PolicyEvaluator.Tier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The policy layer's honesty rules, tested as pure logic.
 *
 * A JVM unit test cannot be a Device Owner, so these tests do not exercise the
 * Android service: they prove that the states the UI renders follow only from
 * the facts Android reported. The Device Owner wrapper itself still needs a
 * disposable provisioned device (see docs/PROTECTION.md).
 */
class PolicyEvaluatorTest {

    private fun facts(
        protectionEnabled: Boolean = true,
        accessibilityEnabled: Boolean = true,
        serviceConnected: Boolean = true,
        detectorReady: Boolean = true,
        detectorFailure: String? = null,
        requestedTier: Tier = Tier.STANDARD,
        deviceOwner: Boolean = false,
        missingRestrictions: List<String> = emptyList(),
    ) = HealthFacts(
        supported = true,
        protectionEnabled = protectionEnabled,
        accessibilityEnabled = accessibilityEnabled,
        serviceConnected = serviceConnected,
        detectorReady = detectorReady,
        detectorFailure = detectorFailure,
        requestedTier = requestedTier,
        deviceOwner = deviceOwner,
        missingRestrictions = missingRestrictions,
    )

    // ------------------------------------------------------------------
    // Protection health
    // ------------------------------------------------------------------

    @Test
    fun `standard protection is active when every observable layer runs`() {
        val result = PolicyEvaluator.health(facts())
        assertEquals(Health.ACTIVE, result.health)
    }

    @Test
    fun `switched-off protection is disabled, not degraded`() {
        val result = PolicyEvaluator.health(facts(protectionEnabled = false))
        assertEquals(Health.DISABLED, result.health)
    }

    @Test
    fun `revoked accessibility is temporarily unavailable`() {
        val result = PolicyEvaluator.health(facts(accessibilityEnabled = false))
        assertEquals(Health.TEMPORARILY_UNAVAILABLE, result.health)
        assertTrue(result.detail.contains("accessibility"))
    }

    @Test
    fun `an enabled but unconnected service is temporarily unavailable`() {
        val result = PolicyEvaluator.health(facts(serviceConnected = false))
        assertEquals(Health.TEMPORARILY_UNAVAILABLE, result.health)
    }

    @Test
    fun `a failed detector degrades protection without claiming blocking stopped`() {
        val result = PolicyEvaluator.health(facts(detectorFailure = "timeout"))
        assertEquals(Health.DEGRADED, result.health)
        assertTrue(result.detail.contains("blocking still work"))
    }

    @Test
    fun `a detector that is still starting is degraded`() {
        val result = PolicyEvaluator.health(facts(detectorReady = false))
        assertEquals(Health.DEGRADED, result.health)
    }

    @Test
    fun `unsupported platform is reported as unsupported`() {
        val result = PolicyEvaluator.health(
            HealthFacts(
                supported = false,
                protectionEnabled = true,
                accessibilityEnabled = true,
                serviceConnected = true,
                detectorReady = true,
                detectorFailure = null,
                requestedTier = Tier.STANDARD,
                deviceOwner = false,
            ),
        )
        assertEquals(Health.UNSUPPORTED, result.health)
    }

    // ------------------------------------------------------------------
    // Protection mode
    // ------------------------------------------------------------------

    @Test
    fun `hardened is never effective without a verified device owner`() {
        assertEquals(Tier.STANDARD, PolicyEvaluator.effectiveTier(Tier.HARDENED, false))
        assertEquals(Tier.HARDENED, PolicyEvaluator.effectiveTier(Tier.HARDENED, true))
        assertEquals(Tier.STANDARD, PolicyEvaluator.effectiveTier(Tier.STANDARD, true))
    }

    @Test
    fun `requesting hardened without device owner degrades rather than claiming it`() {
        val result = PolicyEvaluator.health(
            facts(requestedTier = Tier.HARDENED, deviceOwner = false),
        )
        assertEquals(Health.DEGRADED, result.health)
        assertTrue(result.detail.contains("no verified Device Owner"))
    }

    @Test
    fun `hardened with device owner but missing restrictions is degraded`() {
        val result = PolicyEvaluator.health(
            facts(
                requestedTier = Tier.HARDENED,
                deviceOwner = true,
                missingRestrictions = listOf(DeviceOwner.SAFE_BOOT),
            ),
        )
        assertEquals(Health.DEGRADED, result.health)
        assertTrue(result.detail.contains(DeviceOwner.SAFE_BOOT))
    }

    @Test
    fun `hardened with a verified device owner and every restriction is active`() {
        val result = PolicyEvaluator.health(
            facts(requestedTier = Tier.HARDENED, deviceOwner = true),
        )
        assertEquals(Health.ACTIVE, result.health)
    }

    @Test
    fun `being device owner alone does not require hardened restrictions`() {
        val result = PolicyEvaluator.health(
            facts(requestedTier = Tier.STANDARD, deviceOwner = true),
        )
        assertEquals(Health.ACTIVE, result.health)
    }

    // ------------------------------------------------------------------
    // Device restrictions
    // ------------------------------------------------------------------

    @Test
    fun `restrictions require provisioning without a device owner`() {
        val state = PolicyEvaluator.restrictionState(
            RestrictionFacts(apiAvailable = true, deviceOwner = false, isSet = false),
        )
        assertEquals(State.REQUIRES_PROVISIONING, state)
    }

    @Test
    fun `an unavailable API is unsupported, not inactive`() {
        val state = PolicyEvaluator.restrictionState(
            RestrictionFacts(apiAvailable = false, deviceOwner = true, isSet = true),
        )
        assertEquals(State.UNSUPPORTED, state)
    }

    @Test
    fun `an applied restriction is active`() {
        val state = PolicyEvaluator.restrictionState(
            RestrictionFacts(apiAvailable = true, deviceOwner = true, isSet = true),
        )
        assertEquals(State.ACTIVE, state)
    }

    @Test
    fun `an owner without the restriction is inactive`() {
        val state = PolicyEvaluator.restrictionState(
            RestrictionFacts(apiAvailable = true, deviceOwner = true, isSet = false),
        )
        assertEquals(State.INACTIVE, state)
    }

    @Test
    fun `an unreadable restriction is degraded, never inactive`() {
        val state = PolicyEvaluator.restrictionState(
            RestrictionFacts(
                apiAvailable = true,
                deviceOwner = true,
                isSet = false,
                readError = "SecurityException",
            ),
        )
        assertEquals(State.DEGRADED, state)
    }

    @Test
    fun `device policy APIs exist from android 5`() {
        assertFalse(PolicyEvaluator.apiAvailable(20))
        assertTrue(PolicyEvaluator.apiAvailable(21))
        assertTrue(PolicyEvaluator.apiAvailable(36))
    }

    // ------------------------------------------------------------------
    // Restart and Turn Off
    // ------------------------------------------------------------------

    @Test
    fun `standard restart opens the system power dialog`() {
        val route = PolicyEvaluator.powerRoute(
            PowerAction.RESTART,
            Tier.STANDARD,
            deviceOwner = false,
            accessibilityConnected = true,
        )
        assertEquals(PowerRoute.SYSTEM_POWER_DIALOG, route)
    }

    @Test
    fun `hardened restart on a verified owner uses the device policy api`() {
        val route = PolicyEvaluator.powerRoute(
            PowerAction.RESTART,
            Tier.HARDENED,
            deviceOwner = true,
            accessibilityConnected = false,
        )
        assertEquals(PowerRoute.DEVICE_OWNER_REBOOT, route)
    }

    @Test
    fun `hardened restart without the owner falls back to the power dialog`() {
        val route = PolicyEvaluator.powerRoute(
            PowerAction.RESTART,
            Tier.HARDENED,
            deviceOwner = false,
            accessibilityConnected = true,
        )
        assertEquals(PowerRoute.SYSTEM_POWER_DIALOG, route)
    }

    @Test
    fun `turn off never invents a direct shutdown, even for a device owner`() {
        val route = PolicyEvaluator.powerRoute(
            PowerAction.POWER_OFF,
            Tier.HARDENED,
            deviceOwner = true,
            accessibilityConnected = true,
        )
        assertEquals(PowerRoute.SYSTEM_POWER_DIALOG, route)
    }

    @Test
    fun `power controls report unavailable without accessibility`() {
        assertEquals(
            PowerRoute.UNAVAILABLE,
            PolicyEvaluator.powerRoute(
                PowerAction.RESTART,
                Tier.STANDARD,
                deviceOwner = false,
                accessibilityConnected = false,
            ),
        )
        assertEquals(
            PowerRoute.UNAVAILABLE,
            PolicyEvaluator.powerRoute(
                PowerAction.POWER_OFF,
                Tier.STANDARD,
                deviceOwner = false,
                accessibilityConnected = false,
            ),
        )
    }

    // ------------------------------------------------------------------
    // Anti-tamper transitions
    // ------------------------------------------------------------------

    @Test
    fun `a removed policy is reported as lost`() {
        val transitions = PolicyEvaluator.policyTransitions(
            previous = setOf(
                DeviceOwner.SAFE_BOOT,
                DeviceOwner.APPS_CONTROL,
                DeviceOwner.UNINSTALL_BLOCKED,
            ),
            current = setOf(DeviceOwner.SAFE_BOOT, DeviceOwner.APPS_CONTROL),
        )
        assertEquals(listOf(DeviceOwner.UNINSTALL_BLOCKED), transitions.lost)
        assertTrue(transitions.added.isEmpty())
        assertFalse(transitions.isEmpty)
    }

    @Test
    fun `a newly applied policy is reported as added`() {
        val transitions = PolicyEvaluator.policyTransitions(
            previous = emptySet(),
            current = setOf(DeviceOwner.FACTORY_RESET),
        )
        assertEquals(listOf(DeviceOwner.FACTORY_RESET), transitions.added)
        assertTrue(transitions.lost.isEmpty())
    }

    @Test
    fun `an unchanged signature has no transitions`() {
        val transitions = PolicyEvaluator.policyTransitions(
            previous = setOf(DeviceOwner.SAFE_BOOT),
            current = setOf(DeviceOwner.SAFE_BOOT),
        )
        assertTrue(transitions.isEmpty)
    }

    @Test
    fun `an unknown tier falls back to standard`() {
        assertEquals(Tier.STANDARD, Tier.fromWire("rooted"))
        assertEquals(Tier.STANDARD, Tier.fromWire(null))
        assertEquals(Tier.HARDENED, Tier.fromWire("hardened"))
    }
}
