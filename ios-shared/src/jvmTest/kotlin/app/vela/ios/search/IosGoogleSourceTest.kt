package app.vela.ios.search

import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.ClockFormat
import app.vela.core.data.NoGoogle
import app.vela.core.i18n.DelayText
import app.vela.core.model.LatLng
import app.vela.core.platform.HttpResponse
import app.vela.ios.net.BrowserIdentity
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The common Google source as the iOS app builds it: Safari's headers, the flags at launch. */
class IosGoogleSourceTest {
    private val sf = LatLng(37.7749, -122.4194)

    @AfterTest fun resetHolders() {
        ClockFormat.use24h = false
        DelayText.formatter = null
        NoGoogle.enabled = false
    }

    @Test fun warmsOnceThenSearchesWithSafariHeaders() = runTest {
        val http = FakeHttp { r -> if ("/search?" in r.url) ok(SearchFixture.reply(5)) else ok("<html></html>") }
        val source = IosSources.over(http)
        val first = source.search("coffee", sf, 4000.0)
        source.search("coffee", sf, 4000.0)
        assertEquals(5, first.places.size)
        assertEquals("Fixture Coffee 0", first.places[0].name)
        assertEquals(3, http.requests.size)
        val warm = http.requests[0]
        assertEquals("https://www.google.com/maps?hl=en&gl=us", warm.url)
        assertEquals(BrowserIdentity.SAFARI_MAC.documentHeaders("en-US,en;q=0.9"), warm.headers)
        val search = http.requests[1]
        assertEquals(BrowserIdentity.SAFARI_MAC.xhrHeaders("en-US,en;q=0.9", "https://www.google.com/maps/"), search.headers)
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
        val result = IosSources.over(http).search("coffee", sf)
        assertEquals(47, result.places.size)
    }

    @Test fun anHttpErrorOnTheFirstPageAsksForRecalibration() = runTest {
        val http = FakeHttp { r -> if ("/search?" in r.url) HttpResponse(429, emptyList(), ByteArray(0), r.url) else ok("") }
        assertFailsWith<CalibrationNeededException> { IosSources.over(http).search("coffee", sf) }
    }

    @Test fun theLaunchFlagsReachTheHoldersAndTheRegion() = runTest {
        NoGoogle.enabled = true
        val http = FakeHttp { r -> if ("/search?" in r.url) ok(SearchFixture.reply(3)) else ok("") }
        val source = IosSources.over(http, FakeLocale("fr-FR"))
        IosGoogle.applyFlags(source, use24h = true, region = "FR")
        assertFalse(NoGoogle.enabled)
        assertTrue(ClockFormat.use24h)
        assertEquals("5 min late", DelayText.of(5))
        assertEquals("2 min early", DelayText.of(-2))
        source.search("café", sf)
        val url = http.requests.first { "/search?" in it.url }.url
        assertTrue(url.startsWith("https://www.google.com/search?tbm=map&authuser=0&hl=fr&gl=fr&q=caf%C3%A9&pb="), url)
        val lang = http.requests.first { "/search?" in it.url }.headers.first { it.name == "Accept-Language" }.value
        assertEquals("fr-FR,fr;q=0.9", lang)
    }

    @Test fun aRegionThatIsNotTwoLettersKeepsUs() = runTest {
        val http = FakeHttp { r -> if ("/search?" in r.url) ok(SearchFixture.reply(3)) else ok("") }
        val source = IosSources.over(http)
        IosGoogle.applyFlags(source, use24h = false, region = "419")
        source.search("coffee", sf)
        assertTrue("hl=en&gl=us" in http.requests.first { "/search?" in it.url }.url)
    }

    @Test fun acceptLanguageFollowsChromesRule() {
        assertEquals("en-US,en;q=0.9", BrowserIdentity.acceptLanguageFor(listOf("en-US")))
        assertEquals("fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7", BrowserIdentity.acceptLanguageFor(listOf("fr-FR", "en-US")))
        assertEquals("en-US,en;q=0.9", BrowserIdentity.acceptLanguageFor(emptyList()))
    }

    @Test fun photosAskAsAnImageFromTheMapsPage() {
        val h = IosGoogle.identity(FakeLocale("en-US")).photo().associate { it.name to it.value }
        assertEquals("image", h["Sec-Fetch-Dest"])
        assertEquals("https://www.google.com/", h["Referer"])
        assertEquals(BrowserIdentity.SAFARI_MAC.userAgent, h["User-Agent"])
    }
}
