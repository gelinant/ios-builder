package app.vela.core.data

import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.toLocalDateTime

/**
 * Closing times, closure state and the arrival warning (SPEC 5.7, issue #606). Google's live
 * status text is the primary source ("Open ⋅ Closes 9 PM", "Closed today"); the weekly hours are
 * the fallback when Google sends no status. Times are handled in the phone's own zone, so a
 * closing that runs past midnight stays later than the current minute, and a zone change moves
 * the whole calculation with it.
 *
 * Only an OPEN place yields a closing time: a closed place's status carries an OPENING time
 * ("Closed ⋅ Opens 9 AM") and must not be mistaken for a closing.
 */
object ClosingTime {
    // "9 PM", "7:30 pm", "12 a.m." — the 12-hour shapes Google writes in English-style locales.
    private val T12 = Regex("""(\d{1,2})(?::(\d{2}))?\s*([ap])\.?\s?m\.?""", RegexOption.IGNORE_CASE)

    // "19:00", "19h00", "19.30" — the 24-hour shapes in the other scraped locales.
    private val T24 = Regex("""(\d{1,2})[:hH.](\d{2})""")

    /** The same 60-minute window as Android's `NavController.closingMessage`: an arrival less
     *  than an hour after the doors close, or after they close, warns. */
    const val ARRIVAL_WINDOW_MIN = 60

    /** The card's countdown uses the same window: "Closes in N min" starts below an hour. */
    const val SOON_MIN = 60

    /** The three states the card must name beyond Google's own status spelling. */
    enum class Kind { OPEN, CLOSING_SOON, CLOSED, CLOSED_TODAY, TEMPORARILY_CLOSED, PERMANENTLY_CLOSED, UNKNOWN }

    /** The card's closure line. [closesInMinutes] and [closesAtMinuteOfDay] are -1 when unknown;
     *  a midnight closing is 1440, tonight's midnight. */
    data class Status(
        val kind: Kind,
        val closesInMinutes: Int = -1,
        val closesAtMinuteOfDay: Int = -1,
        val opensAtMinuteOfDay: Int = -1,
        val detail: String? = null,
    ) {
        /** True when the card shows "Closes in N min": under an hour, same as Android's warning. */
        val closingSoon: Boolean get() = kind == Kind.CLOSING_SOON
        val closedToday: Boolean get() = kind == Kind.CLOSED_TODAY
        val temporarilyClosed: Boolean get() = kind == Kind.TEMPORARILY_CLOSED
        val permanentlyClosed: Boolean get() = kind == Kind.PERMANENTLY_CLOSED
    }

    /** The navigation warning: the place closes at [closesAtMinuteOfDay], the drive arrives at
     *  [arrivesAtMinuteOfDay], both local minutes (0..1439). [beforeArrival] is true when the
     *  doors close before the drive lands. */
    data class ArrivalWarning(
        val name: String,
        val closesAtMinuteOfDay: Int,
        val arrivesAtMinuteOfDay: Int,
        val beforeArrival: Boolean,
    )

    /**
     * Today's closing time as a minute-of-day, or null when there is nothing to parse (place
     * closed, "Open 24 hours", no status). A midnight closing ("12 AM" / "00:00") returns 1440,
     * i.e. tonight's midnight, so it stays LATER than any same-day arrival in plain arithmetic.
     */
    fun closingMinuteOfDay(statusText: String?, openNow: Boolean?): Int? {
        if (openNow != true) return null
        val s = statusText ?: return null
        // The LAST time token wins: an open status carries the closing time as its final time
        // ("Open ⋅ Closes 9 PM", "Closes soon ⋅ 9 PM"); "Open 24 hours" carries none.
        val m12 = T12.findAll(s).lastOrNull()
        if (m12 != null) {
            val h = m12.groupValues[1].toInt()
            val min = m12.groupValues[2].ifEmpty { "0" }.toInt()
            if (h !in 1..12 || min > 59) return null
            val pm = m12.groupValues[3].equals("p", ignoreCase = true)
            val h24 = when {
                pm && h < 12 -> h + 12
                !pm && h == 12 -> 24 // "12 AM" as a closing means midnight TONIGHT
                else -> h
            }
            return h24 * 60 + min
        }
        val m24 = T24.findAll(s).lastOrNull() ?: return null
        val h = m24.groupValues[1].toInt()
        val min = m24.groupValues[2].toInt()
        if (h > 24 || min > 59) return null
        return (if (h == 0) 24 else h) * 60 + min // "00:00" closing is midnight tonight too
    }

