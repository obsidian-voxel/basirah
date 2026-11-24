package com.haramblur.haram_blur

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.TakeScreenshotCallback
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.preference.PreferenceManager
import android.util.Log
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.View.OnAttachStateChangeListener
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.TextView
import android.widget.Toast
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private const val TAG = "HaramBlur"

/**
 * System-wide protection.
 *
 * Android 11+ (API 30) lets an accessibility service take screenshots without
 * MediaProjection. Kotlin only captures the frame and draws the result: every
 * score and every blur region comes from the single Dart engine via
 * [DartDetector], so the screen path, the Image lab and the eval cannot use
 * different preprocessing or policy.
 *
 * Capture policy, chosen to avoid ever showing protected content:
 *  - a capture happens on window changes, on throttled content changes, and
 *    while the screen is clean on a slow timer;
 *  - while the overlay is up no re-capture runs, so the overlay is never
 *    removed just to re-measure the screen it is covering;
 *  - our own package is never captured;
 *  - the exclusion list only disables the awrah/skin stage. Nudity is blocked
 *    in every app, excluded or not, as the user asked.
 */
class SystemWideBlurService : AccessibilityService() {

    companion object {
        private const val CHECK_INTERVAL_MS = 2_000L
        private const val WINDOW_CHANGE_DELAY_MS = 400L
        private const val CONTENT_CHANGE_DELAY_MS = 400L
        private const val CONTENT_CHANGE_THROTTLE_MS = 1_500L
        private const val EVENT_THROTTLE_MS = 30_000L
        private const val OVERLAY_VERIFY_MS = 700L
        private const val ATTACH_RETRY_MS = 300L
        private const val ATTACH_MAX_RETRIES = 3

        /** How long a Dismiss press keeps the pixel path quiet. */
        private const val DISMISS_GRACE_MS = 20_000L

        /** A typed address is checked after the user pauses, not per keystroke. */
        private const val TYPED_URL_DEBOUNCE_MS = 450L

        /** Private mode is remembered for one browser visit, not one screen. */
        private const val PRIVATE_SESSION_MS = 20 * 60 * 1000L

        /** Notification shade scans are expensive; three seconds is plenty. */
        private const val SYSTEM_UI_SCAN_MS = 3_000L

        /** Minimum spacing between Settings escapes, so BACK never loops. */
        private const val SETTINGS_GUARD_MS = 4_000L

        /** Android's own Settings package (AOSP and most OEMs). */
        private const val SETTINGS_PACKAGE = "com.android.settings"

        /**
         * Packages that host Android's Settings pages. Android 16 serves the
         * app-info page from `com.android.settings/.spa.SpaActivity`, Pixels
         * ship Settings Services under `com.google.android.settings…`, and
         * OEMs keep their own namespace. The package only decides where to
         * look: [protectionSettingsWord] still demands our own name plus a
         * destructive action, so a wider net cannot block ordinary Settings.
         */
        private val SETTINGS_PACKAGES = listOf(
            SETTINGS_PACKAGE,
            "com.google.android.settings",
            "com.samsung.android.settings",
        )

        /**
         * One audit entry per escape. Several content-changed callbacks arrive
         * for a single page, and the log is only useful if it says how often
         * the user actually tried.
         */
        private const val SETTINGS_AUDIT_MS = 10_000L

        /** Text is read on window/content changes only, never on the timer. */
        private const val NODE_SCAN_THROTTLE_MS = 1_200L
        private const val USAGE_FLUSH_MS = 30_000L

        /**
         * Never blurred even if Flutter has not pushed its list yet (for
         * example right after a reboot). Mirrors
         * `SettingsStore.defaultExclusions` in Dart.
         */
        private val DEFAULT_EXCLUSIONS = setOf(
            "com.android.camera",
            "com.sec.android.app.camera",
            "com.google.android.apps.photos",
            "com.whatsapp",
            "org.thoughtcrime.securesms",
        )

        /**
         * Windows that are not an app: the lock screen, the keyguard and the
         * system panels. They hold no app content to judge, and running the
         * app rules against them is what blocked the lock screen.
         */
        private val SYSTEM_UI_PACKAGES = setOf(
            "com.android.systemui",
            "com.android.keyguard",
        )

        /**
         * Apps that stay reachable during a focus session: the essentials a
         * person needs to call for help, pay or get home.
         */
        private val ESSENTIAL_APPS = setOf(
            "com.android.phone",
            "com.android.server.telecom",
            "com.android.emergency",
            "com.android.settings",
            "com.android.dialer",
            "com.google.android.dialer",
            "com.android.vending",
            "com.android.contacts",
        )

        /**
         * Rows that only appear on a screen able to disable protection. The
         * Settings guard requires our own name AND one of these, so browsing
         * unrelated Settings pages is untouched.
         */
        private val SENSITIVE_SETTINGS_WORDS = listOf(
            "uninstall",
            "force stop",
            "force-stop",
            "deactivate",
            "accessibility",
            "device admin",
            "device administrator",
            "app info",
            // Arabic.
            "إلغاء التثبيت",
            "إيقاف إجباري",
            "إلغاء التنشيط",
            "إمكانية الوصول",
            "مسؤول الجهاز",
            "معلومات التطبيق",
            // Urdu.
            "ان انسٹال",
            "زبردستی روکیں",
            "رسائی",
            // Turkish.
            "kaldır",
            "zorla durdur",
            "erişilebilirlik",
            "cihaz yöneticisi",
            // Indonesian.
            "copot pemasangan",
            "hentikan paksa",
            "aksesibilitas",
            "admin perangkat",
        )
    }

    private lateinit var windowManager: WindowManager
    private lateinit var powerManager: PowerManager
    private lateinit var overlayView: BlurOverlayView

    /** Locks the screen when the same target is hit over and over. */
    private val repeatGuard = RepeatBlockGuard()
    private lateinit var overlayParams: WindowManager.LayoutParams

    private lateinit var worker: HandlerThread
    private lateinit var captureHandler: Handler

    /**
     * Rule scans run here, not on the capture thread. That thread blocks for
     * up to ten seconds inside face detection, so a window change queued its
     * keyword/site/app scan behind the pixel work and could lose the race to
     * an app restart. Enforcement must never wait for the ML pipeline.
     */
    private lateinit var scanWorker: HandlerThread
    private lateinit var scanHandler: Handler
    private lateinit var captureExecutor: ExecutorService
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var detector: DartDetector

    private val prefs: SharedPreferences by lazy {
        PreferenceManager.getDefaultSharedPreferences(this)
    }

    @Volatile
    private var running = false

    @Volatile
    private var foregroundPackage: String? = null

    @Volatile
    private var overlayAdded = false
    private var capturing = false

    /** Confidence of the blur currently on screen, reused by the fail-safe. */
    private var blurredConfidence = 0.0

    /** Consecutive watchdog failures while a detection is active. */
    private var watchdogFailures = 0

    /** Live debug HUD: NSFW score, skin ratio and the decision per capture. */
    private var debugHud: TextView? = null
    private var debugHudAdded = false
    private var debugHudText = ""

    /** Node-tree scan throttle state: the tree is never read on the tick. */
    private var lastNodeScanAt = 0L
    private var lastNodeScanPackage: String? = null

    /** Foreground seconds accrued for apps with a daily cap. Written by the
     * capture thread (usage ticks) and read by the scan thread (daily limit). */
    private val pendingUsage = java.util.concurrent.ConcurrentHashMap<String, Int>()
    private var pendingUsageSince = 0L

    /** Packages that handle https links, cached from PackageManager. */
    private var browserPackages: Set<String>? = null

    /** Packages with a launcher entry, cached from PackageManager. */
    private var launchablePackages: Set<String>? = null

    private var lastEventAt = 0L
    private var lastEventPackage: String? = null
    private var lastContentTrigger = 0L

    /**
     * App whose block the user dismissed. It is not blocked again until the
     * foreground app changes, otherwise the overlay would reappear instantly
     * and the Dismiss button would be useless.
     */
    private var dismissedPackage: String? = null

    /** Uptime of the last Dismiss press; the grace period starts here. */
    private var dismissedAt = 0L

    /**
     * Browser that showed a private-mode label. Navigating inside the session
     * removes the label from the tree, so the visit is remembered until the
     * browser leaves the foreground.
     */
    private var privateSessionPackage: String? = null
    private var privateSessionAt = 0L

    /** Last text a browser address bar reported, checked after a pause. */
    @Volatile
    private var pendingTypedText: String? = null

    private var lastSystemUiScanAt = 0L
    private var lastSettingsGuardAt = 0L

    /** When the last escape was recorded, and for which screen. */
    private var lastSettingsAuditAt = 0L
    private var lastSettingsScreen: String? = null

    /** Usage counters are keyed by day, so a rollover cannot mix days. */
    private var usageDay = ""

    private var prayerCache: List<PrayerTimes.Window>? = null
    private var prayerCacheDay = ""

    /** Blocklists are read on every window change; cache them per edit. */
    private var cachedKeywords: List<String>? = null
    private var cachedWholeWordKeywords: List<String>? = null
    private var cachedUrlPatterns: List<String>? = null
    private var cachedDomains: List<String>? = null
    private var cachedAllowlist: List<String>? = null

    /** Re-created on package install/removal so a new browser is never stale. */
    private var packageWatcher: BroadcastReceiver? = null

    /** dHash of the last analysed frame and the app it belonged to. */
    private var lastFrameHash = 0L
    private var lastHashPackage: String? = null

    /** True after a real window change, so the next capture is never skipped. */
    private var windowChanged = true

    /**
     * True while a scan the tick asked for is still running. Window enumeration
     * can take seconds against an app that is still starting, so the tick asks
     * again on every beat without queueing a second scan behind the first.
     */
    private val scanInFlight = java.util.concurrent.atomic.AtomicBoolean(false)

    /** Number of remaining attach retries for the current overlay attempt. */
    private var attachRetriesLeft = ATTACH_MAX_RETRIES

