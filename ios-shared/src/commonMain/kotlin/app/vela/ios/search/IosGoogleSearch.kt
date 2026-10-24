package app.vela.ios.search

import app.vela.core.config.Calibration
import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.MapDataSource
import app.vela.core.data.google.GoogleResponse
import app.vela.core.data.google.SearchPb
import app.vela.core.data.google.parse.SearchParser
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.ios.net.BrowserIdentity
import app.vela.ios.net.FormUrlEncoder
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext

/**
 * The iOS Google source until C-2 moves `GoogleMapsDataSource` to common: [search] only, built as
 * Android's `search` and `searchPage` (first page, then pages 2 and 3 side by side when the first
 * is full). Not yet here: the nearby pass, other branches, the JS transforms and the diagnostics
 * log. The other [MapDataSource] calls keep the interface defaults.
 */
class IosGoogleSearch(
    private val http: VelaHttp,
    private val locale: PlatformLocale,
    private val calibration: () -> Calibration = { Calibration.DEFAULT },
    private val identity: BrowserIdentity = BrowserIdentity.SAFARI_MAC,
    private val parseDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : MapDataSource {

    val session = IosGoogleSession(http, calibration, identity, ::acceptLanguage)

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult {
        session.ensure()
        // Results are viewport-driven, so a point is required.
        val viewport = near ?: DEFAULT_VIEWPORT
        val cal = calibration()
        val first = page(query, viewport, spanMeters, rankFrom, 0, cal, lang)
        val pageSize = SearchPb.pageSize(cal.searchPb)
        val more = if (pageSize != null && first.places.size >= pageSize - 2) {
            coroutineScope {
                val p2 = async { laterPage(query, viewport, spanMeters, rankFrom, pageSize, cal, lang) }
                val p3 = async { laterPage(query, viewport, spanMeters, rankFrom, pageSize * 2, cal, lang) }
                p2.await() + p3.await()
            }
        } else {
            emptyList()
        }
        return first.copy(places = (first.places + more).distinctBy(::placeKey))
    }

    override suspend fun placeDetails(id: String): Place =
        throw UnsupportedOperationException("placeDetails is not on iOS yet (C-2)")

    override suspend fun directions(
        origin: LatLng,
        destination: LatLng,
        mode: TravelMode,
        waypoints: List<LatLng>,
        avoidTolls: Boolean,
        avoidHighways: Boolean,
        avoidFerries: Boolean,
        urgent: Boolean,
        departBearingDeg: Double?,
        budgetMs: Long?,
    ): List<Route> = throw UnsupportedOperationException("directions are not on iOS yet (I-4)")

    /** A later page never kills the first: any failure there is an empty page. */
    private suspend fun laterPage(query: String, viewport: LatLng, spanMeters: Double?, rankFrom: LatLng?, offset: Int, cal: Calibration, lang: String?): List<Place> =
        try {
            page(query, viewport, spanMeters, rankFrom, offset, cal, lang).places
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            emptyList()
        }

    private suspend fun page(query: String, viewport: LatLng, spanMeters: Double?, rankFrom: LatLng?, offset: Int, cal: Calibration, lang: String?): SearchResult {
        val url = searchUrl(query, viewport, spanMeters, offset, cal, lang)
        val response = http.call(HttpRequest(url = url, headers = identity.xhrHeaders(acceptLanguage())))
        if (!response.isSuccessful) throw CalibrationNeededException("HTTP ${response.code} from /search")
        // The status keyword table follows the app language, as on Android.
        val statusLang = locale.defaultLanguage().lowercase()
        return withContext(parseDispatcher) {
            SearchParser.parse(query, GoogleResponse.parse(response.bodyText()), rankFrom ?: viewport, cal.paths, statusLang)
        }
    }

    /** The request URL, as Android builds it: endpoint, `q`, `pb`, then the `gl` and `hl` rewrites. */
    fun searchUrl(query: String, viewport: LatLng, spanMeters: Double?, offset: Int, cal: Calibration = calibration(), lang: String? = null): String {
        val pb = SearchPb.build(query, viewport, cal.searchPb, spanMeters, offset)
        return localized("${cal.searchEndpoint}&q=${FormUrlEncoder.encode(query)}&pb=${FormUrlEncoder.encode(pb)}", lang)
    }

    /** `gl=us` to the device region, `hl=en` to the app language when the status parser reads it
     *  (Android's `localized` and `regionalized`). English and US stay byte for byte. */
    internal fun localized(url: String, force: String?): String {
        val tag = locale.defaultTag()
        var out = url
        val region = regionOf(tag)
        if (region != null && region != "us") out = out.replace("gl=us", "gl=$region")
        if (force != null) return out.replace("hl=en", "hl=$force")
        val lang = locale.defaultLanguage().lowercase()
        if (lang == "en" || lang !in SearchParser.STATUS_LANGS) return out
        val hl = if (lang == "zh") {
            val parts = tag.split('-', '_')
            val hant = parts.any { it.equals("Hant", ignoreCase = true) } || parts.any { it.uppercase() in setOf("TW", "HK", "MO") }
            if (hant) "zh-TW" else "zh-CN"
        } else {
            lang
        }
        return out.replace("hl=en", "hl=$hl")
    }

    private fun acceptLanguage(): String = BrowserIdentity.acceptLanguageFor(locale.preferredTags())

    private fun placeKey(p: Place) =
        p.featureId ?: "${p.name.lowercase()}|${(p.location.lat * 2000).toInt()}|${(p.location.lng * 2000).toInt()}"

    companion object {
        /** San Francisco, Android's fallback when the caller has no point. */
        val DEFAULT_VIEWPORT = LatLng(37.7749, -122.4194)

        /** The two-letter region subtag of a BCP 47 [tag], lower case, or null. */
        internal fun regionOf(tag: String): String? =
            tag.split('-', '_').drop(1).firstOrNull { it.length == 2 && it.all { c -> c.isLetter() } }?.lowercase()
                ?.takeIf { it.all { c -> c in 'a'..'z' } }
    }
}
