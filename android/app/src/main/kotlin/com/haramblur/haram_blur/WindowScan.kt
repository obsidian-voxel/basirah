package com.haramblur.haram_blur

import android.view.accessibility.AccessibilityNodeInfo

/**
 * Keyword matching with the same semantics as `KeywordBlocker` in Dart:
 * case-insensitive, `*` wildcards, substring by default.
 */
object BlockMatcher {
    /**
     * True when [haystack] (already lowercased by the caller or not) contains
     * [entry], honouring `*` wildcards. Parts must appear in order, so
     * `porn*hub` matches `pornhub` and `porn site hub`.
     */
    fun matches(entry: String, haystack: String, wholeWord: Boolean = false): Boolean =
        matchesLower(entry.trim().lowercase(), haystack.lowercase(), wholeWord)

    /**
     * Same rule as above, but the haystack was lowercased once by the caller.
     * Scanning 20k characters against every keyword re-lowercased the page per
     * entry, which is pure waste on a scroll.
     */
    private fun matchesLower(needle: String, text: String, wholeWord: Boolean): Boolean {
        if (needle.isEmpty()) return false
        if (!needle.contains('*')) {
            if (!wholeWord) return text.contains(needle)
            var from = 0
            while (true) {
                val found = text.indexOf(needle, from)
                if (found < 0) return false
                val before = if (found == 0) null else text[found - 1]
                val afterIndex = found + needle.length
                val after = if (afterIndex >= text.length) null else text[afterIndex]
                if ((before == null || !before.isLetterOrDigit()) &&
                    (after == null || !after.isLetterOrDigit())
                ) {
                    return true
                }
                from = found + 1
            }
        }
        // Wildcards keep substring semantics between their parts: the user
        // wrote the shape they meant.
        var index = 0
        for (part in needle.split('*')) {
            if (part.isEmpty()) continue
            val found = text.indexOf(part, index)
            if (found < 0) return false
            index = found + part.length
        }
        return true
    }

    /** First configured keyword found in [haystack], or null. */
    fun firstMatch(
        entries: List<String>,
        haystack: String,
        wholeWord: Boolean = false,
    ): String? {
        if (haystack.isBlank() || entries.isEmpty()) return null
        val text = haystack.lowercase()
        for (entry in entries) {
            if (matchesLower(entry.trim().lowercase(), text, wholeWord)) return entry
        }
        return null
    }
}

/**
 * Reads the active window's node tree: visible text, a URL if one can be
 * identified, and a confident private-mode hint.
 *
 * Runs on the capture thread, never on the main thread: an app with thousands
 * of nodes would otherwise jank the accessibility service.
 */
object NodeText {
    private const val MAX_NODES = 400
    private const val MAX_CHARS = 20_000

    /** Browsers whose private-mode labels are trusted. */
    private val BROWSERS = setOf(
        "com.android.chrome",
        "com.chrome.beta",
        "com.chrome.dev",
        "com.chrome.canary",
        "org.mozilla.firefox",
        "org.mozilla.firefox_beta",
        "com.microsoft.emmx",
        "com.brave.browser",
        "com.opera.browser",
        "com.opera.mini.native",
        "com.sec.android.app.sbrowser",
        "com.duckduckgo.mobile.android",
        "com.vivaldi.browser",
        "com.kiwibrowser.browser",
    )

    /**
     * Labels that can only be the private-mode *state* itself, never a command.
     * A browser menu says "New Incognito tab", "New private window" or
     * "Turn on InPrivate", so it is deliberately absent: matching those was
     * blocking people for opening the three-dot menu.
     */
    private val PRIVATE_LABELS = setOf(
        "incognito",
        "incognito tab",
        "you've gone incognito",
        "youve gone incognito",
        "you are incognito",
        "private browsing",
        "private tab",
        "private window",
        "inprivate",
        "inprivate window",
        "navigation privée",
        "navegación privada",
        "modo incógnito",
        // Arabic: incognito / private browsing / private tab.
        "التصفح المتخفي",
        "وضع التخفي",
        "التصفح الخاص",
        "تبويب خاص",
        // Urdu.
        "نجی براؤزنگ",
        "انکوگنیٹو",
        "نجی ٹیب",
        // Turkish.
        "gizli mod",
        "gizli sekme",
        "gizli pencere",
        // Indonesian.
        "mode penyamaran",
        "penjelajahan privat",
        "jendela penyamaran",
        // Malay.
        "mod inkognito",
        "pelayaran peribadi",
        "tetingkap peribadi",
        // German.
        "inkognitomodus",
        "privates fenster",
        "inkognito-fenster",
    )

