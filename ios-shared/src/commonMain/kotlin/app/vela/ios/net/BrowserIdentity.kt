package app.vela.ios.net

import app.vela.core.data.google.GoogleIdentity
import app.vela.core.platform.HttpHeader

/**
 * The browser the iOS app's Google requests claim to be (PORTAGE_IOS.md D11): Safari on macOS,
 * the identity the W-1 spike measured from Apple's network stack. Safari sends no client hints,
 * so unlike Android's Chrome set there is no `Sec-CH-UA*`, `Downlink` or `RTT`.
 *
 * Hard-coded until the signed `calibration-ios.json` overlay exists (C-4). [SafariIdentity] hands
 * these lists to the common Google source.
 */
class BrowserIdentity(
    val userAgent: String,
    val acceptDocument: String,
) {
    /** A top-level navigation: the session warm-up. No Referer, as a first navigation has none. */
    fun documentHeaders(acceptLanguage: String): List<HttpHeader> = listOf(
        HttpHeader("User-Agent", userAgent),
        HttpHeader("Accept", acceptDocument),
        HttpHeader("Accept-Language", acceptLanguage),
        HttpHeader("Sec-Fetch-Dest", "document"),
        HttpHeader("Sec-Fetch-Mode", "navigate"),
        HttpHeader("Sec-Fetch-Site", "none"),
    )

    /** A same-origin XHR from the Maps page: the data requests. */
    fun xhrHeaders(acceptLanguage: String, referer: String = MAPS_REFERER): List<HttpHeader> = listOf(
        HttpHeader("User-Agent", userAgent),
        HttpHeader("Accept", "*/*"),
        HttpHeader("Accept-Language", acceptLanguage),
        HttpHeader("Sec-Fetch-Dest", "empty"),
        HttpHeader("Sec-Fetch-Mode", "cors"),
        HttpHeader("Sec-Fetch-Site", "same-origin"),
        HttpHeader("Referer", referer),
    )

    /** An image subresource on a Google host (place photos, Street View tiles) from a page at
     *  [referer]. */
    fun imageHeaders(acceptLanguage: String, referer: String, accept: String = ACCEPT_IMAGE): List<HttpHeader> = listOf(
        HttpHeader("User-Agent", userAgent),
        HttpHeader("Accept", accept),
        HttpHeader("Accept-Language", acceptLanguage),
        HttpHeader("Sec-Fetch-Dest", "image"),
        HttpHeader("Sec-Fetch-Mode", "no-cors"),
        HttpHeader("Sec-Fetch-Site", "cross-site"),
        HttpHeader("Referer", referer),
    )

    companion object {
        /** What Safari 26 asks for an `<img>`. */
        const val ACCEPT_IMAGE = "image/webp,image/avif,image/jxl,image/heic,image/heic-sequence,video/*;q=0.8,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5"

        const val MAPS_REFERER = "https://www.google.com/maps"

        val SAFARI_MAC = BrowserIdentity(
            userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
            acceptDocument = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        )

        /**
         * The `Accept-Language` for a language list, built as Android's `BrowserHeaders.acceptLanguageFor`
         * does: each tag, then its bare language unless the next tag shares it, no duplicates,
         * q-values falling from 0.9 by 0.1 to a floor of 0.1.
         */
        fun acceptLanguageFor(tags: List<String>): String {
            val langs = tags.map { it.trim() }.filter { it.isNotEmpty() }
            if (langs.isEmpty()) return "en-US,en;q=0.9"
            val out = LinkedHashSet<String>()
            for ((i, lang) in langs.withIndex()) {
                out += lang
                val base = lang.substringBefore('-')
                if (base == lang) continue
                if (i < langs.size - 1 && langs[i + 1].substringBefore('-') == base) continue
                out += base
            }
            return out.mapIndexed { i, l -> if (i == 0) l else "$l;q=0.${(10 - i).coerceAtLeast(1)}" }.joinToString(",")
        }
    }
}

/**
 * [GoogleIdentity] for the common `GoogleMapsSource` and `GoogleSession`: [browser]'s lists, with
 * the `Accept-Language` of the device languages read at each request.
 */
class SafariIdentity(
    private val acceptLanguage: () -> String,
    private val browser: BrowserIdentity = BrowserIdentity.SAFARI_MAC,
) : GoogleIdentity {
    override fun document(): List<HttpHeader> = browser.documentHeaders(acceptLanguage())

    override fun xhr(referer: String): List<HttpHeader> = browser.xhrHeaders(acceptLanguage(), referer)

    override fun image(referer: String, accept: String): List<HttpHeader> =
        browser.imageHeaders(acceptLanguage(), referer, accept)

    /** The headers of a place photo in the sheet, loaded as the Maps page would. */
    fun photo(): List<HttpHeader> = image(PHOTO_REFERER, BrowserIdentity.ACCEPT_IMAGE)

    companion object {
        const val PHOTO_REFERER = "https://www.google.com/"
    }
}
