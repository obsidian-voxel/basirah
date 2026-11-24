package com.haramblur.haram_blur

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View

/**
 * Full-screen block overlay.
 *
 * When a violation is detected the user must not see the content at all, so
 * this view paints an opaque cover over the whole display instead of blurring
 * individual regions. The only way out is the Dismiss button, which the user
 * must tap deliberately; the service then leaves the app.
 */
class BlurOverlayView(context: Context) : View(context) {

    /** Set by the service; invoked when the user taps Dismiss. */
    var onDismiss: (() -> Unit)? = null

    private var frame: Bitmap? = null

    /**
     * Reason shown for a rule-based block (app, keyword, URL, schedule, limit,
     * private mode). Null for a visual block, which uses the default copy.
     */
    private var blockMessage: String? = null

    /** User-configured copy; null means the shipped wording. */
    private var customTitle: String? = null
    private var customBody: String? = null

    /** Uptime until which Dismiss is ignored after repeated attempts. */
    private var lockUntil = 0L

    private val lockTicker = object : Runnable {
        override fun run() {
            invalidate()
            if (isLocked()) postDelayed(this, 500L)
        }
    }

    private val backgroundPaint = Paint().apply { color = Color.rgb(10, 10, 12) }
    private val cardPaint = Paint().apply {
        isAntiAlias = true
        color = Color.rgb(26, 27, 32)
    }
    private val titlePaint = Paint().apply {
        isAntiAlias = true
        color = Color.WHITE
        textSize = 26f * resources.displayMetrics.scaledDensity
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    private val bodyPaint = Paint().apply {
        isAntiAlias = true
        color = Color.rgb(190, 192, 200)
        textSize = 15f * resources.displayMetrics.scaledDensity
        textAlign = Paint.Align.CENTER
    }
    private val buttonPaint = Paint().apply {
        isAntiAlias = true
        color = Color.rgb(220, 60, 70)
    }
    private val buttonTextPaint = Paint().apply {
        isAntiAlias = true
        color = Color.WHITE
        textSize = 16f * resources.displayMetrics.scaledDensity
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }

    private val buttonRect = RectF()
    private val cardRect = RectF()

    /**
     * Kept for the service's existing call shape. The captured frame is only
     * held so it can be recycled; it is never drawn, because showing any part
     * of it would defeat the block.
     */
    fun setFrame(
        bitmap: Bitmap,
        framePixelsWide: Int,
        framePixelsHigh: Int,
        regionPixels: List<OverlayGeometry.FrameRect>? = null,
    ) {
        if (frame !== bitmap) {
            frame?.recycle()
        }
        frame = bitmap
        blockMessage = null
        invalidate()
    }

    /**
     * Custom block screen copy from Advanced Settings. Passing null restores
     * the shipped text. Applies to visual and rule-based blocks alike.
     */
    fun setCopy(title: String?, body: String?) {
        customTitle = title?.takeIf { it.isNotBlank() }
        customBody = body?.takeIf { it.isNotBlank() }
        invalidate()
    }

    /**
     * Keeps the screen up with no dismiss button until [untilUptime]. Zero
     * clears the lock. Used by the repeat-attempt guard.
     */
    fun setLock(untilUptime: Long) {
        lockUntil = untilUptime
        removeCallbacks(lockTicker)
        if (isLocked()) post(lockTicker)
        invalidate()
    }

    private fun isLocked(): Boolean = lockUntil > SystemClock.uptimeMillis()

    private fun lockSecondsLeft(): Int {
        val remaining = lockUntil - SystemClock.uptimeMillis()
        return if (remaining <= 0L) 0 else ((remaining + 999L) / 1000L).toInt()
    }

    /** No captured frame: a rule decided this, not the visual model. */
    fun setBlockMessage(message: String) {
        frame?.recycle()
        frame = null
        blockMessage = message
        invalidate()
    }

    fun clear() {
        frame?.recycle()
        frame = null
        blockMessage = null
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), backgroundPaint)

        val centerX = width / 2f
        val centerY = height / 2f
        val cardWidth = minOf(width * 0.86f, 560f)
        val cardHeight = 250f
        cardRect.set(
            centerX - cardWidth / 2f,
            centerY - cardHeight / 2f,
            centerX + cardWidth / 2f,
            centerY + cardHeight / 2f,
        )
        canvas.drawRoundRect(cardRect, 28f, 28f, cardPaint)

        canvas.drawText(
            customTitle ?: "Content blocked",
            centerX,
            centerY - 58f,
            titlePaint,
        )
        val body = customBody ?: blockMessage
        if (body != null) {
            var lineY = centerY - 20f
            for (line in wrap(body, bodyPaint, cardWidth - 40f)) {
                canvas.drawText(line, centerX, lineY, bodyPaint)
                lineY += 22f
            }
            if (customBody == null) {
                canvas.drawText(
                    "This app is being closed.",
                    centerX,
                    maxOf(lineY, centerY + 6f),
                    bodyPaint,
                )
            }
        } else {
            canvas.drawText(
                "Basirah detected explicit content or",
                centerX,
                centerY - 18f,
                bodyPaint,
            )
            canvas.drawText(
                "exposed skin. The app is being closed.",
                centerX,
                centerY + 6f,
                bodyPaint,
            )
        }

        val locked = isLocked()
        buttonRect.set(
            centerX - 110f,
            centerY + 46f,
            centerX + 110f,
            centerY + 102f,
        )
        val fill = if (locked) Color.rgb(70, 72, 80) else Color.rgb(220, 60, 70)
        buttonPaint.color = fill
        canvas.drawRoundRect(buttonRect, 26f, 26f, buttonPaint)
        if (locked) {
            val seconds = lockSecondsLeft()
            val clock = "%d:%02d".format(seconds / 60, seconds % 60)
            canvas.drawText(
                "Locked · $clock",
                centerX,
                buttonRect.centerY() + 6f,
                buttonTextPaint,
            )
            canvas.drawText(
                "Too many attempts. The block screen stays until the timer ends.",
                centerX,
                buttonRect.bottom + 26f,
                bodyPaint,
            )
        } else {
            canvas.drawText(
                "I understand",
                centerX,
                buttonRect.centerY() + 6f,
                buttonTextPaint,
            )
        }
    }

    /** Greedy word wrap so a keyword/URL reason fits the card. */
    private fun wrap(text: String, paint: Paint, maxWidth: Float): List<String> {
        val words = text.split(' ')
        val lines = mutableListOf<String>()
        var current = StringBuilder()
        for (word in words) {
            val candidate = if (current.isEmpty()) word else "$current $word"
            if (paint.measureText(candidate) <= maxWidth) {
                current = StringBuilder(candidate)
            } else {
                if (current.isNotEmpty()) lines.add(current.toString())
                current = StringBuilder(word)
            }
        }
        if (current.isNotEmpty()) lines.add(current.toString())
        return lines
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (isLocked()) return true
        if (event.action == MotionEvent.ACTION_UP &&
            buttonRect.contains(event.x, event.y)
        ) {
            performClick()
            onDismiss?.invoke()
            return true
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }
}
