package app.vela.core.data

import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.util.UrlCodec
import kotlinx.coroutines.CancellationException

/**
 * Shared endpoint list + failover runner for every keyless **Overpass** (OpenStreetMap query API) fetch in
 * Vela: ALPR/Flock cameras ([OverpassAlprCameras]), traffic controls ([OverpassTrafficSignals]) and the
 * offline OSM POI/address index ([OverpassPois]).
 *
 * A single hardcoded endpoint was a real reliability hole. The main instance `overpass-api.de` regularly
 * returns HTTP 504 "dispatcher" errors when it's under load (observed 2026-07-13 - the exact failure behind
 * a "Flock cameras never show" report: the fetch failed and the layer silently stayed empty). [run] tries
 * each endpoint in turn and uses the FIRST that answers 2xx, so one overloaded mirror no longer takes a
 * whole feature down; the caller only sees a failure when EVERY endpoint is unreachable.
 */
object OverpassEndpoints {
    /** Overpass mirrors are community infrastructure and their policies want a contactable client,
     *  so this is the honest identifier, never the scrape's browser UA. Single-sourced from
     *  [app.vela.core.VelaConfig.VELA_UA]: the old local copy said "0.1" long after the app
     *  shipped 0.4, which is exactly the drift a contact string must not have. */
    private val USER_AGENT: String get() = app.vela.core.VelaConfig.VELA_UA

    /** Primary first, then community mirrors. Order is preference; each is tried until one answers 2xx.
     *  All speak the same Overpass QL, so the query string is endpoint-agnostic. */
    val ENDPOINTS = listOf(
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    )

    /**
     * Run [query] against each endpoint in order and hand the FIRST successful (2xx) response body to
     * [onBody], returning its result. A non-2xx status, a network error, a timeout or an exception thrown
     * while parsing one endpoint's body all fall through to the NEXT endpoint. Returns null only when every
     * endpoint failed - callers treat that as "fetch failed" (distinct from a successful-but-empty parse, so
     * a transient outage is never cached as an authoritative "nothing here").
     *
     * [timeoutMillis] is each endpoint's call deadline (0: the client's own). Cancelling the
     * coroutine stops the run.
     */
    suspend fun <T> run(http: VelaHttp, query: String, timeoutMillis: Long = 0, onBody: (ByteArray) -> T): T? {
        for (ep in ENDPOINTS) {
            val url = "$ep?data=" + UrlCodec.encode(query)
            val req = HttpRequest(url, headers = listOf(HttpHeader("User-Agent", USER_AGENT)), timeoutMillis = timeoutMillis)
            try {
                val resp = http.call(req)
                if (resp.isSuccessful) return onBody(resp.body)
                // non-2xx: fall through to the next endpoint
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // network / timeout / parse error on this endpoint - try the next one
            }
        }
        return null
    }
}
