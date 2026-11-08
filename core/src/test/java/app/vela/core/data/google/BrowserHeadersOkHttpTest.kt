package app.vela.core.data.google

import app.vela.core.VelaConfig
import okhttp3.Request
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/** The OkHttp side of [BrowserHeaders]: what OkHttp itself accepts and how the adapters apply a list. */
class BrowserHeadersOkHttpTest {

    @Test fun `every sanitized value is actually sendable`() {
        // The whole point: a value that survives sanitize must never throw inside OkHttp.
        listOf(VelaConfig.USER_AGENT, VelaConfig.SEC_CH_UA, VelaConfig.VELA_UA, "M".repeat(400))
            .forEach { raw ->
                val ok = BrowserHeaders.sanitize(raw)
                assertNotNull("should sanitize: $raw", ok)
                Request.Builder().url("https://www.google.com/").header("User-Agent", ok!!).build()
            }
    }

    @Test fun `the adapter sets the list in order and replaces a header already there`() {
        val list = BrowserHeaders.browserXhrHeaders(VelaConfig.USER_AGENT, VelaConfig.SEC_CH_UA, MAPS_REFERER)
        val r = Request.Builder().url("https://www.google.com/").header("Accept", "text/html").header("X-Other", "1")
            .headers(list).build()
        assertEquals(listOf("X-Other") + list.map { it.name }, (0 until r.headers.size).map { r.headers.name(it) })
        assertEquals("*/*", r.header("Accept"))
    }
}
