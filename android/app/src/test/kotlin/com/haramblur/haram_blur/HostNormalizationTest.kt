package com.haramblur.haram_blur

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins host canonicalisation. A trailing dot, a percent escape and a Unicode
 * spelling all reach the server as the same name, so they must reach the
 * 952k-domain index as the same key.
 */
class HostNormalizationTest {
    @Test
    fun `a trailing dot is the same host`() {
        assertEquals("pornhub.com", BlockPrefs.hostOf("https://pornhub.com./video"))
        assertEquals("pornhub.com", BlockPrefs.hostOf("pornhub.com."))
    }

    @Test
    fun `percent escapes cannot hide a host`() {
        assertEquals("pornhub.com", BlockPrefs.hostOf("https://porn%68ub.com/watch"))
        assertEquals("pornhub.com", BlockPrefs.hostOf("https://PORN%68UB.COM./"))
    }

    @Test
    fun `a unicode host folds to the punycode form the list stores`() {
        assertEquals("xn--mnchen-3ya.de", BlockPrefs.hostOf("https://MÜNCHEN.de/x"))
    }

    @Test
    fun `an ip literal is never treated as a domain`() {
        assertTrue(BlockPrefs.isIpLiteral("192.168.1.1"))
        assertTrue(BlockPrefs.isIpLiteral("3232235777"))
        assertTrue(BlockPrefs.isIpLiteral("0x7f000001"))
        assertFalse(BlockPrefs.isIpLiteral("pornhub.com"))
        assertFalse(BlockPrefs.isIpLiteral(""))
    }

    @Test
    fun `an address with no host normalises to empty`() {
        assertEquals("", BlockPrefs.hostOf("https://..."))
        assertEquals("", BlockPrefs.hostOf(""))
    }
}
