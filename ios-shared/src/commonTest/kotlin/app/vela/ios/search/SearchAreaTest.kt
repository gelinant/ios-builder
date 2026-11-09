package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

private data class AreaCall(val query: String, val near: LatLng?, val span: Double?)

/** A source whose answers the test scripts per call, and whose pagination is explicit. */
private class AreaSource(private val answer: suspend (Int) -> SearchResult) : MapDataSource {
    val calls = mutableListOf<AreaCall>()
    val moreFrom = mutableListOf<Int>()
    var moreRows: List<Place> = emptyList()

    override suspend fun search(
        query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?,
    ): SearchResult {
        calls += AreaCall(query, near, spanMeters)
        return answer(calls.size)
    }

    override suspend fun searchMore(
        query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, fromPage: Int, pages: Int,
    ): List<Place> {
        moreFrom += fromPage
        return moreRows
    }

    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = error("unused")
}

private fun areaPlace(id: String, name: String, lat: Double, lng: Double, featureId: String? = null) =
    Place(id = id, name = name, location = LatLng(lat, lng), featureId = featureId)

private fun areaRows(count: Int) = (0 until count).map {
    areaPlace("G$it", "Place $it", lat = 37.7749 + it * 0.001, lng = -122.4194 + it * 0.001)
}

/** SRCH-AREA: the pan threshold, the current-view bias, the narrowing and the dedup counters. */
@OptIn(ExperimentalCoroutinesApi::class)
class SearchAreaTest {
    @AfterTest fun googleBackOn() {
        NoGoogle.enabled = false
    }

    @Test fun theOfferWaitsForAPanBeyondAndroidPanStep() = runTest {
        NoGoogle.enabled = false
        val source = AreaSource { SearchResult("coffee", areaRows(25)) }
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onViewport(37.70, -122.50, 37.80, -122.40, 13.0)
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        assertEquals(25, store.state.value.results.size)
        assertFalse(store.state.value.searchAreaAvailable, "the first answer already offered the button")

        // 0.005 degree of latitude is about 556 m, under 22 % of the view (~1 940 m).
        store.onViewport(37.705, -122.50, 37.805, -122.40, 13.0)
        assertFalse(store.state.value.searchAreaAvailable, "a framing-sized move offered the button")

        // 0.03 degree is about 3 300 m: a real pan on Android's 22 % step and beyond.
        store.onViewport(37.73, -122.50, 37.83, -122.40, 13.0)
        assertTrue(store.state.value.searchAreaAvailable)
        assertTrue(SearchArea.moved(
            doubleArrayOf(37.70, -122.50, 37.80, -122.40),
            doubleArrayOf(37.73, -122.50, 37.83, -122.40),
        ))
    }

    @Test fun theAreaSearchBiasesToTheMovedViewAndNarrowsItsAnswer() = runTest {
        NoGoogle.enabled = false
        val source = AreaSource { SearchResult("coffee", listOf(
            areaPlace("inside", "Inside Cafe", lat = 37.78, lng = -122.45),
            areaPlace("outside", "Far Cafe", lat = 37.95, lng = -122.20),
        )) }
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onViewport(37.70, -122.50, 37.80, -122.40, 13.0)
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        assertEquals(listOf("inside", "outside"), store.state.value.results.map { it.id })

        store.onViewport(37.73, -122.50, 37.83, -122.40, 13.0)
        assertTrue(store.state.value.searchAreaAvailable)
        store.searchThisArea()
        runCurrent()

        val call = source.calls.last()
        val center = call.near
        assertEquals(37.78, center!!.lat, 1e-9, "the search did not bias to the panned center")
        assertEquals(-122.45, center.lng, 1e-9)
        assertEquals(11_119.0, call.span!!, 20.0, "the search did not use the panned view's height")
        assertEquals(listOf("inside"), store.state.value.results.map { it.id },
            "the answer was not narrowed to the view")
        assertFalse(store.state.value.searchAreaAvailable, "the offer survived its own search")
        assertFalse(store.state.value.searching)
    }

    @Test fun theAreaRefreshDropsDuplicatesAndKeepsTheSourceOrder() = runTest {
        NoGoogle.enabled = false
        val source = AreaSource { SearchResult("coffee", listOf(
            areaPlace("B", "Blue Bottle", lat = 37.78, lng = -122.45, featureId = "fid:blue"),
            areaPlace("A", "Ars Cafe", lat = 37.781, lng = -122.451),
            areaPlace("A-dup", "Ars Cafe", lat = 37.781, lng = -122.451),
            areaPlace("C", "Croissant Cafe", lat = 37.782, lng = -122.452),
        )) }
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onViewport(37.73, -122.50, 37.83, -122.40, 13.0)
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        store.searchThisArea()
        runCurrent()

        val rows = store.state.value.results
        assertEquals(listOf("B", "A", "C"), rows.map { it.id }, "the list order changed")
        assertEquals(1, store.state.value.droppedDuplicates)
    }

    @Test fun moreResultsAfterAnAreaSearchAppendsWithoutRepeatsOrReordering() = runTest {
        NoGoogle.enabled = false
        val source = AreaSource { SearchResult("coffee", areaRows(25)) }
        source.moreRows = listOf(
            areaPlace("G0", "Place 0", lat = 37.7749, lng = -122.4194),
            areaPlace("M25", "More 25", lat = 37.80, lng = -122.44),
        )
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onViewport(37.70, -122.50, 37.80, -122.40, 13.0)
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        store.onViewport(37.73, -122.50, 37.83, -122.40, 13.0)
        store.searchThisArea()
        runCurrent()

        val before = store.state.value.results.map { it.id }
        assertEquals(25, before.size)
        assertEquals(0, store.state.value.droppedDuplicates)
        assertTrue(store.state.value.moreAvailable)

        store.loadMore()
        runCurrent()
        val after = store.state.value.results.map { it.id }
        assertEquals(before + "M25", after, "More results reordered or repeated a row")
        assertEquals(1, store.state.value.droppedDuplicates, "the repeated page was not counted")
        assertTrue(store.state.value.moreAvailable)
    }

    @Test fun aFailedAreaSearchNeverKeepsTheStaleList() = runTest {
        NoGoogle.enabled = true
        val source = AreaSource { call ->
            if (call == 1) SearchResult("market", listOf(areaPlace("old", "Old Market", 37.78, -122.45)))
            else throw IllegalStateException("Photon is unreachable")
        }
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.onViewport(37.73, -122.50, 37.83, -122.40, 13.0)
        store.setQuery("market")
        store.submit()
        runCurrent()
        assertEquals(listOf("old"), store.state.value.results.map { it.id })

        store.onViewport(37.76, -122.50, 37.86, -122.40, 13.0)
        assertTrue(store.state.value.searchAreaAvailable)
        store.searchThisArea()
        runCurrent()

        assertEquals(2, source.calls.size, "the area search did not ask Photon again")
        assertEquals(37.81, source.calls.last().near!!.lat, 1e-9)
        assertTrue(store.state.value.results.isEmpty(), "the stale list survived a failed NoGoogle search")
        assertIs<SearchError.Failed>(store.state.value.error)
        assertFalse(store.state.value.searchAreaAvailable)
        assertNull(store.state.value.results.firstOrNull())
    }
}