    class Scan(
        val text: String,
        val url: String,
        val privateHint: String?,
        /** True when the window hosts an embedded browser (a WebView). */
        val hasWebView: Boolean = false,
        /** Nodes actually walked; diagnostics only, never used for a decision. */
        val nodeCount: Int = 0,
    )

    fun isBrowser(packageName: String): Boolean = BROWSERS.contains(packageName)

    /**
     * True only for an exact state label. Called for browser packages only, and
     * compared for equality after normalisation: a substring test made any
     * sentence that mentions incognito — a menu item, a help page, a settings
     * row — look like private mode.
     */
    fun isPrivateLabel(text: String): Boolean =
        PRIVATE_LABELS.contains(normalizeLabel(text))

    /** Lowercase, curly apostrophes folded, whitespace collapsed, no trailing
     * punctuation: "You’ve gone incognito." must equal the stored label. */
    private fun normalizeLabel(text: String): String {
        val builder = StringBuilder(text.length)
        var lastWasSpace = true
        for (raw in text.lowercase()) {
            val ch = when (raw) {
                '\u2019', '\u2018', '`' -> '\''
                '\u00a0', '\t', '\n', '\r' -> ' '
                else -> raw
            }
            if (ch == ' ') {
                if (!lastWasSpace) builder.append(' ')
                lastWasSpace = true
            } else {
                builder.append(ch)
                lastWasSpace = false
            }
        }
        return builder.toString().trim().trimEnd('.', '…', ':', '!', ',')
    }

    fun collect(root: AccessibilityNodeInfo, packageName: String): Scan {
        val text = StringBuilder()
        var url = ""
        var privateHint: String? = null
        var hasWebView = false
        val browser = isBrowser(packageName)
        // Each entry carries whether an ancestor is clickable, i.e. whether the
        // node belongs to a menu, a tab strip or a button.
        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Boolean>>()
        queue.add(root to false)
        var visited = 0

        while (queue.isNotEmpty() && visited < MAX_NODES) {
            val (node, inMenu) = queue.removeFirst()
            val interactive = inMenu || node.isClickable
            visited++

            val nodeText = node.text?.toString()?.trim().orEmpty()
            val description = node.contentDescription?.toString()?.trim().orEmpty()
            val id = node.viewIdResourceName.orEmpty()
            if (!hasWebView) {
                val className = node.className?.toString().orEmpty()
                if (className.contains("WebView", ignoreCase = true)) hasWebView = true
            }

            if (nodeText.isNotEmpty()) {
                if (text.length < MAX_CHARS) text.append(nodeText).append('\n')
                if (url.isEmpty() && looksLikeUrl(nodeText)) url = nodeText
                if (browser && privateHint == null && isPrivateLabel(nodeText)) {
                    privateHint = nodeText
                }
            }
            // An address bar is often an EditText with "url" in its resource id
            // and the page URL as its text; fall back to that when no node
            // looked like a bare URL.
            if (url.isEmpty() && nodeText.isNotEmpty() && id.contains("url", true)) {
                url = nodeText
            }
            if (description.isNotEmpty() && text.length < MAX_CHARS) {
                text.append(description).append('\n')
            }
            // A view id may hint at private mode, but only outside menus: a
            // menu row id such as `menu_item_incognito` is not private mode.
            if (browser && privateHint == null && !interactive &&
                id.contains("incognito", true)
            ) {
                privateHint = id
            }

            for (index in 0 until node.childCount) {
                val child = node.getChild(index) ?: continue
                queue.add(child to interactive)
            }
            if (node !== root) node.recycle()
        }

        while (queue.isNotEmpty()) {
            val (leftover, _) = queue.removeFirst()
            if (leftover !== root) leftover.recycle()
        }
        return Scan(text.toString(), url, privateHint, hasWebView, visited)
    }

    private fun looksLikeUrl(value: String): Boolean {
        val lower = value.lowercase()
        return lower.startsWith("http://") ||
            lower.startsWith("https://") ||
            lower.startsWith("www.")
    }

    /**
     * A typed address, from an address bar or a search box. Anything with a
     * space is prose, and a host without a dot is a search term, so neither is
     * sent to the domain index. Returns the URL to check, or null.
     */
    fun typedUrl(raw: String): String? {
        val value = raw.trim()
        if (value.length < 4 || value.length > 2048) return null
        if (value.any { it.isWhitespace() }) return null
        val candidate = if (value.contains("://")) value else "https://$value"
        val host = BlockPrefs.hostOf(candidate)
        if (host.isEmpty() || !host.contains('.')) return null
        if (BlockPrefs.isIpLiteral(host)) return null
        return candidate
    }
}
