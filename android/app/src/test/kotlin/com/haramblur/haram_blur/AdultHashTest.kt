package com.haramblur.haram_blur

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the values `tools/build_blocklist_index.py` writes and the suffix walk
 * that makes one entry cover every subdomain.
 */
class AdultHashTest {
    @Test
    fun `hash matches the generator`() {
        // fnv1a_64("pornhub.com") and fnv1a_64("de.pornhub.com") in Python.
        assertEquals(-5518577871501868968L, AdultHash.of("pornhub.com"))
        assertEquals(-6008236253857594609L, AdultHash.of("de.pornhub.com"))
    }

    @Test
    fun `a listed parent covers its subdomains only`() {
        val table = longArrayOf(
            AdultHash.of("pornhub.com"),
            AdultHash.of("example.xxx"),
        ).sortedArray()
        assertTrue(AdultHash.matchesHost(table, "pornhub.com"))
        assertTrue(AdultHash.matchesHost(table, "de.pornhub.com"))
        assertTrue(AdultHash.matchesHost(table, "a.b.pornhub.com"))
        assertTrue(AdultHash.matchesHost(table, "EXAMPLE.XXX"))
        assertFalse(AdultHash.matchesHost(table, "notpornhub.com"))
        assertFalse(AdultHash.matchesHost(table, "pornhub.com.evil.test"))
        assertFalse(AdultHash.matchesHost(table, "example.test"))
    }
}
