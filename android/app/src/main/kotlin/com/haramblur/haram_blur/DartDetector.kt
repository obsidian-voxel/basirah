package com.haramblur.haram_blur

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "HaramBlur"

/**
 * Hosts the headless Dart engine that runs the one inference + policy
 * implementation.
 *
 * Kotlin no longer scores frames: it captures pixels, sends them here, and
 * draws whatever regions Dart returns. The engine is the app's real Dart code,
 * so the screen path, the Image lab and the tests cannot drift apart.
 */
class DartDetector(context: Context) {

    data class Region(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
        val kind: String,
        val confidence: Double,
        val evidence: String,
        /** gate_full, gate_crop, exposed or band. */
        val rule: String,
    )

    data class Analysis(
        val score: Double,
        val fullScore: Double,
        val gate: Double,
        val regions: List<Region>,
        val personCount: Int,
        val maxExposed: Double,
        val elapsedMs: Long,
    )

    companion object {
        const val CHANNEL = "com.haramblur.haram_blur/detector"
        private const val TIMEOUT_MS = 6_000L
        private const val STARTUP_GRACE_MS = 20_000L
    }

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var starting = false
    private var startedAt = 0L

    @Volatile
    var isReady = false
        private set

    @Volatile
    var lastError: String? = null
        private set

    /** Starts the engine if needed. Main thread only. */
    fun ensureStarted() {
        if (engine != null || starting) return
        starting = true
        try {
            val loader = FlutterLoader()
            loader.startInitialization(appContext)
            loader.ensureInitializationComplete(appContext, null)

            val created = FlutterEngine(appContext)
            created.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "detectorMain"),
            )
            val createdChannel = MethodChannel(created.dartExecutor.binaryMessenger, CHANNEL)
            createdChannel.setMethodCallHandler { call, result ->
                if (call.method == "ready") {
                    isReady = true
                    lastError = null
                    Log.i(TAG, "Dart detector ready after ${System.currentTimeMillis() - startedAt} ms")
                    Log.i(
                        TAG,
                        "Lifecycle: DETECTOR_READY after=${System.currentTimeMillis() - startedAt}ms",
                    )
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
            engine = created
            channel = createdChannel
            startedAt = System.currentTimeMillis()
            Log.i(TAG, "Starting Dart detector engine")
        } catch (error: Throwable) {
            lastError = error.message ?: error.toString()
            Log.e(TAG, "Could not start Dart detector", error)
            Log.e(TAG, "Lifecycle: DETECTOR_FAILED reason=${error.javaClass.simpleName}")
            engine = null
            channel = null
        } finally {
            starting = false
        }
    }

    /** Runs one frame through Dart. [callback] receives null on any failure. */
    fun analyze(
        frame: CapturedFrame,
        sensitivity: Int,
        allowAwrah: Boolean,
        faces: List<List<Double>>,
        callback: (Analysis?) -> Unit,
    ) {
        main.post {
            ensureStarted()
            val active = channel
            if (active == null || !isReady) {
                val waited = System.currentTimeMillis() - startedAt
                if (startedAt > 0 && waited > STARTUP_GRACE_MS) {
                    lastError = "Detector engine did not become ready"
                    Log.w(TAG, "Dart detector still not ready after $waited ms")
                }
                callback(null)
                return@post
            }

            val done = AtomicBoolean(false)
            val timeout = Runnable {
                if (done.compareAndSet(false, true)) {
                    Log.w(TAG, "Dart analyze timed out after $TIMEOUT_MS ms")
                    callback(null)
                }
            }
            main.postDelayed(timeout, TIMEOUT_MS)

            val args = mapOf(
                "width" to frame.width,
                "height" to frame.height,
                "stride" to frame.stride,
                "pixels" to frame.argb,
                "sensitivity" to sensitivity,
                "allowAwrah" to allowAwrah,
                "faces" to faces,
            )

            try {
                active.invokeMethod("analyze", args, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (!done.compareAndSet(false, true)) return
                        main.removeCallbacks(timeout)
                        callback(parse(result))
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        if (!done.compareAndSet(false, true)) return
                        main.removeCallbacks(timeout)
                        lastError = "$code: $message"
                        Log.e(TAG, "Dart analyze failed: $code $message")
                        callback(null)
                    }

                    override fun notImplemented() {
                        error("not_implemented", "Dart detector has no analyze handler", null)
                    }
                })
            } catch (error: Throwable) {
                if (done.compareAndSet(false, true)) {
                    main.removeCallbacks(timeout)
                    lastError = error.message
                    Log.e(TAG, "Dart analyze threw", error)
                    callback(null)
                }
            }
        }
    }

    private fun parse(raw: Any?): Analysis? {
        val map = raw as? Map<*, *> ?: return null
        val rawRegions = map["regions"] as? List<*> ?: emptyList<Any>()
        val regions = rawRegions.mapNotNull { entry ->
            val values = entry as? List<*> ?: return@mapNotNull null
            if (values.size < 5) return@mapNotNull null
            Region(
                left = (values[0] as? Number)?.toFloat() ?: return@mapNotNull null,
                top = (values[1] as? Number)?.toFloat() ?: return@mapNotNull null,
                right = (values[2] as? Number)?.toFloat() ?: return@mapNotNull null,
                bottom = (values[3] as? Number)?.toFloat() ?: return@mapNotNull null,
                confidence = (values[4] as? Number)?.toDouble() ?: 0.0,
                kind = values.getOrNull(5) as? String ?: "awrah",
                evidence = values.getOrNull(6) as? String ?: "",
                rule = values.getOrNull(7) as? String ?: "band",
            )
        }
        return Analysis(
            score = (map["score"] as? Number)?.toDouble() ?: 0.0,
            fullScore = (map["fullScore"] as? Number)?.toDouble() ?: 0.0,
            gate = (map["gate"] as? Number)?.toDouble() ?: 0.0,
            regions = regions,
            personCount = (map["personCount"] as? Number)?.toInt() ?: 0,
            maxExposed = (map["maxExposed"] as? Number)?.toDouble() ?: 0.0,
            elapsedMs = (map["elapsedMs"] as? Number)?.toLong() ?: 0L,
        )
    }

    fun shutdown() {
        isReady = false
        try {
            channel?.setMethodCallHandler(null)
        } catch (_: Throwable) {
            // Engine already gone.
        }
        channel = null
        try {
            engine?.destroy()
        } catch (_: Throwable) {
            // Engine already gone.
        }
        engine = null
    }
}
