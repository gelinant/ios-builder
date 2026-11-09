package app.vela.core.data

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.Test
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDateTime

class ClosingTimeTest {

    @Test fun parsesEnglish12h() {
        assertEquals(21 * 60, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 9 PM", true))
    }

    @Test fun parsesMinutes() {
        assertEquals(19 * 60 + 30, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 7:30 PM", true))
    }

    @Test fun parses24hLocales() {
        assertEquals(19 * 60, ClosingTime.closingMinuteOfDay("Ouvert ⋅ Ferme à 19:00", true))
        assertEquals(19 * 60, ClosingTime.closingMinuteOfDay("Geöffnet ⋅ Schließt um 19:00", true))
    }

    @Test fun closesSoonStillFindsTheTime() {
        assertEquals(21 * 60, ClosingTime.closingMinuteOfDay("Open ⋅ Closes soon ⋅ 9 PM", true))
    }

    @Test fun midnightClosingIsTonight() {
        // 1440, not 0 — must stay later than any same-day arrival in plain arithmetic.
        assertEquals(24 * 60, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 12 AM", true))
        assertEquals(24 * 60, ClosingTime.closingMinuteOfDay("Ouvert ⋅ Ferme à 00:00", true))
    }

    @Test fun noonPmIsNoon() {
        assertEquals(12 * 60, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 12 PM", true))
        assertEquals(12 * 60 + 30, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 12:30 PM", true))
    }

    @Test fun earlyMorning12hIsAfterMidnight() {
        // "12:45 AM" is 00:45, not 24:45: the bug that hid the countdown for a 00:45 closing.
        assertEquals(45, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 12:45 AM", true))
        assertEquals(15, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 12:15 AM", true))
        assertEquals(5, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 12:05 a.m.", true))
    }

    @Test fun explicit24hMidnightIsTonight() {
        assertEquals(24 * 60, ClosingTime.closingMinuteOfDay("Open ⋅ Closes 24:00", true))
        assertEquals(24 * 60, ClosingTime.closingMinuteOfDay("Ouvert ⋅ Ferme à 24h00", true))
    }

    @Test fun closedPlaceNeverParses() {
        // A closed status carries an OPENING time; parsing it as a closing is the failure mode.
        assertNull(ClosingTime.closingMinuteOfDay("Closed ⋅ Opens 9 AM", false))
        assertNull(ClosingTime.closingMinuteOfDay("Closed ⋅ Opens 9 AM", null))
    }

    @Test fun open24HoursHasNoClosing() {
        assertNull(ClosingTime.closingMinuteOfDay("Open 24 hours", true))
    }

    @Test fun nullAndBlankStatus() {
        assertNull(ClosingTime.closingMinuteOfDay(null, true))
        assertNull(ClosingTime.closingMinuteOfDay("Open", true))
    }

    // ── The card's state: countdown, closed today, closures ──────────────────────────────────

    private fun epoch(text: String) = Instant.parse(text).epochSeconds

    @Test fun statusUsesGoogleStatusFirst() {
        val s = ClosingTime.status(
            statusText = "Open · Closes 9 PM", openNow = 1, hours = emptyList(),
            permanentlyClosed = false, temporarilyClosed = false,
            nowEpochSec = epoch("2026-10-05T20:30:00Z"), zoneId = "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSING_SOON, s.kind)
        assertEquals(30, s.closesInMinutes)
        assertEquals(21 * 60, s.closesAtMinuteOfDay)
    }

    @Test fun countdownStartsBelowAnHour() {
        val justInside = ClosingTime.status(
            "Open · Closes 9 PM", 1, emptyList(), false, false,
            epoch("2026-10-05T20:01:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSING_SOON, justInside.kind)
        assertEquals(59, justInside.closesInMinutes)
        val atTheLimit = ClosingTime.status(
            "Open · Closes 9 PM", 1, emptyList(), false, false,
            epoch("2026-10-05T20:00:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.OPEN, atTheLimit.kind)
        assertEquals(60, atTheLimit.closesInMinutes)
        val outside = ClosingTime.status(
            "Open · Closes 9 PM", 1, emptyList(), false, false,
            epoch("2026-10-05T19:59:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.OPEN, outside.kind)
        assertEquals(61, outside.closesInMinutes)
    }

    @Test fun midnightClosingStaysLaterThanNow() {
        val s = ClosingTime.status(
            "Open ⋅ Closes 12 AM", 1, emptyList(), false, false,
            epoch("2026-10-05T23:30:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSING_SOON, s.kind)
        assertEquals(30, s.closesInMinutes)
        assertEquals(24 * 60, s.closesAtMinuteOfDay)
    }

    @Test fun countdownStartsAtFiftyFiveMinutes() {
        val s = ClosingTime.status(
            "Open · Closes 9 PM", 1, emptyList(), false, false,
            epoch("2026-10-05T20:05:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSING_SOON, s.kind)
        assertEquals(55, s.closesInMinutes)
        assertEquals(21 * 60, s.closesAtMinuteOfDay)
    }

    @Test fun countdownWrapsToAQuarterToOneClosing() {
        // 23:50 with a 00:45 close: the close belongs to the coming day, 55 minutes away.
        val s = ClosingTime.status(
            "Open ⋅ Closes 12:45 AM", 1, emptyList(), false, false,
            epoch("2026-10-05T23:50:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSING_SOON, s.kind)
        assertEquals(55, s.closesInMinutes)
        assertEquals(45, s.closesAtMinuteOfDay)

        // Same status read at 00:20: the close is still today, 25 minutes away.
        val afterMidnight = ClosingTime.status(
            "Open ⋅ Closes 12:45 AM", 1, emptyList(), false, false,
            epoch("2026-10-06T00:20:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSING_SOON, afterMidnight.kind)
        assertEquals(25, afterMidnight.closesInMinutes)
        assertEquals(45, afterMidnight.closesAtMinuteOfDay)
    }

    @Test fun weeklyHoursCountAQuarterToOneClose() {
        val s = ClosingTime.status(
            null, 1, listOf("Monday: 9 AM–12:45 AM"), false, false,
            epoch("2026-10-05T23:50:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSING_SOON, s.kind)
        assertEquals(55, s.closesInMinutes)
        assertEquals(45, s.closesAtMinuteOfDay)
    }

    @Test fun timeZoneMovesTheSameInstantAcrossMidnight() {
        // 23:30 UTC on 8 October is 00:30 on the 9th in London (BST). "Closes 1 AM" is then 30
        // minutes away in London and 90 minutes away when the same instant is read as UTC.
        val instant = epoch("2026-10-08T23:30:00Z")
        val london = ClosingTime.status("Open · Closes 1 AM", 1, emptyList(), false, false, instant, "Europe/London")
        val utc = ClosingTime.status("Open · Closes 1 AM", 1, emptyList(), false, false, instant, "UTC")
        assertEquals(ClosingTime.Kind.CLOSING_SOON, london.kind)
        assertEquals(30, london.closesInMinutes)
        assertEquals(ClosingTime.Kind.OPEN, utc.kind)
        assertEquals(90, utc.closesInMinutes)
    }

    @Test fun permanentlyAndTemporarilyClosedWinOverTheStatus() {
        assertEquals(
            ClosingTime.Kind.PERMANENTLY_CLOSED,
            ClosingTime.status("Open · Closes 9 PM", 1, emptyList(), true, false, 0, "UTC").kind,
        )
        assertEquals(
            ClosingTime.Kind.TEMPORARILY_CLOSED,
            ClosingTime.status(null, 0, emptyList(), false, true, 0, "UTC").kind,
        )
    }

    @Test fun closedTodayComesFromTheWeeklyHours() {
        val at = epoch("2026-10-05T12:00:00Z") // Monday noon
        val closedToday = ClosingTime.status(
            null, 0, listOf("Monday: Closed", "Tuesday: 9 AM–5 PM"), false, false, at, "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSED_TODAY, closedToday.kind)
        val afterHours = ClosingTime.status(
            null, 0, listOf("Monday: 9 AM–5 PM"), false, false, epoch("2026-10-05T20:00:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSED, afterHours.kind)
    }

    @Test fun weeklyHoursFallbackCountsDownToo() {
        val open = ClosingTime.status(
            null, 1, listOf("Monday: 9 AM–5 PM"), false, false,
            epoch("2026-10-05T16:45:00Z"), "UTC",
        )
        assertEquals(ClosingTime.Kind.CLOSING_SOON, open.kind)
        assertEquals(15, open.closesInMinutes)
        assertEquals(17 * 60, open.closesAtMinuteOfDay)
    }

    @Test fun statusAtUnderstands24HourLinesAndOvernightRanges() {
        val at = LocalDateTime(2026, 10, 5, 23, 30)
        val late = ClosingTime.statusAt(listOf("Monday: 09:00–01:00"), at)
        assertNotNull(late)
        assertTrue(late.open)
        assertEquals(60, late.closesAtMinuteOfDay)
        assertFalse(ClosingTime.statusAt(listOf("Monday: 09:00–17:00"), at)!!.open)
    }

    // ── The navigation warning: same 60-minute window as Android ─────────────────────────────

    @Test fun arrivalWarningWithinAnHourAndAfterClose() {
        val now = epoch("2026-10-05T16:00:00Z") // Monday 16:00 UTC
        val soon = ClosingTime.arrivalWarning("Co-op", "Open · Closes 5 PM", 1, 1_800.0, now, "UTC")
        assertNotNull(soon)
        assertEquals("Co-op", soon.name)
        assertEquals(17 * 60, soon.closesAtMinuteOfDay)
        assertEquals(16 * 60 + 30, soon.arrivesAtMinuteOfDay)
        assertFalse(soon.beforeArrival)
        val after = ClosingTime.arrivalWarning("Co-op", "Open · Closes 5 PM", 1, 5_400.0, now, "UTC")
        assertNotNull(after)
        assertTrue(after.beforeArrival)
        assertEquals(16 * 60 + 90, after.arrivesAtMinuteOfDay % 1440)
    }

    @Test fun arrivalWarningOutsideTheWindowIsSilent() {
        val now = epoch("2026-10-05T16:00:00Z")
        assertNull(ClosingTime.arrivalWarning("Co-op", "Open · Closes 5 PM", 1, 0.0, now, "UTC"))
        assertNull(ClosingTime.arrivalWarning("Co-op", "Closed · Opens 9 AM", 0, 1_800.0, now, "UTC"))
        assertNull(ClosingTime.arrivalWarning("Co-op", "Open 24 hours", 1, 1_800.0, now, "UTC"))
    }

    @Test fun arrivalWarningCrossesMidnight() {
        val now = epoch("2026-10-05T23:30:00Z")
        val w = ClosingTime.arrivalWarning("Diner", "Open ⋅ Closes 1 AM", 1, 2_700.0, now, "UTC")
        assertNotNull(w)
        assertEquals(60, w.closesAtMinuteOfDay)
        assertEquals((23 * 60 + 30 + 45) % 1440, w.arrivesAtMinuteOfDay)
        assertFalse(w.beforeArrival)
    }
}
