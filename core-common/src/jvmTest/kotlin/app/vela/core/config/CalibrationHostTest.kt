package app.vela.core.config

import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals

/** [CalibrationStore.urlHost] against `java.net.URI.getHost`, which the allowlist used before. */
class CalibrationHostTest {
    private val allowed = setOf("www.google.com", "google.com")

    private val corpus = listOf(
        "https://www.google.com/search?tbm=map&authuser=0&hl=en",
        "https://www.google.com/maps/preview/directions?authuser=0",
        "https://google.com/s?tbm=map&gs_ri=maps&suggest=p",
        "https://www.google.com",
        "https://www.google.com?x=1",
        "https://www.google.com#frag",
        "https://www.google.com:443/maps",
        "https://www.google.com:/maps",
        "https://www.google.com:44x/maps",
        "https://user@www.google.com/maps",
        "https://user:pw@www.google.com/maps",
        "https://@www.google.com/maps",
        "https://a@b@www.google.com/maps",
        "https://evil.com@www.google.com/maps",
        "https://www.google.com@evil.com/maps",
        "https://www.google.com.evil.com/maps",
        "https://evil.com/www.google.com",
        "https://evil.com?u=https://www.google.com",
        "https://WWW.GOOGLE.COM/maps",
        "HTTPS://www.google.com/maps",
        "http://www.google.com/maps",
        "ftp://www.google.com/maps",
        "www.google.com/maps",
        "//www.google.com/maps",
        "https:/www.google.com/maps",
        "//evil.com/maps",
        "https:///maps",
        "https://",
        "",
        "https://www.google.com/pa th",
        "https://www.google.com/a\nb",
        "https://www.google.com\n/maps",
        " https://www.google.com/maps",
        "https://www.google.com/maps ",
        "https://www.google.com/a%2Fb",
        "https://www.google.com/a%2",
        "https://www.google.com/a%zz",
        "https://www.google.com/a#b#c",
        "https://www.google.com/a|b",
        "https://www.google.com/a{b}",
        "https://www.google.com/a[0]",
        "https://www.google.com/a\"b",
        "https://www.google.com/a\\b",
        "https://www.google.com/a^b",
        "https://www.google.com/a`b",
        "https://www.google.com/caf\u00e9",
        "https://www.google.com/a\u00a0b",
        "https://www.goo_gle.com/maps",
        "https://-www.google.com/maps",
        "https://www-.google.com/maps",
        "https://www..google.com/maps",
        "https://www.google.com./maps",
        "https://www.google.123/maps",
        "https://8.8.8.8/maps",
        "https://[::1]/maps",
        "https://www.g\u00f6ogle.com/maps",
        "https://www.google.com/s?tbm=map&pb=!1m3!2d-121.74!3d38.54!4f13.1",
        "https://www.google.com/maps/rpc/photo/listentityphotos?authuser=0&hl=en&gl=us&pb={PB}",
        "1https://www.google.com/maps",
        "ht tps://www.google.com/maps",
        "h+t.t-p://www.google.com/maps",
    )

    private fun uriHost(s: String): String? = runCatching { URI(s).host }.getOrNull()

    @Test fun `the allowlist decision matches java net URI`() {
        val differ = corpus.filter { (uriHost(it) in allowed) != (CalibrationStore.urlHost(it) in allowed) }
        assertEquals(emptyList(), differ)
    }

    @Test fun `a plain URL gives the same host as java net URI`() {
        val differ = corpus.filter { s -> CalibrationStore.urlHost(s)?.let { it != uriHost(s) } ?: false }
        assertEquals(emptyList(), differ)
    }

    @Test fun `the published endpoints all resolve to google`() {
        val d = Calibration.DEFAULT
        for (s in listOf(d.searchEndpoint, d.directionsEndpoint, d.reviewsEndpoint, d.photosEndpoint, d.sessionWarmUrl, d.suggestEndpoint)) {
            assertEquals(uriHost(s), CalibrationStore.urlHost(s), "host of <$s>")
        }
    }
}
