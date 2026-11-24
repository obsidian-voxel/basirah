package com.haramblur.haram_blur

/**
 * Repeat-attempt lock for the block screen.
 *
 * Typing a blocked address over and over is the usual way out: the block
 * screen is dismissed and the app reopened within seconds. When the same
 * target is blocked [limit] times inside [windowMs], the caller gets a
 * `lockUntil` timestamp and keeps the screen up for [lockMs] with no dismiss
 * button.
 *
 * Times are uptime milliseconds, matching `SystemClock.uptimeMillis()`; nothing
 * here touches wall-clock time, so a clock change cannot shorten the lock.
 * Not thread-safe by design: the accessibility service calls it from its single
 * capture thread.
 */
class RepeatBlockGuard(
    private val windowMs: Long = WINDOW_MS,
    private val limit: Int = LIMIT,
    private val lockMs: Long = LOCK_MS,
) {
    private val strikes = HashMap<String, MutableList<Long>>()

    /**
     * Records one block of [key] at [now]. Returns the uptime until which the
     * screen must stay locked, or null when this is still an ordinary block.
     */
    fun onBlock(key: String, now: Long): Long? {
        val recent = strikes.getOrPut(key) { mutableListOf() }
        recent.removeAll { now - it > windowMs || it > now }
        recent.add(now)
        if (recent.size < limit) return null
        // The streak is spent: start counting again after this lock so the user
        // is not locked forever for one burst of retries.
        recent.clear()
        return now + lockMs
    }

    /** Forgets every target, e.g. when protection is switched back on. */
    fun reset() = strikes.clear()

    /** Blocks recorded for [key] inside the window, for diagnostics. */
    fun recentCount(key: String, now: Long): Int =
        strikes[key]?.count { now - it <= windowMs } ?: 0

    companion object {
        const val WINDOW_MS = 120_000L
        const val LIMIT = 5
        const val LOCK_MS = 300_000L
    }
}
