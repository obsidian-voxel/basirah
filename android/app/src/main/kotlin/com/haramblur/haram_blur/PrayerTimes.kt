package com.haramblur.haram_blur

import android.content.Context
import java.util.Calendar
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.tan

/**
 * Offline prayer times, computed from the device clock, coordinates the user
 * typed and the day's solar declination.
 *
 * The app has no location permission and no network: the user enters a
 * latitude and longitude once, and the same arithmetic runs every day on the
 * service side, so a prayer window still blocks when the Flutter engine is
 * gone. No table, no server, no learned model.
 *
 * Coordinates and method live in [BlockPrefs]; [today] returns the windows for
 * the current day in minutes since midnight.
 */
object PrayerTimes {

    /** One prayer and how long the block lasts after it begins. */
    data class Window(val name: String, val startMinute: Int, val endMinute: Int) {
        /** `start > end` wraps midnight, matching `ScheduleWindow`. */
        fun contains(minute: Int): Boolean =
            if (startMinute <= endMinute) {
                minute in startMinute..endMinute
            } else {
                minute >= startMinute || minute <= endMinute
            }
    }

    /**
     * Fajr and Isha twilight angles in degrees. Islamic schools differ; these
     * are the four common presets, and the numbers are the only difference.
     */
    enum class Method(val fajrAngle: Double, val ishaAngle: Double) {
        MuslimWorldLeague(18.0, 17.0),
        Egyptian(19.5, 17.5),
        Karachi(18.0, 18.0),
        Isna(15.0, 15.0),
        UmmAlQura(18.5, 0.0),
        ;

        companion object {
            fun of(name: String?): Method =
                values().firstOrNull { it.name.equals(name, ignoreCase = true) }
                    ?: MuslimWorldLeague
        }
    }

    /** Solar altitude used for sunrise/sunset: refraction plus the sun's disc. */
    private const val HORIZON_ALTITUDE = -0.833

    /** Asr shadow length factor: 1 = Shafi, Maliki, Hanbali; 2 = Hanafi. */
    private const val ASR_SHADOW = 1.0

    /** Isha fallback for Umm al-Qura: 90 minutes after Maghrib. */
    private const val UMM_AL_QURA_ISHA_MINUTES = 90

    /** Today's windows from the stored configuration; empty when disabled. */
    fun today(context: Context, now: Calendar = Calendar.getInstance()): List<Window> =
        if (BlockPrefs.prayerEnabled(context)) preview(context, now) else emptyList()

    /**
     * Today's windows regardless of the switch, so Settings can show what the
     * times would be before the user turns blocking on.
     */
    fun preview(context: Context, now: Calendar = Calendar.getInstance()): List<Window> {
        val latitude = BlockPrefs.prayerLatitude(context)
        val longitude = BlockPrefs.prayerLongitude(context)
        if (latitude.isNaN() || longitude.isNaN()) return emptyList()
        val minutesAfter = BlockPrefs.prayerMinutesAfter(context).coerceIn(1, 120)
        val method = Method.of(BlockPrefs.prayerMethod(context))
        val zone = TimeZone.getDefault()
        val offsetHours =
            zone.getOffset(now.timeInMillis).toDouble() / 3_600_000.0
        return forDate(now, latitude, longitude, offsetHours, minutesAfter, method)
    }

