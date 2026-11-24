package com.haramblur.haram_blur

import java.util.Calendar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The prayer windows are computed, not looked up, so these tests pin the
 * arithmetic to real dates instead of a table.
 */
class PrayerTimesTest {
    private fun date(year: Int, month: Int, day: Int): Calendar =
        Calendar.getInstance().apply {
            clear()
            set(year, month - 1, day, 12, 0, 0)
        }

    @Test
    fun `cairo in november has five ascending windows`() {
        val windows = PrayerTimes.forDate(
            date(2026, 11, 18),
            30.0444,
            31.2357,
            2.0,
            15,
            PrayerTimes.Method.Egyptian,
        )
        assertEquals(
            listOf("Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"),
            windows.map { it.name },
        )
        val starts = windows.map { it.startMinute }
        assertEquals(starts.sorted(), starts)
        val dhuhr = windows.first { it.name == "Dhuhr" }
        assertTrue("dhuhr was ${dhuhr.startMinute}", dhuhr.startMinute in 11 * 60..13 * 60)
        val maghrib = windows.first { it.name == "Maghrib" }
        assertTrue(
            "maghrib was ${maghrib.startMinute}",
            maghrib.startMinute in 16 * 60..18 * 60,
        )
        assertTrue(windows.all { it.endMinute - it.startMinute == 15 })
    }

    @Test
    fun `a window contains its own minutes`() {
        val window = PrayerTimes.Window("Asr", 14 * 60, 14 * 60 + 15)
        assertTrue(window.contains(14 * 60))
        assertTrue(window.contains(14 * 60 + 15))
        assertFalse(window.contains(14 * 60 + 16))
        assertFalse(window.contains(13 * 60 + 59))
    }

    @Test
    fun `a sun that never reaches the twilight angle omits the prayer`() {
        // Stockholm in June: the sun stays above 18 degrees below the horizon
        // all night, so Fajr and Isha cannot be computed.
        val windows = PrayerTimes.forDate(
            date(2026, 6, 21),
            59.3293,
            18.0686,
            2.0,
            10,
            PrayerTimes.Method.MuslimWorldLeague,
        )
        assertFalse(windows.any { it.name == "Fajr" })
        assertFalse(windows.any { it.name == "Isha" })
        assertTrue(windows.any { it.name == "Dhuhr" })
        assertTrue(windows.any { it.name == "Maghrib" })
    }

    @Test
    fun `impossible coordinates produce no windows`() {
        val windows = PrayerTimes.forDate(
            date(2026, 11, 18),
            120.0,
            31.2357,
            2.0,
            15,
            PrayerTimes.Method.MuslimWorldLeague,
        )
        assertTrue(windows.isEmpty())
    }
}
