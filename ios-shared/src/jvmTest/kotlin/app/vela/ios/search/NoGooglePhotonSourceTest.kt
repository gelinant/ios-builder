package app.vela.ios.search

import app.vela.core.data.NoGoogle
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * I-2c on the JVM: with NoGoogle on, the real iOS Google source (the one `MapSession` builds)
 * answers a search through photon.komoot.io only, and no Google host is ever contacted.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NoGooglePhotonSourceTest {
    @AfterTest fun googleBackOn() {
        NoGoogle.enabled = false
    }

    private val photonReply = """
        {"features":[{"geometry":{"coordinates":[-121.76,38.558]},
        "properties":{"name":"Covell Market","housenumber":"1451","street":"West Covell Boulevard",
        "city":"Davis","state":"CA","postcode":"95616","osm_id":1451,
        "osm_key":"shop","osm_value":"supermarket"}}]}
    """.trimIndent()

    private class Installed(private val rows: List<Place>) : OfflineSearch {
        override fun offlineOnly() = true
        override suspend fun search(query: String, near: LatLng?): List<Place> = rows
    }

    @Test fun noGoogleSearchAsksPhotonOnlyAndMergesInstalledRows() = runTest {
        NoGoogle.enabled = true
        val http = FakeHttp { r -> ok(photonReply, r.url) }
        val source = IosSources.over(http, FakeLocale("en-US"))
        val local = Place(
            id = "osm:9", name = "Covell Center", location = LatLng(38.5581, -121.7601),
            category = "Shopping",
        )
        val store = SearchStore(source, backgroundScope).apply {
            offline = Installed(listOf(local))
            onViewport(38.5579, -121.7601, 38.5581, -121.7599, 19.0)
            start()
        }
        store.setQuery("1451 W Covell Blvd")
        store.submit()
        // The real source answers on the IO dispatcher, so wait for the state instead of draining
        // the test scheduler.
        store.state.first { !it.searching && it.submissions == 1 }

        val urls = http.requests.map { it.url }
        assertTrue(urls.isNotEmpty(), "NoGoogle search made no request at all")
        assertTrue(urls.all { it.startsWith("https://photon.komoot.io/api/?") }, "a non-Photon request left: $urls")
        assertTrue(urls.none { "google." in it || "googleapis." in it }, "a Google request left: $urls")
        // The ranked (soft bias, no bbox) and nearby (hard metro box) variants, like Android.
        assertEquals(2, urls.size, urls.joinToString())
        assertTrue(urls.any { "&bbox=" in it })
        assertTrue(urls.any { "&lat=38.558&lon=-121.75999" in it }, urls.joinToString())

        val results = store.state.value.results
        assertEquals("photon:1451", results.first().id)
        assertEquals("Covell Market", results.first().name)
        assertEquals("Supermarket", results.first().category)
        assertTrue(results.any { it.id == "osm:9" })
        assertFalse(store.state.value.usedOffline)
        assertTrue(store.state.value.error == null)
    }
}