    /** The card's one closure line. [openNow] is 1 open, 0 closed, -1 unknown, because Swift
     *  carries the nullable Kotlin Boolean awkwardly. A permanent or temporary closure wins over
     *  every status. */
    fun status(
        statusText: String?,
        openNow: Int,
        hours: List<String>,
        permanentlyClosed: Boolean,
        temporarilyClosed: Boolean,
        nowEpochSec: Long,
        zoneId: String,
    ): Status {
        if (permanentlyClosed) return Status(Kind.PERMANENTLY_CLOSED)
        if (temporarilyClosed) return Status(Kind.TEMPORARILY_CLOSED)
        val at = localTime(nowEpochSec, zoneId)
        val nowMinute = at.hour * 60 + at.minute
        val parsed = parseHours(hours)
        val closedToday = when {
            parsed != null -> isClosedAllDay(parsed, at)
            else -> saysClosedToday(statusText)
        }
        if (!statusText.isNullOrBlank()) {
            if (openNow == 0) {
                return Status(if (closedToday) Kind.CLOSED_TODAY else Kind.CLOSED)
            }
            if (openNow == 1) {
                val closing = closingMinuteOfDay(statusText, true)
                if (closing != null) return open(closing, nowMinute)
                return Status(Kind.OPEN, detail = statusText)
            }
            return Status(if (closedToday) Kind.CLOSED_TODAY else Kind.UNKNOWN, detail = statusText)
        }
        val computed = parsed?.let { statusAt(it, at) } ?: return Status(
            if (closedToday) Kind.CLOSED_TODAY else Kind.UNKNOWN,
        )
        if (!computed.open) {
            return Status(
                if (closedToday) Kind.CLOSED_TODAY else Kind.CLOSED,
                opensAtMinuteOfDay = computed.opensAtMinuteOfDay,
                detail = computed.detail,
            )
        }
        val closing = computed.closesAtMinuteOfDay
        return if (closing < 0) {
            Status(Kind.OPEN, detail = computed.detail)
        } else {
            open(closing, nowMinute)
        }
    }

    /** The navigation warning for an arrival [arrivalInSeconds] from now, or null when the place
     *  has no parsable closing time or the arrival is more than [ARRIVAL_WINDOW_MIN] before it. */
    fun arrivalWarning(
        name: String,
        statusText: String?,
        openNow: Int,
        arrivalInSeconds: Double,
        nowEpochSec: Long,
        zoneId: String,
    ): ArrivalWarning? {
        if (openNow != 1) return null
        val closing = closingMinuteOfDay(statusText, true) ?: return null
        val at = localTime(nowEpochSec, zoneId)
        val nowMinute = at.hour * 60 + at.minute
        // A closing that reads EARLIER than now is past midnight ("Closes 1 AM" seen at 11 PM).
        val closeAbsolute = if (closing < nowMinute) closing + DAY else closing
        val arriveMinute = nowMinute + (arrivalInSeconds / 60.0).toInt()
        val gap = closeAbsolute - arriveMinute
        if (gap >= ARRIVAL_WINDOW_MIN) return null
        return ArrivalWarning(
            name = name,
            closesAtMinuteOfDay = closeAbsolute % DAY,
            arrivesAtMinuteOfDay = arriveMinute % DAY,
            beforeArrival = gap < 0,
        )
    }

