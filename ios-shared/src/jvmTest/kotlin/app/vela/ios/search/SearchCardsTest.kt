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
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private fun cardPlace(
    id: String,
    name: String,
    lat: Double = 37.78,
    lng: Double = -122.41,
    address: String? = null,
    featureId: String? = null,
) = Place(id = id, name = name, location = LatLng(lat, lng), address = address, featureId = featureId)

/** SRCH-CARDS: Android's suggestion order, the card's Google fields, and "More results". */
@OptIn(ExperimentalCoroutinesApi::class)
class SearchCardsTest {
    @Test fun ownPlacesLeadThenNetworkWithoutDuplicates() {
        val recent = cardPlace("recent:1", "Blue Bottle Coffee", lat = 37.776, lng = -122.414, featureId = "fid:blue")
        val saved = cardPlace("saved:2", "Coffee Bar", lat = 37.780, lng = -122.410)
        val other = cardPlace("saved:3", "Zeta Cafe", lat = 37.790, lng = -122.400)
        val networkSameName = cardPlace("google:1", "Blue Bottle Coffee", lat = 37.7761, lng = -122.4141, featureId = "fid:blue")
        val networkNew = cardPlace("google:2", "Coffee Bean & Tea Leaf", lat = 37.785, lng = -122.420)

        val rows = SuggestionPriority.merge(
            local = listOf(recent, saved, other),
            network = listOf(networkSameName, networkNew),
            term = "coffee",
        )

        assertEquals(listOf("recent:1", "saved:2", "google:2"), rows.map { it.id })
        assertEquals(2, SuggestionPriority.select(listOf(recent, saved, other), "coffee").size)
        assertEquals(2, SuggestionPriority.select(listOf(recent, saved, other), "COFFEE").size)
    }

    @Test fun ownPlacesAlsoMatchTheAddress() {
        val home = cardPlace("saved:1", "Home", address = "1451 West Covell Boulevard, Davis")
        assertEquals(listOf("saved:1"), SuggestionPriority.select(listOf(home), "covell").map { it.id })
        assertTrue(SuggestionPriority.select(listOf(home), "davis").isNotEmpty())
        assertTrue(SuggestionPriority.select(listOf(home), "zzz").isEmpty())
    }

    @Test fun networkRowsAreCappedAfterTheOwnRows() {
        val own = (0 until SuggestionPriority.LOCAL_LIMIT + 2).map {
            cardPlace("saved:$it", "Coffee $it")
        }
        val network = (0 until SuggestionPriority.NETWORK_LIMIT + 4).map {
            cardPlace("google:$it", "Other $it")
        }
        val rows = SuggestionPriority.merge(own, network, "coffee")
        assertEquals(SuggestionPriority.LOCAL_LIMIT, rows.count { it.id.startsWith("saved:") })
        assertEquals(SuggestionPriority.NETWORK_LIMIT, rows.count { it.id.startsWith("google:") })
    }

    @Test fun mergedRowsKeepTheGoogleCardFields() {
        val google = Place(
            id = "google:1", name = "Blue Bottle Coffee", location = LatLng(37.776, -122.414),
            category = "Coffee shop", address = "66 Mint St, San Francisco", rating = 4.5,
            reviewCount = 1200, priceText = "$$", openNow = true,
            statusText = "Open ⋅ Closes 6 PM", phone = "+1 510-555-0100",
            photoUrls = listOf("https://lh5.googleusercontent.com/p/blue=w600-h450"),
            featureId = "fid:blue",
        )
        val installed = Place(
            id = "offline:1", name = "Blue Bottle Coffee", location = LatLng(37.7761, -122.4141),
            address = "66 Mint Street",
        )

        val merged = SearchMerge.merge(listOf(google), listOf(installed), "coffee", null, emptyList()).single()

        assertEquals("google:1", merged.id)
        assertEquals(4.5, merged.rating)
        assertEquals(1200, merged.reviewCount)
        assertEquals("$$", merged.priceText)
        assertEquals("Coffee shop", merged.category)
        assertEquals(true, merged.openNow)
        assertEquals("Open ⋅ Closes 6 PM", merged.statusText)
        assertEquals("+1 510-555-0100", merged.phone)
        assertEquals(listOf("https://lh5.googleusercontent.com/p/blue=w600-h450"), merged.photoUrls)
        assertEquals("66 Mint St, San Francisco", merged.address)
        assertFalse(merged.permanentlyClosed)
    }

    @Test fun moreResultsAppendsWithoutDuplicatesAndHidesWhenEmpty() = runTest {
        NoGoogle.enabled = false
        val source = MoreSource()
        val store = SearchStore(source, backgroundScope).apply { start() }
        store.setQuery("coffee")
        store.submit()
        runCurrent()
        assertEquals(25, store.state.value.results.size)
        assertTrue(store.state.value.moreAvailable)
        assertEquals(0, source.moreFrom.size)

        store.loadMore()
        runCurrent()
        assertEquals(listOf(3), source.moreFrom)
        // The second page repeats G0 and adds M1: the duplicate never shows twice.
        assertEquals(26, store.state.value.results.size)
        assertEquals(1, store.state.value.results.count { it.id == "G0" })
        assertTrue(store.state.value.results.any { it.id == "M1" })
        assertTrue(store.state.value.moreAvailable)

        store.loadMore()
        runCurrent()
        assertEquals(listOf(3, 6), source.moreFrom)
        assertFalse(store.state.value.moreAvailable)
        assertFalse(store.state.value.loadingMore)
        assertEquals(26, store.state.value.results.size)
    }
}

private class MoreSource : MapDataSource {
    val moreFrom = mutableListOf<Int>()

    override suspend fun search(
        query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?,
    ): SearchResult = SearchResult(query, (0 until 25).map { cardPlace("G$it", "Place $it") })

    override suspend fun searchMore(
        query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, fromPage: Int, pages: Int,
    ): List<Place> {
        moreFrom += fromPage
        return if (moreFrom.size == 1) {
            listOf(cardPlace("G0", "Place 0"), cardPlace("M1", "More 1"))
        } else {
            emptyList()
        }
    }

    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = error("unused")
}
