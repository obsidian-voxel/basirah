package com.haramblur.haram_blur

import android.accessibilityservice.AccessibilityService.ScreenshotResult
import android.graphics.Bitmap
import android.util.Log

private const val TAG = "HaramBlur"

/**
 * One screenshot as the detector needs it.
 *
 * [argb] keeps the capture's real row stride: `stride` can exceed `width` when
 * the hardware buffer is aligned, and reading it as if it were tight shears
 * every row. Dart tightens it row by row (tested in `frame_pixels_test.dart`).
 */
class CapturedFrame(
    val width: Int,
    val height: Int,
    val stride: Int,
    val argb: IntArray,
    /** Working copy for the log card (long edge <= 960). */
    val preview: Bitmap,
    /** Heavily downscaled copy drawn by the blur overlay. */
    val overlayFrame: Bitmap,
) {
    val rowPadding: Int get() = stride - width
}

/**
 * Converts `takeScreenshot` output to a padded ARGB buffer plus small previews.
 *
 * The frame is reduced to a 960 px long edge before it is sent to Dart. Full
 * 1080x2400 screenshots cost ~10 MB per platform-channel copy and make the
 * per-pixel skin pass in Dart needlessly slow; 960 px keeps the whole photo
 * larger than the 224 px model input while bounding both.
 */
object ScreenshotConverter {
    const val WORK_MAX = 960
    private const val OVERLAY_MAX = 96

    fun convert(screenshot: ScreenshotResult): CapturedFrame? {
        val buffer = screenshot.hardwareBuffer
        var wrapped: Bitmap? = null
        var software: Bitmap? = null
        try {
            wrapped = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
            software = wrapped?.copy(Bitmap.Config.ARGB_8888, false)
        } catch (error: Throwable) {
            Log.e(TAG, "Screenshot conversion failed", error)
        } finally {
            wrapped?.recycle()
            buffer.close()
        }

        val source = software ?: return null
        var working: Bitmap? = null
        return try {
            working = downscale(source, WORK_MAX)

            // rowBytes is in bytes; getPixels works in pixels. Using the real
            // stride here means a padded buffer arrives padded instead of
            // being silently misread.
            val stride = (working.rowBytes / 4).coerceAtLeast(working.width)
            val pixels = IntArray(stride * working.height)
            working.getPixels(pixels, 0, stride, 0, 0, working.width, working.height)

            CapturedFrame(
                width = working.width,
                height = working.height,
                stride = stride,
                argb = pixels,
                preview = working.copy(Bitmap.Config.ARGB_8888, false),
                overlayFrame = downscale(working, OVERLAY_MAX),
            )
        } finally {
            working?.recycle()
            source.recycle()
        }
    }

    private fun downscale(source: Bitmap, maxDimension: Int): Bitmap {
        val longest = maxOf(source.width, source.height).coerceAtLeast(1)
        if (longest <= maxDimension) {
            return source.copy(Bitmap.Config.ARGB_8888, false)
        }
        val scale = maxDimension.toFloat() / longest
        val width = (source.width * scale).toInt().coerceAtLeast(1)
        val height = (source.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(source, width, height, true)
    }
}
