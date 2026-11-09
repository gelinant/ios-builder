package app.vela.ios.transit

import app.vela.core.model.StopDeparture
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TransitBoardStoreTest {
    private var nowMs = 1_800_000_000_000L
    private val nowSec = nowMs / 1000L

    private fun departure(offset: Long, live: Boolean, text: String? = null) =
        StopDeparture(clockText = text ?: "9:0${offset / 60 % 10}", epochSec = nowSec + offset, realtime = live)

    private fun board(vararg lines: StopDepartureLine, name: String = "Ferry Building") =
        StopDepartures(stationName = name, lines = lines.toList())

    private fun line(label: String, mode: TransitMode, headsign: String?, vararg deps: StopDeparture) =
        StopDepartureLine(label = label, mode = mode, headsign = headsign, colorHex = "#cc0000", upcoming = deps.toList())

    @Test fun departuresCarryMinutesAndOnlyTheFeedsLiveFlag() = runTest {
        val answers = ArrayDeque(
            listOf(
                board(
                    line("14", TransitMode.BUS, "Ferry Plaza", departure(180, true), departure(600, false)),
                    line("K", TransitMode.TRAM, "Embarcadero", departure(61, true)),
                ),
            ),
        )
        val store = TransitBoardStore(backgroundScope, { answers.removeFirstOrNull() }, { nowMs }, refreshMillis = 1_000_000L)
        store.open(37.7955, -122.3937, "Ferry Building")
        runCurrent()

        val s = store.state.value
        assertEquals(true, s.open)
        assertFalse(s.loading)
        assertEquals("Ferry Building", s.stopName)
        assertEquals(2, s.lines.size)
        assertEquals("14", s.lines[0].label)
        assertEquals("Ferry Plaza", s.lines[0].headsign)
        assertEquals("#cc0000", s.lines[0].color)
        assertEquals(listOf(3, 10), s.lines[0].departures.map { it.minutes })
        assertEquals(listOf(true, false), s.lines[0].departures.map { it.realtime })
        // 61 s is the next minute, not the current one.
        assertEquals(2, s.lines[1].departures.single().minutes)
        assertEquals(2, s.realtimeCount)
        assertEquals(2, s.soonestMinutes)
        assertNull(s.error)
    }

    @Test fun aDepartedRunDisappearsAndAMissingBoardIsNamed() = runTest {
        val answers = ArrayDeque(
            listOf(
                board(line("14", TransitMode.BUS, "Ferry Plaza", departure(-90, false), departure(-120, false))),
                null,
            ),
        )
        val store = TransitBoardStore(backgroundScope, { answers.removeFirstOrNull() }, { nowMs }, refreshMillis = 1_000_000L)
        store.open(37.7955, -122.3937, "Ferry Building")
        runCurrent()
        // Runs that left more than a minute ago are gone; the line then has no departure at all
        // and is not listed.
        assertEquals(emptyList(), store.state.value.lines)
        assertEquals("no_departures", store.state.value.error)

        store.refresh()
        runCurrent()
        assertEquals("no_departures", store.state.value.error)
    }

    @Test fun aRunThatLeftLessThanAMinuteAgoShowsZero() = runTest {
        val answers = ArrayDeque(listOf(board(line("14", TransitMode.BUS, "Ferry Plaza", departure(-30, false)))))
        val store = TransitBoardStore(backgroundScope, { answers.removeFirstOrNull() }, { nowMs }, refreshMillis = 1_000_000L)
        store.open(37.7955, -122.3937, "Ferry Building")
        runCurrent()
        assertEquals(0, store.state.value.lines.single().departures.single().minutes)
    }

    @Test fun aLiveBoardReplacesAnOlderOneAndAStaleRefreshKeepsIt() = runTest {
        val answers = ArrayDeque(
            listOf(
                board(line("14", TransitMode.BUS, "Ferry Plaza", departure(300, false))),
                board(line("14", TransitMode.BUS, "Ferry Plaza", departure(300, true))),
                null,
            ),
        )
        val store = TransitBoardStore(backgroundScope, { answers.removeFirstOrNull() }, { nowMs }, refreshMillis = 1_000_000L)
        store.open(37.7955, -122.3937, "Ferry Building")
        runCurrent()
        assertEquals(5, store.state.value.lines.single().departures.single().minutes)

        nowMs += 60_000
        store.refresh()
        runCurrent()
        assertEquals(4, store.state.value.lines.single().departures.single().minutes)
        assertTrue(store.state.value.lines.single().departures.single().realtime)

        store.refresh()
        runCurrent()
        // A failed refresh keeps the last real board and marks it stale instead of emptying it.
        assertEquals(4, store.state.value.lines.single().departures.single().minutes)
        assertTrue(store.state.value.refreshFailed)
        assertNull(store.state.value.error)
    }

    @Test fun theAutomaticRefreshAsksAgainWhileOpen() = runTest {
        var asks = 0
        val store = TransitBoardStore(
            backgroundScope,
            {
                asks += 1
                board(line("14", TransitMode.BUS, "Ferry Plaza", departure(300, false)))
            },
            { nowMs },
            refreshMillis = 30_000L,
        )
        store.open(37.7955, -122.3937, "Ferry Building")
        runCurrent()
        assertEquals(1, asks)
        advanceTimeBy(30_001)
        runCurrent()
        assertEquals(2, asks)
        store.close()
        advanceTimeBy(30_001)
        runCurrent()
        assertEquals(2, asks)
        assertFalse(store.state.value.open)
        assertEquals(emptyList(), store.state.value.lines)
    }

    @Test fun theStopTapGateExcludesFuelAndEmergency() {
        assertTrue(TransitBoardStore.isTransitKind("bus stop"))
        assertTrue(TransitBoardStore.isTransitKind("Ferry terminal"))
        assertTrue(TransitBoardStore.isTransitKind("railway station"))
        assertTrue(TransitBoardStore.isTransitKind("Haltestelle"))
        assertFalse(TransitBoardStore.isTransitKind("Gas station"))
        assertFalse(TransitBoardStore.isTransitKind("Charging station"))
        assertFalse(TransitBoardStore.isTransitKind("Fire station"))
        assertFalse(TransitBoardStore.isTransitKind("cafe"))
        assertFalse(TransitBoardStore.isTransitKind(null))
        assertFalse(TransitBoardStore.isTransitKind("  "))
    }
}
