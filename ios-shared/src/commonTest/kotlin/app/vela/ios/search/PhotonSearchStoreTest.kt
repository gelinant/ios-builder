package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.SuggestResult
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * I-2c: with "Use Vela without Google" on, the source still answers online, through Photon
 * (`GoogleMapsSource`'s NoGoogle branch), and a failure degrades to the installed store.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PhotonSearchStoreTest {
    @AfterTest fun googleBackOn() {
        NoGoogle.enabled = false
    }

    /** The source is the only online path; it records the calls and answers [answer] or throws. */
    private class Source(
        private val answer: SearchResult = SearchResult("", emptyList()),
        private val failure: Exception? = null,
    ) : MapDataSource {
        val calls = mutableListOf<String>()

        override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult {
            calls += query
            failure?.let { throw it }
            return answer
        }

        override suspend fun suggest(query: String, near: LatLng?, spanMeters: Double?, lang: String?): SuggestResult {
            calls += "suggest:$query"
            return SuggestResult(emptyList(), emptyList())
        }

        override suspend fun placeDetails(id: String): Place = error("unused")

        override suspend fun directions(
            origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
            avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
        ): List<Route> = error("unused")
    }

    /** OfflineStore under NoGoogle: `offlineOnly` is true even though the network is up. */
    private class Installed(private val rows: List<Place>) : OfflineSearch {
        val queries = mutableListOf<String>()
        override fun offlineOnly() = true
        override suspend fun search(query: String, near: LatLng?): List<Place> {
            queries += query
            return rows
        }
    }

    private fun photonPlace() = Place(
        id = "photon:1451", name = "1451 West Covell Boulevard",
        location = LatLng(38.5580, -121.7600), category = "Address",
        address = "1451 West Covell Boulevard, Davis, CA",
    )

    private fun localPlace() = Place(
        id = "osm:9", name = "Covell Market", location = LatLng(38.5581, -121.7601),
        category = "Supermarket",
    )

    @Test fun noGoogleSearchesOnlineThroughTheSourceAndSkipsTheSecondPhotonLookup() = runTest {
        NoGoogle.enabled = true
        val source = Source(SearchResult("1451 W Covell Blvd", listOf(photonPlace())))
        var photonLookups = 0
        val store = SearchStore(source, backgroundScope).apply {
            offline = Installed(listOf(localPlace()))
            photon = { _, _, _, _ ->
                photonLookups++
                emptyList()
            }
            onViewport(38.5579, -121.7601, 38.5581, -121.7599, 19.0)
            start()
        }
        store.setQuery("1451 W Covell Blvd")
        store.submit()
        runCurrent()
        assertEquals(listOf("1451 W Covell Blvd"), source.calls)
        // The source already asked Photon for the ranked and the nearby variants.
        assertEquals(0, photonLookups)
        assertEquals(listOf("photon:1451", "osm:9"), store.state.value.results.map { it.id })
        assertFalse(store.state.value.usedOffline)
        assertNull(store.state.value.error)
    }

    @Test fun noGoogleOnlineFailureFallsBackToTheInstalledStoreNotToGoogle() = runTest {
        NoGoogle.enabled = true
        val source = Source(failure = IllegalStateException("photon unreachable"))
        val store = SearchStore(source, backgroundScope).apply {
            offline = Installed(listOf(localPlace()))
            start()
        }
        store.setQuery("covell market")
        store.submit()
        runCurrent()
        assertEquals(1, source.calls.size)
        assertEquals(listOf("osm:9"), store.state.value.results.map { it.id })
        assertTrue(store.state.value.usedOffline)
        assertNull(store.state.value.error)
    }

    @Test fun noGoogleAddressSuggestionsStillUsePhotonWithoutSpammingTheSource() = runTest {
        NoGoogle.enabled = true
        val source = Source()
        val store = SearchStore(source, backgroundScope).apply {
            offline = Installed(listOf(localPlace()))
            photon = { _, _, limit, hardBox ->
                assertEquals(4, limit)
                assertEquals(true, hardBox)
                listOf(photonPlace())
            }
            start()
        }
        store.setQuery("1451 W Covell Blvd")
        advanceTimeBy(SearchStore.SUGGEST_DEBOUNCE_MS)
        runCurrent()
        // One source autocomplete attempt, which answers nothing under NoGoogle, and one Photon
        // address lookup per typing pause.
        assertEquals(listOf("suggest:1451 W Covell Blvd"), source.calls)
        assertEquals(listOf("photon:1451"), store.state.value.suggestions.map { it.id })
        assertTrue(store.state.value.querySuggestions.isEmpty())
    }

    @Test fun aPlainOfflineRequestStillSkipsTheSource() = runTest {
        val source = Source(failure = IllegalStateException("must not run"))
        val store = SearchStore(source, backgroundScope).apply {
            offline = Installed(listOf(localPlace()))
            start()
        }
        store.setQuery("covell market")
        store.submit()
        runCurrent()
        assertTrue(source.calls.isEmpty())
        assertEquals(listOf("osm:9"), store.state.value.results.map { it.id })
        assertTrue(store.state.value.usedOffline)
    }
}
