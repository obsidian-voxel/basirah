package com.haramblur.haram_blur

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.UserManager
import android.util.Log

private const val TAG = "HaramBlur"

/**
 * Device Owner (Device Policy Controller) support for Hardened Protection.
 *
 * This is a thin fact-gathering and policy wrapper around
 * [DevicePolicyManager]: every state it reports is read back from Android, and
 * every change is verified afterwards rather than assumed. The decisions live
 * in [PolicyEvaluator] so they can be tested without a provisioned device.
 *
 * Basirah reuses its existing [DeviceAdmin] receiver as the policy-management
 * component. Being a Device Owner is a provisioning decision the user makes on
 * a managed device; it is never requested from this code.
 */
object DeviceOwner {

    const val SAFE_BOOT = "safe_boot"
    const val APPS_CONTROL = "apps_control"
    const val FACTORY_RESET = "factory_reset"
    const val UNINSTALL_BLOCKED = "uninstall_blocked"

    /** Every policy Hardened Protection applies. Nothing else is touched. */
    val ALL: List<String> = listOf(SAFE_BOOT, APPS_CONTROL, FACTORY_RESET, UNINSTALL_BLOCKED)

    private fun dpm(context: Context): DevicePolicyManager? = try {
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
    } catch (_: Throwable) {
        null
    }

    /** The admin component used for both device admin and Device Owner. */
    fun component(context: Context): ComponentName =
        ComponentName(context, DeviceAdmin::class.java)

    /** True only when Android reports this package as the Device Owner. */
    fun isDeviceOwner(context: Context): Boolean = try {
        dpm(context)?.isDeviceOwnerApp(context.packageName) == true
    } catch (_: Throwable) {
        false
    }

    /** Ordinary device admin is weaker than Device Owner and is read separately. */
    fun isAdminActive(context: Context): Boolean = try {
        dpm(context)?.isAdminActive(component(context)) == true
    } catch (_: Throwable) {
        false
    }

    /**
     * One policy as Android reports it. [PolicyEvaluator.RestrictionFacts] is
     * kept separate so the UI state has no Android types in it.
     */
    data class PolicyFact(
        val key: String,
        val facts: PolicyEvaluator.RestrictionFacts,
        val detail: String,
    ) {
        val state: PolicyEvaluator.State
            get() = PolicyEvaluator.restrictionState(facts)
    }

    /** What this device can and cannot report about Device Owner policies. */
    fun snapshot(context: Context): List<PolicyFact> {
        val owner = isDeviceOwner(context)
        val apiAvailable = PolicyEvaluator.apiAvailable(Build.VERSION.SDK_INT)
        val users = try {
            context.getSystemService(Context.USER_SERVICE) as? UserManager
        } catch (_: Throwable) {
            null
        }
        return listOf(
            userRestriction(
                users,
                SAFE_BOOT,
                UserManager.DISALLOW_SAFE_BOOT,
                owner,
                apiAvailable,
                "Android will not offer Safe Mode on the next start.",
                "Safe Mode would let every third-party service and app start " +
                    "without Basirah, so this is the bypass it closes.",
            ),
            userRestriction(
                users,
                APPS_CONTROL,
                UserManager.DISALLOW_APPS_CONTROL,
                owner,
                apiAvailable,
                "Settings cannot uninstall, disable or force-stop apps.",
                "This covers app management in Settings. It does not stop ADB, " +
                    "root or an OEM tool from removing apps.",
            ),
            userRestriction(
                users,
                FACTORY_RESET,
                UserManager.DISALLOW_FACTORY_RESET,
                owner,
                apiAvailable,
                "Android Settings cannot erase the device.",
                "Recovery-mode wipes, firmware reflashes and Find My Mobile " +
                    "erasure are outside what any app can block.",
            ),
            uninstallBlocked(context, owner, apiAvailable),
        )
    }

    private fun userRestriction(
        users: UserManager?,
        key: String,
        restriction: String,
        owner: Boolean,
        apiAvailable: Boolean,
        activeDetail: String,
        inactiveDetail: String,
    ): PolicyFact {
        if (users == null) {
            return PolicyFact(
                key,
                PolicyEvaluator.RestrictionFacts(
                    apiAvailable = apiAvailable,
                    deviceOwner = owner,
                    isSet = false,
                    readError = "The user manager is unavailable",
                ),
                "Android did not expose this restriction on this build.",
            )
        }
        val isSet = try {
            users.hasUserRestriction(restriction)
        } catch (error: Throwable) {
            Log.w(TAG, "Policy $key could not be read: ${error.javaClass.simpleName}")
            return PolicyFact(
                key,
                PolicyEvaluator.RestrictionFacts(
                    apiAvailable = apiAvailable,
                    deviceOwner = owner,
                    isSet = false,
                    readError = error.javaClass.simpleName,
                ),
                "Android would not report this restriction, so it is not claimed.",
            )
        }
        return PolicyFact(
            key,
            PolicyEvaluator.RestrictionFacts(
                apiAvailable = apiAvailable,
                deviceOwner = owner,
                isSet = isSet,
            ),
            if (isSet) activeDetail else inactiveDetail,
        )
    }

