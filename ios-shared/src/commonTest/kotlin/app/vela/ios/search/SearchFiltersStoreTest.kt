package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * SRCH-FILTER on the store: Open now re-runs the SAME search once with the localized phrase, every
 * other control only re-thins the answer, and NoGoogle drops the controls Photon cannot honour
 * instead of emptying the list.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SearchFiltersStoreTest {
    @AfterTest fun googleBackOn() {
        NoGoogle.enabled = false
    }

    private class RecordingSource(private val places: List<Place>) : MapDataSource {
        val queries = mutableListOf<String>()
        override suspend fun search(
            query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?,
        ): SearchResult {
            queries += query
            return SearchResult(query, places)
        }

        override suspend fun placeDetails(id: String): Place = error("unused")

        override suspend fun directions(
            origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>,
            avoidTolls: Boolean, avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean,
            departBearingDeg: Double?, budgetMs: Long?,
        ): List<Route> = error("unused")
    }

    private fun place(name: String, rating: Double, price: Int, accessible: Boolean) = Place(
        id = name, name = name, location = LatLng(37.78, -122.41),
        rating = rating, priceLevel = price, wheelchairAccessible = accessible, openNow = true,
        distanceMeters = rating * 100,
    )

    private fun started(source: RecordingSource, scope: CoroutineScope): SearchStore {
        val store = SearchStore(source, scope)
        store.start()
        store.onViewport(37.77, -122.42, 37.79, -122.40, 14.0)
        store.setQuery("coffee")
        store.submit()
        return store
    }

    @Test fun openNowRerunsTheSameQueryOnceAndOffRestoresThePlainOne() = runTest {
        val source = RecordingSource(listOf(place("a", 4.2, 1, true), place("b", 4.8, 3, false)))
        val store = started(source, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        store.setOpenNowPhrase("open now")
        assertEquals(listOf("coffee"), source.queries)

        store.setFilters(openNow = true, minRating = 0.0, priceMax = 0, accessibleOnly = false, sort = 0)
        assertEquals(listOf("coffee", "coffee open now"), source.queries, "one re-run, not a second query")
        assertTrue(store.state.value.filters.openNow)

        store.setFilters(openNow = false, minRating = 0.0, priceMax = 0, accessibleOnly = false, sort = 0)
        assertEquals(listOf("coffee", "coffee open now", "coffee"), source.queries)
    }

    @Test fun ratingPriceAccessibilityAndSortNeverAskTheSourceAgain() = runTest {
        val source = RecordingSource(listOf(place("a", 4.2, 1, true), place("b", 4.8, 3, false)))
        val store = started(source, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        assertEquals(2, store.state.value.results.size)

        store.setFilters(openNow = false, minRating = 4.5, priceMax = 0, accessibleOnly = false, sort = 0)
        assertEquals(listOf("b"), store.state.value.results.map { it.name })
        store.setFilters(openNow = false, minRating = 0.0, priceMax = 1, accessibleOnly = false, sort = 0)
        assertEquals(listOf("a"), store.state.value.results.map { it.name })
        store.setFilters(openNow = false, minRating = 0.0, priceMax = 0, accessibleOnly = true, sort = 0)
        assertEquals(listOf("a"), store.state.value.results.map { it.name })
        store.setFilters(openNow = false, minRating = 0.0, priceMax = 0, accessibleOnly = false, sort = 2)
        assertEquals(listOf("a", "b"), store.state.value.results.map { it.name })
        assertEquals(listOf("coffee"), source.queries, "a local filter must not touch the network")
    }

    @Test fun noGoogleDropsUnsupportedFiltersAndKeepsThePlainQuery() = runTest {
        NoGoogle.enabled = true
        val source = RecordingSource(listOf(place("a", 4.2, 1, true)))
        val store = started(source, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        store.setOpenNowPhrase("open now")
        store.setFilters(openNow = true, minRating = 4.5, priceMax = 1, accessibleOnly = true, sort = 1)

        assertEquals(SearchFilters(), store.state.value.filters)
        assertEquals(listOf("coffee"), source.queries, "NoGoogle must not send the Google-only phrase")
        assertEquals(1, store.state.value.results.size)
        assertTrue(!store.state.value.filterSupport.openNow)
        assertTrue(store.state.value.filterSupport.sortDistance)
    }
}
