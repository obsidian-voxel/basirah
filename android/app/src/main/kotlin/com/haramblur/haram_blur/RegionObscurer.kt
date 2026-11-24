package com.haramblur.haram_blur

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Region obscuration applied by the overlay.
 *
 * Each region is downscaled so its long side is at most `longSide / factor`
 * (never below [MIN_LONG_SIDE]), upscaled bilinearly back to region size, then
 * box-blurred. Pure IntArray math so it can be unit-tested on the JVM without
 * an Android Bitmap.
 */
object RegionObscurer {
    const val STANDARD = "standard"
    const val STRONG = "strong"
    const val MAX = "max"
    const val MIN_LONG_SIDE = 8

    /** Downscale divisor: standard 1/60, strong 1/40, max 1/25. */
    fun factorFor(strength: String): Int = when (strength) {
        STANDARD -> 60
        MAX -> 25
        else -> 40
    }

    fun passesFor(strength: String): Int = when (strength) {
        STANDARD -> 0
        MAX -> 2
        else -> 1
    }

    fun obscure(pixels: IntArray, width: Int, height: Int, strength: String): IntArray {
        if (width <= 0 || height <= 0 || pixels.size < width * height) {
            return pixels.copyOf()
        }
        val longSide = max(width, height)
        val factor = factorFor(strength)
        val targetLong = max(MIN_LONG_SIDE, longSide / factor)
        val targetWidth = max(1, width * targetLong / longSide)
        val targetHeight = max(1, height * targetLong / longSide)

        var out = if (targetWidth >= width && targetHeight >= height) {
            pixels.copyOf()
        } else {
            upscale(
                downscale(pixels, width, height, targetWidth, targetHeight),
                targetWidth,
                targetHeight,
                width,
                height,
            )
        }
        repeat(passesFor(strength)) {
            out = boxBlur(out, width, height, radius = 2)
        }
        return out
    }

    private fun downscale(
        pixels: IntArray,
        width: Int,
        height: Int,
        outWidth: Int,
        outHeight: Int,
    ): IntArray {
        val out = IntArray(outWidth * outHeight)
        for (y in 0 until outHeight) {
            val y0 = y * height / outHeight
            val y1 = max(y0 + 1, (y + 1) * height / outHeight)
            for (x in 0 until outWidth) {
                val x0 = x * width / outWidth
                val x1 = max(x0 + 1, (x + 1) * width / outWidth)
                var a = 0L
                var r = 0L
                var g = 0L
                var b = 0L
                var count = 0
                for (sy in y0 until min(y1, height)) {
                    val row = sy * width
                    for (sx in x0 until min(x1, width)) {
                        val c = pixels[row + sx]
                        a += (c ushr 24) and 0xFF
                        r += (c shr 16) and 0xFF
                        g += (c shr 8) and 0xFF
                        b += c and 0xFF
                        count++
                    }
                }
                if (count == 0) continue
                out[y * outWidth + x] = ((a / count).toInt() shl 24) or
                    ((r / count).toInt() shl 16) or
                    ((g / count).toInt() shl 8) or
                    (b / count).toInt()
            }
        }
        return out
    }

    private fun upscale(
        pixels: IntArray,
        width: Int,
        height: Int,
        outWidth: Int,
        outHeight: Int,
    ): IntArray {
        val out = IntArray(outWidth * outHeight)
        for (y in 0 until outHeight) {
            val srcY = ((y + 0.5) * height / outHeight - 0.5)
                .coerceIn(0.0, (height - 1).toDouble())
            val y0 = srcY.toInt()
            val y1 = min(y0 + 1, height - 1)
            val fy = srcY - y0
            for (x in 0 until outWidth) {
                val srcX = ((x + 0.5) * width / outWidth - 0.5)
                    .coerceIn(0.0, (width - 1).toDouble())
                val x0 = srcX.toInt()
                val x1 = min(x0 + 1, width - 1)
                val fx = srcX - x0
                out[y * outWidth + x] = blend(
                    pixels[y0 * width + x0],
                    pixels[y0 * width + x1],
                    pixels[y1 * width + x0],
                    pixels[y1 * width + x1],
                    fx,
                    fy,
                )
            }
        }
        return out
    }

    private fun blend(a: Int, b: Int, c: Int, d: Int, fx: Double, fy: Double): Int {
        fun channel(shift: Int): Int {
            val av = (a ushr shift) and 0xFF
            val bv = (b ushr shift) and 0xFF
            val cv = (c ushr shift) and 0xFF
            val dv = (d ushr shift) and 0xFF
            val top = av + (bv - av) * fx
            val bottom = cv + (dv - cv) * fx
            return (top + (bottom - top) * fy).toInt().coerceIn(0, 255)
        }
        return (channel(24) shl 24) or (channel(16) shl 16) or
            (channel(8) shl 8) or channel(0)
    }

    private fun boxBlur(pixels: IntArray, width: Int, height: Int, radius: Int): IntArray {
        val out = IntArray(pixels.size)
        for (y in 0 until height) {
            for (x in 0 until width) {
                var a = 0L
                var r = 0L
                var g = 0L
                var b = 0L
                var count = 0
                for (dy in -radius..radius) {
                    val sy = y + dy
                    if (sy < 0 || sy >= height) continue
                    for (dx in -radius..radius) {
                        val sx = x + dx
                        if (sx < 0 || sx >= width) continue
                        val c = pixels[sy * width + sx]
                        a += (c ushr 24) and 0xFF
                        r += (c shr 16) and 0xFF
                        g += (c shr 8) and 0xFF
                        b += c and 0xFF
                        count++
                    }
                }
                out[y * width + x] = ((a / count).toInt() shl 24) or
                    ((r / count).toInt() shl 16) or
                    ((g / count).toInt() shl 8) or
                    (b / count).toInt()
            }
        }
        return out
    }

    /** Mean absolute Laplacian luminance: a simple high-frequency measure. */
    fun meanAbsLaplacian(pixels: IntArray, width: Int, height: Int): Double {
        if (width < 3 || height < 3) return 0.0
        var total = 0.0
        var count = 0
        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                val center = luminance(pixels[y * width + x])
                val lap = 4 * center -
                    luminance(pixels[y * width + x - 1]) -
                    luminance(pixels[y * width + x + 1]) -
                    luminance(pixels[(y - 1) * width + x]) -
                    luminance(pixels[(y + 1) * width + x])
                total += abs(lap)
                count++
            }
        }
        return if (count == 0) 0.0 else total / count
    }

    private fun luminance(color: Int): Double {
        val r = (color shr 16) and 0xFF
        val g = (color shr 8) and 0xFF
        val b = color and 0xFF
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
