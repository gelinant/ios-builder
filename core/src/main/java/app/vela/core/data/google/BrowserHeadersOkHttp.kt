package app.vela.core.data.google

import app.vela.core.platform.HttpHeader
import okhttp3.Request

/**
 * [BrowserHeaders]'s lists on an OkHttp request, for the Android code that still builds OkHttp
 * requests itself (the image loader's hook, the health probe). Each header is set with `header`,
 * in list order, so one the request already carries is replaced and moves to that place.
 */
fun Request.Builder.headers(list: List<HttpHeader>): Request.Builder = apply {
    list.forEach { header(it.name, it.value) }
}

/** [BrowserHeaders.browserHeaders] on this request. */
fun Request.Builder.browserHeaders(
    ua: String,
    secChUa: String,
    referer: String? = null,
    accept: String = BrowserHeaders.ACCEPT_DOCUMENT,
    fetchDest: String = "document",
    fetchMode: String = "navigate",
    fetchSite: String = "none",
    networkHints: Boolean = referer != null,
): Request.Builder = headers(BrowserHeaders.browserHeaders(ua, secChUa, referer, accept, fetchDest, fetchMode, fetchSite, networkHints))

/** [BrowserHeaders.browserXhrHeaders] on this request. */
fun Request.Builder.browserXhrHeaders(ua: String, secChUa: String, referer: String): Request.Builder =
    headers(BrowserHeaders.browserXhrHeaders(ua, secChUa, referer))
