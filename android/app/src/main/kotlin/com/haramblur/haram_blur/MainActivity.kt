package com.haramblur.haram_blur

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.preference.PreferenceManager
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val TAG = "HaramBlur"

/**
 * Hosts the Flutter UI and the single control channel
 * (`com.haramblur.haram_blur/control`).
 *
 * Only this class registers a handler for the channel. The accessibility
 * service exposes plain methods instead, which used to overwrite the Flutter
 * handler and made every toggle a no-op.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "com.haramblur.haram_blur/control"

        const val KEY_PROTECTION_ENABLED = "system_wide_enabled"
        const val KEY_SENSITIVITY = "blur_sensitivity"
        const val KEY_EXCLUSIONS = "excluded_packages"
        const val KEY_BLUR_STRENGTH = "blur_strength"
        const val KEY_DEBUG_OVERLAY = "debug_overlay_enabled"

        private const val REQ_PICK = 4701
        private const val REQ_CAPTURE = 4702
        private const val REQ_NOTIFICATIONS = 4703
        private const val WATCHDOG_CHANNEL = "haram_blur_watchdog"
        private const val WATCHDOG_NOTIFICATION_ID = 4711

        /** Set by [SystemWideBlurService] while Android has it bound. */
        @Volatile
        var service: SystemWideBlurService? = null
    }

    private val prefs: SharedPreferences by lazy {
        PreferenceManager.getDefaultSharedPreferences(this)
    }

    private var pendingImage: MethodChannel.Result? = null
    private var pendingCapture: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> result.success(statusMap())

                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setProtectionEnabled(enabled)
                        result.success(statusMap())
                    }

                    "setSensitivity" -> {
                        val level = (call.argument<Number>("level") ?: 5)
                            .toInt().coerceIn(1, 10)
                        prefs.edit().putInt(KEY_SENSITIVITY, level).apply()
                        result.success(statusMap())
                    }

                    "setExclusions" -> {
                        val packages = (call.argument<List<*>>("packages") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                            .toSet()
                        prefs.edit().putStringSet(KEY_EXCLUSIONS, packages).apply()
                        result.success(null)
                    }

                    "setDebugOverlay" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        prefs.edit().putBoolean(KEY_DEBUG_OVERLAY, enabled).apply()
                        service?.setDebugOverlay(enabled)
                        Log.i(TAG, "Debug overlay set to $enabled")
                        result.success(statusMap())
                    }

                    "appDocumentsDirectory" -> {
                        result.success(this.filesDir.path)
                    }


                    "setBlockScreen" -> {
                        BlockPrefs.writeScreen(
                            this,
                            call.argument<String>("title"),
                            call.argument<String>("message"),
                        )
                        result.success(null)
                    }

                    "setBlockedApps" -> {
                        val packages = (call.argument<List<*>>("packages") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                        BlockPrefs.writeBlockedApps(this, packages)
                        Log.i(TAG, "Blocked apps set: ${packages.size}")
                        result.success(null)
                    }

                    "setKeywordBlocklist" -> {
                        val keywords = (call.argument<List<*>>("keywords") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                        BlockPrefs.writeKeywords(this, keywords)
                        Log.i(TAG, "Blocked keywords set: ${keywords.size}")
                        result.success(null)
                    }

                    "setAppSchedules" -> {
                        val args = call.arguments as? Map<*, *>
                        BlockPrefs.writeSchedules(
                            this,
                            args?.get("schedules") as? Map<*, *>,
                        )
                        result.success(null)
                    }

                    "setDailyLimits" -> {
                        val args = call.arguments as? Map<*, *>
                        BlockPrefs.writeLimits(
                            this,
                            args?.get("limits") as? Map<*, *>,
                        )
                        result.success(null)
                    }

                    "listApps" -> result.success(listApps())

                    "setBlockedDomains" -> {
                        val domains = (call.argument<List<*>>("domains") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                        BlockPrefs.writeDomains(this, domains)
                        Log.i(TAG, "Blocked domains set: ${domains.size}")
                        result.success(null)
                    }

                    "setBlockedUrlPatterns" -> {
                        val patterns = (call.argument<List<*>>("patterns") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                        BlockPrefs.writeUrlPatterns(this, patterns)
                        Log.i(TAG, "Blocked URL patterns set: ${patterns.size}")
                        result.success(null)
                    }

                    "setAllowlistedDomains" -> {
                        val domains = (call.argument<List<*>>("domains") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                        BlockPrefs.writeAllowlistedDomains(this, domains)
                        Log.i(TAG, "Allowlisted domains set: ${domains.size}")
                        result.success(null)
                    }

                    "setWholeWordKeywords" -> {
                        val keywords = (call.argument<List<*>>("keywords") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                        BlockPrefs.writeWholeWordKeywords(this, keywords)
                        result.success(null)
                    }

                    "setInAppBrowserApps" -> {
                        val packages = (call.argument<List<*>>("packages") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                        BlockPrefs.writeInAppBrowserApps(this, packages)
                        result.success(null)
                    }

                    "setPrayerPolicy" -> {
                        val args = call.arguments as? Map<*, *>
                        BlockPrefs.writePrayer(
                            this,
                            enabled = args?.get("enabled") as? Boolean ?: false,
                            latitude = (args?.get("latitude") as? Number)?.toDouble(),
                            longitude = (args?.get("longitude") as? Number)?.toDouble(),
                            minutesAfter = (args?.get("minutesAfter") as? Number)?.toInt() ?: 15,
                            method = args?.get("method") as? String,
                        )
                        result.success(null)
                    }

                    "getPrayerTimes" -> result.success(
                        PrayerTimes.preview(this).map {
                            mapOf(
                                "name" to it.name,
                                "start" to it.startMinute,
                                "end" to it.endMinute,
                            )
                        },
                    )

                    "rebaselineNewApps" -> {
                        val apps = listApps().mapNotNull { it["package"] }
                        BlockPrefs.captureBaseline(this, apps)
                        BlockPrefs.captureBrowserBaseline(this, apps.filter { isBrowser(it) })
                        SecurityAudit.record(
                            this,
                            "baseline",
                            "re-based on ${apps.size} installed apps",
                        )
                        result.success(statusMap())
                    }

                    "trustApp" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg.isNullOrBlank()) {
                            result.error("no_package", "No package supplied", null)
                        } else {
                            BlockPrefs.trustPackage(this, pkg)
                            SecurityAudit.record(this, "baseline", "trusted $pkg")
                            result.success(statusMap())
                        }
                    }

                    "getSecurityAudit" -> result.success(SecurityAudit.read(this, 40))

                    "setWhitelistedApps" -> {
                        val packages = (call.argument<List<*>>("packages") ?: emptyList<Any>())
                            .filterIsInstance<String>()
                        BlockPrefs.writeWhitelist(this, packages)
                        result.success(null)
                    }

                    "setFocusState" -> {
                        val args = call.arguments as? Map<*, *>
                        val activeUntil = (args?.get("activeUntil") as? Number)?.toLong() ?: 0L
                        val allowed = (args?.get("allowedApps") as? List<*>)
                            ?.filterIsInstance<String>() ?: emptyList()
                        val preventExit = args?.get("preventExit") as? Boolean ?: false
                        BlockPrefs.writeFocus(this, activeUntil, allowed, preventExit)
                        result.success(null)
                    }

                    "setAdvancedPolicy" -> {
                        val args = call.arguments as? Map<*, *>
                        BlockPrefs.writeAdvanced(this, args)
                        // Turning "block new apps" on snapshots today's apps, so
                        // only apps installed afterwards count as new.
                        if (BlockPrefs.flag(this, BlockPrefs.KEY_BLOCK_NEW_APPS) &&
                            BlockPrefs.baseline(this).isEmpty()
                        ) {
                            BlockPrefs.captureBaseline(
                                this,
                                listApps().mapNotNull { it["package"] },
                            )
                        }
                        // The browser guard snapshots the browsers present now,
                        // so a browser installed later is the thing it blocks.
                        if (BlockPrefs.flag(this, BlockPrefs.KEY_BLOCK_NEW_BROWSERS) &&
                            BlockPrefs.browserBaseline(this).isEmpty()
                        ) {
                            BlockPrefs.captureBrowserBaseline(
                                this,
                                listApps()
                                    .mapNotNull { it["package"] }
                                    .filter { isBrowser(it) },
                            )
                        }
                        SecurityAudit.check(this, "policy-updated")
                        result.success(null)
                    }

                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }

                    "notifyProtectionOff" -> {
                        notifyProtectionOff()
                        result.success(null)
                    }

                    "openAccessibilitySettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }

                    "openNotificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.parse("package:$packageName"))
                        }
                        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }

                    "detectFaces" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("no_image", "No image bytes supplied", null)
                        } else {
                            try {
                                val bitmap = android.graphics.BitmapFactory
                                    .decodeByteArray(bytes, 0, bytes.size)
                                if (bitmap == null) {
                                    result.error("decode_failed", "Could not decode image", null)
                                } else {
                                    val faces = FaceBoxes.detect(this@MainActivity, bitmap)
                                    bitmap.recycle()
                                    Log.i(TAG, "detectFaces: ${faces.size} face(s)")
                                    result.success(faces)
                                }
                            } catch (error: Throwable) {
                                Log.e(TAG, "detectFaces failed", error)
                                result.error(
                                    "face_detect_failed",
                                    error.message ?: "Face detection failed",
                                    null,
                                )
                            }
                        }
                    }

                    "setBlurStrength" -> {
                        val strength = call.argument<String>("strength") ?: "strong"
                        val safe = if (strength in setOf("standard", "strong", "max")) {
                            strength
                        } else {
                            "strong"
                        }
                        prefs.edit().putString(KEY_BLUR_STRENGTH, safe).apply()
                        Log.i(TAG, "Blur strength set to $safe")
                        result.success(statusMap())
                    }

                    "openDeviceAdmin" -> openDeviceAdmin(result)

                    "pickImage" -> requestImage(capture = false, result = result)

                    "takePhoto" -> requestImage(capture = true, result = result)

                    "getLastCapture" -> {
                        val summary = CaptureLog.lastSummary.toMutableMap()
                        summary["preview"] = CaptureLog.lastPreview
                        summary["log"] = CaptureLog.read(this, limit = 50)
                        result.success(summary)
                    }

                    "getCaptureLog" -> result.success(CaptureLog.read(this, limit = 50))

                    "testDeviceAdminIntent" -> result.success(testDeviceAdminIntent())

                    "exportCaptureLog" -> {
                        try {
                            result.success(CaptureLog.exportToDownloads(this))
                        } catch (error: Throwable) {
                            Log.e(TAG, "exportCaptureLog failed", error)
                            result.error(
                                "export_failed",
                                error.message ?: "Could not export the capture log.",
                                null,
                            )
                        }
                    }

                    "clearCaptureLog" -> {
                        CaptureLog.clear(this)
                        result.success(null)
                    }

                    "getProtectionReport" ->
                        result.success(ProtectionHealth.report(this, service))

                    "setProtectionTier" -> {
                        val tier = PolicyEvaluator.Tier.fromWire(
                            call.argument<String>("tier"),
                        )
                        ProtectionHealth.setRequestedTier(this, tier)
                        SecurityAudit.record(
                            this,
                            "protection_tier",
                            "requested ${tier.wire}",
                        )
                        val report = ProtectionHealth.report(this, service).toMutableMap()
                        // report() already downgraded the effective tier when
                        // Android does not report a Device Owner. Say so instead
                        // of leaving a silent mismatch.
                        if (tier == PolicyEvaluator.Tier.HARDENED &&
                            report["tier"] != PolicyEvaluator.Tier.HARDENED.wire
                        ) {
                            report["notice"] =
                                "This device has no verified Device Owner, so Standard " +
                                    "protection is still running. Hardened protection " +
                                    "needs provisioning first."
                        }
                        result.success(report)
                    }

                    "applyHardenedRestrictions" ->
                        result.success(changePolicies(apply = true))

                    "removeHardenedRestrictions" ->
                        result.success(changePolicies(apply = false))

                    "restartDevice" -> result.success(
                        powerResult(PowerControls.restart(this, service)),
                    )

                    "powerOffDevice" -> result.success(
                        powerResult(PowerControls.powerOff(this, service)),
                    )

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Applies or removes every Hardened policy and reports only what Android
     * confirmed afterwards. `ok` is derived from the re-read policy state, never
     * from the absence of an exception: a policy that silently did nothing must
     * not look applied.
     */
    private fun changePolicies(apply: Boolean): Map<String, Any?> {
        if (!DeviceOwner.isDeviceOwner(this)) {
            return mapOf(
                "ok" to false,
                "message" to "Hardened protection needs a verified Device Owner on " +
                    "this device. Nothing was changed.",
                "report" to ProtectionHealth.report(this, service),
            )
        }
        val keys = DeviceOwner.ALL.toSet()
        val results = if (apply) {
            DeviceOwner.apply(this, keys)
        } else {
            DeviceOwner.clear(this, keys)
        }
        val failures = results.filterValues { it != null }
        val policies = DeviceOwner.snapshot(this)
        val unverified = policies.filter { it.facts.readError != null || it.facts.isSet != apply }
        val ok = failures.isEmpty() && unverified.isEmpty()
        val message = when {
            ok && apply ->
                "Android confirmed every restriction: " +
                    DeviceOwner.ALL.joinToString(", ") + "."
            ok -> "Android confirmed that every restriction is removed."
            else -> "Android did not confirm: " +
                unverified.map { it.key }.joinToString(", ") + ". Nothing more is claimed."
        }
        SecurityAudit.record(
            this,
            if (apply) "policy_applied" else "policy_removed",
            if (ok) {
                DeviceOwner.ALL.joinToString(",")
            } else {
                "unverified=" + unverified.joinToString(",") { it.key }
            },
        )
        if (ok) {
            ProtectionHealth.setRequestedTier(
                this,
                if (apply) PolicyEvaluator.Tier.HARDENED else PolicyEvaluator.Tier.STANDARD,
            )
        }
        return mapOf(
            "ok" to ok,
            "message" to message,
            "report" to ProtectionHealth.report(this, service),
        )
    }

    /** One shape for both power actions, with a fresh report attached. */
    private fun powerResult(result: PowerControls.Result): Map<String, Any?> = mapOf(
        "ok" to result.ok,
        "route" to result.route,
        "message" to result.message,
        "report" to ProtectionHealth.report(this, service),
    )

    override fun onResume() {
        super.onResume()
        // The service may have been connected while the activity was paused.
        service?.setEnabled(prefs.getBoolean(KEY_PROTECTION_ENABLED, false))
        // Never leave a blur over our own UI, and never classify it.
        service?.onOwnAppVisible()
    }

    // ------------------------------------------------------------------
    // Image import / capture
    // ------------------------------------------------------------------

    /**
     * Uses the system document picker and camera app directly. image_picker's
     * camera path asks `resolveActivity(ACTION_IMAGE_CAPTURE)`, which Android
     * 11+ package visibility answers with null without a `<queries>` entry, so
     * captures failed with "no_available_camera". These intents need no
     * storage or camera permission and the camera writes through FileProvider.
     */
    private fun requestImage(capture: Boolean, result: MethodChannel.Result) {
        if (pendingImage != null) {
            result.error("busy", "Another image request is still open.", null)
            return
        }

        val intent: Intent
        if (capture) {
            val prepared = newCaptureIntent()
            if (prepared == null) {
                result.error("no_camera", "No camera app is available on this device.", null)
                return
            }
            intent = prepared
        } else {
            intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
            }
        }

        pendingImage = result
        try {
            startActivityForResult(intent, if (capture) REQ_CAPTURE else REQ_PICK)
        } catch (error: Throwable) {
            pendingImage = null
            pendingCapture = null
            val code = if (capture) "no_camera" else "unavailable"
            result.error(code, error.message ?: "Could not open a system app.", null)
        }
    }

    private fun newCaptureIntent(): Intent? {
        val directory = File(cacheDir, "captures").apply { mkdirs() }
        directory.listFiles()?.forEach { it.delete() }
        val output = File(directory, "capture_${System.currentTimeMillis()}.jpg")
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", output)
            pendingCapture = output
            Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                clipData = ClipData.newRawUri("capture", uri)
                addFlags(
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
        } catch (error: Throwable) {
            Log.e(TAG, "Could not prepare camera output", error)
            null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQ_PICK && requestCode != REQ_CAPTURE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val reply = pendingImage
        pendingImage = null
        val captureFile = pendingCapture
        pendingCapture = null
        if (reply == null) return

        if (resultCode != Activity.RESULT_OK) {
            reply.success(null) // Cancelled: not an error.
            return
        }

        Thread {
            try {
                val file = if (requestCode == REQ_CAPTURE) {
                    val captured = captureFile
                    if (captured == null || !captured.exists() || captured.length() == 0L) {
                        throw IllegalStateException("The camera did not write an image.")
                    }
                    captured
                } else {
                    copyPickedImage(data?.data)
                }
                reply.success(file.absolutePath)
            } catch (error: Throwable) {
                reply.error("read_failed", error.message ?: "Could not read the image.", null)
            }
        }.start()
    }

    private fun copyPickedImage(uri: Uri?): File {
        if (uri == null) throw IllegalStateException("The picker returned no image.")
        val directory = File(cacheDir, "picked").apply { mkdirs() }
        directory.listFiles()?.forEach { it.delete() }
        val target = File(directory, "pick_${System.currentTimeMillis()}.img")
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("The selected image could not be opened.")
        if (target.length() == 0L) throw IllegalStateException("The selected image is empty.")
        return target
    }

    /** Launchable apps, for the blocked-apps picker. */
    private fun listApps(): List<Map<String, String>> {
        return try {
            val intent = Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
            val resolved = packageManager.queryIntentActivities(intent, 0)
            val seen = LinkedHashMap<String, String>()
            for (info in resolved) {
                val pkg = info.activityInfo?.packageName ?: continue
                if (pkg == packageName) continue
                if (seen.containsKey(pkg)) continue
                val label = try {
                    info.loadLabel(packageManager).toString()
                } catch (_: Throwable) {
                    pkg
                }
                seen[pkg] = label
            }
            seen.entries
                .sortedBy { it.value.lowercase() }
                .map { mapOf("package" to it.key, "label" to it.value) }
        } catch (error: Throwable) {
            Log.e(TAG, "listApps failed", error)
            emptyList()
        }
    }

    /**
     * Posts the watchdog notification. The app can only *tell* the user that
     * protection stopped; Android gives no app the power to restart an
     * accessibility service or survive a force-stop.
     */
    private fun notifyProtectionOff() {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    WATCHDOG_CHANNEL,
                    "Protection watchdog",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Alerts when screen protection stops running"
                }
                manager.createNotificationChannel(channel)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                Log.w(TAG, "notifyProtectionOff: notification permission not granted")
                return
            }
            val intent = Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            val pending = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, WATCHDOG_CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val notification = builder
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentTitle("Basirah protection is off")
                .setContentText("The accessibility service is not connected. Tap to fix it.")
                .setContentIntent(pending)
                .setAutoCancel(true)
                .build()
            manager.notify(WATCHDOG_NOTIFICATION_ID, notification)
            Log.w(TAG, "Watchdog notification posted: protection not connected")
        } catch (error: Throwable) {
            Log.e(TAG, "notifyProtectionOff failed", error)
        }
    }

    private fun setProtectionEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_PROTECTION_ENABLED, enabled).apply()
        service?.setEnabled(enabled)
        if (!enabled) service?.clearOverlay()
    }

    private fun statusMap(): Map<String, Any?> {
        val events = EventLog.read(this, limit = 50)
        return mapOf(
            "supported" to true,
            "accessibilityEnabled" to ProtectionHealth.isAccessibilityEnabled(this),
            "serviceConnected" to (service != null),
            "protectionEnabled" to prefs.getBoolean(KEY_PROTECTION_ENABLED, false),
            "deviceAdmin" to DeviceOwner.isAdminActive(this),
            "sensitivity" to prefs.getInt(KEY_SENSITIVITY, 5),
            "debugOverlay" to prefs.getBoolean(KEY_DEBUG_OVERLAY, true),
            "blurStrength" to (prefs.getString(KEY_BLUR_STRENGTH, "strong") ?: "strong"),
            "todayBlurs" to EventLog.countToday(this),
            "totalBlurs" to EventLog.countTotal(this),
            "detectorReady" to (service?.isDetectorReady() ?: false),
            "notificationsEnabled" to notificationsEnabled(),
            "batteryOptimizationIgnored" to batteryOptimizationIgnored(),
            "securityAudit" to SecurityAudit.read(this, 10),
            "prayerWindows" to PrayerTimes.preview(this).map {
                mapOf(
                    "name" to it.name,
                    "start" to it.startMinute,
                    "end" to it.endMinute,
                )
            },
            "events" to events,
        )
    }

    /** True when [pkg] can open https links, i.e. is a browser. */
    private fun isBrowser(pkg: String): Boolean = try {
        packageManager.queryIntentActivities(
            Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")),
            0,
        ).any { it.activityInfo?.packageName == pkg }
    } catch (_: Throwable) {
        false
    }

    private fun notificationsEnabled(): Boolean = try {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.areNotificationsEnabled()
    } catch (_: Throwable) {
        true
    }

    private fun batteryOptimizationIgnored(): Boolean = try {
        val power = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        power.isIgnoringBatteryOptimizations(packageName)
    } catch (_: Throwable) {
        true
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
    }

    /**
     * Opens Android's battery-optimisation list rather than the one-tap
     * exemption dialog. The dialog requires
     * REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, a restricted permission Google Play
     * grants only for an accepted list of use cases that does not include
     * content blockers. The permission is therefore not declared; the user
     * opens the list and picks Basirah, which grants the same exemption.
     */
    private fun requestIgnoreBatteryOptimizations() {
        if (batteryOptimizationIgnored()) return
        try {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (error: Throwable) {
            Log.e(TAG, "Could not open battery optimization settings", error)
        }
    }

    /**
     * Builds the exact Activate intent and reports what it resolves to, without
     * launching it. The Settings developer row shows this verbatim so a dead
     * button can never be silent again.
     */
    private fun testDeviceAdminIntent(): Map<String, Any?> {
        val admin = ComponentName(this, DeviceAdmin::class.java)
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return try {
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                .putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Makes it harder to remove Basirah while protection is on.",
                )
            val resolved = intent.resolveActivity(packageManager)
            Log.i(
                TAG,
                "testDeviceAdminIntent: action=${intent.action} " +
                    "component=${admin.flattenToString()} resolved=$resolved",
            )
            mapOf(
                "action" to intent.action,
                "component" to admin.flattenToString(),
                "resolved" to resolved?.flattenToShortString(),
                "active" to dpm.isAdminActive(admin),
                "exception" to null,
            )
        } catch (error: Throwable) {
            Log.e(TAG, "testDeviceAdminIntent failed", error)
            mapOf(
                "action" to DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN,
                "component" to admin.flattenToString(),
                "resolved" to null,
                "active" to dpm.isAdminActive(admin),
                "exception" to (error.message ?: error.toString()),
            )
        }
    }

    /**
     * Opens Android's device-admin activation screen.
     *
     * Every step is logged under HaramBlur so a silent no-op on a device is
     * diagnosable, failures are returned to Dart instead of being swallowed by
     * the bridge, and OEMs without AddDeviceAdminActivity get the security
     * settings fallback rather than nothing.
     */
    private fun openDeviceAdmin(result: MethodChannel.Result) {
        Log.i(TAG, "Channel call received: openDeviceAdmin")
        try {
            val admin = ComponentName(this, DeviceAdmin::class.java)
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val active = dpm.isAdminActive(admin)
            Log.i(TAG, "Device admin active=$active component=${admin.flattenToString()}")

            if (active) {
                val settings = Intent(Settings.ACTION_SECURITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                Log.i(TAG, "Admin already active; starting ${settings.action}")
                startActivity(settings)
                Log.i(TAG, "startActivity returned for ${settings.action}")
                result.success(statusMap())
                return
            }

            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                .putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Makes it harder to remove Basirah while protection is on.",
                )
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            // Launch the system activation dialog directly. resolveActivity()
            // returns null for this action on Android 11+ even though a system
            // handler exists, and gating on it is what made the button open
            // Security settings without ever showing the activation prompt.
            try {
                startActivity(intent)
                Log.i(TAG, "Device-admin activation dialog requested")
            } catch (notFound: android.content.ActivityNotFoundException) {
                Log.w(TAG, "No ADD_DEVICE_ADMIN handler; opening security settings", notFound)
                startActivity(
                    Intent(Settings.ACTION_SECURITY_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(statusMap() + mapOf("deviceAdminFallback" to true))
                return
            }
            result.success(statusMap())
        } catch (error: Throwable) {
            Log.e(TAG, "openDeviceAdmin failed", error)
            result.error(
                "device_admin_failed",
                error.message ?: "Could not open device admin settings.",
                null,
            )
        }
    }

}
