package com.haramblur.haram_blur

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the flat-frame guard: a secure window captures as pure black and a
 * blank or fully dimmed screen has nothing to classify, so neither may reach
 * the detector and turn into a block.
 */
class FrameFlatTest {
    private fun gray(value: Int): Int = (0xFF shl 24) or (value shl 16) or (value shl 8) or value

    @Test
    fun `a black secure frame is flat`() {
        assertTrue(FrameHash.isFlatPixels(IntArray(256) { 0xFF000000.toInt() }))
    }

    @Test
    fun `a uniform grey frame is flat`() {
        assertTrue(FrameHash.isFlatPixels(IntArray(256) { gray(140) }))
    }

    @Test
    fun `a real screen with contrast is not flat`() {
        val frame = IntArray(256) { gray(if (it % 16 < 8) 20 else 220) }
        assertFalse(FrameHash.isFlatPixels(frame))
    }

    @Test
    fun `a screen with a bright status bar over dark content is not flat`() {
        val frame = IntArray(256) { if (it < 16) gray(250) else gray(10) }
        assertFalse(FrameHash.isFlatPixels(frame))
    }
}
