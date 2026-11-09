package app.vela.ios.search

import app.vela.core.model.LatLng
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class FakeUnifiedSource(
    override val name: String,
    override val deadlineMs: Long = 1_000L,
    private val answer: suspend () -> List<UnifiedHit> = { emptyList() },
) : UnifiedSource {
    var calls = 0
        private set

    override suspend fun search(query: UnifiedQuery): List<UnifiedHit> {
        calls++
        return answer()
    }
}

private fun saved(name: String, lat: Double = 37.78, lng: Double = -122.41, id: String = name) =
    UnifiedHits.saved(
        id = id, title = name, subtitle = "Saved", lat = lat, lng = lng,
        placeId = id, featureId = null, listId = null,
    )

private fun place(name: String, index: Int, lat: Double = 37.78, lng: Double = -122.41) =
    UnifiedHits.place(
        index = index, title = name, subtitle = "Cafe", lat = lat, lng = lng,
        featureId = null, address = false,
    )

@OptIn(ExperimentalCoroutinesApi::class)
class UnifiedSearchTest {
    @Test
    fun exactLocalBeatsFuzzyLocalAndEveryOnlineRow() = runTest {
        val online = FakeUnifiedSource(UnifiedSources.WIKI) { listOf(place("Blue Bottle", 0)) }
        val store = UnifiedSearchStore(backgroundScope, listOf(online))
        store.setLocal(
            listOf(
                saved("Blue Bottle Coffee"),
                saved("Blue Bottle"),
                UnifiedHits.setting("settings-units", "Units", "Appearance", "metric imperial"),
            ),
        )
        store.setQuery("blue bottle")
        assertEquals(listOf("Blue Bottle", "Blue Bottle Coffee"), store.state.value.rows.map { it.title })
        advanceTimeBy(400)
        runCurrent()
        // The local fuzzy row still leads the exact-name online place.
        assertEquals("Blue Bottle", store.state.value.rows.first().title)
        assertEquals(UnifiedKinds.SAVED, store.state.value.rows.first().kind)
    }

    @Test
    fun aSavedPlaceSuppressesTheOnlinePlaceItNames() = runTest {
        val online = FakeUnifiedSource(UnifiedSources.WIKI) {
            listOf(place("Blue Bottle", 0, 37.7801, -122.4101), place("Blue Bottle Roastery", 1))
        }
        val store = UnifiedSearchStore(backgroundScope, listOf(online))
        store.setLocal(listOf(saved("Blue Bottle", 37.78, -122.41, id = "saved-blue")))
        store.setQuery("blue")
        advanceTimeBy(400)
        runCurrent()
        val rows = store.state.value.rows
        assertEquals(1, rows.count { it.title == "Blue Bottle" })
        assertEquals(UnifiedKinds.SAVED, rows.first { it.title == "Blue Bottle" }.kind)
        assertTrue(rows.any { it.title == "Blue Bottle Roastery" }, "the other place was dropped with the duplicate")
    }

    @Test
    fun aSourceThatTimesOutNeverBlocksTheOthers() = runTest {
        val slow = FakeUnifiedSource(UnifiedSources.WIKI, deadlineMs = 5_000) {
            delay(10_000)
            listOf(UnifiedHits.wiki("Late", null, "https://en.wikipedia.org/wiki/Late", "en", null, null))
        }
        val fast = FakeUnifiedSource(UnifiedSources.TRANSIT, deadlineMs = 1_000) {
            listOf(UnifiedHits.stop("s1", "Ferry Building", "Bus · Transit stop", 37.79, -122.39))
        }
        val store = UnifiedSearchStore(backgroundScope, listOf(slow, fast))
        store.setQuery("ferry")
        advanceTimeBy(400)
        runCurrent()
        // The fast answer is already on screen while the slow one still runs.
        assertEquals(1, store.state.value.loading)
        assertEquals("Ferry Building", store.state.value.rows.first().title)
        advanceTimeBy(5_000)
        runCurrent()
        val state = store.state.value
        assertEquals(0, state.loading)
        assertEquals("wiki", state.timedOut)
        assertTrue(state.rows.none { it.title == "Late" })
        assertEquals(1, state.rounds)
    }

    @Test
    fun oneTypingPauseMakesOneRequestPerSource() = runTest {
        val source = FakeUnifiedSource(UnifiedSources.TRANSIT) { emptyList() }
        val store = UnifiedSearchStore(backgroundScope, listOf(source))
        store.setQuery("fer")
        advanceTimeBy(100)
        store.setQuery("ferr")
        advanceTimeBy(100)
        store.setQuery("ferry")
        advanceTimeBy(100)
        runCurrent()
        assertEquals(0, source.calls, "a source ran before the pause")
        advanceTimeBy(250)
        runCurrent()
        assertEquals(1, source.calls)
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(1, source.calls, "the field asked again without a keystroke")
    }

    @Test
    fun aTypedCoordinateIsAnsweredLocallyAndStopsEverySource() = runTest {
        val source = FakeUnifiedSource(UnifiedSources.WIKI) { error("must not be called") }
        val store = UnifiedSearchStore(backgroundScope, listOf(source))
        store.setQuery("37.7749, -122.4194")
        advanceTimeBy(400)
        runCurrent()
        val row = store.state.value.rows.single()
        assertEquals(UnifiedKinds.COORDINATE, row.kind)
        assertEquals(0, source.calls)
        assertEquals(37.7749, row.lat)
        assertEquals(-122.4194, row.lng)
    }

    @Test
    fun emptyStatesNameTheSourceThatHadNothing() = runTest {
        val transit = FakeUnifiedSource(UnifiedSources.TRANSIT) { emptyList() }
        val wiki = FakeUnifiedSource(UnifiedSources.WIKI) { emptyList() }
        val store = UnifiedSearchStore(backgroundScope, listOf(transit, wiki))
        store.setLocal(listOf(saved("Home")))
        store.setQuery("mughal")
        advanceTimeBy(400)
        runCurrent()
        val empty = store.state.value.empty
        assertTrue(UnifiedKinds.SAVED in empty, "no saved empty state: $empty")
        assertTrue(UnifiedKinds.STOP in empty, "no transit empty state: $empty")
        assertTrue(UnifiedKinds.WIKI in empty, "no wiki empty state: $empty")
    }

    @Test
    fun remotePlacesKeepTheirSearchStoreIndex() = runTest {
        val store = UnifiedSearchStore(backgroundScope, emptyList())
        store.setRemote(listOf(place("Coffee", index = 4)))
        store.setQuery("coffee")
        assertEquals(4, store.state.value.rows.single { it.kind == UnifiedKinds.PLACE }.index)
    }

    @Test
    fun coordinateForms() {
        assertNotNull(UnifiedCoordinates.parse("37.7749, -122.4194"))
        assertNotNull(UnifiedCoordinates.parse("37.7749 -122.4194"))
        assertEquals(LatLng(48.8584, 2.2945), UnifiedCoordinates.parse("48.8584° N, 2.2945° E"))
        assertEquals(LatLng(-33.8688, 151.2093), UnifiedCoordinates.parse("geo:-33.8688,151.2093"))
        assertNull(UnifiedCoordinates.parse("37.7749"))
        assertNull(UnifiedCoordinates.parse("coffee"))
        assertNull(UnifiedCoordinates.parse("91, 0"))
    }
}