    // ------------------------------------------------------------------
    // Reboot / rebind lifecycle
    // ------------------------------------------------------------------

    /**
     * Milestones already logged, keyed `stage|package`: the first window and
     * the first scan are per app, because the service can connect while the
     * launcher is in front and the page that matters comes later. Capped so
     * switching between apps cannot turn a diagnostic into a log stream.
     */
    private val lifecycleSeen = LinkedHashSet<String>()
    private var protectionActiveLogged = false

    /**
     * Chronological milestones for the reboot path (S10): connect, restored
     * preferences, detector, first window, first scan and first enforcement.
     *
     * Package names and counts only. Page text, matched words and preference
     * values never reach logcat, so a diagnostic build does not become a log of
     * what the user was reading. Remove this or lower it to `Log.v` once the
     * harness covers the reboot path.
     */
    private fun lifecycle(stage: String, detail: String = "") {
        Log.i(TAG, "Lifecycle: $stage" + if (detail.isEmpty()) "" else " $detail")
    }

    /** Logs [stage] once per [pkg]; true only on the call that logged it. */
    private fun lifecycleOnce(stage: String, pkg: String, detail: String = ""): Boolean {
        val key = "$stage|$pkg"
        if (!lifecycleSeen.add(key) || lifecycleSeen.size > 12) return false
        lifecycle(stage, "pkg=$pkg" + if (detail.isEmpty()) "" else " $detail")
        return true
    }

    /**
     * A rebind must re-read the protection flag and re-arm the loop, without
     * rebuilding the worker thread, capture executor or Dart engine.
     */
    private fun resumeAfterRebind() {
        // Re-read the flag: the preference may have changed, or been unreadable,
        // since the first connect.
        running = prefs.getBoolean(MainActivity.KEY_PROTECTION_ENABLED, false)
        lifecycle("SERVICE_RECONNECTED", "running=$running")
        SecurityAudit.check(this, "service-rebind")
        captureHandler.removeCallbacks(tick)
        if (running) {
            captureHandler.post(tick)
            adoptForegroundWindow()
        }
    }

    /**
     * The service can connect while an app is already on screen: a cold boot
     * binds tens of seconds after the launcher appears, so a browser opened in
     * that interval produces no window-state change the service can see. The
     * first usable window is therefore judged once at connect instead of
     * waiting for the user to switch apps.
     */
    /**
     * Adopts the window that is actually in front and returns it, or null when
     * the tree has no adoptable app (own UI, a system panel, or no window yet).
     * The return value lets callers tell whether the tree agrees with the
     * package they were about to act on.
     */
    private fun adoptForegroundWindow(): String? {
        val active = try {
            rootInActiveWindow
        } catch (_: Throwable) {
            null
        } ?: return null
        val pkg = try {
            active.packageName?.toString()
        } catch (_: Throwable) {
            null
        } finally {
            recycleQuietly(active)
        }
        if (pkg == null || isOwnPackage(pkg)) return null
        if (isSystemUi(pkg) || isSettingsPackage(pkg)) return null
        if (foregroundPackage == pkg) return pkg
        foregroundPackage = pkg
        windowChanged = true
        lifecycleOnce("FIRST_WINDOW_AVAILABLE", pkg, "source=adopted")
        requestScan(pkg)
        return pkg
    }

    /** One scan at a time: a slow read must not queue a backlog of its own. */
    private fun requestScan(pkg: String) {
        if (!scanInFlight.compareAndSet(false, true)) return
        scanHandler.post {
            try {
                evaluateWindow(pkg)
            } finally {
                scanInFlight.set(false)
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        MainActivity.service = this

        // Android calls onServiceConnected again when the service is rebound
        // without its process being killed. Rebuilding the worker thread, the
        // capture executor and the Dart engine on each of those callbacks
        // leaked one of each and armed a second tick.
        if (::captureHandler.isInitialized) {
            resumeAfterRebind()
            return
        }

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        overlayView = BlurOverlayView(this)
        overlayView.onDismiss = {
            mainHandler.post {
                dismissedPackage = foregroundPackage
                dismissedAt = SystemClock.uptimeMillis()
                hideOverlay()
            }
        }
        overlayParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            // Not focusable, but touchable: the Dismiss button must be able
            // to receive taps while the rest of the screen stays blocked.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.FILL
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
        }

        worker = HandlerThread("haram-blur-capture").also { it.start() }
        captureHandler = Handler(worker.looper)
        scanWorker = HandlerThread("haram-blur-scan").also { it.start() }
        scanHandler = Handler(scanWorker.looper)
        captureExecutor = Executors.newSingleThreadExecutor()

        detector = DartDetector(applicationContext)
        // Starting the Flutter engine loads libflutter.so and verifies the whole
        // app: 27 s on a cold boot. Doing that inside onServiceConnected held
        // the accessibility main thread past the system's service-start
        // timeout, so the binding was re-created over and over (five connects
        // in two minutes) and the teardown marked a live instance as not
        // running, which silently skipped the enforcement of a block that had
        // already matched. The bind now returns immediately; the engine warms
        // up behind it and [DartDetector.analyze] still starts it lazily.

        running = prefs.getBoolean(MainActivity.KEY_PROTECTION_ENABLED, false)
        lifecycle(
            "SERVICE_CONNECTED",
            "pid=${android.os.Process.myPid()} instance=${System.identityHashCode(this)} " +
                "running=$running",
        )
        // Counts only: this proves the whole policy survived the reboot without
        // putting the user's lists or terms into the log.
        lifecycle(
            "PREFERENCES_RESTORED",
            "entries=${prefs.all.size} keywords=${BlockPrefs.keywords(this).size}/" +
                "${BlockPrefs.wholeWordKeywords(this).size} " +
                "apps=${BlockPrefs.blockedApps(this).size} " +
                "sites=${BlockPrefs.domains(this).size} " +
                "allowlist=${BlockPrefs.allowlistedDomains(this).size} " +
                "settingsGuard=${BlockPrefs.guardSettings(this)}",
        )
        usageDay = BlockPrefs.dayKey()
        prefs.registerOnSharedPreferenceChangeListener(prefListener)
        watchPackages()
        // Uninstall protection is audited at every service start, not assumed
        // to still be active because it was once switched on.
        SecurityAudit.check(this, "service-start")
        // Protection health is re-read from Android on every bind, so the
        // dashboard never has to trust a cached answer.
        ProtectionHealth.onServiceConnected(this)
        if (running) {
            mainHandler.post { detector.ensureStarted() }
            captureHandler.post(tick)
            lifecycle("PROTECTION_ARMED", "foreground=${foregroundPackage ?: "-"}")
            adoptForegroundWindow()
        } else {
            lifecycle("PROTECTION_IDLE", "reason=system_wide_enabled is false")
        }
    }

    /**
     * A list edit must be visible to the very next window change. The service
     * used to hold the previous list until Android recreated it.
     */
    private val prefListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            when (key) {
                BlockPrefs.KEY_KEYWORDS -> cachedKeywords = null
                BlockPrefs.KEY_WHOLEWORD_KEYWORDS -> cachedWholeWordKeywords = null
                BlockPrefs.KEY_URL_PATTERNS -> cachedUrlPatterns = null
                BlockPrefs.KEY_BLOCKED_DOMAINS -> cachedDomains = null
                BlockPrefs.KEY_ALLOWLISTED_DOMAINS -> cachedAllowlist = null
            }
        }

    /**
     * The browser and launcher package lists were cached forever, so a browser
     * installed after the service started could never be recognised as one.
     */
    private fun watchPackages() {
        if (packageWatcher != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                invalidatePackageCaches()
                if (intent?.action == Intent.ACTION_PACKAGE_ADDED) {
                    SecurityAudit.record(
                        this@SystemWideBlurService,
                        "package_installed",
                        intent.data?.schemeSpecificPart.orEmpty(),
                    )
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        try {
            registerReceiver(receiver, filter)
            packageWatcher = receiver
        } catch (_: Throwable) {
            // A restricted context is not worth crashing the service over.
        }
    }

    private fun invalidatePackageCaches() {
        browserPackages = null
        launchablePackages = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return

        // A typed address is judged before the page loads, which is the one
        // moment the domain is guaranteed to be in the tree.
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED) {
            onTextChanged(pkg, event)
            return
        }
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            onContentChanged(pkg)
            return
        }
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        // Our own windows (the blur overlay, or the real app) must never be
        // treated as "another app came forward": doing that hid the blur in
        // the same frame it was drawn. Opening the real app calls
        // [onOwnAppVisible] from MainActivity, so a stale blur still clears.
        if (pkg == packageName) return

        if (isSettingsPackage(pkg)) guardSettings(pkg)

        // The lock screen and system panels are not an app: nothing to judge,
        // nothing to block, and a blur must not float over the keyguard. The
        // shade is still worth reading: a notification preview is a place
        // explicit content appears without opening an app.
        if (isSystemUi(pkg)) {
            foregroundPackage = pkg
            dismissedPackage = null
            dismissedAt = 0L
            captureHandler.removeCallbacks(captureNow)
            mainHandler.post { hideOverlay() }
            scanSystemUi(pkg)
            return
        }

        val sameAppWhileBlurred = overlayAdded && pkg == foregroundPackage
        // A private-mode label is only on the incognito new tab; the visit is
        // what is remembered, and it ends when the browser does.
        if (privateSessionPackage != null && pkg != privateSessionPackage) {
            privateSessionPackage = null
        }
        foregroundPackage = pkg
        windowChanged = true
        lifecycleOnce("FIRST_WINDOW_AVAILABLE", pkg)
        if (pkg != dismissedPackage) {
            dismissedPackage = null
            dismissedAt = 0L
        }

        captureHandler.removeCallbacks(captureNow)
        if (!running || isOwnPackage(pkg)) {
            mainHandler.post { hideOverlay() }
            return
        }

        // Defense in depth runs before any pixel work: app/schedule/limit
        // blocks need no capture, and the node tree is read on its own thread
        // so neither the main thread nor the pixel pipeline can delay it.
        scanHandler.post { evaluateWindow(pkg) }

        // A new window inside the app that is already blurred (dialog, video,
        // navigation) must not uncover it: a fresh screenshot is only possible
        // with the overlay removed, which would show the content for the whole
        // capture delay. Keep the cover until the user leaves the app.
        if (sameAppWhileBlurred) return

        // Drop the old overlay first so the new screen is captured unblurred.
        mainHandler.post { hideOverlay() }
        captureHandler.postDelayed(captureNow, WINDOW_CHANGE_DELAY_MS)
    }

