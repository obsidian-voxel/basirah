package com.haramblur.haram_blur

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the wildcard semantics the accessibility service runs on every page
 * URL, using entries from the shipped adult-pattern list.
 */
class BlockMatcherTest {
    @Test
    fun `a search-query pattern matches only the matching query`() {
        assertTrue(
            BlockMatcher.matches("*q=*porn*", "https://www.bing.com/search?q=free+porn"),
        )
        assertFalse(
            BlockMatcher.matches("*q=*porn*", "https://www.bing.com/search?q=hijab+tutorial"),
        )
    }

    @Test
    fun `a tld pattern covers the whole extension`() {
        assertTrue(BlockMatcher.matches("*.xxx", "https://example.xxx/watch"))
        assertFalse(BlockMatcher.matches("*.xxx", "https://example.com/watch"))
    }

    @Test
    fun `wildcard parts must appear in order`() {
        assertTrue(BlockMatcher.matches("*adult*clip*", "https://site.test/adult-clip"))
        assertFalse(BlockMatcher.matches("*adult*clip*", "https://site.test/clip-adult"))
    }

    @Test
    fun `first match reports the configured entry`() {
        val patterns = listOf("*.xxx", "*porn*")
        assertEquals("*porn*", BlockMatcher.firstMatch(patterns, "https://a.test/porn"))
        assertNull(BlockMatcher.firstMatch(patterns, "https://a.test/news"))
    }
}
