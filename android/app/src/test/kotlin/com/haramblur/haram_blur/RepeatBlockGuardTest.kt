package com.haramblur.haram_blur

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Behaviour of the "cross block screen limit" guard. */
class RepeatBlockGuardTest {

    @Test
    fun `four attempts in the window are ordinary blocks`() {
        val guard = RepeatBlockGuard()
        for (i in 0 until 4) {
            assertNull(guard.onBlock("com.x|app|", i * 1_000L))
        }
        assertEquals(4, guard.recentCount("com.x|app|", 3_000L))
    }

    @Test
    fun `the fifth attempt inside two minutes locks for five minutes`() {
        val guard = RepeatBlockGuard()
        var lock: Long? = null
        for (i in 0 until 5) {
            lock = guard.onBlock("com.x|app|", i * 1_000L)
        }
        assertNotNull(lock)
        assertEquals(4_000L + RepeatBlockGuard.LOCK_MS, lock)
    }

    @Test
    fun `attempts older than the window are forgotten`() {
        val guard = RepeatBlockGuard()
        // One attempt every 70 s keeps at most two inside a 2 min window, so
        // the five-attempt burst never forms.
        for (i in 0 until 8) {
            assertNull(guard.onBlock("com.x|app|", i * 70_000L))
        }
    }

    @Test
    fun `a lock resets the strike list instead of locking forever`() {
        val guard = RepeatBlockGuard()
        for (i in 0 until 5) guard.onBlock("key", i * 100L)
        assertEquals(0, guard.recentCount("key", 500L))
        assertNull(guard.onBlock("key", 600L))
    }

    @Test
    fun `different targets do not share a counter`() {
        val guard = RepeatBlockGuard()
        for (i in 0 until 4) guard.onBlock("a", i * 100L)
        for (i in 0 until 4) assertNull(guard.onBlock("b", i * 100L))
    }

    @Test
    fun `a backwards clock jump cannot shorten a burst`() {
        val guard = RepeatBlockGuard()
        for (i in 0 until 4) guard.onBlock("k", 10_000L - i * 100L)
        // A stale timestamp from the future is discarded rather than counted.
        assertTrue(guard.recentCount("k", 9_000L) >= 1)
    }
}