    /**
     * Five windows for [date]. A prayer whose twilight never reaches the
     * required angle (high-latitude summer, polar winter) is omitted rather
     * than replaced by a guessed time: a wrong window would block a prayer
     * that has not begun.
     */
    fun forDate(
        date: Calendar,
        latitude: Double,
        longitude: Double,
        timezoneHours: Double,
        minutesAfter: Int,
        method: Method,
    ): List<Window> {
        if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return emptyList()
        val jd = julianDay(date)
        val (declination, equationOfTime) = sunPosition(jd)
        val noon = 12.0 + timezoneHours - longitude / 15.0 - equationOfTime

        val sunriseHour = hourAngle(HORIZON_ALTITUDE, latitude, declination) ?: return emptyList()
        val fajrOffset = hourAngle(-method.fajrAngle, latitude, declination)
        val ishaOffset = hourAngle(-method.ishaAngle, latitude, declination)
        val asrAltitude = Math.toDegrees(
            atan(1.0 / (ASR_SHADOW + tan(Math.toRadians(abs(latitude - declination))))),
        )
        val asrOffset = hourAngle(asrAltitude, latitude, declination)

        // Local solar hours; Dhuhr is solar noon, Maghrib is sunset.
        val dhuhr = noon
        val maghrib = noon + sunriseHour
        val entries = ArrayList<Pair<String, Double>>(5)
        fajrOffset?.let { entries.add("Fajr" to noon - it) }
        entries.add("Dhuhr" to dhuhr)
        asrOffset?.let { entries.add("Asr" to noon + it) }
        entries.add("Maghrib" to maghrib + 1.0 / 60.0)
        when {
            method.ishaAngle > 0.0 && ishaOffset != null ->
                entries.add("Isha" to noon + ishaOffset)
            method == Method.UmmAlQura ->
                entries.add("Isha" to maghrib + UMM_AL_QURA_ISHA_MINUTES / 60.0)
        }

        val hold = minutesAfter.coerceIn(1, 120)
        return entries.mapNotNull { (name, hour) -> window(name, hour, hold) }
    }

    private fun window(name: String, hour: Double, hold: Int): Window? {
        if (hour.isNaN() || hour.isInfinite()) return null
        val start = (hour * 60.0).roundToInt()
        if (start < 0 || start >= 1440) return null
        // A window that would run past midnight stops at midnight; the next
        // day's Fajr window is computed fresh rather than carried over.
        val end = (start + hold).coerceAtMost(1439)
        return Window(name, start, end)
    }

    /**
     * Hour angle of the sun at [altitudeDeg], in hours. Null when the sun
     * never reaches that altitude on this day at this latitude.
     */
    private fun hourAngle(altitudeDeg: Double, latitude: Double, declination: Double): Double? {
        val latRad = Math.toRadians(latitude)
        val decRad = Math.toRadians(declination)
        val altRad = Math.toRadians(altitudeDeg)
        val cosH = (sin(altRad) - sin(latRad) * sin(decRad)) / (cos(latRad) * cos(decRad))
        if (cosH.isNaN() || cosH > 1.0 || cosH < -1.0) return null
        return Math.toDegrees(acos(cosH)) / 15.0
    }

    /** Julian day number at 00:00 local time. */
    private fun julianDay(date: Calendar): Double {
        var year = date.get(Calendar.YEAR)
        var month = date.get(Calendar.MONTH) + 1
        val day = date.get(Calendar.DAY_OF_MONTH)
        if (month <= 2) {
            year -= 1
            month += 12
        }
        val a = floor(year / 100.0)
        val b = 2 - a + floor(a / 4.0)
        return floor(365.25 * (year + 4716)) +
            floor(30.6001 * (month + 1)) + day + b - 1524.5
    }

    /** Solar declination (degrees) and equation of time (hours). */
    private fun sunPosition(julianDay: Double): Pair<Double, Double> {
        val d = julianDay - 2_451_545.0
        val meanAnomaly = fixAngle(357.529 + 0.98560028 * d)
        val meanLongitude = fixAngle(280.459 + 0.98564736 * d)
        val eclipticLongitude = fixAngle(
            meanLongitude + 1.915 * sin(Math.toRadians(meanAnomaly)) +
                0.020 * sin(Math.toRadians(2 * meanAnomaly)),
        )
        val obliquity = 23.439 - 0.00000036 * d
        val rightAscension = Math.toDegrees(
            atan2(
                cos(Math.toRadians(obliquity)) * sin(Math.toRadians(eclipticLongitude)),
                cos(Math.toRadians(eclipticLongitude)),
            ),
        ) / 15.0
        val declination = Math.toDegrees(
            asin(sin(Math.toRadians(obliquity)) * sin(Math.toRadians(eclipticLongitude))),
        )
        val equationOfTime = meanLongitude / 15.0 - fixHour(rightAscension)
        return declination to equationOfTime
    }

    private fun fixAngle(value: Double): Double = value - 360.0 * floor(value / 360.0)

    private fun fixHour(value: Double): Double = value - 24.0 * floor(value / 24.0)
}
