package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private class OfflineSource(
    private val answer: SearchResult? = null,
    private val failure: Exception? = null,
) : MapDataSource {
    var calls = 0
    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult {
        calls++
        failure?.let { throw it }
        return answer ?: SearchResult(query, emptyList())
    }

    override suspend fun placeDetails(id: String): Place = error("unused")
    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = error("unused")
}

private class LocalSource(
    private val rows: List<Place>,
    private val forced: Boolean = false,
) : OfflineSearch {
    val queries = mutableListOf<String>()
    val biases = mutableListOf<LatLng?>()
    override fun offlineOnly() = forced
    override suspend fun search(query: String, near: LatLng?): List<Place> {
        queries += query
        biases += near
        return rows
    }
}

private fun offlinePlace(id: String, name: String, category: String? = null) = Place(
    id = id, name = name, location = LatLng(43.7391, 7.4280), category = category,
)

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class OfflineSearchStoreTest {
    @Test fun offlineOnlySkipsGoogleAndUsesLocalRows() = runTest {
        val online = OfflineSource(failure = IllegalStateException("must not run"))
        val local = offlinePlace("osm:1", "Casino de Monte Carlo")
        val store = SearchStore(online, backgroundScope).apply {
            offline = LocalSource(listOf(local), forced = true)
            start()
        }
        store.setQuery("casino")
        store.submit()
        runCurrent()
        assertEquals(0, online.calls)
        assertEquals(listOf(local), store.state.value.results)
        assertTrue(store.state.value.usedOffline)
    }

    @Test fun onlineAndOfflineRowsMergeWithoutSamePlaceDuplicates() = runTest {
        val shared = offlinePlace("google:1", "Cafe")
        val localTwin = offlinePlace("osm:1", "cafe")
        val localOnly = offlinePlace("osm:2", "Pharmacie")
        val online = OfflineSource(SearchResult("cafe", listOf(shared)))
        val store = SearchStore(online, backgroundScope).apply {
            offline = LocalSource(listOf(localTwin, localOnly))
            start()
        }
        store.setQuery("cafe")
        store.submit()
        runCurrent()
        assertEquals(listOf("Cafe", "Pharmacie"), store.state.value.results.map { it.name })
        assertFalse(store.state.value.usedOffline)
    }

    @Test fun aNetworkFailureFallsBackToLocalRows() = runTest {
        val online = OfflineSource(failure = IllegalStateException("network"))
        val local = offlinePlace("osm:1", "Cafe")
        val store = SearchStore(online, backgroundScope).apply {
            offline = LocalSource(listOf(local))
            start()
        }
        store.setQuery("cafe")
        store.submit()
        runCurrent()
        assertEquals(listOf(local), store.state.value.results)
        assertTrue(store.state.value.usedOffline)
        assertEquals(null, store.state.value.error)
    }

    @Test fun noGoogleUsesTheTypedHouseNumberFromTheInstalledAddressStore() = runTest {
        val online = OfflineSource(failure = IllegalStateException("must not run"))
        val address = offlinePlace("addr:1451", "1451 West Covell Boulevard", "Address").copy(
            address = "1451 West Covell Boulevard, Davis",
        )
        val business = offlinePlace("osm:9", "Covell Market", "Supermarket")
        val local = LocalSource(listOf(address, business), forced = true)
        val store = SearchStore(online, backgroundScope).apply {
            offline = local
            onViewport(38.55, -121.77, 38.56, -121.75, 15.0)
            start()
        }
        store.setQuery("1451 W Covell Blvd")
        store.submit()
        runCurrent()
        assertEquals(0, online.calls)
        assertEquals(listOf("1451 W Covell Blvd"), local.queries)
        assertEquals(38.555, local.biases.single()!!.lat, 1e-9)
        assertEquals(listOf(address, business), store.state.value.results)
        assertTrue(store.state.value.usedOffline)
    }

    @Test fun aNetworkFailureStillReturnsAnInstalledHouseNumber() = runTest {
        val online = OfflineSource(failure = IllegalStateException("network down"))
        val address = offlinePlace("addr:500", "500 E 8th St", "Address").copy(address = "500 E 8th St, Davis")
        val local = LocalSource(listOf(address))
        val store = SearchStore(online, backgroundScope).apply {
            offline = local
            start()
        }
        store.setQuery("500 E 8th Street")
        store.submit()
        runCurrent()
        assertEquals(listOf("500 E 8th Street"), local.queries)
        assertEquals(listOf(address), store.state.value.results)
        assertTrue(store.state.value.usedOffline)
        assertEquals(null, store.state.value.error)
    }
}
