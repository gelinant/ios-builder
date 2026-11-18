package app.vela.ios.search

import app.vela.core.data.NoGoogle
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * SRCH-AREA without Google: the real iOS source (the one `MapSession` builds) answers the area
 * search through Photon with the panned view as its bias, and no Google host is contacted.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NoGoogleAreaSearchTest {
    @AfterTest fun googleBackOn() {
        NoGoogle.enabled = false
    }

    private val photonReply = """
        {"features":[{"geometry":{"coordinates":[-121.76,38.558]},
        "properties":{"name":"Covell Market","housenumber":"1451","street":"West Covell Boulevard",
        "city":"Davis","state":"CA","postcode":"95616","osm_id":1451,
        "osm_key":"shop","osm_value":"supermarket"}}]}
    """.trimIndent()

    @Test fun theAreaSearchAsksPhotonForThePannedView() = runTest {
        NoGoogle.enabled = true
        val http = FakeHttp { r -> ok(photonReply, r.url) }
        val source = IosSources.over(http, FakeLocale("en-US"))
        val store = SearchStore(source, backgroundScope).apply {
            start()
            onViewport(38.5579, -121.7601, 38.5581, -121.7599, 17.0)
        }
        store.setQuery("market")
        store.submit()
        store.state.first { !it.searching && it.submissions == 1 }
        val firstCount = http.requests.size
        assertTrue(firstCount > 0, "the first NoGoogle search made no request")

        // A pan of about 880 m, far beyond 22 % of a z17 view.
        store.onViewport(38.5579, -121.7501, 38.5581, -121.7499, 17.0)
        assertTrue(store.state.value.searchAreaAvailable, "the pan did not offer the area search")
        store.searchThisArea()
        store.state.first { !it.searching && it.submissions == 2 }

        val urls = http.requests.drop(firstCount).map { it.url }
        assertTrue(urls.isNotEmpty(), "the area search made no request")
        assertTrue(urls.all { it.startsWith("https://photon.komoot.io/api/?") }, "a non-Photon request left: $urls")
        assertTrue(urls.none { "google." in it || "googleapis." in it }, "a Google request left: $urls")
        // The ranked query carries the panned center as its soft bias.
        assertTrue(urls.any { "lat=38.558" in it && "lon=-121.75" in it }, urls.joinToString())
        assertNull(store.state.value.error)
        assertEquals(1, store.state.value.results.size, "Photon's answer was lost by the area search")
    }
}
