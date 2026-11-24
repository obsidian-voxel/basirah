package com.haramblur.haram_blur

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RegionObscurerTest {

    private fun detailPattern(width: Int, height: Int): IntArray {
        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val checker = ((x / 4) + (y / 4)) % 2 == 0
                // Text-like thin strokes on top of the checkerboard.
                val stroke = (y % 9 == 0) || (x % 13 == 0)
                pixels[y * width + x] = when {
                    stroke -> 0xFF000000.toInt()
                    checker -> 0xFFFFFFFF.toInt()
                    else -> 0xFF101010.toInt()
                }
            }
        }
        return pixels
    }

    @Test
    fun `output keeps the input region dimensions for every strength`() {
        val width = 120
        val height = 84
        val input = detailPattern(width, height)
        for (strength in listOf(
            RegionObscurer.STANDARD,
            RegionObscurer.STRONG,
            RegionObscurer.MAX,
        )) {
            val output = RegionObscurer.obscure(input, width, height, strength)
            assertEquals("$strength width", width * height, output.size)
        }
    }

    @Test
    fun `strong and max remove at least 90 percent of high-frequency energy`() {
        val width = 128
        val height = 128
        val input = detailPattern(width, height)
        val before = RegionObscurer.meanAbsLaplacian(input, width, height)

        for (strength in listOf(RegionObscurer.STRONG, RegionObscurer.MAX)) {
            val output = RegionObscurer.obscure(input, width, height, strength)
            val after = RegionObscurer.meanAbsLaplacian(output, width, height)
            assertTrue(
                "$strength energy $after should be <= 10% of $before",
                after <= before * 0.10,
            )
        }
    }

    @Test
    fun `factors match the documented strengths`() {
        assertEquals(60, RegionObscurer.factorFor(RegionObscurer.STANDARD))
        assertEquals(40, RegionObscurer.factorFor(RegionObscurer.STRONG))
        assertEquals(25, RegionObscurer.factorFor(RegionObscurer.MAX))
    }
}