    /** The weekly hours' open/closed state, a timezone-aware port of Android's OpeningHours. */
    data class DayStatus(
        val open: Boolean,
        val detail: String,
        val closesAtMinuteOfDay: Int = -1,
        val opensAtMinuteOfDay: Int = -1,
    )

    fun statusAt(hours: List<String>, at: LocalDateTime): DayStatus? {
        val byDay = parseHours(hours)?.takeIf { it.isNotEmpty() } ?: return null
        return statusAt(byDay, at)
    }

    private fun statusAt(byDay: Map<DayOfWeek, List<Pair<Int, Int>>>, at: LocalDateTime): DayStatus? {
        val today = at.dayOfWeek
        val nowMin = at.hour * 60 + at.minute
        val todayIv = byDay[today].orEmpty()
        val yesterdayIv = byDay[shift(today, -1)].orEmpty()
        val hitToday = todayIv.firstOrNull { nowMin >= it.first && nowMin < it.second }
        val hitYesterday = yesterdayIv.firstOrNull { it.second > DAY && nowMin < it.second - DAY }
        if (hitToday != null || hitYesterday != null) {
            if (hitToday != null && hitToday.first == 0 && hitToday.second >= DAY) {
                return DayStatus(true, "Open 24 hours")
            }
            val close = (hitToday?.second ?: hitYesterday!!.second) % DAY
            return DayStatus(true, "Closes ${fmt(close)}", closesAtMinuteOfDay = close)
        }
        todayIv.filter { it.first > nowMin }.minByOrNull { it.first }
            ?.let { return DayStatus(false, "Opens ${fmt(it.first)}", opensAtMinuteOfDay = it.first) }
        for (d in 1..7) {
            val day = shift(today, d)
            val iv = byDay[day].orEmpty().minByOrNull { it.first } ?: continue
            val name = DAY_NAMES[day.isoDayNumber - 1].take(3)
            val suffix = if (d == 1) "tomorrow" else name
            return DayStatus(false, "Opens ${fmt(iv.first)} $suffix", opensAtMinuteOfDay = iv.first)
        }
        return DayStatus(false, "Closed")
    }

    private const val DAY = 1440
    private val DAY_NAMES = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

    private fun localTime(epochSec: Long, zoneId: String): LocalDateTime {
        val zone = runCatching { TimeZone.of(zoneId) }.getOrDefault(TimeZone.UTC)
        return Instant.fromEpochSeconds(epochSec).toLocalDateTime(zone)
    }

    private fun open(closesAt: Int, nowMinute: Int): Status {
        val closeAbsolute = if (closesAt < nowMinute) closesAt + DAY else closesAt
        val inMinutes = closeAbsolute - nowMinute
        return Status(
            kind = if (inMinutes in 0 until SOON_MIN) Kind.CLOSING_SOON else Kind.OPEN,
            closesInMinutes = inMinutes,
            closesAtMinuteOfDay = closesAt,
        )
    }

    private fun shift(day: DayOfWeek, delta: Int): DayOfWeek =
        DayOfWeek((day.isoDayNumber - 1 + delta + 7) % 7 + 1)

    private fun isClosedAllDay(byDay: Map<DayOfWeek, List<Pair<Int, Int>>>, at: LocalDateTime): Boolean {
        val today = byDay[at.dayOfWeek].orEmpty()
        val yesterday = byDay[shift(at.dayOfWeek, -1)].orEmpty()
        return today.isEmpty() && yesterday.none { it.second > DAY }
    }

    /** "Monday: 6 AM–1 AM" lines to DayOfWeek intervals. Null when any day cannot be parsed, so
     *  the card shows Google's status rather than a guess. */
    private fun parseHours(hours: List<String>): Map<DayOfWeek, List<Pair<Int, Int>>>? {
        if (hours.isEmpty()) return null
        val map = HashMap<DayOfWeek, List<Pair<Int, Int>>>()
        for (line in hours) {
            val i = line.indexOf(": ")
            if (i < 0) continue
            val day = dayOf(line.substring(0, i).trim()) ?: continue
            val ivs = intervals(line.substring(i + 2).trim()) ?: return null
            map[day] = ivs
        }
        return map.takeIf { it.isNotEmpty() }
    }

