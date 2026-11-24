package com.haramblur.haram_blur

import android.graphics.Bitmap

/**
 * 64-bit difference hash (dHash) of a frame. Used to skip inference when the
 * reduced capture is perceptually identical to the previous one and no window
 * change happened — a paused video or a static browser page no longer costs a
 * model run every tick.
 */
object FrameHash {

    /** Maximum Hamming distance still treated as "the same screen". */
    const val SAME_SCREEN_DISTANCE = 6

    fun of(bitmap: Bitmap): Long {
        val small = Bitmap.createScaledBitmap(bitmap, 9, 8, true)
        val pixels = IntArray(9 * 8)
        small.getPixels(pixels, 0, 9, 0, 0, 9, 8)
        if (small !== bitmap) small.recycle()

        var hash = 0L
        for (y in 0 until 8) {
            for (x in 0 until 8) {
                val left = gray(pixels[y * 9 + x])
                val right = gray(pixels[y * 9 + x + 1])
                if (left > right) {
                    hash = hash or (1L shl (y * 8 + x))
                }
            }
        }
        return hash
    }

    fun distance(a: Long, b: Long): Int = java.lang.Long.bitCount(a xor b)

    /** Share of pixels that must sit near the median luminance. */
    private const val FLAT_PIXEL_RATIO = 0.97

    /** Luminance band, out of 255, still treated as the same shade. */
    private const val FLAT_LUMINANCE_TOLERANCE = 10

    /**
     * True when the frame is essentially one flat shade. A window with
     * FLAG_SECURE (banking, password managers, some private-mode screens)
     * captures as pure black, and a dimmed or blank screen has nothing to
     * classify: scoring those pixels is what produced the rare blocks on
     * apps with protected screens and on the lock screen.
     */
    fun isFlat(bitmap: Bitmap): Boolean {
        val small = Bitmap.createScaledBitmap(bitmap, 16, 16, true)
        val pixels = IntArray(16 * 16)
        small.getPixels(pixels, 0, 16, 0, 0, 16, 16)
        if (small !== bitmap) small.recycle()
        return isFlatPixels(pixels)
    }

    /** Pure form of [isFlat], so the threshold stays testable off-device. */
    fun isFlatPixels(pixels: IntArray): Boolean {
        if (pixels.isEmpty()) return true
        val luma = IntArray(pixels.size) { gray(pixels[it]) }
        luma.sort()
        val median = luma[luma.size / 2]
        var near = 0
        for (value in luma) {
            if (kotlin.math.abs(value - median) <= FLAT_LUMINANCE_TOLERANCE) near++
        }
        return near.toDouble() / luma.size >= FLAT_PIXEL_RATIO
    }

    private fun gray(color: Int): Int {
        val r = (color shr 16) and 0xFF
        val g = (color shr 8) and 0xFF
        val b = color and 0xFF
        return (r * 299 + g * 587 + b * 114) / 1000
    }
}
