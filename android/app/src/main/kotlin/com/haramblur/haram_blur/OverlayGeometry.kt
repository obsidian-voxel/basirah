package com.haramblur.haram_blur

/**
 * Pure geometry between the captured frame and the full-screen overlay view.
 *
 * The screenshot and the overlay both cover the entire display, including the
 * status bar and the navigation bar. The overlay window is MATCH_PARENT with
 * FLAG_LAYOUT_NO_LIMITS and no inset handling, so the mapping is simply
 * "capture-full-screen to view-full-screen": scale by width and height, with
 * **zero offsets**. Subtracting system-bar insets or applying a center-crop
 * offset here shifts every region and was the cause of the floating thumbnail.
 */
object OverlayGeometry {

    data class FrameRect(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    )

    data class ViewRect(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    )

    fun frameRectToViewRect(
        rect: FrameRect,
        frameWidth: Int,
        frameHeight: Int,
        viewWidth: Int,
        viewHeight: Int,
    ): ViewRect {
        if (frameWidth <= 0 || frameHeight <= 0 || viewWidth <= 0 || viewHeight <= 0) {
            return ViewRect(0f, 0f, 0f, 0f)
        }

        val scaleX = viewWidth.toFloat() / frameWidth
        val scaleY = viewHeight.toFloat() / frameHeight

        fun clampX(value: Float) = value.coerceIn(0f, viewWidth.toFloat())
        fun clampY(value: Float) = value.coerceIn(0f, viewHeight.toFloat())

        // Normalise in case a region arrives with inverted edges.
        val left = clampX(minOf(rect.left, rect.right) * scaleX)
        val right = clampX(maxOf(rect.left, rect.right) * scaleX)
        val top = clampY(minOf(rect.top, rect.bottom) * scaleY)
        val bottom = clampY(maxOf(rect.top, rect.bottom) * scaleY)

        return ViewRect(left, top, right, bottom)
    }
}