    private fun uninstallBlocked(
        context: Context,
        owner: Boolean,
        apiAvailable: Boolean,
    ): PolicyFact {
        val service = dpm(context)
        val isSet = try {
            service?.isUninstallBlocked(component(context), context.packageName) == true
        } catch (error: Throwable) {
            return PolicyFact(
                UNINSTALL_BLOCKED,
                PolicyEvaluator.RestrictionFacts(
                    apiAvailable = apiAvailable,
                    deviceOwner = owner,
                    isSet = false,
                    readError = error.javaClass.simpleName,
                ),
                "Android would not report this policy, so it is not claimed.",
            )
        }
        return PolicyFact(
            UNINSTALL_BLOCKED,
            PolicyEvaluator.RestrictionFacts(
                apiAvailable = apiAvailable,
                deviceOwner = owner,
                isSet = isSet,
            ),
            if (isSet) {
                "Android refuses to uninstall Basirah. This does not defeat ADB, " +
                    "root or a privileged device-management tool."
            } else {
                "Basirah can still be uninstalled the usual way."
            },
        )
    }

    /**
     * Applies the requested policies and returns the failure reason per key
     * (`null` when Android accepted it). Acceptance is not verification: the
     * caller re-reads [snapshot] before telling the user anything is active.
     */
    fun apply(context: Context, keys: Set<String>): Map<String, String?> {
        val results = LinkedHashMap<String, String?>()
        val service = dpm(context)
        if (service == null) {
            keys.forEach { results[it] = "The device policy service is unavailable" }
            return results
        }
        if (!isDeviceOwner(context)) {
            keys.forEach { results[it] = "Basirah is not this device's Device Owner" }
            return results
        }
        val admin = component(context)
        for (key in keys) {
            try {
                if (key == UNINSTALL_BLOCKED) {
                    service.setUninstallBlocked(admin, context.packageName, true)
                } else {
                    val restriction = restrictionKey(key)
                    if (restriction == null) {
                        results[key] = "Unknown policy"
                        continue
                    }
                    service.addUserRestriction(admin, restriction)
                }
                results[key] = null
            } catch (error: Throwable) {
                Log.w(TAG, "Policy $key was refused: ${error.javaClass.simpleName}")
                results[key] = describe(error)
            }
        }
        return results
    }

    /**
     * Removes policies. This is the in-app recovery path and must stay
     * available while Basirah is Device Owner; it never removes the Device
     * Owner itself, which only a factory reset (or the platform's own
     * provisioning tooling on a test device) can do.
     */
    fun clear(context: Context, keys: Set<String>): Map<String, String?> {
        val results = LinkedHashMap<String, String?>()
        val service = dpm(context)
        if (service == null) {
            keys.forEach { results[it] = "The device policy service is unavailable" }
            return results
        }
        val admin = component(context)
        for (key in keys) {
            try {
                if (key == UNINSTALL_BLOCKED) {
                    service.setUninstallBlocked(admin, context.packageName, false)
                } else {
                    val restriction = restrictionKey(key)
                    if (restriction == null) {
                        results[key] = "Unknown policy"
                        continue
                    }
                    service.clearUserRestriction(admin, restriction)
                }
                results[key] = null
            } catch (error: Throwable) {
                Log.w(TAG, "Policy $key could not be removed: ${error.javaClass.simpleName}")
                results[key] = describe(error)
            }
        }
        return results
    }

    /** Keys that are set right now, for the anti-tamper signature. */
    fun activeKeys(context: Context): Set<String> =
        snapshot(context).filter { it.facts.isSet }.map { it.key }.toSet()

    private fun restrictionKey(key: String): String? = when (key) {
        SAFE_BOOT -> UserManager.DISALLOW_SAFE_BOOT
        APPS_CONTROL -> UserManager.DISALLOW_APPS_CONTROL
        FACTORY_RESET -> UserManager.DISALLOW_FACTORY_RESET
        else -> null
    }

    private fun describe(error: Throwable): String =
        error.javaClass.simpleName + ": " +
            (error.message?.take(120) ?: "Android refused the policy change")
}
