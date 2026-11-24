package com.haramblur.haram_blur

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Dart reference has always supported whole-word keywords; the native
 * matcher silently ignored the option. These tests pin the native rule to the
 * same semantics.
 */
class WholeWordTest {
    @Test
    fun `substring is still the default`() {
        assertTrue(BlockMatcher.matches("porn", "pornhub"))
    }

    @Test
    fun `whole word refuses to match inside a longer word`() {
        assertFalse(BlockMatcher.matches("porn", "pornhub", wholeWord = true))
        assertFalse(BlockMatcher.matches("porn", "pornography", wholeWord = true))
        assertTrue(BlockMatcher.matches("porn", "free porn here", wholeWord = true))
        assertTrue(BlockMatcher.matches("porn", "porn", wholeWord = true))
    }

    @Test
    fun `wildcards keep their substring meaning`() {
        assertTrue(BlockMatcher.matches("xxx*", "xxxvideo", wholeWord = true))
    }

    @Test
    fun `first match lowercases once and honours whole words`() {
        assertEquals(
            "porn",
            BlockMatcher.firstMatch(listOf("porn"), "PORN", wholeWord = true),
        )
        assertNull(
            BlockMatcher.firstMatch(listOf("porn"), "PORNHUB", wholeWord = true),
        )
    }
}
