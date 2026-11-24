package com.haramblur.haram_blur

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

private const val TAG = "HaramBlur"

/**
 * One JSON line per capture, written to `cacheDir/haram_capture_log.jsonl`.
 *
 * This is the evidence trail for "Analytics said nudity but nothing blurred":
 * it records the exact frame dimensions, row stride, gate score and decision,
 * so a miss can be attributed to the screenshot, the model or the policy.
 *
 * The last five captured frames are kept as small JPEGs so the developer
 * export can show exactly what the pipeline saw.
 */
object CaptureLog {
    private const val FILE_NAME = "haram_capture_log.jsonl"
    private const val MAX_LINES = 200
    private const val MAX_READ = 50
    private const val RECENT_FRAMES = 5
    private const val JPEG_QUALITY = 80

    @Volatile
    var lastPreview: ByteArray? = null
        private set

    @Volatile
    var lastSummary: Map<String, Any?> = emptyMap()
        private set

    private val recentFrames = ArrayDeque<ByteArray>()

    @Synchronized
    fun record(context: Context, line: Map<String, Any?>, preview: Bitmap?, previewMax: Int = 240) {
        val json = JSONObject()
        line.forEach { (key, value) -> json.put(key, value ?: JSONObject.NULL) }

        if (preview != null) {
            try {
                val scaled = scale(preview, previewMax)
                val png = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.PNG, 100, png)
                lastPreview = png.toByteArray()
                json.put("previewWidth", scaled.width)
                json.put("previewHeight", scaled.height)

                val jpeg = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, jpeg)
                recentFrames.addLast(jpeg.toByteArray())
                while (recentFrames.size > RECENT_FRAMES) recentFrames.removeFirst()

                if (scaled !== preview) scaled.recycle()
            } catch (error: Throwable) {
                Log.w(TAG, "Could not encode capture preview", error)
            }
        }
        lastSummary = line

        try {
            val file = File(context.cacheDir, FILE_NAME)
            file.appendText(json.toString() + "\n")
            trim(file)
        } catch (error: Throwable) {
            Log.w(TAG, "Could not write capture log", error)
        }
    }

    private fun scale(source: Bitmap, maxDimension: Int): Bitmap {
        val longest = maxOf(source.width, source.height).coerceAtLeast(1)
        if (longest <= maxDimension) return source
        val ratio = maxDimension.toFloat() / longest
        return Bitmap.createScaledBitmap(
            source,
            (source.width * ratio).toInt().coerceAtLeast(1),
            (source.height * ratio).toInt().coerceAtLeast(1),
            true,
        )
    }

    private fun trim(file: File) {
        val lines = file.readLines()
        if (lines.size <= MAX_LINES) return
        file.writeText(lines.takeLast(MAX_LINES).joinToString("\n", postfix = "\n"))
    }

    fun read(context: Context, limit: Int = MAX_READ): String =
        try {
            val file = File(context.cacheDir, FILE_NAME)
            if (!file.exists()) "" else file.readLines().takeLast(limit).joinToString("\n")
        } catch (error: Throwable) {
            Log.w(TAG, "Could not read capture log", error)
            ""
        }

    /**
     * Copies the JSONL log and the last five frames into
     * `Downloads/haram_debug/`. Returns the visible path. Usable without any
     * storage permission through MediaStore.
     */
    @Synchronized
    fun exportToDownloads(context: Context): String {
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/haram_debug"

        fun write(name: String, mime: String, bytes: ByteArray) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            }
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("MediaStore rejected $name")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not open $name for writing")
        }

        val log = read(context, limit = MAX_LINES).ifEmpty { "(no captures yet)\n" }
        write("haram_capture_log.jsonl", "text/plain", log.toByteArray())

        val frames = recentFrames.toList()
        frames.forEachIndexed { index, bytes ->
            write("haram_frame_${index + 1}.jpg", "image/jpeg", bytes)
        }
        Log.i(TAG, "Exported capture log and ${frames.size} frames to $relative")
        return "$relative/ (${frames.size} frame(s))"
    }

    fun clear(context: Context) {
        lastPreview = null
        lastSummary = emptyMap()
        synchronized(this) { recentFrames.clear() }
        try {
            File(context.cacheDir, FILE_NAME).delete()
        } catch (error: Throwable) {
            Log.w(TAG, "Could not clear capture log", error)
        }
    }
}
