package com.haramblur.haram_blur

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the private-mode label rule. Browser menu rows and help text used to
 * match on a substring ("incognito"), which blocked people for opening the
 * three-dot menu; only an exact private-mode state label may match now.
 */
class PrivateModeLabelTest {
    @Test
    fun `browser menu rows do not look like private mode`() {
        assertFalse(NodeText.isPrivateLabel("New Incognito tab"))
        assertFalse(NodeText.isPrivateLabel("New private tab"))
        assertFalse(NodeText.isPrivateLabel("New Private Window"))
        assertFalse(NodeText.isPrivateLabel("Turn on InPrivate browsing"))
        assertFalse(NodeText.isPrivateLabel("Open incognito mode"))
        assertFalse(NodeText.isPrivateLabel("Close all incognito tabs"))
        assertFalse(NodeText.isPrivateLabel("Incognito tabs are locked when you leave Chrome"))
        assertFalse(NodeText.isPrivateLabel("Learn more about private browsing"))
    }

    @Test
    fun `the private mode state labels still match`() {
        assertTrue(NodeText.isPrivateLabel("You've gone incognito"))
        assertTrue(NodeText.isPrivateLabel("You’ve gone incognito."))
        assertTrue(NodeText.isPrivateLabel("  you've   gone   INCOGNITO  "))
        assertTrue(NodeText.isPrivateLabel("Incognito"))
        assertTrue(NodeText.isPrivateLabel("Incognito tab"))
        assertTrue(NodeText.isPrivateLabel("Private Browsing"))
        assertTrue(NodeText.isPrivateLabel("InPrivate"))
        assertTrue(NodeText.isPrivateLabel("Navigation privée"))
        assertTrue(NodeText.isPrivateLabel("Navegación privada"))
    }

    @Test
    fun `private mode is recognised outside english`() {
        assertTrue(NodeText.isPrivateLabel("التصفح المتخفي"))
        assertTrue(NodeText.isPrivateLabel("وضع التخفي"))
        assertTrue(NodeText.isPrivateLabel("نجی براؤزنگ"))
        assertTrue(NodeText.isPrivateLabel("Gizli mod"))
        assertTrue(NodeText.isPrivateLabel("Mode penyamaran"))
        assertTrue(NodeText.isPrivateLabel("Pelayaran peribadi"))
        assertTrue(NodeText.isPrivateLabel("Inkognitomodus"))
        assertTrue(NodeText.isPrivateLabel("Privates Fenster"))
    }

    @Test
    fun `empty text is never private mode`() {
        assertFalse(NodeText.isPrivateLabel(""))
        assertFalse(NodeText.isPrivateLabel("   "))
    }
}
