package com.haramblur.haram_blur

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The capture and the overlay both cover the full display, so a region must map
 * with one scale per axis and zero offsets. These tests pin the numbers.
 */
class OverlayGeometryTest {

    @Test
    fun `frame region maps to the same place on a 1080x2400 view`() {
        val mapped = OverlayGeometry.frameRectToViewRect(
            OverlayGeometry.FrameRect(96f, 213.3f, 480f, 1066.5f),
            frameWidth = 960,
            frameHeight = 2133,
            viewWidth = 1080,
            viewHeight = 2400,
        )

        assertEquals(108f, mapped.left, 0.01f)
        assertEquals(240f, mapped.top, 0.01f)
        assertEquals(540f, mapped.right, 0.01f)
        assertEquals(1200f, mapped.bottom, 0.01f)
    }

    @Test
    fun `a full-frame region covers the whole view`() {
        val mapped = OverlayGeometry.frameRectToViewRect(
            OverlayGeometry.FrameRect(0f, 0f, 960f, 2133f),
            frameWidth = 960,
            frameHeight = 2133,
            viewWidth = 1080,
            viewHeight = 2400,
        )

        assertEquals(0f, mapped.left, 0.01f)
        assertEquals(0f, mapped.top, 0.01f)
        assertEquals(1080f, mapped.right, 0.01f)
        assertEquals(2400f, mapped.bottom, 0.01f)
    }

    @Test
    fun `regions are clamped to the view bounds`() {
        val mapped = OverlayGeometry.frameRectToViewRect(
            OverlayGeometry.FrameRect(-50f, -50f, 1200f, 3000f),
            frameWidth = 960,
            frameHeight = 2133,
            viewWidth = 1080,
            viewHeight = 2400,
        )

        assertEquals(0f, mapped.left, 0.01f)
        assertEquals(0f, mapped.top, 0.01f)
        assertEquals(1080f, mapped.right, 0.01f)
        assertEquals(2400f, mapped.bottom, 0.01f)
    }

    @Test
    fun `inverted edges are normalised instead of producing an empty rect`() {
        val mapped = OverlayGeometry.frameRectToViewRect(
            OverlayGeometry.FrameRect(480f, 1066.5f, 96f, 213.3f),
            frameWidth = 960,
            frameHeight = 2133,
            viewWidth = 1080,
            viewHeight = 2400,
        )

        assertEquals(108f, mapped.left, 0.01f)
        assertEquals(240f, mapped.top, 0.01f)
        assertEquals(540f, mapped.right, 0.01f)
        assertEquals(1200f, mapped.bottom, 0.01f)
    }

    @Test
    fun `degenerate sizes produce an empty rect instead of dividing by zero`() {
        val mapped = OverlayGeometry.frameRectToViewRect(
            OverlayGeometry.FrameRect(1f, 1f, 2f, 2f),
            frameWidth = 0,
            frameHeight = 0,
            viewWidth = 1080,
            viewHeight = 2400,
        )

        assertTrue(mapped.right <= mapped.left)
        assertTrue(mapped.bottom <= mapped.top)
    }
}
