package app.vela.ios.search

import kotlinx.datetime.LocalDateTime

/**
 * Open right now from the weekly hours Google and the installed packs carry ("Monday: 6 AM-1 AM").
 *
 * The Kotlin port of Android's `OpeningHours.statusAt` (core/src/main/java/app/vela/core/util),
 * reduced to the Boolean the results filter needs: Android's version also names the next
 * transition ("Closes 1 AM"), which no iOS surface shows. Google's live `openNow` stays primary;
 * this is the fallback when the multi-result reply omitted the status, as on Android.
 *
 * Returns null when a present day cannot be read, so a filter never guesses.
 */
object PlaceHours {
    private const val DAY = 1440

    fun openAt(hours: List<String>, now: LocalDateTime): Boolean? {
        val byDay = parse(hours)?.takeIf { days -> days.any { it != null } } ?: return null
        val today = now.dayOfWeek.ordinal
        val nowMin = now.hour * 60 + now.minute
        val todayIv = byDay[today].orEmpty()
        val yesterdayIv = byDay[(today + 6) % 7].orEmpty()
        if (todayIv.any { nowMin >= it.first && nowMin < it.second }) return true
        // A range that runs past midnight ("6 PM-1 AM") belongs to yesterday's line.
        if (yesterdayIv.any { it.second > DAY && nowMin < it.second - DAY }) return true
        return false
    }

    /** Day index (Monday 0) to minute intervals; a past-midnight close is stored as close + 1440. */
    private fun parse(hours: List<String>): Array<List<Pair<Int, Int>>?>? {
        val byDay = arrayOfNulls<List<Pair<Int, Int>>>(7)
        for (line in hours) {
            val i = line.indexOf(": ")
            if (i < 0) continue
            val day = dayOf(line.substring(0, i).trim()) ?: continue
            val ivs = intervals(line.substring(i + 2).trim()) ?: return null
            byDay[day] = ivs
        }
        return byDay
    }

    private fun intervals(raw: String): List<Pair<Int, Int>>? {
        val spec = raw.substringBefore(" · ").trim() // drop a trailing holiday label
        if (spec.isEmpty()) return null
        val low = spec.lowercase()
        if (low.startsWith("closed")) return emptyList()
        if (low.contains("24 hour")) return listOf(0 to DAY)
        return spec.split(",").map { it.trim() }.filter { it.isNotEmpty() }.map { range ->
            val parts = range.split("\u2013", "\u2014", "-", " to ").map { it.trim() }.filter { it.isNotEmpty() }
            if (parts.size != 2) return null
            // An implicit meridian ("5-10 PM") lets the opening time inherit the closing one.
            val endMeridian = meridian(parts[1])
            val open = parseTime(parts[0], if (hasMeridian(parts[0])) null else endMeridian) ?: return null
            var close = parseTime(parts[1], null) ?: return null
            if (close <= open) close += DAY
            open to close
        }
    }

    private fun hasMeridian(s: String) = s.lowercase().let { it.contains("am") || it.contains("pm") }

    private fun meridian(s: String): String? =
        s.lowercase().let { if (it.contains("pm")) "pm" else if (it.contains("am")) "am" else null }

    /** "6 AM" / "6:30 PM" / "12 PM" (noon) / "12 AM" (midnight) to minutes from midnight. */
    private fun parseTime(raw: String, inheritMeridian: String?): Int? {
        val s = raw.trim().lowercase().replace(".", "")
        val mer = when {
            s.contains("pm") -> "pm"
            s.contains("am") -> "am"
            else -> inheritMeridian
        } ?: return null
        val digits = s.replace("am", "").replace("pm", "").trim()
        val (h, m) = if (digits.contains(":")) {
            val p = digits.split(":")
            (p[0].toIntOrNull() ?: return null) to (p.getOrNull(1)?.toIntOrNull() ?: return null)
        } else {
            (digits.toIntOrNull() ?: return null) to 0
        }
        if (h < 1 || h > 12 || m < 0 || m > 59) return null
        val h24 = when {
            mer == "am" && h == 12 -> 0
            mer == "am" -> h
            mer == "pm" && h == 12 -> 12
            else -> h + 12
        }
        return h24 * 60 + m
    }

    private fun dayOf(name: String): Int? = when (name.trim().lowercase().take(3)) {
        "mon" -> 0
        "tue" -> 1
        "wed" -> 2
        "thu" -> 3
        "fri" -> 4
        "sat" -> 5
        "sun" -> 6
        else -> null
    }
}
