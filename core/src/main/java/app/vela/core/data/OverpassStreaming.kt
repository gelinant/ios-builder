package app.vela.core.data

import app.vela.core.util.UrlCodec
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.ResponseBody

/**
 * [OverpassEndpoints.run] for the JVM, blocking, with the body as a stream. `OverpassPois` pulls
 * the largest Overpass replies (an offline area's addresses and streets), which stay off the
 * [app.vela.core.platform.VelaHttp] seam because it reads a body whole into memory.
 */
object OverpassStreaming {
    /** Same order, request and failover as [OverpassEndpoints.run]; [onBody] must consume the body
     *  before it returns. */
    fun <T> run(http: OkHttpClient, query: String, onBody: (ResponseBody) -> T): T? {
        for (ep in OverpassEndpoints.ENDPOINTS) {
            val url = "$ep?data=" + UrlCodec.encode(query)
            val req = Request.Builder().url(url).header("User-Agent", app.vela.core.VelaConfig.VELA_UA).build()
            try {
                http.newCall(req).execute().use { resp ->
                    val body = resp.body
                    if (resp.isSuccessful && body != null) return onBody(body)
                }
            } catch (e: Exception) {
                // network / timeout / parse error on this endpoint - try the next one
            }
        }
        return null
    }
}
