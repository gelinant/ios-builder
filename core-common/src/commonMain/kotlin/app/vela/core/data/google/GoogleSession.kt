package app.vela.core.data.google

import app.vela.core.config.CalibrationStore
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import kotlin.concurrent.Volatile

/**
 * Cookie warming for the per-user session.
 *
 * Calibration (2026-06-15) showed that both the search and directions endpoints
 * need NO per-user token, only ordinary cookies. So this is deliberately tiny:
 * a single GET of the maps home page so the shared client's cookie jar picks up
 * Google's consent/NID cookies, after which the data requests behave like one
 * logged-out browser. No API key, no extracted token: that's what keeps Vela
 * on the NewPipe footing.
 *
 * In consent-gated regions (much of the EU) a cookieless GET would redirect to a
 * consent wall; the shared cookie jar (Android: CoreModule's InMemoryCookieJar) pre-seeds
 * SOCS + CONSENT so it does not. Posting the consent form is left for the case
 * where reports show the wall persisting anyway.
 */
class GoogleSession(
    /** The shared client, whose cookie jar keeps what the warm-up is given. */
    private val http: VelaHttp,
    private val calibration: CalibrationStore,
    private val identity: GoogleIdentity,
) {
    @Volatile
    private var warmed = false

    suspend fun ensure() {
        if (warmed) return
        runCatching {
            // A real first navigation to maps.google.com: document dest, no Referer,
            // Sec-Fetch-Site "none". The data RPCs that follow use the XHR headers instead.
            http.call(HttpRequest(calibration.current().sessionWarmUrl, headers = identity.document()))
        }
        warmed = true
    }

    fun invalidate() {
        warmed = false
    }
}