    /**
     * Scrolling a feed or a gallery changes what is on screen without a window
     * change. One capture per second at most, and never while a blur is up.
     */
    private fun onContentChanged(pkg: String) {
        if (!running || overlayAdded || isOwnPackage(pkg)) return
        if (isSystemUi(pkg)) {
            foregroundPackage = pkg
            scanSystemUi(pkg)
            return
        }
        if (isSettingsPackage(pkg)) {
            guardSettings(pkg)
            return
        }
        foregroundPackage = pkg
        scanHandler.post { evaluateWindow(pkg) }
        val now = SystemClock.uptimeMillis()
        if (now - lastContentTrigger < CONTENT_CHANGE_THROTTLE_MS) return
        lastContentTrigger = now
        captureHandler.removeCallbacks(captureNow)
        captureHandler.postDelayed(captureNow, CONTENT_CHANGE_DELAY_MS)
    }

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        // The system can unbind a service the user still wants — and on this
        // image a `uiautomator` dump (UiAutomation) tears the connection down
        // and re-creates it. That is not a user decision: the intent lives in
        // `system_wide_enabled`. Clearing `running` here skipped the
        // enforcement of a block that had already matched
        // (`Block skipped: ... running=false`), leaving the page on screen.
        // The loops are paused; the next bind re-arms them.
        lifecycle("SERVICE_UNBOUND", "instance=${System.identityHashCode(this)} running=$running")
        ProtectionHealth.onServiceUnbound(this)
        if (::captureHandler.isInitialized) {
            captureHandler.removeCallbacks(tick)
            captureHandler.removeCallbacks(captureNow)
        }
        mainHandler.removeCallbacks(overlayVerify)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        lifecycle("SERVICE_DESTROYED", "instance=${System.identityHashCode(this)}")
        running = false
        flushUsage()
        prefs.unregisterOnSharedPreferenceChangeListener(prefListener)
        packageWatcher?.let { receiver ->
            try {
                unregisterReceiver(receiver)
            } catch (_: Throwable) {
                // Already gone with the process.
            }
        }
        packageWatcher = null
        mainHandler.post {
            hideOverlay()
            hideDebugHud()
        }
        if (::captureHandler.isInitialized) {
            captureHandler.removeCallbacksAndMessages(null)
        }
        if (::scanHandler.isInitialized) scanHandler.removeCallbacksAndMessages(null)
        mainHandler.removeCallbacks(overlayVerify)
        if (::worker.isInitialized) worker.quitSafely()
        if (::scanWorker.isInitialized) scanWorker.quitSafely()
        if (::captureExecutor.isInitialized) captureExecutor.shutdownNow()
        if (::detector.isInitialized) detector.shutdown()
        if (MainActivity.service === this) MainActivity.service = null
        super.onDestroy()
    }

    // ------------------------------------------------------------------
    // Control API used by MainActivity
    // ------------------------------------------------------------------

    fun setEnabled(enabled: Boolean) {
        running = enabled
        if (!::captureHandler.isInitialized) return
        captureHandler.removeCallbacks(tick)
        captureHandler.removeCallbacks(captureNow)
        mainHandler.removeCallbacks(overlayVerify)
        if (enabled) {
            captureHandler.post(tick)
            // Block immediately if the app on screen right now is on a list,
            // instead of waiting for the next window event.
            foregroundPackage?.let { pkg ->
                if (!isOwnPackage(pkg)) scanHandler.post { evaluateWindow(pkg) }
            }
        } else {
            flushUsage()
            mainHandler.post {
                hideOverlay()
                hideDebugHud()
            }
        }
    }

    fun refreshSensitivity() {
        // Thresholds are derived in Dart from the level sent with each frame,
        // so there is nothing to recompute natively.
    }

    fun clearOverlay() {
        mainHandler.post {
            hideOverlay()
            hideDebugHud()
        }
    }

    /** Shows or hides the live capture HUD without touching the blur overlay. */
    fun setDebugOverlay(enabled: Boolean) {
        mainHandler.post {
            if (enabled && running) showDebugHud() else hideDebugHud()
        }
    }

    /**
     * Called when Basirah's own activity is visible. Clears any blur left
     * over it and stops the timer from classifying our own UI.
     */
    fun onOwnAppVisible() {
        foregroundPackage = packageName
        mainHandler.post { hideOverlay() }
    }

    fun isDetectorReady(): Boolean = ::detector.isInitialized && detector.isReady

    /** The last Dart engine failure, for the protection report (null if none). */
    fun detectorError(): String? = if (::detector.isInitialized) detector.lastError else null

    /**
     * Opens Android's own power dialog. This is the only power action an
     * accessibility service can perform: the user confirms in the system UI,
     * and Basirah never claims the phone has restarted before it has.
     */
    fun openPowerDialog(): Boolean = try {
        performGlobalAction(GLOBAL_ACTION_POWER_DIALOG)
    } catch (_: Throwable) {
        false
    }

    // ------------------------------------------------------------------
    // Capture loop
    // ------------------------------------------------------------------

    private val tick = object : Runnable {
        override fun run() {
            try {
            if (!running) return
            var pkg = foregroundPackage
            // A bind can happen while the page is already on screen (right
            // after a reboot, or after Android re-created the connection) and
            // no window event follows it. Adopt what is in front instead of
            // waiting for the user to switch apps.
            if (pkg == null) {
                adoptForegroundWindow()
                pkg = foregroundPackage
            }
            // A scan that found no window yet (a browser still starting after
            // a reboot reads an empty tree), or that read the window before the
            // page inside it had rendered, must not be the last word: the page
            // appears with no further window event (run 20261123T094754Z read
            // the Chrome URL and 150 characters of toolbar, then never looked
            // again). The foreground app is therefore re-read on every beat;
            // scanNodeTree's own throttle keeps that to one read a second and
            // scanInFlight keeps a slow read from stacking up behind itself.
            val pending = pkg
            if (pending != null && !isOwnPackage(pending) && !isSystemUi(pending)) {
                // Window events can leave foregroundPackage naming an app that
                // is no longer in front (the launcher keeps its window in the
                // tree while the browser holds focus), and then this retry would
                // re-read the wrong app until the user switches apps again.
                // The tree is the authority here; adoption queues its own scan
                // when it finds a different package, so only retry `pending`
                // when the tree still agrees with it.
                val actual = adoptForegroundWindow() ?: pending
                if (actual == pending) requestScan(pending)
            }
            // A detector that never becomes ready is degraded protection, not
            // silence: the transition is recorded once and shown on the
            // dashboard. Rules-based blocking keeps working throughout.
            ProtectionHealth.onDetectorState(
                this@SystemWideBlurService,
                detector.isReady,
                detector.lastError,
            )
            // The lock screen and the system panels are not an app: neither
            // judge their pixels nor run app rules against them.
            if (pkg != null && isSystemUi(pkg)) return
            if (pkg != null && !isOwnPackage(pkg)) {
                accountUsage(pkg)
                // A missed window event must not leave a blocked app open.
                if (!overlayAdded && !isDismissed(pkg) && checkHardBlocks(pkg)) {
                    return
                }
            }
            if (pkg != null && !isOwnPackage(pkg) && !overlayAdded &&
                !isDismissed(pkg) && powerManager.isInteractive
            ) {
                capture()
            } else if (pkg != null && overlayAdded && !isOwnPackage(pkg)) {
                // Verify on the main thread: it owns the overlay window.
                mainHandler.post {
                    if (running && overlayAdded &&
                        (!overlayView.isAttachedToWindow ||
                            overlayView.windowVisibility != View.VISIBLE)
                    ) {
                        watchdogFailures++
                        Log.w(TAG, "Watchdog tick #$watchdogFailures: overlay detached or invisible; pkg=$pkg")
                        if (watchdogFailures >= 3) {
                            quitForegroundApp(pkg, blurredConfidence, "WATCHDOG_REMOVED")
                            watchdogFailures = 0
                        }
                    } else {
                        watchdogFailures = 0
                    }
                }
            }
            } finally {
                // Always reschedule, including after a hard-block return.
                captureHandler.postDelayed(this, CHECK_INTERVAL_MS)
            }
        }
    }

    private val captureNow = Runnable {
        if (!running) return@Runnable
        val pkg = foregroundPackage ?: return@Runnable
        if (!isOwnPackage(pkg)) capture()
    }

    private fun capture() {
        // Never capture over our own block overlay: the screenshot would be of
        // the cover, not of the app. A system window is not app content either.
        if (capturing || overlayAdded) return
        foregroundPackage?.let { pkg ->
            if (isSystemUi(pkg)) return
            // The Dismiss button buys a short quiet period; after it expires
            // the same screen is judged again instead of being a free pass.
            if (isDismissed(pkg)) return
        }
        capturing = true
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                captureExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(
                        screenshot: android.accessibilityservice.AccessibilityService.ScreenshotResult,
                    ) {
                        val frame = try {
                            ScreenshotConverter.convert(screenshot)
                        } catch (error: Throwable) {
                            Log.e(TAG, "Could not convert screenshot", error)
                            null
                        }
                        if (frame == null) {
                            capturing = false
                            return
                        }
                        onCaptured(frame)
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.w(TAG, "takeScreenshot failed: $errorCode")
                        capturing = false
                    }
                },
            )
        } catch (_: Throwable) {
            // Screenshot unavailable (secure window, service paused): retry on
            // the next tick instead of crashing the service.
            capturing = false
        }
    }

    /** Runs on the capture thread once pixels exist; Dart does the scoring. */
    private fun onCaptured(frame: CapturedFrame) {
        val pkg = foregroundPackage
        if (pkg == null || !running || isOwnPackage(pkg)) {
            frame.preview.recycle()
            frame.overlayFrame.recycle()
            capturing = false
            mainHandler.post { hideOverlay() }
            return
        }

        // Cheap perceptual check before touching the model: a secure window
        // or a blank screen is a flat shade, so there is nothing to classify.
        val flat = try {
            FrameHash.isFlat(frame.preview)
        } catch (_: Throwable) {
            false
        }
        if (flat) {
            logSkipped(pkg, frame, "flat_frame")
            frame.preview.recycle()
            frame.overlayFrame.recycle()
            capturing = false
            return
        }

        // Cheap perceptual check before touching the model: an unchanged
        // screen (paused video, static page) keeps the current state.
        val hash = try {
            FrameHash.of(frame.preview)
        } catch (_: Throwable) {
            -1L
        }
        if (hash >= 0 && !windowChanged && pkg == lastHashPackage &&
            FrameHash.distance(hash, lastFrameHash) <= FrameHash.SAME_SCREEN_DISTANCE
        ) {
            logSkipped(pkg, frame)
            frame.preview.recycle()
            frame.overlayFrame.recycle()
            capturing = false
            return
        }
        if (hash >= 0) {
            lastFrameHash = hash
            lastHashPackage = pkg
            windowChanged = false
        }

        val started = System.currentTimeMillis()
        val sensitivity = prefs.getInt(MainActivity.KEY_SENSITIVITY, 5)
        // Real face boxes, normalised to this working frame. Detection runs on
        // the capture thread; no face means the exposure rule has no exclusion.
        val faces = FaceBoxes.detect(frame.preview)
        detector.analyze(
            frame,
            sensitivity,
            allowAwrah = !isAwrahExcluded(pkg),
            faces = faces,
        ) { analysis ->
            val elapsed = System.currentTimeMillis() - started
            // Feed the HUD exactly what the engine measured, before any blur
            // decision is drawn, so PASS captures are visible too.
            val decision = when {
                analysis == null -> "ERROR"
                analysis.regions.isEmpty() -> "PASS"
                else -> "BLOCK"
            }
            updateDebugHud(
                "NSFW: ${formatScore(analysis?.score ?: 0.0)}\n" +
                    "Skin: ${formatScore(analysis?.maxExposed ?: 0.0)}\n" +
                    "Decision: $decision",
            )
            // PNG encoding and file I/O must not run on the platform main
            // thread; the capture executor owns the preview bitmap.
            try {
                captureExecutor.execute {
                    logCapture(pkg, frame, analysis, elapsed)
                    frame.preview.recycle()
                }
            } catch (_: Throwable) {
                frame.preview.recycle()
            }
            try {
                if (analysis == null || analysis.regions.isEmpty()) {
                    frame.overlayFrame.recycle()
                    mainHandler.post { hideOverlay() }
                    // Exposed skin that stayed under the block threshold is
                    // still worth recording: these are the borderline cases
                    // the tuning work needs to see.
                    if (analysis != null && analysis.maxExposed > 0.0 &&
                        !isAwrahExcluded(pkg)
                    ) {
                        recordExposedBelowThreshold(pkg, analysis.maxExposed)
                    }
                    return@analyze
                }

                // Regions stay in working-frame pixels. The overlay maps
                // frame → view exactly once using its own measured size; any
                // pre-scaling here is what produced the floating thumbnail.
                val regions = analysis.regions.map {
                    OverlayGeometry.FrameRect(it.left, it.top, it.right, it.bottom)
                }
                val reason = if (analysis.regions.any { it.kind == "nudity" }) {
                    "nsfw"
                } else {
                    "exposure"
                }

                mainHandler.post {
                    // Drop a stale frame if the user switched apps meanwhile.
                    if (!running || foregroundPackage != pkg) {
                        frame.overlayFrame.recycle()
                        return@post
                    }
                    if (showOverlay(frame.overlayFrame, frame.width, frame.height, regions)) {
                        recordEvent(pkg, reason, analysis.score)
                        keepBlurred(blurredConfidence = analysis.score)
                        // The block is full-screen; re-add the HUD so the
                        // decision stays readable above it.
                        promoteDebugHud()
                        // Drive the user out of the content: three BACKs in a
                        // row close most apps; the full-screen block remains
                        // if they do not.
                        nudgeBack(pkg)
                    } else {
                        // Nudity was detected but we could not cover it: leaving
                        // the content on screen is the one outcome that must
                        // never happen.
                        quitForegroundApp(pkg, analysis.score, "ATTACH_FAILED")
                    }
                }
            } finally {
                // preview is recycled by the logging task above; overlayFrame
                // is owned by the overlay once shown.
                capturing = false
            }
        }
    }

    /** Records a capture that was skipped before inference. */
    private fun logSkipped(
        pkg: String,
        frame: CapturedFrame,
        reason: String = "frame_hash_match",
    ) {
        CaptureLog.record(
            this,
            mapOf(
                "t" to System.currentTimeMillis(),
                "pkg" to pkg,
                "w" to frame.width,
                "h" to frame.height,
                "rowPadding" to frame.rowPadding,
                "decision" to "skipped",
                "regions" to 0,
                "rules" to "",
                "ms" to 0,
                "engine" to "dart",
                "reason" to reason,
            ),
            null,
        )
    }

    private fun logCapture(
        pkg: String,
        frame: CapturedFrame,
        analysis: DartDetector.Analysis?,
        elapsed: Long,
    ) {
        val decision = when {
            analysis == null -> "engine_error"
            analysis.regions.isEmpty() -> "clean"
            else -> "blur"
        }
        CaptureLog.record(
            this,
            mapOf(
                "t" to System.currentTimeMillis(),
                "pkg" to pkg,
                "w" to frame.width,
                "h" to frame.height,
                "stride" to frame.stride,
                "rowPadding" to frame.rowPadding,
                "gate" to analysis?.gate,
                "score" to analysis?.score,
                "fullScore" to analysis?.fullScore,
                "exposed" to analysis?.maxExposed,
                "persons" to analysis?.personCount,
                "regions" to (analysis?.regions?.size ?: 0),
                "rules" to (analysis?.regions?.map { it.rule }?.distinct()?.joinToString(",") ?: ""),
                "decision" to decision,
                "ms" to elapsed,
                "engine" to "dart",
                "awrahAllowed" to !isAwrahExcluded(pkg),
                "detectorReady" to detector.isReady,
                "detectorError" to detector.lastError,
            ),
            frame.preview,
        )
    }

    /**
     * Three BACK presses, 200 ms apart, to close the offending app. Each one
     * re-checks that the app is still foreground and still not excluded.
     */
    private fun nudgeBack(pkg: String, force: Boolean = false) {
        if (!running) return
        if (!force && isAwrahExcluded(pkg)) return
        for (index in 0 until 3) {
            mainHandler.postDelayed({
                if (running && foregroundPackage == pkg &&
                    (force || !isAwrahExcluded(pkg))
                ) {
                    performGlobalAction(GLOBAL_ACTION_BACK)
                }
            }, 200L * index)
        }
    }

    /** Logs "exposed skin" at 0% confidence with the measured ratio as its score. */
    private fun recordExposedBelowThreshold(pkg: String, ratio: Double) {
        val now = System.currentTimeMillis()
        if (pkg == lastEventPackage && now - lastEventAt < EVENT_THROTTLE_MS) return
        lastEventPackage = pkg
        lastEventAt = now
        EventLog.append(this, pkg, "exposed skin", 0.0, ratio)
    }

    private fun recordEvent(
        packageName: String,
        reason: String,
        confidence: Double,
        force: Boolean = false,
    ) {
        val now = System.currentTimeMillis()
        if (!force && packageName == lastEventPackage &&
            now - lastEventAt < EVENT_THROTTLE_MS
        ) {
            return
        }
        lastEventPackage = packageName
        lastEventAt = now
        EventLog.append(this, packageName, reason, confidence)
    }

    // ------------------------------------------------------------------
    // Rule-based blocking: app, schedule, limit, private mode, URL, keyword
    // ------------------------------------------------------------------

    /** Hard blocks first, then the node tree. Capture thread only. */
    private fun evaluateWindow(pkg: String) {
        if (!running || isOwnPackage(pkg) || isSystemUi(pkg) || foregroundPackage != pkg) return
        // While a dismissal is in its grace period the app rules stay quiet
        // (otherwise Dismiss does nothing), but a page that turns out to hold
        // a blocked site or word is still caught by the node scan.
        if (checkHardBlocks(pkg, skipAppRules = isDismissed(pkg))) return
        scanNodeTree(pkg)
    }

    /** True while a Dismiss press still covers this app. */
    private fun isDismissed(pkg: String): Boolean =
        pkg == dismissedPackage &&
            SystemClock.uptimeMillis() - dismissedAt <= DISMISS_GRACE_MS

    /**
     * Blocks that need no pixels: the app blocklist, allowed hours and the
     * daily cap. This is the most reliable layer in the app.
     */
    private fun checkHardBlocks(pkg: String, skipAppRules: Boolean = false): Boolean {
        if (!running || isOwnPackage(pkg)) return false
        // No app rules apply to the lock screen or a system panel.
        if (isSystemUi(pkg)) return false
        // One block at a time: a visible overlay already covers the screen.
        if (overlayAdded) return false
        if (skipAppRules) return false

        val whitelist = BlockPrefs.whitelist(this)

        // Focus mode locks every app that is not explicitly allowed, so the
        // session holds even if the blocklist is edited while it runs.
        if (BlockPrefs.focusActive(this)) {
            val allowed = BlockPrefs.focusAllowedApps(this)
            if (pkg !in allowed && pkg !in ESSENTIAL_APPS) {
                hardBlock(
                    pkg,
                    "focus",
                    "Blocked: ${appLabel(pkg)} is locked during this focus session.",
                )
                return true
            }
        }

        if (BlockPrefs.blockedApps(this).contains(pkg) && pkg !in whitelist) {
            hardBlock(pkg, "app", "Blocked: ${appLabel(pkg)} is on your blocklist.")
            return true
        }

        val window = BlockPrefs.schedules(this)[pkg]
        if (window != null && !BlockPrefs.withinWindow(window)) {
            hardBlock(
                pkg,
                "schedule",
                "Blocked: ${appLabel(pkg)} is only allowed " +
                    "${BlockPrefs.windowLabel(window)}.",
            )
            return true
        }

        val limit = BlockPrefs.limits(this)[pkg] ?: 0
        if (limit > 0) {
            // Unflushed seconds count too: otherwise the cap could be exceeded
            // by up to one flush interval.
            val used = BlockPrefs.usedSeconds(this, pkg) + (pendingUsage[pkg] ?: 0)
            if (used >= limit * 60) {
                hardBlock(pkg, "dailyLimit", "Blocked: daily limit of $limit min reached.")
                return true
            }
        }

        // Salah-aware scheduling: the five prayers become windows from the
        // user's own coordinates, computed on this device every day.
        val prayer = prayerWindowNow()
        if (prayer != null && pkg !in ESSENTIAL_APPS && pkg !in whitelist) {
            hardBlock(
                pkg,
                "prayer",
                "Blocked: ${prayer.name} time (${clockLabel(prayer.startMinute)}).",
                prayer.name,
            )
            return true
        }

        // Anything installed after protection was set up is untrusted: a new
        // browser or dating app is exactly the impulsive bypass path.
        if (BlockPrefs.flag(this, BlockPrefs.KEY_BLOCK_NEW_APPS)) {
            val baseline = BlockPrefs.baseline(this)
            // The baseline only holds launcher apps, so a package without an
            // icon (system UI, an input method, a background service) would
            // otherwise look like it was installed after protection.
            if (baseline.isNotEmpty() && !baseline.contains(pkg) && isLaunchable(pkg)) {
                hardBlock(
                    pkg,
                    "newApp",
                    "Blocked: ${appLabel(pkg)} was installed after protection was set up.",
                )
                return true
            }
        }

        // The browser counterpart of the rule above. The switch existed in the
        // UI and in preferences but nothing ever read it.
        if (BlockPrefs.flag(this, BlockPrefs.KEY_BLOCK_NEW_BROWSERS)) {
            val baseline = BlockPrefs.browserBaseline(this)
            if (baseline.isNotEmpty() && isBrowserPackage(pkg) &&
                !baseline.contains(pkg) && pkg !in whitelist
            ) {
                hardBlock(
                    pkg,
                    "newBrowser",
                    "Blocked: ${appLabel(pkg)} was installed after protection was set up.",
                )
                return true
            }
        }

        if (BlockPrefs.flag(this, BlockPrefs.KEY_BLOCK_UNSUPPORTED_BROWSERS) &&
            isBrowserPackage(pkg) && !NodeText.isBrowser(pkg)
        ) {
            hardBlock(pkg, "app", "Blocked: ${appLabel(pkg)} is an unsupported browser.")
            return true
        }
        return false
    }

    /**
     * Every window owned by [pkg], active window first.
     *
     * Reading `windows` is also what makes a WebView expose its page tree: a
     * WebView builds that tree on the first request for a window root, so a
     * scan limited to `rootInActiveWindow` saw only the browser chrome.
     */
    private fun appWindows(pkg: String): List<AccessibilityNodeInfo> {
        val found = ArrayList<AccessibilityNodeInfo>(2)
        val active = try {
            rootInActiveWindow
        } catch (_: Throwable) {
            null
        }
        if (active != null) {
            val activePkg = try {
                active.packageName?.toString()
            } catch (_: Throwable) {
                null
            }
            if (activePkg == pkg) found.add(active) else recycleQuietly(active)
        }
        try {
            for (window in windows.orEmpty()) {
                if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                if (found.any { it.windowId == window.id }) continue
                val node = try {
                    window.root
                } catch (_: Throwable) {
                    null
                } ?: continue
                val nodePkg = try {
                    node.packageName?.toString()
                } catch (_: Throwable) {
                    null
                }
                if (nodePkg == pkg) found.add(node) else recycleQuietly(node)
            }
        } catch (_: Throwable) {
            // No interactive-window list on this device; the active root stands.
        }
        return found
    }

    private fun recycleQuietly(node: AccessibilityNodeInfo) {
        try {
            node.recycle()
        } catch (_: Throwable) {
            // Already recycled by the platform.
        }
    }

    /** One scan's text from all of the app's windows, with the first non-empty
     * URL and private-mode hint. Keeps the per-window reads independent. */
    private fun mergeScans(scans: List<NodeText.Scan>): NodeText.Scan {
        if (scans.isEmpty()) return NodeText.Scan("", "", null)
        if (scans.size == 1) return scans[0]
        val text = StringBuilder()
        var url = ""
        var privateHint: String? = null
        var hasWebView = false
        var nodes = 0
        for (scan in scans) {
            if (text.length < 20_000) text.append(scan.text)
            if (url.isEmpty()) url = scan.url
            if (privateHint == null) privateHint = scan.privateHint
            hasWebView = hasWebView || scan.hasWebView
            nodes += scan.nodeCount
        }
        return NodeText.Scan(text.toString(), url, privateHint, hasWebView, nodes)
    }

    /**
     * Diagnostics only: which windows the service can currently see, with each
     * root's package and child count. Chrome hosts page content in a subtree of
     * its own window, so a scan that reads the toolbar but not the page has to
     * be able to say whether the content window exists at all.
     */
    private fun windowSummary(): String = try {
        windows.orEmpty().joinToString(";") { window ->
            val node = try {
                window.root
            } catch (_: Throwable) {
                null
            }
            val pkg = try {
                node?.packageName?.toString()
            } catch (_: Throwable) {
                null
            } ?: "?"
            val kids = try {
                node?.childCount ?: -1
            } catch (_: Throwable) {
                -1
            }
            try {
                node?.recycle()
            } catch (_: Throwable) {
                // Platform already recycled it.
            }
            "t${window.type}:$pkg/$kids"
        }
    } catch (_: Throwable) {
        "?"
    }

    /** True when [pkg] has a launcher icon, i.e. is an app people open. */
    private fun isLaunchable(pkg: String): Boolean {
        val cached = launchablePackages ?: try {
            packageManager.queryIntentActivities(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
                0,
            ).mapNotNull { it.activityInfo?.packageName }.toSet().also {
                launchablePackages = it
            }
        } catch (_: Throwable) {
            emptySet()
        }
        return cached.contains(pkg)
    }

    /** Lock screen, keyguard and system panels: never an app to block. */
    private fun isSystemUi(pkg: String): Boolean =
        pkg in SYSTEM_UI_PACKAGES || pkg.endsWith(".systemui")

    /**
     * True when [pkg] can open https links (i.e. is a browser).
     */
    private fun isBrowserPackage(pkg: String): Boolean {
        val cached = browserPackages ?: try {
            packageManager.queryIntentActivities(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")),
                0,
            ).mapNotNull { it.activityInfo?.packageName }.toSet().also { browserPackages = it }
        } catch (_: Throwable) {
            emptySet()
        }
        return cached.contains(pkg)
    }

    /**
     * True when the active window occupies noticeably less than the screen,
     * which is what split screen and free-form windows look like.
     */
    private fun isSplitScreen(root: android.view.accessibility.AccessibilityNodeInfo): Boolean {
        val metrics = android.util.DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)
        val screenWidth = metrics.widthPixels
        val screenHeight = metrics.heightPixels
        if (screenWidth <= 0 || screenHeight <= 0) return false

        // Interactive windows are the authoritative view: split screen and
        // free-form windows are shorter than the display, and the root bounds
        // lie when an app draws a full-bleed layout inside a small task.
        try {
            val interactive = windows
            if (!interactive.isNullOrEmpty()) {
                for (window in interactive) {
                    if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                    if (window.id == root.windowId) continue
                    val other = android.graphics.Rect()
                    window.getBoundsInScreen(other)
                    if (other.height() > 0 && other.height() < screenHeight * 0.75) {
                        return true
                    }
                }
                val own = android.graphics.Rect()
                root.getBoundsInScreen(own)
                return own.height() > 0 && own.height() < screenHeight * 0.75
            }
        } catch (_: Throwable) {
            // No interactive-window list: fall back to the area test.
        }

        val bounds = android.graphics.Rect()
        root.getBoundsInScreen(bounds)
        if (bounds.width() <= 0 || bounds.height() <= 0) return false
        val covered = bounds.width().toDouble() * bounds.height().toDouble()
        val total = screenWidth.toDouble() * screenHeight.toDouble()
        if (total <= 0.0) return false
        // A full-screen app covers (almost) everything; split screen does not.
        return covered / total < 0.85
    }

    /**
     * Reads the active window once, then blocks on a confident private-mode
     * label, a blocked domain in the URL, or a blocked keyword in the text.
     */
    private fun scanNodeTree(pkg: String) {
        if (!running || isOwnPackage(pkg) || overlayAdded) return
        val now = SystemClock.uptimeMillis()
        if (pkg == lastNodeScanPackage && now - lastNodeScanAt < NODE_SCAN_THROTTLE_MS) {
            return
        }
        lastNodeScanAt = now
        lastNodeScanPackage = pkg

        // Read every window that belongs to the foreground app, not just
        // rootInActiveWindow. Chrome hosts the page in its own window and
        // initialises the web-content provider lazily, on the first request
        // for a window root: asking only for the active window returned the
        // browser toolbar and no page text at all. Enumerating the app's
        // windows both initialises that provider and covers apps that split
        // their UI across windows.
        val windowsStarted = SystemClock.uptimeMillis()
        val roots = appWindows(pkg)
        if (roots.isEmpty()) {
            // Silence here is indistinguishable from "the page is clean": a
            // service that cannot read the window has to say so, with how long
            // the enumeration took — on a cold boot it can block for tens of
            // seconds against a starting browser.
            Log.d(
                TAG,
                "Node scan: no window for $pkg after=" +
                    "${SystemClock.uptimeMillis() - windowsStarted}ms",
            )
            return
        }
        val root = roots.first()
        // Captured before the roots are recycled; diagnostics only.
        val rootKids = root.childCount
        val windowPkg = try {
            root.packageName?.toString().orEmpty()
        } catch (_: Throwable) {
            "?"
        }


        // Split screen shrinks the app window, which is a classic way to run
        // a blocked app next to something else. Dialogs and permission sheets
        // of a non-launchable package are not split screen.
        if (BlockPrefs.flag(this, BlockPrefs.KEY_BLOCK_SPLIT_SCREEN) &&
            isLaunchable(pkg) &&
            isSplitScreen(root)
        ) {
            hardBlock(pkg, "splitScreen", "Blocked: split screen is not allowed.")
            return
        }

        val scans = ArrayList<NodeText.Scan>(roots.size)
        for (candidate in roots) {
            try {
                scans.add(NodeText.collect(candidate, pkg))
            } catch (error: Throwable) {
                Log.w(TAG, "Node scan failed", error)
            } finally {
                try {
                    candidate.recycle()
                } catch (_: Throwable) {
                    // Already recycled by the platform.
                }
            }
        }
        val scan = mergeScans(scans)

        // Private mode is only trusted inside a known browser with an explicit
        // incognito/private label, so false positives stay rare. The label is
        // only on the new-tab screen, so the visit is remembered: otherwise
        // the first navigation turned every private session into a free one.
        val privateSession = pkg == privateSessionPackage &&
            SystemClock.uptimeMillis() - privateSessionAt <= PRIVATE_SESSION_MS
        if ((scan.privateHint != null || privateSession) &&
            BlockPrefs.flag(this, BlockPrefs.KEY_BLOCK_INCOGNITO)
        ) {
            if (scan.privateHint != null) {
                privateSessionPackage = pkg
                privateSessionAt = SystemClock.uptimeMillis()
            }
            hardBlock(
                pkg,
                "privateMode",
                "Private mode blocked.",
                scan.privateHint ?: "private session",
            )
            return
        }

        // Embedded browsers inside social and shopping apps are a common
        // bypass: the blocked site opens without ever touching the real
        // browser. Off by default because it also blocks ordinary help pages.
        // The user can scope the rule to the apps that actually host the
        // bypass, instead of disabling it everywhere because one help page
        // opened inside a shopping app was a false positive.
        val inAppScope = BlockPrefs.inAppBrowserApps(this)
        if (BlockPrefs.flag(this, BlockPrefs.KEY_BLOCK_INAPP_BROWSERS) &&
            scan.hasWebView && !NodeText.isBrowser(pkg) &&
            (inAppScope.isEmpty() || pkg in inAppScope)
        ) {
            hardBlock(
                pkg,
                "inAppBrowser",
                "Blocked: in-app browsers are disabled. Open links in your browser.",
            )
            return
        }

        // A trusted site wins over every site list. A hash index cannot
        // express "everything except this one", so this is the only way to
        // repair a false positive in the bundled 952k-domain table.
        val allowlisted = isAllowlisted(scan.url)

        // Sites: a domain hit is unambiguous. Your own list is a short string
        // list in preferences; the bundled list is the hash index, searched by
        // host suffix.
        if (!allowlisted && scan.url.isNotEmpty()) {
            val domainHit = BlockPrefs.matchingDomain(domains(), scan.url)
            if (domainHit != null) {
                hardBlock(
                    pkg,
                    "url",
                    "Blocked: $domainHit is on your site list.",
                    domainHit,
                )
                return
            }
            if (AdultDomainIndex.isBlocked(this, scan.url)) {
                val host = BlockPrefs.hostOf(scan.url)
                hardBlock(
                    pkg,
                    "url",
                    "Blocked: $host is on the adult-site list.",
                    host,
                )
                return
            }

            // Bundled URL patterns: search queries and TLDs that a host suffix
            // cannot express (`*q=*porn*`, `*.xxx`). URL only, never text.
            val patterns = urlPatterns()
            if (patterns.isNotEmpty()) {
                val patternHit = BlockMatcher.firstMatch(patterns, scan.url)
                if (patternHit != null) {
                    hardBlock(
                        pkg,
                        "url",
                        "Blocked: this page matches \"$patternHit\".",
                        patternHit,
                    )
                    return
                }
            }
        }

        val keywords = keywords()
        val exactKeywords = wholeWordKeywords()
        // Diagnostics: a scan that read the browser but not the page is
        // indistinguishable from a clean page without the raw numbers. The
        // sample proves which window was read and how much of it.
        // Counts only: the page text and the user's keyword list never go into
        // logcat. What is left is enough to see which window was read and
        // whether the scanner had text, a URL and rules to work with.
        Log.d(
            TAG,
            "Node scan: pkg=$pkg root=$windowPkg nodes=${scan.nodeCount} chars=${scan.text.length} " +
                "rootKids=$rootKids wins=${windowSummary()} " +
                "url=${scan.url} private=${scan.privateHint} webview=${scan.hasWebView} " +
                "kws=${keywords.size}/${exactKeywords.size}",
        )
        // The dashboard's "last successful scan" is this exact point: the rules
        // were read and a screen was scanned. Throttled inside the recorder.
        ProtectionHealth.markScan(this)
        if (lifecycleOnce(
                "FIRST_SCAN_COMPLETED",
                pkg,
                "nodes=${scan.nodeCount} chars=${scan.text.length} " +
                    "kws=${keywords.size}/${exactKeywords.size}",
            )
        ) {
            if (keywords.isEmpty() && exactKeywords.isEmpty()) {
                lifecycle("MATCHER_EMPTY", "rules=0")
            } else {
                lifecycle("MATCHER_READY", "rules=${keywords.size + exactKeywords.size}")
            }
        }
        if (keywords.isEmpty() && exactKeywords.isEmpty()) return

        if (!allowlisted && scan.url.isNotEmpty()) {
            val urlHit = BlockMatcher.firstMatch(keywords, scan.url)
                ?: BlockMatcher.firstMatch(exactKeywords, scan.url, wholeWord = true)
            if (urlHit != null) {
                hardBlock(pkg, "url", "Blocked: this page matches \"$urlHit\".", urlHit)
                return
            }
        }
        // Whole-word keywords exist because the native matcher used to ignore
        // the `wholeWord` option the Dart reference implements.
        val textHit = BlockMatcher.firstMatch(keywords, scan.text)
            ?: BlockMatcher.firstMatch(exactKeywords, scan.text, wholeWord = true)
        if (textHit != null) {
            // The decision and the enforcement are separate steps on separate
            // threads; logging only the scan made a missed block unfalsifiable.
            Log.i(TAG, "Keyword match: pkg=$pkg hit=$textHit")
            hardBlock(pkg, "keyword", "Blocked: the page contains \"$textHit\".", textHit)
        }
    }

    /** Covers the screen, logs the reason and closes the app. Main thread. */
    private fun hardBlock(
        pkg: String,
        reason: String,
        message: String,
        matched: String? = null,
    ) {
        mainHandler.post {
            if (!running || foregroundPackage != pkg) {
                Log.d(
                    TAG,
                    "Block skipped: pkg=$pkg fg=$foregroundPackage running=$running reason=$reason",
                )
                return@post
            }
            val lockUntil = repeatLock(pkg, reason, matched)
            updateDebugHud(
                buildString {
                    append("NSFW: n/a").append('\n')
                    append("Skin: n/a").append('\n')
                    append("Decision: BLOCK").append('\n')
                    append("Reason: ").append(reason)
                    if (matched != null) append('\n').append("Matched: ").append(matched)
                },
            )
            if (showBlockOverlay(message, lockUntil)) {
                if (!protectionActiveLogged) {
                    protectionActiveLogged = true
                    lifecycle("PROTECTION_ACTIVE", "pkg=$pkg reason=$reason")
                }
                promoteDebugHud()
                recordEvent(pkg, reason, 1.0, force = true)
                nudgeBack(pkg, force = true)
            } else {
                // Nudity was not involved, but leaving the content visible is
                // never acceptable.
                quitForegroundApp(pkg, 1.0, "ATTACH_FAILED")
            }
        }
    }

    /**
     * Returns the uptime to keep the screen locked until, when this block is
     * one of several attempts at the same target. Never blocks permanently:
     * the guard forgets the burst once it fires.
     */
    private fun repeatLock(pkg: String, reason: String, matched: String?): Long {
        if (!BlockPrefs.flag(this, BlockPrefs.KEY_CROSS_BLOCK_LIMIT)) return 0L
        // A block right after Dismiss is the block the user just dismissed,
        // not a fresh attempt at a new target. Counting it turned one press
        // into a five-minute lock.
        if (isDismissed(pkg)) return 0L
        val key = "$pkg|$reason|${matched.orEmpty()}"
        return repeatGuard.onBlock(key, SystemClock.uptimeMillis()) ?: 0L
    }

    // ------------------------------------------------------------------
    // Cached policy + typed URLs + Settings guard + prayer windows
    // ------------------------------------------------------------------

    private fun keywords(): List<String> =
        cachedKeywords ?: BlockPrefs.keywords(this).also { cachedKeywords = it }

    private fun wholeWordKeywords(): List<String> =
        cachedWholeWordKeywords
            ?: BlockPrefs.wholeWordKeywords(this).also { cachedWholeWordKeywords = it }

    private fun urlPatterns(): List<String> =
        cachedUrlPatterns ?: BlockPrefs.urlPatterns(this).also { cachedUrlPatterns = it }

    private fun domains(): List<String> =
        cachedDomains ?: BlockPrefs.domains(this).also { cachedDomains = it }

    private fun allowlistedDomains(): List<String> =
        cachedAllowlist
            ?: BlockPrefs.allowlistedDomains(this).also { cachedAllowlist = it }

    private fun isAllowlisted(url: String): Boolean {
        if (url.isEmpty()) return false
        return BlockPrefs.matchingDomain(allowlistedDomains(), url) != null
    }

    /**
     * An address bar reports each keystroke. The text is kept until the user
     * pauses, then only the host is checked: a page that has not loaded yet
     * cannot be judged by its pixels or its text.
     */
    private fun onTextChanged(pkg: String, event: AccessibilityEvent) {
        if (!running || overlayAdded || isOwnPackage(pkg) || isSystemUi(pkg)) return
        if (!NodeText.isBrowser(pkg)) return
        val typed = event.text?.joinToString(" ")?.trim().orEmpty()
        if (typed.isEmpty()) return
        pendingTypedText = typed
        captureHandler.removeCallbacks(typedUrlCheck)
        captureHandler.postDelayed(typedUrlCheck, TYPED_URL_DEBOUNCE_MS)
    }

    private val typedUrlCheck = Runnable {
        val typed = pendingTypedText ?: return@Runnable
        pendingTypedText = null
        val pkg = foregroundPackage ?: return@Runnable
        blockTypedUrl(pkg, typed)
    }

    private fun blockTypedUrl(pkg: String, raw: String) {
        if (!running || overlayAdded || isOwnPackage(pkg) || isSystemUi(pkg)) return
        if (foregroundPackage != pkg || !NodeText.isBrowser(pkg)) return
        val url = NodeText.typedUrl(raw) ?: return
        if (isAllowlisted(url)) return
        val custom = BlockPrefs.matchingDomain(domains(), url)
        val bundled = custom == null && AdultDomainIndex.isBlocked(this, url)
        if (custom == null && !bundled) return
        val label = custom ?: BlockPrefs.hostOf(url)
        hardBlock(pkg, "url", "Blocked: $label is blocked.", label)
    }

    /**
     * Notification previews are readable without opening anything, so the
     * expanded shade is scanned for blocked words. Pixels are never captured
     * and no app rule applies; only a keyword hit blocks.
     */
    private fun scanSystemUi(pkg: String) {
        if (!running || overlayAdded || !powerManager.isInteractive) return
        val now = SystemClock.uptimeMillis()
        if (now - lastSystemUiScanAt < SYSTEM_UI_SCAN_MS) return
        lastSystemUiScanAt = now
        val keywords = keywords()
        val exact = wholeWordKeywords()
        if (keywords.isEmpty() && exact.isEmpty()) return
        val roots = try {
            windows.orEmpty()
                .filter { it.type == AccessibilityWindowInfo.TYPE_SYSTEM }
                .mapNotNull { window ->
                    try {
                        window.root
                    } catch (_: Throwable) {
                        null
                    }
                }
        } catch (_: Throwable) {
            emptyList()
        }
        if (roots.isEmpty()) return
        val text = StringBuilder()
        for (root in roots) {
            try {
                text.append(NodeText.collect(root, pkg).text)
            } catch (_: Throwable) {
                // A window that vanished mid-read is not a failure.
            } finally {
                try {
                    root.recycle()
                } catch (_: Throwable) {
                    // Platform already recycled it.
                }
            }
            if (text.length > 20_000) break
        }
        if (text.isBlank()) return
        val hit = BlockMatcher.firstMatch(keywords, text.toString())
            ?: BlockMatcher.firstMatch(exact, text.toString(), wholeWord = true)
            ?: return
        hardBlock(pkg, "keyword", "Blocked: a notification contains \"$hit\".", hit)
    }

    /**
     * Leaves the Android screens that can switch protection off.
     *
     * An accessibility service cannot prevent a tap inside Settings, but it
     * can see the app-info, accessibility and device-admin pages and take the
     * user back out of them. Only screens that name Basirah and offer an
     * uninstall, force-stop, accessibility or admin action are affected, so
     * ordinary Settings use is untouched.
     */
    /** Settings, and the packages that host its pages (see [SETTINGS_PACKAGES]). */
    private fun isSettingsPackage(pkg: String): Boolean =
        SETTINGS_PACKAGES.any { pkg == it || pkg.startsWith("$it.") }

    /**
     * Leaves the Android screens that can switch protection off.
     *
     * An accessibility service cannot prevent a tap inside Settings, but it
     * can see the app-info, accessibility and device-admin pages and take the
     * user back out of them. Only screens that name Basirah and offer an
     * uninstall, force-stop, accessibility or admin action are affected, so
     * ordinary Settings use is untouched.
     *
     * Android 16 re-hosts the app-info page as
     * `com.android.settings/.spa.SpaActivity`, so the screen is identified from
     * its text, never from the activity class, and the package's application
     * windows are read instead of `rootInActiveWindow` alone: a re-hosted SPA
     * is not guaranteed to be in the active window's subtree.
     */
    private fun guardSettings(pkg: String) {
        if (!running || !BlockPrefs.guardSettings(this)) return
        if (!powerManager.isInteractive) return
        val now = SystemClock.uptimeMillis()
        if (now - lastSettingsGuardAt < SETTINGS_GUARD_MS) return
        lastSettingsGuardAt = now
        val roots = appWindows(pkg)
        if (roots.isEmpty()) {
            Log.d(TAG, "Settings guard: no window for $pkg")
            return
        }
        val scans = ArrayList<NodeText.Scan>(roots.size)
        try {
            for (root in roots) scans.add(NodeText.collect(root, pkg))
        } catch (_: Throwable) {
            // A window that vanished mid-read is not an escape attempt.
        } finally {
            for (root in roots) recycleQuietly(root)
        }
        val text = mergeScans(scans).text
        if (text.isBlank()) {
            Log.d(TAG, "Settings guard: empty tree for $pkg")
            return
        }
        // Diagnostics name the matched action word, never the page content.
        val word = protectionSettingsWord(text) ?: return
        Log.d(TAG, "Settings guard: $pkg shows \"$word\" next to our name")
        val screen = text.replace('\n', ' ').take(80)
        if (screen == lastSettingsScreen && now - lastSettingsAuditAt < SETTINGS_AUDIT_MS) {
            Log.d(TAG, "Settings guard: repeated callback for the same screen, not recorded twice")
            return
        }
        lastSettingsScreen = screen
        lastSettingsAuditAt = now
        SecurityAudit.record(
            this,
            "settings_escape",
            text.replace('\n', ' ').take(120),
        )
        Toast.makeText(
            this,
            "Protection settings are changed inside Basirah.",
            Toast.LENGTH_SHORT,
        ).show()
        performGlobalAction(GLOBAL_ACTION_BACK)
    }

    /**
     * The sensitive action a protected screen offers, or null when the screen is
     * ordinary Settings. Both halves are required: our own name *and* an action
     * that can switch protection off.
     */
    private fun protectionSettingsWord(text: String): String? {
        if (text.isEmpty()) return null
        val lower = text.lowercase()
        val label = appLabel(packageName).lowercase()
        val mentionsUs = lower.contains(label) || lower.contains(packageName)
        if (!mentionsUs) return null
        return SENSITIVE_SETTINGS_WORDS.firstOrNull { lower.contains(it) }
    }

    /** The prayer window that contains the current minute, or null. */
    private fun prayerWindowNow(): PrayerTimes.Window? {
        if (!BlockPrefs.prayerEnabled(this)) return null
        val day = BlockPrefs.dayKey()
        if (day != prayerCacheDay) {
            prayerCache = PrayerTimes.today(this)
            prayerCacheDay = day
        }
        val now = Calendar.getInstance()
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return prayerCache?.firstOrNull { it.contains(minute) }
    }

    private fun clockLabel(minute: Int): String =
        "%02d:%02d".format(minute / 60, minute % 60)

    /** Foreground seconds for the daily caps. Only capped apps are counted. */
    private fun accountUsage(pkg: String) {
        // Time spent looking at the block screen is not time spent using the
        // app; counting it burned the day's budget while the user was locked
        // out, and the midnight reset then handed out a second budget.
        if (overlayAdded) return
        if (!BlockPrefs.limits(this).containsKey(pkg)) return
        val day = BlockPrefs.dayKey()
        if (day != usageDay) {
            // Never carry seconds across midnight: they belong to yesterday.
            pendingUsage.clear()
            pendingUsageSince = 0L
            usageDay = day
        }
        val tickSeconds = (CHECK_INTERVAL_MS / 1000).toInt()
        pendingUsage[pkg] = (pendingUsage[pkg] ?: 0) + tickSeconds
        val now = SystemClock.uptimeMillis()
        if (pendingUsageSince == 0L) pendingUsageSince = now
        if (now - pendingUsageSince >= USAGE_FLUSH_MS) flushUsage()
    }

    private fun flushUsage() {
        if (pendingUsage.isEmpty()) return
        for ((pkg, seconds) in pendingUsage) {
            BlockPrefs.addUsage(this, pkg, seconds)
        }
        pendingUsage.clear()
        pendingUsageSince = 0L
    }

    private fun appLabel(pkg: String): String = try {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (_: Throwable) {
        pkg
    }

    // ------------------------------------------------------------------
    // Overlay
    // ------------------------------------------------------------------

    /**
     * Main thread only. Returns true only when the blur is actually attached and
     * visible, so the caller can fall back to leaving the app instead of
     * reporting a blur that nobody can see.
     */
    private fun showOverlay(
        preview: Bitmap,
        frameWidth: Int,
        frameHeight: Int,
        regions: List<OverlayGeometry.FrameRect>,
    ): Boolean {
        if (overlayAdded && !overlayView.isAttachedToWindow) {
            detachOverlay() // Platform removed it behind our back: start clean.
        }
        if (overlayAdded) {
            overlayView.setCopy(BlockPrefs.screenTitle(this), BlockPrefs.screenMessage(this))
            overlayView.setLock(0L)
            overlayView.setFrame(preview, frameWidth, frameHeight, regions)
            return verifyOverlayAttached()
        }
        overlayView.setCopy(BlockPrefs.screenTitle(this), BlockPrefs.screenMessage(this))
        overlayView.setLock(0L)
        overlayView.setFrame(preview, frameWidth, frameHeight, regions)
        return attachOverlayWindow()
    }

    /** Rule-based block: no captured frame, just the reason and its source. */
    private fun showBlockOverlay(message: String, lockUntil: Long = 0L): Boolean {
        if (overlayAdded && !overlayView.isAttachedToWindow) {
            detachOverlay()
        }
        if (overlayAdded) {
            overlayView.setCopy(BlockPrefs.screenTitle(this), BlockPrefs.screenMessage(this))
            overlayView.setBlockMessage(message)
            overlayView.setLock(lockUntil)
            return verifyOverlayAttached()
        }
        overlayView.setCopy(BlockPrefs.screenTitle(this), BlockPrefs.screenMessage(this))
        overlayView.setBlockMessage(message)
        overlayView.setLock(lockUntil)
        return attachOverlayWindow()
    }

    /** Adds the overlay window and verifies it actually became visible. */
    private fun attachOverlayWindow(): Boolean {
        return try {
            windowManager.addView(overlayView, overlayParams)
            overlayAdded = true
            attachRetriesLeft = ATTACH_MAX_RETRIES
            overlayView.addOnAttachStateChangeListener(object : OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) {
                    Log.d(TAG, "Overlay view attached to window")
                    if (overlayAdded) {
                        if (verifyOverlayAttached()) {
                            Log.d(TAG, "Overlay attach verified via listener")
                        } else {
                            scheduleAttachRetry()
                        }
                    }
                }

                override fun onViewDetachedFromWindow(v: View) {
                    Log.d(TAG, "Overlay view detached from window")
                    overlayAdded = false
                }
            })
            attemptAttachVerification()
        } catch (_: Throwable) {
            overlayView.clear()
            overlayAdded = false
            Log.e(TAG, "addView threw: could not add overlay window")
            false
        }
    }

    private fun attemptAttachVerification(): Boolean {
        if (verifyOverlayAttached()) {
            Log.d(TAG, "Overlay attach verified immediately")
            return true
        }
        if (attachRetriesLeft <= 0) {
            Log.w(TAG, "Attach verification exhausted $ATTACH_MAX_RETRIES retries: declaring ATTACH_FAILED")
            return false
        }
        attachRetriesLeft--
        mainHandler.postDelayed(attachRetryRunnable, ATTACH_RETRY_MS)
        // The retry loop owns failure reporting; returning true here means
        // "pending", and the watchdog exits the app if it never attaches.
        return true
    }

    private val attachRetryRunnable = object : Runnable {
        override fun run() {
            if (verifyOverlayAttached()) {
                Log.d(TAG, "Overlay attach verified on retry")
                attachRetriesLeft = ATTACH_MAX_RETRIES
            } else if (attachRetriesLeft > 0) {
                attachRetriesLeft--
                mainHandler.postDelayed(this, ATTACH_RETRY_MS)
            } else {
                Log.w(TAG, "Attach verification exhausted $ATTACH_MAX_RETRIES retries: declaring ATTACH_FAILED")
                attachRetriesLeft = ATTACH_MAX_RETRIES
                detachOverlay()
            }
        }
    }

    /** Returns true once the overlay is attached+visible, false otherwise. */
    private fun verifyOverlayAttached(): Boolean {
        return overlayView.isAttachedToWindow &&
            overlayView.windowVisibility == View.VISIBLE
    }

    private fun scheduleAttachRetry() {
        if (attachRetriesLeft > 0) {
            attachRetriesLeft--
            mainHandler.postDelayed(attachRetryRunnable, ATTACH_RETRY_MS)
        } else {
            Log.w(TAG, "Attach verification exhausted $ATTACH_MAX_RETRIES retries: declaring ATTACH_FAILED")
            attachRetriesLeft = ATTACH_MAX_RETRIES
            detachOverlay()
        }
    }

    private fun detachOverlay() {
        mainHandler.removeCallbacks(overlayVerify)
        try {
            windowManager.removeViewImmediate(overlayView)
        } catch (_: Throwable) {
            // Already detached.
        }
        overlayView.clear()
        overlayAdded = false
    }

    // ------------------------------------------------------------------
    // Live debug HUD
    // ------------------------------------------------------------------

    private fun debugOverlayEnabled(): Boolean =
        prefs.getBoolean(MainActivity.KEY_DEBUG_OVERLAY, true)

    /** Capture-thread safe: the HUD lives on the main thread's window manager. */
    private fun updateDebugHud(text: String) {
        debugHudText = text
        if (!running || !debugOverlayEnabled()) return
        mainHandler.post { showDebugHud() }
    }

    /** Main thread only. Adds the HUD window the first time it is needed. */
    private fun showDebugHud() {
        if (!running || !debugOverlayEnabled()) return
        if (!::windowManager.isInitialized) return
        val view = debugHud ?: TextView(this).also {
            it.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            it.setTextColor(Color.WHITE)
            it.setBackgroundColor(Color.argb(150, 0, 0, 0))
            val pad = (8 * resources.displayMetrics.density).toInt()
            it.setPadding(pad, pad / 2, pad, pad / 2)
            it.isClickable = false
            it.isFocusable = false
            debugHud = it
        }
        view.text = debugHudText
        if (debugHudAdded && view.isAttachedToWindow) return
        try {
            windowManager.addView(view, debugHudParams())
            debugHudAdded = true
            if (view.isAttachedToWindow && view.windowVisibility == View.VISIBLE) {
                Log.i(TAG, "Debug HUD visible at top-right: $debugHudText")
            } else {
                Log.w(TAG, "Debug HUD added but not visible")
            }
        } catch (error: Throwable) {
            debugHudAdded = false
            Log.w(TAG, "Could not add debug HUD", error)
        }
    }

    /** Main thread only. */
    private fun hideDebugHud() {
        val view = debugHud ?: return
        if (!debugHudAdded && !view.isAttachedToWindow) return
        try {
            windowManager.removeViewImmediate(view)
        } catch (_: Throwable) {
            // Already detached.
        }
        debugHudAdded = false
    }

    /** Main thread only. Re-adds the HUD so it stacks above a new blur window. */
    private fun promoteDebugHud() {
        if (!debugHudAdded) return
        hideDebugHud()
        showDebugHud()
    }

    /**
     * Accessibility overlay window: drawn above every app, but never focusable
     * and never touchable, so it cannot steal input from the app underneath.
     */
    private fun debugHudParams(): WindowManager.LayoutParams =
        WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            val margin = (12 * resources.displayMetrics.density).toInt()
            x = margin
            y = margin + (40 * resources.displayMetrics.density).toInt()
        }

    private fun formatScore(value: Double): String =
        String.format(Locale.US, "%.2f", value)

    /** Main thread only. */
    private fun hideOverlay() {
        if (!::overlayView.isInitialized) return
        mainHandler.removeCallbacks(overlayVerify)
        blurredConfidence = 0.0
        if (overlayAdded || overlayView.isAttachedToWindow) {
            detachOverlay()
        } else {
            overlayView.clear()
        }
    }

    /**
     * Fail-safe requested by the user: if nudity is detected but the blur is
     * not on screen, leave the app rather than leave the content visible.
     *
     * `GLOBAL_ACTION_HOME` is the only way an accessibility service can take
     * the user out of an app.
     */
    private fun quitForegroundApp(pkg: String, confidence: Double, reason: String) {
        if (foregroundPackage != pkg) return
        hideOverlay()
        // Never throttled: this is a safety action, not a repeat blur.
        recordEvent(pkg, reason, confidence, force = true)
        Log.w(TAG, "Fail-safe triggered: reason=$reason pkg=$pkg confidence=$confidence")
        performGlobalAction(GLOBAL_ACTION_HOME)
        // Any in-flight capture now belongs to the app we just left; dropping
        // the package stops a stale frame from being drawn over the launcher.
        foregroundPackage = null
        watchdogFailures = 0
        val msg = when (reason) {
            "ATTACH_FAILED" -> "Basirah could not attach the blur overlay, so it closed the app."
            "WATCHDOG_REMOVED" -> "Basirah overlay was removed, so it closed the app."
            "EVENT_HIDDEN" -> "Basirah overlay was hidden by the system, so it closed the app."
            else -> "Basirah could not cover this screen, so it closed the app."
        }
        Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
    }

    private fun keepBlurred(blurredConfidence: Double) {
        this.blurredConfidence = blurredConfidence
        mainHandler.removeCallbacks(overlayVerify)
        mainHandler.postDelayed(overlayVerify, OVERLAY_VERIFY_MS)
    }

    private val overlayVerify = object : Runnable {
        override fun run() {
            if (!running || !overlayAdded) return
            val pkg = foregroundPackage ?: return
            if (pkg == packageName) return
            if (!overlayView.isAttachedToWindow ||
                overlayView.windowVisibility != View.VISIBLE
            ) {
                watchdogFailures++
                Log.w(TAG, "OverlayVerify tick #$watchdogFailures: overlay not visible; pkg=$pkg")
                if (watchdogFailures >= 3) {
                    quitForegroundApp(pkg, blurredConfidence, "WATCHDOG_REMOVED")
                    watchdogFailures = 0
                }
                return
            }
            watchdogFailures = 0
            mainHandler.postDelayed(this, CHECK_INTERVAL_MS)
        }
    }

    // ------------------------------------------------------------------
    // Filtering
    // ------------------------------------------------------------------

    private fun isOwnPackage(pkg: String): Boolean = pkg == packageName

    /**
     * Apps the user excluded from body/awrah blur (camera, gallery, private
     * messengers by default). Nudity is still blocked there: the exclusion
     * only suppresses the segmentation-based skin stage, never the whole-frame
     * gate.
     */
    private fun isAwrahExcluded(pkg: String): Boolean {
        if (isOwnPackage(pkg)) return true
        val custom = prefs.getStringSet(MainActivity.KEY_EXCLUSIONS, null) ?: emptySet()
        return custom.contains(pkg) || DEFAULT_EXCLUSIONS.contains(pkg)
    }

    /** Exposed for diagnostics in the Flutter UI. */
    fun isRunning(): Boolean = running
}
