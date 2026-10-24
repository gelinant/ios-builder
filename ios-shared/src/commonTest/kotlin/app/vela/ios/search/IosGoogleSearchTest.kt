package app.vela.ios.search

import app.vela.core.data.CalibrationNeededException
import app.vela.core.model.LatLng
import app.vela.core.platform.HttpResponse
import app.vela.ios.net.BrowserIdentity
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class IosGoogleSearchTest {
    private val sf = LatLng(37.7749, -122.4194)

    private fun searchUrls(http: FakeHttp) = http.requests.map { it.url }.filter { "/search?" in it }

    @Test fun warmsOnceThenSearchesWithSafariXhrHeaders() = runTest {
        val http = FakeHttp { r -> if ("/search?" in r.url) ok(SearchFixture.reply(5)) else ok("<html></html>") }
        val source = IosGoogleSearch(http, FakeLocale("en-US"), parseDispatcher = StandardTestDispatcher(testScheduler))
        val first = source.search("coffee", sf, 4000.0)
        source.search("coffee", sf, 4000.0)
        assertEquals(5, first.places.size)
        assertEquals("Fixture Coffee 0", first.places[0].name)
        assertEquals(4.0, first.places[0].rating)
        assertEquals("100 Market St, San Francisco, CA 94103", first.places[0].address)
        assertEquals(3, http.requests.size)
        val warm = http.requests[0]
        assertEquals("https://www.google.com/maps?hl=en&gl=us", warm.url)
        assertEquals(BrowserIdentity.SAFARI_MAC.documentHeaders("en-US,en;q=0.9"), warm.headers)
        val search = http.requests[1]
        val h = search.headers.associate { it.name to it.value }
        assertEquals(BrowserIdentity.SAFARI_MAC.userAgent, h["User-Agent"])
        assertEquals("https://www.google.com/maps", h["Referer"])
        assertEquals("same-origin", h["Sec-Fetch-Site"])
        assertEquals("en-US,en;q=0.9", h["Accept-Language"])
        assertTrue(search.headers.none { it.name.startsWith("Sec-CH", ignoreCase = true) })
        assertTrue(search.url.startsWith("https://www.google.com/search?tbm=map&authuser=0&hl=en&gl=us&q=coffee&pb=%211scoffee%214m8"))
    }

    @Test fun aFullFirstPageFetchesTwoMore() = runTest {
        val http = FakeHttp { r ->
            when {
                "/search?" !in r.url -> ok("")
                "%218i40" in r.url -> ok(SearchFixture.reply(7, first = 40))
                "%218i20" in r.url -> ok(SearchFixture.reply(20, first = 20))
                else -> ok(SearchFixture.reply(20))
            }
        }
        val result = IosGoogleSearch(http, FakeLocale("en-US"), parseDispatcher = StandardTestDispatcher(testScheduler)).search("coffee", sf)
        assertEquals(47, result.places.size)
        assertEquals(3, searchUrls(http).size)
    }

    @Test fun aFailingLaterPageKeepsTheFirst() = runTest {
        val http = FakeHttp { r ->
            when {
                "/search?" !in r.url -> ok("")
                "%218i" in r.url -> HttpResponse(500, emptyList(), ByteArray(0), r.url)
                else -> ok(SearchFixture.reply(20))
            }
        }
        val result = IosGoogleSearch(http, FakeLocale("en-US"), parseDispatcher = StandardTestDispatcher(testScheduler)).search("coffee", sf)
        assertEquals(20, result.places.size)
    }

    @Test fun anHttpErrorOnTheFirstPageAsksForRecalibration() = runTest {
        val http = FakeHttp { r -> if ("/search?" in r.url) HttpResponse(429, emptyList(), ByteArray(0), r.url) else ok("") }
        assertFailsWith<CalibrationNeededException> {
            IosGoogleSearch(http, FakeLocale("en-US"), parseDispatcher = StandardTestDispatcher(testScheduler)).search("coffee", sf)
        }
    }

    @Test fun aFailedWarmUpDoesNotStopTheSearch() = runTest {
        val http = FakeHttp { r -> if ("/search?" in r.url) ok(SearchFixture.reply(3)) else error("offline") }
        val result = IosGoogleSearch(http, FakeLocale("en-US"), parseDispatcher = StandardTestDispatcher(testScheduler)).search("coffee", sf)
        assertEquals(3, result.places.size)
    }

    @Test fun regionAndLanguageRewriteTheEndpoint() {
        val http = FakeHttp { ok("") }
        val fr = IosGoogleSearch(http, FakeLocale("fr-FR")).searchUrl("café", sf, null, 0)
        assertTrue(fr.startsWith("https://www.google.com/search?tbm=map&authuser=0&hl=fr&gl=fr&q=caf%C3%A9&pb="), fr)
        val us = IosGoogleSearch(http, FakeLocale("en-US")).searchUrl("coffee", sf, null, 0)
        assertTrue("hl=en&gl=us" in us)
        val tw = IosGoogleSearch(http, FakeLocale("zh-Hant-TW", "zh")).searchUrl("coffee", sf, null, 0)
        assertTrue("hl=zh-TW&gl=tw" in tw, tw)
        val cn = IosGoogleSearch(http, FakeLocale("zh-Hans-CN", "zh")).searchUrl("coffee", sf, null, 0)
        assertTrue("hl=zh-CN&gl=cn" in cn, cn)
    }

    @Test fun regionSubtag() {
        assertEquals("us", IosGoogleSearch.regionOf("en-US"))
        assertEquals("tw", IosGoogleSearch.regionOf("zh-Hant-TW"))
        assertNull(IosGoogleSearch.regionOf("en"))
        assertNull(IosGoogleSearch.regionOf("es-419"))
    }

    @Test fun acceptLanguageFollowsChromesRule() {
        assertEquals("en-US,en;q=0.9", BrowserIdentity.acceptLanguageFor(listOf("en-US")))
        assertEquals("fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7", BrowserIdentity.acceptLanguageFor(listOf("fr-FR", "en-US")))
        assertEquals("en-US,en;q=0.9", BrowserIdentity.acceptLanguageFor(emptyList()))
    }
}
