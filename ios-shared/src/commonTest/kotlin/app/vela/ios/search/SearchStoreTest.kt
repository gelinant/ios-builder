package app.vela.ios.search

import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.MapDataSource
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

private data class Call(val query: String, val near: LatLng?, val span: Double?, val rankFrom: LatLng?)

/** A source whose answers the test hands out one call at a time. */
private class FakeSource : MapDataSource {
    val calls = mutableListOf<Call>()
    val answers = mutableListOf<CompletableDeferred<SearchResult>>()

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult {
        calls += Call(query, near, spanMeters, rankFrom)
        val answer = CompletableDeferred<SearchResult>()
        answers += answer
        return answer.await()
    }

    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = error("unused")
}

private fun place(name: String) = Place(id = name, name = name, location = LatLng(37.78, -122.41))

@OptIn(ExperimentalCoroutinesApi::class)
class SearchStoreTest {
    @Test fun constructionDoesNothingAndSubmitWaitsForStart() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope)
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        assertTrue(source.calls.isEmpty())
        assertFalse(store.state.value.searching)
        store.start()
        store.submit()
        runCurrent()
        assertEquals(1, source.calls.size)
        assertTrue(store.state.value.searching)
    }

    @Test fun startedWithAnImmediateDispatcher() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, kotlinx.coroutines.CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        store.start()
        store.setQuery("coffee")
        store.submit()
        assertEquals(1, source.calls.size)
        source.answers[0].complete(SearchResult("coffee", listOf(place("A"))))
        assertEquals(listOf("A"), store.state.value.results.map { it.name })
    }

    @Test fun anEmptyQueryIsIgnored() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("   ")
        store.submit()
        runCurrent()
        assertTrue(source.calls.isEmpty())
    }

    @Test fun successFillsResultsAndStopsSearching() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onViewport(37.70, -122.50, 37.80, -122.40, 13.0)
        store.setQuery(" coffee ")
        store.submit()
        runCurrent()
        val call = source.calls.single()
        assertEquals("coffee", call.query)
        assertEquals(37.75, call.near!!.lat, 1e-9)
        assertEquals(-122.45, call.near!!.lng, 1e-9)
        // The viewport height: 0.1 degree of latitude.
        assertEquals(11_119.0, call.span!!, 20.0)
        assertNull(call.rankFrom)
        source.answers[0].complete(SearchResult("coffee", listOf(place("A"), place("B"))))
        runCurrent()
        val s = store.state.value
        assertFalse(s.searching)
        assertEquals(listOf("A", "B"), s.results.map { it.name })
        assertNull(s.error)
    }

    @Test fun noResultsIsAnError() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("zzzz")
        store.submit()
        runCurrent()
        source.answers[0].complete(SearchResult("zzzz", emptyList()))
        runCurrent()
        assertEquals(SearchError.NoResults, store.state.value.error)
        assertFalse(store.state.value.searching)
    }

    @Test fun aReplacedSearchNeverWritesItsAnswer() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("tea")
        store.submit()
        runCurrent()
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        assertEquals(2, source.calls.size)
        source.answers[0].completeExceptionally(IllegalStateException("late failure"))
        source.answers[1].complete(SearchResult("coffee", listOf(place("C"))))
        runCurrent()
        assertEquals(listOf("C"), store.state.value.results.map { it.name })
        assertNull(store.state.value.error)
    }

    @Test fun calibrationDriftIsItsOwnError() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        source.answers[0].completeExceptionally(CalibrationNeededException("HTTP 429 from /search"))
        runCurrent()
        val error = assertIs<SearchError.NeedsRecalibration>(store.state.value.error)
        assertTrue(error.where!!.contains("HTTP 429"))
        assertFalse(store.state.value.searching)
    }

    @Test fun otherFailuresCarryTheirReason() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        source.answers[0].completeExceptionally(RuntimeException("offline"))
        runCurrent()
        assertEquals(SearchError.Failed("offline"), store.state.value.error)
    }

    @Test fun noViewportAndNoLocationMeansNoBias() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        assertNull(source.calls.single().near)
        assertNull(source.calls.single().span)
    }

    @Test fun aPointNearZeroZeroIsNotABias() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onViewport(-0.2, -0.2, 0.2, 0.2, 10.0)
        store.onLocation(0.1, 0.3)
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        assertNull(source.calls.single().near)
        assertNull(source.calls.single().rankFrom)
    }

    @Test fun theLocationBiasesWithoutAViewportAndRanksNearby() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onLocation(38.5449, -121.7405)
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        assertEquals(LatLng(38.5449, -121.7405), source.calls[0].near)
        assertEquals(LatLng(38.5449, -121.7405), source.calls[0].rankFrom)
        // Looking at San Francisco from Davis, over 50 km: ranked from the view.
        store.onViewport(37.70, -122.50, 37.80, -122.40, 13.0)
        store.submit()
        runCurrent()
        assertNull(source.calls[1].rankFrom)
    }

    @Test fun clearCancelsAndResets() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        store.clear()
        source.answers[0].complete(SearchResult("coffee", listOf(place("A"))))
        runCurrent()
        assertEquals(SearchState(), store.state.value)
    }

    @Test fun watchSeesEachState() = runTest {
        val source = FakeSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        val seen = mutableListOf<SearchState>()
        val handle = store.watch { seen += it }
        runCurrent()
        store.setQuery("coffee")
        runCurrent()
        store.submit()
        runCurrent()
        source.answers[0].complete(SearchResult("coffee", listOf(place("A"))))
        runCurrent()
        handle.cancel()
        store.clear()
        runCurrent()
        assertEquals(listOf(false, false, true, false), seen.map { it.searching })
        assertEquals("A", seen.last().results.single().name)
    }
}