    private fun intervals(specRaw: String): List<Pair<Int, Int>>? {
        val spec = specRaw.substringBefore(" · ").trim()
        if (spec.isBlank()) return null
        val low = spec.lowercase()
        if (low.startsWith("closed")) return emptyList()
        if (low.contains("24 hour")) return listOf(0 to DAY)
        return spec.split(",").map { it.trim() }.filter { it.isNotEmpty() }.map { range ->
            val parts = range.split("\u2013", "\u2014", "-", " to ").map { it.trim() }.filter { it.isNotEmpty() }
            if (parts.size != 2) return null
            val endMer = meridian(parts[1])
            val open = parseTime(parts[0], inheritMeridian = if (hasMeridian(parts[0])) null else endMer) ?: return null
            var close = parseTime(parts[1], null) ?: return null
            if (close <= open) close += DAY
            open to close
        }
    }

    private fun hasMeridian(s: String) = s.lowercase().let { it.contains("am") || it.contains("pm") }
    private fun meridian(s: String): String? = s.lowercase().let {
        when {
            it.contains("pm") -> "pm"
            it.contains("am") -> "am"
            else -> null
        }
    }

    /** "6 AM" / "6:30 PM" / "12 PM" / "09:00" / "19:30" to minutes from midnight. */
    private fun parseTime(sRaw: String, inheritMeridian: String?): Int? {
        val s = sRaw.trim().lowercase().replace(".", "")
        val mer = when {
            s.contains("pm") -> "pm"
            s.contains("am") -> "am"
            else -> inheritMeridian
        }
        val digits = s.replace("am", "").replace("pm", "").trim()
        val parts = if (digits.contains(":")) digits.split(":") else listOf(digits, "0")
        if (parts.size != 2) return null
        val h = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        if (m !in 0..59) return null
        if (mer == null) {
            // A 24-hour line: the scraped locales that write these have no AM/PM at all.
            if (h !in 0..24 || !sRaw.contains(":")) return null
            return (if (h == 24) 0 else h) * 60 + m
        }
        if (h !in 1..12) return null
        val h24 = when {
            mer == "am" && h == 12 -> 0
            mer == "am" -> h
            mer == "pm" && h == 12 -> 12
            else -> h + 12
        }
        return h24 * 60 + m
    }

    private fun fmt(min: Int): String {
        val h = min / 60
        val m = min % 60
        val mer = if (h < 12) "AM" else "PM"
        val h12 = when {
            h == 0 -> 12
            h > 12 -> h - 12
            else -> h
        }
        return if (m == 0) "$h12 $mer" else "$h12:${m.toString().padStart(2, '0')} $mer"
    }

    private fun dayOf(nameRaw: String): DayOfWeek? = when (nameRaw.trim().lowercase().take(3)) {
        "mon" -> DayOfWeek.MONDAY
        "tue" -> DayOfWeek.TUESDAY
        "wed" -> DayOfWeek.WEDNESDAY
        "thu" -> DayOfWeek.THURSDAY
        "fri" -> DayOfWeek.FRIDAY
        "sat" -> DayOfWeek.SATURDAY
        "sun" -> DayOfWeek.SUNDAY
        else -> null
    }

    // Google's own "closed today" wording, in the scraped languages, for a place whose weekly
    // hours did not come through. The weekly hours win when they are present.
    private val CLOSED_TODAY = listOf(
        "closed today", "closed for the day", "fermé aujourd'hui", "heute geschlossen",
        "cerrado hoy", "chiuso oggi", "fechado hoje", "gesloten vandaag", "stängt idag",
    )

    private fun saysClosedToday(statusText: String?): Boolean {
        val s = statusText?.lowercase() ?: return false
        return CLOSED_TODAY.any { s.contains(it) }
    }
}
