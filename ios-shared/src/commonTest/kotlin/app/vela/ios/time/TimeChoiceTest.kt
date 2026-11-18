package app.vela.ios.time

import app.vela.core.data.ClockFormat
import kotlinx.datetime.TimeZone
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class TimeChoiceTest {
    private val previous24h = ClockFormat.use24h

    @AfterTest
    fun restoreClock() {
        ClockFormat.use24h = previous24h
    }

    @Test
    fun theThreeModesKeepThePlannerNumbers() {
        assertEquals(0, TimeChoice.normalizedMode(0))
        assertEquals(1, TimeChoice.normalizedMode(1))
        assertEquals(2, TimeChoice.normalizedMode(2))
        assertEquals(0, TimeChoice.normalizedMode(3), "an unknown mode is leave now")
        assertEquals(0, TimeChoice.normalizedMode(-1), "an unknown mode is leave now")
    }

    @Test
    fun onlyAFutureModeSendsATime() {
        assertNull(TimeChoice.queryEpoch(TimeChoice.NOW, 1_800_000_000L), "leave now sends no time")
        assertNull(TimeChoice.queryEpoch(TimeChoice.DEPART, 0L), "no epoch means no time")
        assertEquals(1_800_000_000L, TimeChoice.queryEpoch(TimeChoice.DEPART, 1_800_000_000L))
        assertEquals(1_800_000_000L, TimeChoice.queryEpoch(TimeChoice.ARRIVE, 1_800_000_000L))
    }

    @Test
    fun leaveNowStoresNoEpoch() {
        assertEquals(0L, TimeChoice.normalizedEpoch(TimeChoice.NOW, 1_800_000_000L, 1_790_000_000L))
        assertEquals(0L, TimeChoice.normalizedEpoch(TimeChoice.NOW, 0L, 1_790_000_000L))
    }

    @Test
    fun aPastTimeMovesToTheNextSlot() {
        val now = 1_790_000_001L
        val slot = TimeChoice.nextFiveMinuteSlot(now)
        assertEquals(slot, TimeChoice.normalizedEpoch(TimeChoice.DEPART, 0L, now))
        assertEquals(slot, TimeChoice.normalizedEpoch(TimeChoice.DEPART, now - 60L, now))
        assertEquals(slot, TimeChoice.normalizedEpoch(TimeChoice.ARRIVE, now, now))
        assertEquals(slot, TimeChoice.normalizedEpoch(TimeChoice.ARRIVE, now - 3_600L, now))
    }

    @Test
    fun aFutureTimeIsKept() {
        val now = 1_790_000_001L
        val later = now + 86_400L
        assertEquals(later, TimeChoice.normalizedEpoch(TimeChoice.DEPART, later, now))
        assertEquals(later, TimeChoice.normalizedEpoch(TimeChoice.ARRIVE, later, now))
    }

    @Test
    fun theNextSlotIsAlwaysOnAFiveMinuteGrid() {
        assertEquals(1_800L, TimeChoice.nextFiveMinuteSlot(1_800L), "a slot keeps itself")
        assertEquals(2_100L, TimeChoice.nextFiveMinuteSlot(1_801L))
        assertEquals(2_100L, TimeChoice.nextFiveMinuteSlot(2_099L))
        val now = 1_790_000_000L
        val next = TimeChoice.nextFiveMinuteSlot(now)
        assertEquals(0L, next % TimeChoice.SLOT_SECONDS)
        assertEquals(0L, TimeChoice.nextFiveMinuteSlot(next + 3_600L) % TimeChoice.SLOT_SECONDS)
    }

    @Test
    fun plusFifteenMinutesStaysOnTheGrid() {
        assertEquals(1_800L + 900L, TimeChoice.plusFifteenMinutes(1_800L))
        assertEquals(0L, TimeChoice.plusFifteenMinutes(1_800L) % TimeChoice.SLOT_SECONDS)
    }

    @Test
    fun labelsNameTheModeAndTheClockTime() {
        ClockFormat.use24h = true
        val zone = TimeZone.UTC
        assertEquals("Leave now", TimeChoice.label(TimeChoice.NOW, 0L, zone))
        assertEquals("Leave now", TimeChoice.label(7, 1_800L, zone))
        assertEquals("Depart at 09:05", TimeChoice.label(TimeChoice.DEPART, 1_792_746_300L, zone))
        assertEquals("Arrive by 09:00", TimeChoice.label(TimeChoice.ARRIVE, 1_792_746_000L, zone))
    }

    @Test
    fun labelsFollowTheTwelveHourClockWhenItIsChosen() {
        ClockFormat.use24h = false
        val zone = TimeZone.UTC
        assertEquals("Depart at 9:05 AM", TimeChoice.label(TimeChoice.DEPART, 1_792_746_300L, zone))
        assertEquals("Arrive by 9:00 PM", TimeChoice.label(TimeChoice.ARRIVE, 1_792_789_200L, zone))
    }

    @Test
    fun labelsFollowTheZoneAcrossADstChange() {
        ClockFormat.use24h = true
        val zone = TimeZone.of("America/New_York")
        // 2026-03-08: 02:00 local does not exist, so 07:00 UTC reads 03:00, not 02:00.
        assertEquals("Depart at 01:59", TimeChoice.label(TimeChoice.DEPART, 1_772_953_140L, zone))
        assertEquals("Depart at 03:00", TimeChoice.label(TimeChoice.DEPART, 1_772_953_200L, zone))
    }
}
