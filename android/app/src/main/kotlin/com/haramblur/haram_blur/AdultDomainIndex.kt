package com.haramblur.haram_blur

import android.content.Context
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Arrays

/**
 * FNV-1a 64-bit hashing of a host, shared by the index lookup and its tests.
 *
 * `tools/build_blocklist_index.py` computes the same values with the same
 * signed ordering, so the bundled table can be searched with a plain binary
 * search. Changing either side without the other breaks every lookup.
 */
object AdultHash {
    /** 0xcbf29ce484222325 as a signed Long. */
    private const val FNV_OFFSET = -3750763034362895579L
    private const val FNV_PRIME = 0x100000001b3L

    fun of(value: String): Long {
        var digest = FNV_OFFSET
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            digest = digest xor (byte.toLong() and 0xff)
            digest *= FNV_PRIME
        }
        return digest
    }

    /** True when [value] is present in a sorted table (see the generator). */
    fun containsSorted(table: LongArray, value: Long): Boolean =
        Arrays.binarySearch(table, value) >= 0

    /**
     * True when [host] or any parent domain of it is in [table], so a listing
     * for `pornhub.com` also covers `de.pornhub.com` without an entry each.
     */
    fun matchesHost(table: LongArray, host: String): Boolean {
        var candidate = host.trim().lowercase()
        while (candidate.isNotEmpty()) {
            if (containsSorted(table, of(candidate))) return true
            val dot = candidate.indexOf('.')
            if (dot < 0) return false
            candidate = candidate.substring(dot + 1)
        }
        return false
    }
}

/**
 * The bundled adult-domain list: about 952k hosts, stored as a sorted array of
 * 64-bit hashes.
 *
 * The text list is 25 MB, and roughly 85 MB once parsed into strings, which is
 * far too much for a service that also runs the detector. Hashes cost 7.3 MB
 * on disk and the same in the heap, and a hit is a binary search per host
 * label (`de.pornhub.com`, `pornhub.com`, `com`), so subdomains are covered
 * without listing them. A 64-bit hash of 952k hosts has a collision chance of
 * about 1 in 40 million, i.e. a false block is not a practical concern.
 */
object AdultDomainIndex {
    private const val TAG = "AdultDomainIndex"

    /** Flutter bundles assets under `assets/flutter_assets/`. */
    private const val ASSET = "flutter_assets/assets/blocklists/adult_domains.idx"

    @Volatile
    private var hashes: LongArray? = null

    @Volatile
    private var unavailable = false

    /** True when [url]'s host, or any parent domain of it, is on the list. */
    fun isBlocked(context: Context, url: String): Boolean {
        val host = BlockPrefs.hostOf(url)
        if (host.isEmpty()) return false
        return isBlockedHost(context, host)
    }

    fun isBlockedHost(context: Context, host: String): Boolean {
        val table = load(context) ?: return false
        return AdultHash.matchesHost(table, host)
    }

    /** Number of bundled entries, 0 while the asset could not be read. */
    fun size(context: Context): Int = load(context)?.size ?: 0

    /**
     * Reads the index once per process. Called from the capture thread, never
     * from the main thread; a missing asset only weakens the domain layer, so
     * failure is logged and remembered rather than thrown.
     */
    private fun load(context: Context): LongArray? {
        hashes?.let { return it }
        if (unavailable) return null
        synchronized(this) {
            hashes?.let { return it }
            if (unavailable) return null
            return try {
                val bytes = context.applicationContext.assets
                    .open(ASSET)
                    .use { it.readBytes() }
                val values = LongArray(bytes.size / 8)
                ByteBuffer.wrap(bytes)
                    .order(ByteOrder.LITTLE_ENDIAN)
                    .asLongBuffer()
                    .get(values)
                // Already sorted by the generator; a sorted check is cheap and
                // keeps a truncated or reordered asset from blocking at random.
                if (!isSorted(values)) values.sort()
                Log.i(TAG, "Loaded ${values.size} bundled adult domains")
                values.also { hashes = it }
            } catch (error: Throwable) {
                Log.w(TAG, "Bundled adult-domain index unavailable", error)
                unavailable = true
                null
            }
        }
    }

    private fun isSorted(values: LongArray): Boolean {
        for (index in 1 until values.size) {
            if (values[index] < values[index - 1]) return false
        }
        return true
    }
}
