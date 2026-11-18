package app.vela.ios.search

import app.vela.core.data.NoGoogle
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * SRCH-FILTER against the real iOS Google source: Open now must reach the SAME
 * `/search?tbm=map&q=...&pb=...` endpoint Android calls, with the query encoded the same way
 * (a space becomes `+`), and no extra parameter of its own.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SearchFilterRequestTest {
    @AfterTest fun googleBackOn() {
        NoGoogle.enabled = false
    }

    @Test fun openNowTravelsInTheQParameterOfTheGoogleSearch() = runTest {
        val http = FakeHttp { r -> ok(SearchFixture.reply(5), r.url) }
        val store = SearchStore(IosSources.over(http), backgroundScope).apply {
            onViewport(37.77, -122.42, 37.79, -122.40, 14.0)
            setOpenNowPhrase("open now")
            start()
            setQuery("coffee")
            setFilters(openNow = true, minRating = 0.0, priceMax = 0, accessibleOnly = false, sort = 0)
            submit()
        }
        store.state.first { !it.searching && it.submissions == 1 }

        val search = http.requests.map { it.url }.filter { "/search?" in it }
        assertEquals(1, search.size, search.joinToString())
        val url = search.single()
        assertTrue(url.startsWith("https://www.google.com/search?tbm=map&authuser=0"), url)
        assertTrue(url.contains("&q=coffee+open+now&pb="), url)
        // The pb skeleton stays the calibrated one; Open now adds no filter token of its own.
        assertTrue(url.contains("%211scoffee+open+now%214m8"), url)
        // And the store kept the user's own words for the box.
        assertEquals("coffee", store.state.value.query)
        // The fixture carries no live status and no weekly hours, so the local Open now pass
        // drops it: the filter never trusts a row it cannot confirm open.
        assertTrue(store.state.value.results.isEmpty())
    }

    @Test fun openNowWithNoGoogleNeverReachesGoogle() = runTest {
        NoGoogle.enabled = true
        val http = FakeHttp { r -> ok("""{"features":[]}""", r.url) }
        val store = SearchStore(IosSources.over(http), backgroundScope).apply {
            onViewport(37.77, -122.42, 37.79, -122.40, 14.0)
            setOpenNowPhrase("open now")
            start()
            setQuery("coffee")
            setFilters(openNow = true, minRating = 4.0, priceMax = 2, accessibleOnly = true, sort = 1)
        }
        // NoGoogle drops every filter Photon cannot honour and does not reword the query.
        assertEquals(SearchFilters(), store.state.value.filters)
        store.submit()
        store.state.first { !it.searching && it.submissions == 1 }
        val urls = http.requests.map { it.url }
        assertTrue(urls.all { it.startsWith("https://photon.komoot.io/api/?") }, urls.joinToString())
        assertTrue(urls.all { "open+now" !in it && "open%20now" !in it }, urls.joinToString())
    }
}
