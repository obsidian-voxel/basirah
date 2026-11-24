package com.haramblur.haram_blur

import android.app.admin.DevicePolicyManager
import android.content.Context
import android.util.Log

private const val TAG = "HaramBlur"

/**
 * Restart and Turn Off, through mechanisms Android actually provides.
 *
 * * Standard Protection cannot restart the phone. The accessibility service can
 *   open Android's own power dialog (`GLOBAL_ACTION_POWER_DIALOG`), and the
 *   user finishes the action in the system UI.
 * * Hardened Protection on a verified Device Owner can call
 *   `DevicePolicyManager.reboot()`. It is still the operating system that
 *   restarts, and Android can refuse while a call is in progress.
 * * There is no public shutdown API at any privilege level, so Turn Off always
 *   goes through the system power dialog. No direct-shutdown claim is made.
 *
 * Nothing here reports success before Android has accepted the request, and
 * every use is written to the local security audit.
 */
object PowerControls {

    data class Result(
        val ok: Boolean,
        val route: String,
        val message: String,
    )

    /** Shown whenever no supported route exists or the request was refused. */
    private const val MANUAL_POWER_MENU =
        "Basirah cannot open the power menu without the accessibility service. " +
            "Hold the phone's side button until Android's power menu appears, then " +
            "choose Restart or Power off there."

    fun restart(context: Context, service: SystemWideBlurService?): Result {
        val tier = ProtectionHealth.effectiveTier(context)
        val owner = DeviceOwner.isDeviceOwner(context)
        val route = PolicyEvaluator.powerRoute(
            PolicyEvaluator.PowerAction.RESTART,
            tier,
            owner,
            service != null,
        )
        val result = when (route) {
            PolicyEvaluator.PowerRoute.DEVICE_OWNER_REBOOT -> rebootAsDeviceOwner(context)
            PolicyEvaluator.PowerRoute.SYSTEM_POWER_DIALOG ->
                openPowerDialog(service, "Restart")
            PolicyEvaluator.PowerRoute.UNAVAILABLE -> Result(false, route.wire, MANUAL_POWER_MENU)
        }
        audit(context, PolicyEvaluator.PowerAction.RESTART, result)
        return result
    }

    /**
     * Android exposes no direct shutdown, even to a Device Owner, so this always
     * resolves to the system power menu (or the manual instruction).
     */
    fun powerOff(context: Context, service: SystemWideBlurService?): Result {
        val tier = ProtectionHealth.effectiveTier(context)
        val owner = DeviceOwner.isDeviceOwner(context)
        val route = PolicyEvaluator.powerRoute(
            PolicyEvaluator.PowerAction.POWER_OFF,
            tier,
            owner,
            service != null,
        )
        val result = when (route) {
            PolicyEvaluator.PowerRoute.SYSTEM_POWER_DIALOG ->
                openPowerDialog(service, "Power off")
            PolicyEvaluator.PowerRoute.DEVICE_OWNER_REBOOT,
            PolicyEvaluator.PowerRoute.UNAVAILABLE,
            -> Result(false, route.wire, MANUAL_POWER_MENU)
        }
        audit(context, PolicyEvaluator.PowerAction.POWER_OFF, result)
        return result
    }

    private fun rebootAsDeviceOwner(context: Context): Result {
        val service = try {
            context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
        } catch (_: Throwable) {
            null
        } ?: return Result(
            false,
            PolicyEvaluator.PowerRoute.DEVICE_OWNER_REBOOT.wire,
            "The device policy service is unavailable, so Basirah cannot restart the phone. " +
                "Use the power menu instead.",
        )
        return try {
            service.reboot(DeviceOwner.component(context))
            Result(
                true,
                PolicyEvaluator.PowerRoute.DEVICE_OWNER_REBOOT.wire,
                "Android accepted the restart request. The phone restarts now.",
            )
        } catch (error: IllegalStateException) {
            // Android documents this for an ongoing call (and similar states).
            Log.w(TAG, "Device Owner reboot refused: IllegalStateException")
            Result(
                false,
                PolicyEvaluator.PowerRoute.DEVICE_OWNER_REBOOT.wire,
                "Android refused the restart: " +
                    (error.message?.take(120) ?: "a call or another restriction is in progress") +
                    ". End the call and try again, or use the power menu.",
            )
        } catch (error: SecurityException) {
            Log.w(TAG, "Device Owner reboot refused: SecurityException")
            Result(
                false,
                PolicyEvaluator.PowerRoute.DEVICE_OWNER_REBOOT.wire,
                "Android refused the restart because Basirah is not the verified " +
                    "Device Owner any more. Use the power menu instead.",
            )
        } catch (error: Throwable) {
            Log.w(TAG, "Device Owner reboot failed: ${error.javaClass.simpleName}")
            Result(
                false,
                PolicyEvaluator.PowerRoute.DEVICE_OWNER_REBOOT.wire,
                "The restart request failed (" + error.javaClass.simpleName +
                    "). Use the power menu instead.",
            )
        }
    }

    private fun openPowerDialog(service: SystemWideBlurService?, action: String): Result {
        if (service == null) {
            return Result(
                false,
                PolicyEvaluator.PowerRoute.SYSTEM_POWER_DIALOG.wire,
                MANUAL_POWER_MENU,
            )
        }
        val shown = service.openPowerDialog()
        return if (shown) {
            Result(
                true,
                PolicyEvaluator.PowerRoute.SYSTEM_POWER_DIALOG.wire,
                "Android's power menu is open. Choose $action there; Basirah has not " +
                    "restarted or switched off anything itself.",
            )
        } else {
            Result(false, PolicyEvaluator.PowerRoute.SYSTEM_POWER_DIALOG.wire, MANUAL_POWER_MENU)
        }
    }

    private fun audit(
        context: Context,
        action: PolicyEvaluator.PowerAction,
        result: Result,
    ) {
        SecurityAudit.record(
            context,
            "device_control",
            "${action.wire} route=${result.route} accepted=${result.ok}",
        )
    }
}
