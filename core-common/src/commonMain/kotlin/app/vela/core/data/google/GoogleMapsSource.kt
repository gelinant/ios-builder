package app.vela.core.data.google

import app.vela.core.VelaConfig
import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.CategoryFilter
import app.vela.core.data.LowDataMode
import app.vela.core.data.LowRamMode
import app.vela.core.data.MapDataSource
import app.vela.core.data.SuggestResult
import app.vela.core.data.google.parse.DirectionsParser
import app.vela.core.data.google.parse.EntityListParser
import app.vela.core.data.google.parse.PhotosParser
import app.vela.core.data.google.parse.ReviewsParser
import app.vela.core.data.google.parse.SearchParser
import app.vela.core.diag.DiagSink
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Review
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import app.vela.core.model.destinationPoint
import app.vela.core.model.distanceTo
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.RequestTags
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.platform.i
import app.vela.core.platform.w
import app.vela.core.util.Fmt
import app.vela.core.util.UrlCodec
import app.vela.core.util.ioDispatcher
import kotlin.concurrent.Volatile
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlin.math.ln
import kotlin.math.log2
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit

/**
 * How prominent a place is on the map ≈ how many people know it. Review count dominates (a Safeway has
 * thousands, the sushi counter inside it dozens), log-compressed so a mega-chain doesn't utterly bury
 * everything, and nudged by rating so among similarly-popular places the better-rated wins.
 */
fun ambientProminence(p: Place): Double =
    ln((p.reviewCount ?: 0) + 1.0) * (0.6 + (p.rating ?: 3.5) / 10.0) +
        (categoryPrior(p.category) - NEUTRAL_PRIOR) * PRIOR_WEIGHT

/**
 * What KIND of place it is, on the same 1.0-4.5 scale the open-places bake uses, so the two places
 * sources rank alike (user 2026-09-18: "hospitals, supermarkets, shit like that should be the big
 * POIs in a plaza"). Google returns no ranking of its own - the ambient pool is the merge of ~13
 * per-category searches, each ordered by its own relevance - so review count was the whole story,
 * and a busy taco window could take the label off the hospital behind it.
 *
 * It is applied as a DIFFERENCE from [NEUTRAL_PRIOR] (the everyday-business tier), not as an
 * addition, so an ordinary restaurant's prominence is unchanged and the zoom x prominence label
 * tiers keep meaning what they meant: anchors rise, unknown-category junk sinks, the middle stays.
 *
 * Google's category text arrives in the app's language, and these keywords are English, so a
 * non-English session simply gets the neutral prior - the ranking it had before this existed.
 * Sharing the multilingual keyword tables CategoryFilter already carries is the upgrade path.
 */
internal fun categoryPrior(category: String?): Double {
    val c = category?.lowercase()?.trim() ?: return 1.6 // no category at all: the fan-out's junk tier
    fun any(vararg k: String) = k.any { it in c }
    return when {
        any("hospital", "medical center", "medical centre", "university", "college", "airport",
            "stadium", "arena", "museum", "zoo", "aquarium", "amusement park", "theme park",
            "shopping mall", "shopping center", "shopping centre", "supermarket", "grocery",
            "department store", "convention cent", "casino", "warehouse club") -> 4.5
        any("hotel", "motel", "resort", "pharmacy", "drugstore", "bank", "credit union",
            "movie theater", "cinema", "gym", "fitness", "library", "church", "mosque",
            "synagogue", "temple", "bowling", "hardware", "car dealer", "furniture",
            "electronics", "sporting goods", "home improvement", "discount store") -> 3.2
        any("restaurant", "cafe", "café", "coffee", "bar", "pub", "bakery", "fast food",
            "ice cream", "brewery", "winery", "gas station", "charging station", "auto repair",
            "car wash", "pet store", "book store", "bookstore", "clothing", "shoe store",
            "jewelry", "florist", "liquor", "tobacco", "toy store", "bicycle", "dentist",
            "veterinar", "optometr", "urgent care", "post office", "atm", "laundr",
            "dry clean", "barber", "salon", "spa", "tattoo") -> 2.2
        else -> 1.0
    }
}

/** The tier an ordinary shop or restaurant sits in: the prior shifts prominence around THIS. */
private const val NEUTRAL_PRIOR = 2.2

/** How hard the kind of place pulls, in prominence points per tier step. 0.9 puts an anchor about
 *  two points over a same-sized neighbor, which is roughly a supermarket's review-count edge over
 *  the sushi counter inside it - enough to settle the label, not enough to beat a real landmark. */
private const val PRIOR_WEIGHT = 0.9

/**
 * Order ambient Google POIs for the browse map. Callers treat "first = wins the label slot" (the ambient
 * layer places a lower symbol-sort-key first and drops overlapping dots), so this decides which POI shows
 * when several collide AND which survive the take-N cap. **Prominence-first**, exact distance only as a
 * tiebreak. This is what a map wants: the recognizable landmarks (a Safeway with 1,273 reviews, an
 * Applebee's with 1,192) lead, and the low-signal junk the category fan-out drags in (a 0-review mobile
 * mechanic, an adult-family-home, a road intersection) sinks to the bottom and is dropped/loses its
 * collision. Distance-bucketing was tried and REVERTED: it floated that near-center junk above the
 * landmarks (device-measured). The anchor-beats-tenant case still holds (Safeway's reviews ≫ its in-store
 * sushi counter's, so it wins their shared point).
 */
/** Referer the keyless data endpoints expect: a real in-page RPC comes from the Maps document. */
const val MAPS_REFERER = "https://www.google.com/maps/"

internal fun rankAmbientPlaces(places: List<Place>): List<Place> =
    places.sortedWith(
        compareByDescending<Place> { ambientProminence(it) }
            .thenBy { it.distanceMeters ?: Double.MAX_VALUE },
    )


/**
 * The real extractor, calibrated against maps.google.com (2026-06-15): every Google request and its
 * parse, on the platform seams.
 *
 * Search is `/search?tbm=map&q=...` plus a pb built by [SearchPb] from the calibrated
 * template, which carries the viewport (center + span) and the page offset.
 * Directions needs a pb (built by [DirectionsPb]) but no session token. Both are the same endpoints
 * google.com/maps calls from a browser, so they work without Play Services: good for GrapheneOS.
 *
 * [directions] here is Google's own reply, retried ([googleDirectionsRetried]). Android's
 * `GoogleMapsDataSource` extends this class with the hybrid router (OSRM, Valhalla, the on-device
 * engine, the street names) and overrides [directions] and [nameRoute].
 */
open class GoogleMapsSource(
    /** The seams; [CoreGraph.http] is the shared client every request but [largeReplyHttp]'s uses. */
    private val graph: CoreGraph,
    /** For a reply that runs to megabytes (a custom map's KML and its viewer page, a shared list).
     *  On Android: derived from the shared client (still counted, still through Cronet) with a
     *  90 s call and a 60 s read timeout. The shared client's 12 s call timeout cuts such a body
     *  off, and the failure is swallowed. The deadline is set rather than removed: the Cronet
     *  transport reads `callTimeout(0)` as 30 s. Each request also carries the 90 s. */
    private val largeReplyHttp: VelaHttp,
    private val session: GoogleSession,
    protected val calibration: CalibrationStore,
    private val jsTransforms: JsTransforms,
    protected val diag: DiagSink,
    /** The browser the requests claim to be: Android's is [ChromeIdentity]. */
    private val identity: GoogleIdentity,
) : MapDataSource {

    /** ISO 3166 alpha-2 of the region the phone is in (cell-network country, falling back to the
     *  locale's), set by the app layer at startup; drives the `gl=` rewrite in [regionalized]. */
    @Volatile var glRegion: String? = null

    /** Caps how many ambient category requests parse AT ONCE. Each response is loaded whole and
     *  built into a JsonElement tree (~tens of MB for a dense area); the ~13-term fan-out fired them
     *  all in parallel, so a fresh launch / fast far pan allocated ~400 MB of transient parse trees
     *  in a burst, filled the 512 MB heap, and stalled every allocation on a blocking GC (measured
     *  on a Pixel 9: 401 MB live, 80-86 ms WaitForGcToComplete storms, 400 ms frames). Bounding the
     *  fan-out to a few at a time caps the peak transient heap (~4x30 MB instead of 13x30 MB) with the
     *  same final pool - the streaming onPartial paint keeps first dots fast. Shared across calls so
     *  a pan mid-load can't double the burst. */
    // Permits fleet-tunable through calibration.json ("ambientFanoutPermits") - CLAUDE.md's own
    // escape hatch ("if a dense area still spikes, lower the permit") without an app release.
    // Read at construction, so a pushed change applies on the next process start.
    /** The nearby pass's window height: a walkable radius, the Google app's own bias. */
    private val NEARBY_SPAN_M = 2500.0

    /** Branches still without an address after the "near me" list, looked up one by one. */
    private val BRANCH_FILL_MAX = 3
    private val BRANCH_SPAN_M = 30_000.0

    private val ambientFanout = kotlinx.coroutines.sync.Semaphore(
        calibration.current().tune("ambientFanoutPermits", 4.0).toInt().coerceIn(1, 13),
    )

    /** One result page: [offset] rows in, over a [viewport]-centered window [spanMeters] tall. A
     *  parse drift on page 0 is thrown (and recorded) so the caller can surface it; on any later
     *  page it yields an empty list, because a later page drifting must never kill page 0. */
    private suspend fun searchPage(query: String, viewport: LatLng, spanMeters: Double?, rankFrom: LatLng?, offset: Int, cal: app.vela.core.config.Calibration, lang: String? = null, onMeta: ((SearchResult) -> Unit)? = null): List<Place> {
        val url = "${cal.searchEndpoint}&q=${query.enc()}&pb=${SearchPb.build(query, viewport, cal.searchPb, spanMeters, offset).enc()}".localized(lang)
        val raw = get(url)
        // A remote transforms.js can fully re-parse a reshaped response (searchOverride);
        // otherwise the compiled parser runs. Either way, an optional transformPlaces
        // hook gets the last word. No hook / any error → pure compiled path.
        return try {
            jsTransforms.searchOverride(raw)
                ?: SearchParser.parse(query, GoogleResponse.parse(raw), rankFrom ?: viewport, cal.paths, graph.locale.defaultLanguage().lowercase())
                    .also { onMeta?.invoke(it) }.places
        } catch (e: CalibrationNeededException) {
            if (offset == 0) {
                // Capture the exact request that drifted so an opted-in user can hand it
                // to a dev (no-op unless diagnostics are on).
                diag.record("drift", "search parse drift: ${e.message}", url)
                throw e
            }
            emptyList()
        }
    }

    private fun placeKey(p: Place) =
        p.featureId ?: "${p.name.lowercase()}|${(p.location.lat * 2000).toInt()}|${(p.location.lng * 2000).toInt()}"

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult = io {
        // Without Google (NoGoogle): the OpenStreetMap geocoder answers, biased around the user.
        // It knows names and addresses, not categories; the downloaded place packs cover those
        // where a region is installed (the view model runs them only when offline, or when this
        // search throws or comes back empty).
        if (app.vela.core.data.NoGoogle.enabled) {
            val bias = rankFrom ?: near
            val lang = graph.locale.defaultLanguage()
            // Photon's own ranking (importance, softly biased to the user) leads, so a city or a
            // landmark across the state is found; the suggest path's hard metro box is appended
            // for the partial-address case. Checked on a device the other way round: the box
            // led with fuzzy address rows two states away and the city itself never showed.
            // The two run side by side (one after the other was most of the wait, issue #647).
            val (ranked, nearby) = coroutineScope {
                // Ranked in English when Photon does not speak the UI language (issue #652): with no
                // language it matched only local names, and "eiffel tower" found a peak in Alberta
                // before the Tour Eiffel, whose English name is the one people type.
                val rankLang = if (lang in app.vela.core.data.PhotonGeocoder.LANGS) lang else "en"
                val r = async(ioDispatcher) { app.vela.core.data.PhotonGeocoder.suggest(http, query, bias, rankLang, limit = 20, hardBox = false) }
                val n = async(ioDispatcher) { app.vela.core.data.PhotonGeocoder.suggest(http, query, bias, lang, limit = 10) }
                r.await() to n.await()
            }
            val places = (ranked + nearby).distinctBy { it.id }
            return@io SearchResult(query, places)
        }
        session.ensure()
        // Results are viewport-driven, so a location is required; callers
        // normally pass the user's location, with a fallback for the rare null.
        val viewport = near ?: DEFAULT_VIEWPORT
        val cal = calibration.current()
        val firstUrl = "${cal.searchEndpoint}&q=${query.enc()}&pb=${SearchPb.build(query, viewport, cal.searchPb, spanMeters).enc()}".localized(lang)
        suspend fun page(offset: Int): List<Place> = searchPage(query, viewport, spanMeters, rankFrom, offset, cal, lang)
        // NEARBY PASS (2026-09-13): Google's keyless ranking is prominence-heavy over the WHOLE
        // window, so at town zoom the outlet next to the user loses its slot to better-known
        // places across the visible area and misses all three pages; the ambient merge below
        // only catches it when the category fan-out happened to hold it. A second request over
        // a tight window around the user (the Google app weights distance the same way) leads
        // the list. Only when the user is INSIDE the search window and that window is wider
        // than the nearby one, so a search over another neighborhood or another city keeps
        // Google's order for where the user is looking.
        var focused = false
        var focusPlace: Place? = null
        var stripped = false
        val nearbyWanted = rankFrom != null &&
            (spanMeters == null || (rankFrom.distanceTo(viewport) <= spanMeters / 2 && spanMeters > NEARBY_SPAN_M * 1.5))
        val (nearby, first) = kotlinx.coroutines.coroutineScope {
            val n = async {
                if (nearbyWanted) runCatching { searchPage(query, rankFrom!!, NEARBY_SPAN_M, rankFrom, 0, cal, lang) }.getOrDefault(emptyList())
                else emptyList()
            }
            val f = async { searchPage(query, viewport, spanMeters, rankFrom, 0, cal, lang) { focused = it.focusedSingle; focusPlace = it.focus; stripped = it.strippedFocus } }
            n.await() to f.await()
        }.let { (n, f) ->
            // OTHER BRANCHES (discussion #656). Automatic only with the setting on; otherwise the
            // result carries [SearchResult.focus] and the app offers them on a tap.
            val focus = focusPlace
            if (!focused || focus == null || f.isEmpty()) { focusPlace = null; return@let n to f }
            if (!app.vela.core.data.OtherLocations.auto) return@let n to f
            focusPlace = null
            n to branchesOf(query, focus, f, viewport, spanMeters, rankFrom, cal, lang, stripped)
        }
        // PAGINATE like the Google app: a page is !7iN results (20 today) and a FULL first page
        // means the viewport holds more. Google's keyless web ranking is prominence-heavy over
        // the whole box, so a modest place sitting right next to the user ranks 21-60 for a
        // category query - one page was exactly why "the restaurant right next to me" never made
        // the list (user 2026-07-18). Pages 2+3 fetch CONCURRENTLY (one extra round trip, not
        // two); either failing quietly leaves page 1 intact. Specific-name queries return
        // partial pages and never paginate, so they cost nothing extra. Page size + offsets are
        // DERIVED from the calibrated template (searchPb is remote-updatable); a recaptured
        // template without a !7i token skips pagination rather than guessing.
        val pageSize = SearchPb.pageSize(cal.searchPb)
        val more = if (pageSize != null && first.size >= pageSize - 2) {
            kotlinx.coroutines.coroutineScope {
                val p2 = async { runCatching { page(pageSize) }.getOrDefault(emptyList()) }
                val p3 = async { runCatching { page(pageSize * 2) }.getOrDefault(emptyList()) }
                p2.await() + p3.await()
            }
        } else emptyList()
        val places = (nearby + first + more).distinctBy(::placeKey)
        // detail = the exact request URL so an opted-in user's export is replayable.
        diag.record("search", "\"$query\" near ${near?.lat ?: "?"},${near?.lng ?: "?"} → ${places.size} results (page1 ${first.size}, nearby ${if (nearbyWanted) nearby.size.toString() else "off"})", firstUrl)
        // open/closed diagnosis: what status + hours did we actually parse for each result? (compare
        // the status string to the hours to see whether Google's string is wrong or we mis-parse.)
        places.take(6).forEach { p ->
            diag.record(
                "placestatus",
                "${p.name}: openNow=${p.openNow} status=\"${p.statusText}\" permClosed=${p.permanentlyClosed} " +
                    "| hours(${p.hours.size}): ${p.hours.joinToString(" · ").take(180)}",
                "",
            )
        }
        SearchResult(query, CategoryFilter.applyIfEnabled(jsTransforms.refineSearch(places)), focus = focusPlace, strippedFocus = stripped)
    }

    /** Google answers a business NAME with one focused branch wherever the map is, and lists only
     *  some of the others, without addresses, in its related block. The same name plus "near me"
     *  comes back as a LIST with full cards (checked in a real browser from Montreal, New York and
     *  a wide view; a one-location business answers with itself). A branch still without an
     *  address is asked for by name at its own spot. */
    private suspend fun branchesOf(query: String, focus: Place, have: List<Place>, viewport: LatLng, spanMeters: Double?, rankFrom: LatLng?, cal: app.vela.core.config.Calibration, lang: String?, stripped: Boolean): List<Place> {
        // Asked over a fixed window around the FOCUSED place, not the view: the list is capped
        // (4 for a 5-branch chain) and which ones it holds changes with the window, and a city-wide
        // one around the business holds its neighbors whatever the map is showing.
        val listed = runCatching { searchPage("$query near me", focus.location, BRANCH_SPAN_M, rankFrom, 0, cal, lang) }.getOrDefault(emptyList())
            .filter { SearchParser.isBranch(query, focus, it) }
        // A new session's first seconds answer with the focused place and none of its related
        // block (seen on the 4a: the same request carries it seconds later). Only then is the
        // plain search asked again, and after the "near me" one so the session is that much older.
        val again = if (!stripped) emptyList()
        else runCatching { searchPage(query, viewport, spanMeters, rankFrom, 0, cal, lang) }.getOrDefault(emptyList())
            .filter { SearchParser.isBranch(query, focus, it) }
        var merged = SearchParser.mergeBranches(have + listed + again)
        val bare = merged.filter { it.address.isNullOrBlank() && SearchParser.isBranch(query, focus, it) }.take(BRANCH_FILL_MAX)
        if (bare.isNotEmpty()) {
            val filled = coroutineScope {
                bare.map { b ->
                    async {
                        b to runCatching { searchOnce(b.name, b.location, lang) }.getOrDefault(emptyList())
                            .filter { it.location.distanceTo(b.location) < 60.0 && SearchParser.isBranch(query, focus, it) }
                            .minByOrNull { it.location.distanceTo(b.location) }
                    }
                }.awaitAll()
            }.toMap()
            merged = merged.map { p -> filled[p] ?: p }
        }
        diag.record("search", "branches of \"$query\": had ${have.size}, near me ${listed.size}, now ${merged.size}, with address ${merged.count { !it.address.isNullOrBlank() }}")
        return merged
    }

    override suspend fun searchBranches(query: String, focus: Place, current: List<Place>, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?, stripped: Boolean): List<Place> = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io current
        session.ensure()
        CategoryFilter.applyIfEnabled(branchesOf(query, focus, current, near ?: DEFAULT_VIEWPORT, spanMeters, rankFrom, calibration.current(), lang, stripped))
    }

    /** The tap resolve's search: page one only. A chain's name fills the page, and [search] then
     *  fetched pages two and three too, a second round trip that could only add branches farther
     *  from the tap than the ones already on page one (measured 2026-09-22 on the 4a: 4.3 s of a
     *  4.7 s tap). Without Google, the OSM geocoder answers as [search] does. */
    override suspend fun searchOnce(query: String, near: LatLng, lang: String?): List<Place> = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io search(query, near, null, null, lang).places
        session.ensure()
        val cal = calibration.current()
        val places = searchPage(query, near, null, null, 0, cal, lang)
        CategoryFilter.applyIfEnabled(jsTransforms.refineSearch(places))
    }

    /**
     * Google's own autocomplete (see [SuggestParser]) for the typed suggestions. Not the
     * calibrated search endpoint: that one ranks a partial address by prominence over the
     * window and answered a bare five-digit house number with a same-looking ZIP code in
     * another state while houses with that number sat a mile away. The bias is the viewport center and span, the same window the
     * search uses; hl/gl follow the app language and the phone's region like every other
     * request. Without Google the OSM geocoder answers as before (the view model's path).
     */
    override suspend fun suggest(query: String, near: LatLng?, spanMeters: Double?, lang: String?): SuggestResult = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io SuggestResult(emptyList(), emptyList())
        session.ensure()
        val at = near ?: DEFAULT_VIEWPORT
        val span = RequestShape.span((spanMeters ?: SUGGEST_SPAN_M).coerceIn(2_000.0, 500_000.0))
        val cal = calibration.current()
        val pb = cal.suggestPb.replace("{SPAN}", span.toString()).replace("{LNG}", at.lng.toString()).replace("{LAT}", at.lat.toString())
            .replace("{W}", BrowserViewport.width.toString()).replace("{H}", BrowserViewport.height.toString())
        val url = "${cal.suggestEndpoint}&pb=${pb.enc()}&q=${query.enc()}&tch=1&ech=${RequestShape.nextEch()}".localized(lang)
        val raw = try { get(url) } catch (e: Exception) {
            graph.log.w("VelaSuggest", "${query.length} chars: ${e::class.simpleName} ${e.message}")
            throw e
        }
        val parsed = SuggestParser.parse(raw, cal.suggestPaths)
        // One line per keystroke pause, like VelaUpdate/VelaWeb: what the autocomplete answered,
        // and the head of the body when it answered nothing (a consent page, a block, a reshape).
        // The typed text itself stays out of the system log.
        graph.log.i("VelaSuggest", "${query.length} chars, span $span → ${parsed.places.size} places, ${parsed.queries.size} queries" +
            if (parsed.places.isEmpty() && parsed.queries.isEmpty()) " body[${raw.length}]=${raw.take(120).replace('\n', ' ')}" else "")
        diag.record("suggest", "\"$query\" near ${at.lat},${at.lng} span $span → ${parsed.places.size} places, ${parsed.queries.size} queries", url)
        SuggestResult(parsed.places, parsed.queries)
    }

    /** Pages [fromPage] onward of the same query, for the results list's "More results" row
     *  (2026-09-13). Same window, same ranking point; the pages fetch concurrently and a
     *  failing one is just missing. Dedupe against what is already shown is the caller's. */
    override suspend fun searchMore(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, fromPage: Int, pages: Int): List<Place> = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io emptyList()
        session.ensure()
        val viewport = near ?: DEFAULT_VIEWPORT
        val cal = calibration.current()
        val pageSize = SearchPb.pageSize(cal.searchPb) ?: return@io emptyList()
        val got = kotlinx.coroutines.coroutineScope {
            (fromPage until fromPage + pages).map { pg ->
                async { runCatching { searchPage(query, viewport, spanMeters, rankFrom, pg * pageSize, cal) }.getOrDefault(emptyList()) }
            }.map { it.await() }
        }.flatten().distinctBy(::placeKey)
        diag.record("search", "\"$query\" pages $fromPage..${fromPage + pages - 1} → ${got.size} more results")
        got
    }

    override suspend fun nearbyPlaces(center: LatLng, spanMeters: Double, onPartial: ((List<Place>) -> Unit)?): List<Place> = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io emptyList()
        session.ensure()
        val cal = calibration.current()
        // The wide default search (!1d≈25229, !4f13.1) returns the ~20 most prominent places over a
        // big area, so a strip mall shows almost none. Tighten the viewport (and match the !4f zoom)
        // + ask for more (!7i40). Calibrated live: span 25229↔zoom 13.1; span ~3.5–4 km returns
        // ~25 places within 700 m vs 1 at the default.
        val zoom = (13.1 + log2(25229.0 / spanMeters)).coerceIn(13.0, 17.5)
        // FAN OUT across category terms + merge: one "places" query is biased to prominent food/
        // shops, so it misses whole tiers (a strip mall's plumber, nail salon, IT shop). A handful
        // of category queries roughly DOUBLES local coverage (live: 22→52 unique within 600 m).
        val allTerms = listOf(
            "places", "restaurants", "coffee", "stores", "shopping", "services", "beauty salon", "fast food",
            // High-traffic everyday categories the food/shop-biased set above under-returns, so the map
            // shows a Google-like MIX (a gas station, a gym, a grocer) rather than mostly restaurants.
            // Low-signal extras are fine: the prominence sort keeps them from displacing real businesses.
            "grocery store", "gas station", "gym", "bar", "pharmacy",
            // Civic/green POIs (schools, parks): these render as edu/park icons (PoiIcons.groupForCategory
            // maps "…school"→edu, "…park"→park) but were never in the fan-out, so at z14+ browse (ambient
            // active → the OSM poi layers are hidden) they showed from NEITHER source. Their few reviews keep
            // their prominence low, so they surface in quiet/residential views without crowding businesses.
            "school", "park",
        )
        // LOW-RAM: the fan-out is the app's single largest allocation burst. Each term buffers a
        // full response String, a stripped copy, and a JsonElement DOM (GoogleResponse.parse), and
        // 15 of those run 4-at-a-time per pan - the documented ~180 MB/12 s churn. Constrained
        // devices fetch an 8-term subset instead (ported from vela-dpad, 2026-07-23).
        //
        // The subset is NOT just the first N. "school" and "park" are retained DELIBERATELY: while
        // the ambient layer is active at z14+ the basemap's OSM poi layers are filter-hidden, so
        // those categories have NO second source - dropping them makes parks and schools vanish
        // from the map entirely (the fork lost every park/school pin on a first 6-term attempt,
        // caught by A/B screenshot). What goes instead are terms whose places still surface via
        // "places"/"stores" or degrade gracefully: shopping, services, beauty salon, fast food,
        // gym, bar, pharmacy. Fewer ambient POIs is a visible trade, and the right one on a phone
        // that otherwise OOMs. Roomier devices are unaffected.
        // Lean fan-out on a constrained heap OR a constrained LINK (issue #235): fewer terms,
        // smaller page - the satellite case wants bytes back, not just heap.
        val terms = if (LowRamMode.enabled || LowDataMode.enabled) {
            listOf("places", "restaurants", "coffee", "stores", "grocery store", "gas station", "school", "park")
        } else {
            allTerms
        }
        suspend fun fetchTerm(term: String): List<Place> = ambientFanout.withPermit {
            runCatching {
                val pb = SearchPb.build(term, center, cal.searchPb)
                    .replaceFirst(Regex("!1d[0-9.]+"), "!1d${spanMeters.toInt()}")
                    .replaceFirst(Regex("!4f[0-9.]+"), "!4f${Fmt.fixed(zoom, 1)}")
                    .replaceFirst(
                        Regex("!7i\\d+"),
                        // Deep pool per term, so zooming in can go down the rank. Halved on low-RAM:
                        // the pool size drives the RESPONSE BODY size, and the body is what gets
                        // buffered and DOM-parsed per term.
                        if (LowRamMode.enabled || LowDataMode.enabled) "!7i30" else "!7i60",
                    )
                val url = "${cal.searchEndpoint}&q=${term.enc()}&pb=${pb.enc()}".localized()
                SearchParser.parse(term, GoogleResponse.parse(get(url, kind = "nearby places")), center, cal.paths, graph.locale.defaultLanguage().lowercase()).places
            }.getOrDefault(emptyList())
        }
        // Dedup by feature id (same place returned under several terms); fall back to name+coords,
        // then rank for the map (locality + prominence, see rankAmbientPlaces).
        fun finish(pool: List<Place>): List<Place> = rankAmbientPlaces(
            CategoryFilter.applyIfEnabled(
                pool.distinctBy {
                    it.featureId ?: "${it.name}@${(it.location.lat * 1e4).toInt()},${(it.location.lng * 1e4).toInt()}"
                },
            ),
        )
        var all = coroutineScope {
            if (onPartial == null) {
                terms.map { term -> async { fetchTerm(term) } }.awaitAll().flatten()
            } else {
                // STREAM the fan-out: paint the accumulated pool as terms land (growth- and
                // time-throttled so the map isn't re-tessellating on every landing) instead of
                // gating the first dots on the SLOWEST of ~13 requests - the tail was most of
                // the perceived wait. The final return below still carries the complete pool.
                val pool = mutableListOf<Place>()
                val mutex = Mutex()
                var landed = 0
                var paintedCount = 0
                var lastPaintNs = 0L
                terms.map { term ->
                    launch {
                        val places = fetchTerm(term)
                        mutex.withLock {
                            pool += places
                            landed++
                            val now = graph.clock.monotonicNanos()
                            // Escalating batch size: the FIRST dots should land fast (10 places is
                            // enough to make the map feel alive), but each partial re-runs symbol
                            // placement for the WHOLE layer, and in a dense downtown 6-8 repaints in
                            // the first seconds were most of the cold-load frame drops (user
                            // 2026-07-14). Once the map is already populated, wait for bigger
                            // batches - the user can't tell 60 dots from 85 mid-stream, but they can
                            // feel the placement passes.
                            // Bigger batches = FEWER whole-layer symbol-collision passes during the
                            // cold load, which is where a weak GPU (4a) stutters (each onPartial
                            // re-places the entire ambient layer). First paint at 25 keeps the map
                            // feeling alive fast; after that wait for +50 so a dense area re-collides
                            // ~2-3 times instead of ~8 (user 2026-07-17). The final return still carries
                            // the complete pool.
                            // Third rung (user 2026-07-17): once 100+ places are painted the map
                            // already reads "full" - later mid-stream repaints are invisible to the
                            // eye but each one re-places every symbol, so demand a bigger batch and
                            // a longer quiet gap before paying for another pass. Dense downtowns go
                            // from ~3-4 passes to ~2-3; sparse areas never reach this rung.
                            val minGrowth = when {
                                paintedCount == 0 -> 25
                                paintedCount >= 100 -> 80
                                else -> 50
                            }
                            val grown = pool.size - paintedCount >= minGrowth
                            val due = now - lastPaintNs > (if (paintedCount >= 100) 800_000_000L else 500_000_000L)
                            if (landed < terms.size && pool.isNotEmpty() && grown && (paintedCount == 0 || due)) {
                                paintedCount = pool.size
                                lastPaintNs = now
                                onPartial(finish(pool.toList()))
                            }
                        }
                    }
                }.joinAll()
                pool
            }
        }
        // SLIM-FLAVOR HEAL (live-bisected 2026-07-14): for the first ~3 s of a fresh session Google
        // serves a stripped per-place block - rating present, review count ABSENT (same query + pb
        // returns the full block seconds later). A cold-start fan-out lands entirely inside that
        // window, so the whole ambient pool parsed with reviewCount=null, which zeroed
        // ambientProminence and silently broke everything keyed on it: prominence ranking, dot
        // sizing, label tiers - all flat. Detect the flavor (rated places but not one count) and
        // refetch ONCE; by then the session is warm and the rich pool overwrites the slim one
        // (and the disk cache stores real counts). Doubles the request burst only on a cold start.
        // Majority (not all-slim): the session can warm MID-burst, leaving a mixed pool.
        val rated = all.count { it.rating != null }
        if (rated >= 3 && all.count { it.rating != null && it.reviewCount == null } > rated / 2) {
            delay(app.vela.core.util.Jitter.around(1200))
            val healed = coroutineScope { terms.map { term -> async { fetchTerm(term) } }.awaitAll().flatten() }
            if (healed.any { it.reviewCount != null }) {
                diag.record("ambient", "slim cold-start pool healed: ${all.size} -> ${healed.size} places with counts")
                // Healed first so distinctBy keeps the rich copy when a term partially failed.
                all = healed + all
            }
        }
        finish(all)
    }

    override suspend fun placeDetails(id: String): Place = io {
        // CALIBRATE: the dedicated place-detail RPC (reviews, hours, popular
        // times) under /maps/preview/place is not yet mapped. Search already
        // returns name/rating/reviews/address/category, so the UI uses the
        // Place from the search result directly until this is calibrated.
        throw CalibrationNeededException("placeDetails RPC not yet mapped")
    }

    override suspend fun reverseGeocode(location: LatLng): Place? = io {
        // OpenStreetMap's Nominatim: keyless, on-ethos (open data), and a stable
        // documented API, so unlike the Google endpoints it needs no recalibration.
        // Best-effort: any failure (network, rate-limit, no match) → null.
        runCatching {
            val url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&zoom=18" +
                "&lat=${location.lat}&lon=${location.lng}"
            val root = Json.parseToJsonElement(getNominatim(url)).jsonObject
            val addr = root["address"]?.jsonObject ?: return@runCatching null
            fun str(k: String): String? = (addr[k] as? JsonPrimitive)?.takeUnless { it is JsonNull }?.content
            val street = listOfNotNull(str("house_number"), str("road")).joinToString(" ").ifBlank { null }
            val city = str("city") ?: str("town") ?: str("village") ?: str("hamlet") ?: str("suburb")
            val regionPost = listOfNotNull(str("state"), str("postcode")).joinToString(" ").ifBlank { null }
            val addressLine = listOfNotNull(street, city, regionPost).joinToString(", ")
                .ifBlank { (root["display_name"] as? JsonPrimitive)?.content }
            Place(
                id = "pin:${location.lat},${location.lng}",
                name = street ?: city ?: "Dropped pin",
                location = location,
                address = addressLine,
            )
        }.getOrNull()
    }

    override suspend fun reviews(featureId: String): List<Review> = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io emptyList()
        // /maps/preview/review/listentitiesreviews: a keyless GET. The feature id
        // "0xHIGH:0xLOW" splits into two unsigned-64 decimals (1y/2y); 2i/3i page,
        // 3e1 sorts by most-relevant. The 1s session token can be any string.
        // (Calibrated live 2026-06-16.)
        val parts = featureId.split(":")
        if (parts.size != 2) return@io emptyList()
        val high = runCatching { parts[0].removePrefix("0x").toULong(16) }.getOrNull() ?: return@io emptyList()
        val low = runCatching { parts[1].removePrefix("0x").toULong(16) }.getOrNull() ?: return@io emptyList()
        val cal = calibration.current()
        val pb = cal.reviewsPb.replace("{HIGH}", high.toString()).replace("{LOW}", low.toString())
        val url = "${cal.reviewsEndpoint}&pb=${pb.enc()}"
        runCatching { ReviewsParser.parse(GoogleResponse.parse(get(url))) }.getOrDefault(emptyList())
    }

    override suspend fun reviewFeed(featureId: String, hl: String?, pageToken: String): app.vela.core.data.google.parse.ReviewFeed? = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io null
        if (!featureId.contains(":")) return@io null
        session.ensure()
        val cal = calibration.current()
        // The token rides inside a JSON string inside the proto: keep it to the base64url alphabet.
        val token = pageToken.filter { it.isLetterOrDigit() || it == '-' || it == '_' || it == '=' }
        val inner = cal.reviewFeedProto.replace("{FID}", featureId).replace("{TOKEN}", token)
        val freq = "[[[\"qv9Egd\",${JsonPrimitive(inner)},null,\"generic\"]]]"
        val url = "https://www.google.com/maps/_/MapsWizUi/data/batchexecute?rpcids=qv9Egd&source-path=%2Fmaps&hl=en&gl=us" +
            "&_reqid=${RequestShape.nextReqId()}&rt=c"
        runCatching {
            val raw = post(url.localized(hl), "f.req=${freq.enc()}&", aged = true)
            ReviewFeedDebug.sink?.let { sink -> runCatching { sink(raw) } }
            app.vela.core.data.google.parse.ReviewFeedParser.parse(raw)
        }
            .onFailure { diag.record("reviews", "feed failed: ${it::class.simpleName} ${it.message}") }
            .getOrNull()
            ?.also { diag.record("reviews", "feed${if (token.isNotEmpty()) " page" else ""}: ${it.reviews.size} review(s)${if (it.end) ", end of list" else ""}${if (it.nextToken != null) ", more to come" else ""}") }
    }

    override suspend fun placeDetails(place: app.vela.core.model.Place): app.vela.core.model.PlaceDetails? = io {
        if (app.vela.core.data.NoGoogle.enabled || place.name.isBlank()) return@io null
        session.ensure()
        val cal = calibration.current()
        // Same query the WebView details fetch builds (WebPopularTimesFetcher.specificQuery): name +
        // comma-less address, so the reply is the single focused result that carries [84].
        val addr = place.address?.replace(',', ' ')?.replace(Regex("\\s+"), " ")?.trim()
        val query = if (addr.isNullOrBlank()) place.name else "${place.name} $addr"
        val url = "${cal.searchEndpoint}&q=${query.enc()}&pb=${SearchPb.build(query, place.location, cal.searchPb).enc()}".localized()
        runCatching { app.vela.core.data.google.parse.PopularTimesParser.parse(get(url, aged = true, kind = "place details"), place.featureId, cal.paths, graph.locale.defaultLanguage().lowercase()) }.getOrNull()
    }

    override suspend fun placePhotoPage(featureId: String, pageToken: String): app.vela.core.data.google.parse.PhotoPage? = io {
        if (app.vela.core.data.NoGoogle.enabled || !featureId.contains(":")) return@io null
        session.ensure()
        val cal = calibration.current()
        var inner = cal.photosProto.replace("{FID}", featureId).replace("{COUNT}", PHOTO_COUNT.toString())
            .replace("[1200,1000]", "[${BrowserViewport.width},${BrowserViewport.height}]")
        if (pageToken.isNotEmpty()) {
            // The cursor goes at [4][2][2], beside the page size (found by trying each slot against a
            // live reply, 2026-09-23). A template of another shape gets no paging rather than a
            // malformed request.
            inner = runCatching {
                val root = kotlinx.serialization.json.Json.parseToJsonElement(inner).jsonArray
                val paging = root[4].jsonArray[2].jsonArray
                val newPaging = kotlinx.serialization.json.JsonArray(paging.toMutableList().also { it[2] = JsonPrimitive(pageToken) })
                val new4 = kotlinx.serialization.json.JsonArray(root[4].jsonArray.toMutableList().also { it[2] = newPaging })
                kotlinx.serialization.json.JsonArray(root.toMutableList().also { it[4] = new4 }).toString()
            }.getOrNull() ?: return@io null
        }
        val freq = "[[[\"hspqX\",${JsonPrimitive(inner)},null,\"generic\"]]]"
        runCatching { app.vela.core.data.google.parse.PhotosParser.parsePage(post(RequestShape.batchUrl(cal.photosEndpoint).localized(), "f.req=${freq.enc()}&", aged = true)) }
            .onFailure { diag.record("photos", "gallery page failed: ${it::class.simpleName}") }
            .getOrNull()
    }

    override suspend fun placePhotos(featureId: String): List<app.vela.core.model.Photo> = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io emptyList()
        // batchexecute `hspqX` (/MapsPhotoService.ListEntityPhotos): a keyless POST
        // (no `at` token, just the warmed session cookies). The feature id goes in
        // the proto verbatim ([2][0]); the response carries the full gallery, URL at
        // each entry's [6][0]. (Calibrated live 2026-06-17.) Best-effort: any failure
        // returns empty so the caller keeps the search-preview photos.
        if (!featureId.contains(":")) return@io emptyList()
        session.ensure()
        val cal = calibration.current()
        val inner = cal.photosProto.replace("{FID}", featureId).replace("{COUNT}", PHOTO_COUNT.toString())
            .replace("[1200,1000]", "[${BrowserViewport.width},${BrowserViewport.height}]") // this install's window, not one shared size
        // JsonPrimitive(...).toString() = the proto as a properly-escaped JSON string literal.
        val freq = "[[[\"hspqX\",${JsonPrimitive(inner)},null,\"generic\"]]]"
        runCatching { PhotosParser.parse(post(RequestShape.batchUrl(cal.photosEndpoint).localized(), "f.req=${freq.enc()}&", aged = true)) }.getOrDefault(emptyList())
    }

    override suspend fun streetView(location: LatLng, preferStreet: String?): app.vela.core.model.StreetViewPano? = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io null
        // Keyless nearest-pano lookup - the JS Maps API's own GeoPhotoService.SingleImageSearch,
        // authorized by referer (the get() helper already sends it). The parser returns null with no
        // imagery near the point.
        val cal = calibration.current()
        val nearest = streetViewNearest(cal.streetViewMetaUrl, location.lat, location.lng) ?: return@io null

        // Address-street preference (Google-like). Google's address geocode can sit SET-BACK from the
        // street - a mid-block building has the frontage on the avenue and a service alley behind, and
        // the geocode lands nearer the alley. The alley pano is then not just the nearest, its whole
        // connectivity graph is the back cluster, so the real frontage pano is unreachable by walking.
        // When the nearest pano isn't on the address's own street, PROBE toward the street: the nearest
        // pano's heading is the (parallel) street axis, so the frontage sits perpendicular to it. Query
        // a few points out along both perpendiculars and adopt the nearest pano that IS on the address's
        // street. No-regression: no street given / already matches / nothing labeled found → keep the
        // nearest pano, and the probes only fire in the mismatch case.
        if (preferStreet.isNullOrBlank() ||
            StreetViewParser.streetOf(preferStreet) == null ||
            StreetViewParser.streetMatches(nearest.addressLabel, preferStreet)
        ) {
            return@io nearest
        }
        val perpA = (nearest.headingDeg + 90.0) % 360.0
        val perpB = (nearest.headingDeg + 270.0) % 360.0
        val probes = STREET_PROBE_RADII_M.flatMap {
            listOf(location.destinationPoint(it, perpA), location.destinationPoint(it, perpB))
        }
        val match = coroutineScope {
            probes.map { pt -> async { streetViewNearest(cal.streetViewMetaUrl, pt.lat, pt.lng) } }.awaitAll()
        }.filterNotNull()
            .filter { StreetViewParser.streetMatches(it.addressLabel, preferStreet) }
            .distinctBy { it.panoId }
            .minByOrNull { location.distanceTo(LatLng(it.lat, it.lng)) }
        match ?: nearest
    }

    /** The nearest pano to a point. [metaUrl] is the old GET lookup, which Google switched off on
     *  2026-10-05 (it answers "decommissioned"); the POST its own web library makes now is tried
     *  first and the old one only if that fails, in case a region still serves it. */
    private val STREETVIEW_RADII_M = listOf(50, 200)

    private suspend fun streetViewNearest(metaUrl: String, lat: Double, lng: Double): app.vela.core.model.StreetViewPano? {
        val cal = calibration.current()
        // 50 m first (the pano on the place's own frontage), then wider: a store set back behind its
        // lot, or a point whose only close image is a user's photo sphere, has Google's imagery
        // within a couple of hundred meters.
        for (radius in STREETVIEW_RADII_M) {
            val body = cal.streetViewSearchBody
                .replace("{LAT}", Fmt.fixed(lat, 7))
                .replace("{LNG}", Fmt.fixed(lng, 7))
                .replace("{RADIUS}", radius.toString())
            runCatching {
                val resp = http.call(
                    HttpRequest(
                        url = app.vela.core.config.Calibration.STREETVIEW_SEARCH_URL,
                        method = "POST",
                        headers = identity.xhr(MAPS_REFERER) + HttpHeader("x-user-agent", "grpc-web-javascript/0.1"),
                        body = body.encodeToByteArray(),
                        // The charset is the one OkHttp added to a String body before the move.
                        contentType = "application/json+protobuf; charset=utf-8",
                    ),
                )
                if (resp.isSuccessful) StreetViewParser.parse(resp.bodyText(), lat, lng) else null
            }.getOrNull()?.let { return it }
        }
        val url = metaUrl
            .replace("callback=cb", "callback=${RequestShape.callbackName()}")
            .replace("{LAT}", Fmt.fixed(lat, 7))
            .replace("{LNG}", Fmt.fixed(lng, 7))
        return runCatching { StreetViewParser.parse(get(url), lat, lng) }.getOrNull()
    }

    override suspend fun streetViewByPano(panoId: String): app.vela.core.model.StreetViewPano? = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io null
        // Epoch-exact pano fetch (walking): photometa/v1 by id, keyless. Same parser - it handles
        // the )]}' guard and the extra nesting. Lat/lng fall back to the response's own position.
        val cal = calibration.current()
        val url = cal.streetViewPanoUrl.replace("{PANOID}", panoId)
        runCatching { StreetViewParser.parse(get(url), 0.0, 0.0) }.getOrNull()?.takeIf { it.lat != 0.0 || it.lng != 0.0 }
    }

    override suspend fun streetViewTile(panoId: String, x: Int, y: Int, zoom: Int): ByteArray? = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io null
        // The consumer equirect tile endpoint (what maps.google.com renders) - keyless, JPEG,
        // needs only the Google referer. Fixed template, no calibration: the panoid + x/y/zoom
        // fully address a tile in the standard SV pyramid.
        val url = "https://streetviewpixels-pa.googleapis.com/v1/tile" +
            "?cb_client=maps_sv.tactile&panoid=$panoId&x=$x&y=$y&zoom=$zoom&nbt=1&fover=2"
        runCatching { getBytes(url) }.getOrNull()
    }


    /** Google's routes alone, with their traffic, from [googleDirectionsRetried]. */
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
    ): List<Route> = io {
        googleDirectionsRetried(origin, destination, mode, avoidTolls = avoidTolls, avoidHighways = avoidHighways, avoidFerries = avoidFerries, waypoints = waypoints)
    }

    /** [googleDirections] with the same transient-blip retry the OSRM path has (routeOsrm goes
     *  3x with backoff; Google got ONE shot). The keyless endpoint intermittently hands back a
     *  degraded or empty reply, worst right after a burst of requests, e.g. ending a route and
     *  restarting it, and a single miss used to cost the whole fetch its traffic ratio, its
     *  jam-avoiding snap AND Google's alternates: the picker then led with free-flow OSRM routes
     *  whose white, trafficless ETAs read minutes faster than anything traffic-aware and varied
     *  drastically between restarts (user real-drive report 2026-07-14). Two short backoff
     *  retries recover the routine blips; a genuinely unreachable Google still degrades to
     *  free-flow exactly as before, just honestly rarer. */
    protected suspend fun googleDirectionsRetried(origin: LatLng, destination: LatLng, mode: TravelMode, tries: Int = 3, avoidTolls: Boolean = false, avoidHighways: Boolean = false, avoidFerries: Boolean = false, waypoints: List<LatLng> = emptyList()): List<Route> {
        var routes: List<Route> = emptyList()
        if (!app.vela.core.data.RoutingPrefs.googleTraffic) return routes
        for (attempt in 0 until tries) {
            if (attempt > 0) kotlinx.coroutines.delay(app.vela.core.util.Jitter.around(300L * attempt, 0.5))
            routes = runCatching { googleDirections(origin, destination, mode, avoidTolls, avoidHighways, avoidFerries, waypoints) }.getOrNull().orEmpty()
            if (routes.isNotEmpty()) return routes
        }
        diag.record("directions", "google directions empty after $tries attempt(s) \u2014 trafficless fetch")
        return routes
    }

    /** Google's keyless directions: now the FALLBACK router (OSRM unreachable) and the
     *  live-traffic source (ETA / duration-in-traffic / congestion spans). Its step list is
     *  abbreviated for long routes, which is exactly why OSRM is primary. */
    protected suspend fun googleDirections(origin: LatLng, destination: LatLng, mode: TravelMode, avoidTolls: Boolean = false, avoidHighways: Boolean = false, avoidFerries: Boolean = false, waypoints: List<LatLng> = emptyList(), walkCompare: Boolean = false): List<Route> {
        // Without Google the open router's answer stands alone: no traffic, no Google alternates,
        // no abbreviated fallback. Every caller already handles an empty reply as "Google did not
        // answer", which is exactly the state this is.
        if (app.vela.core.data.NoGoogle.enabled || !app.vela.core.data.RoutingPrefs.googleTraffic) return emptyList()
        // Walking is the open router's (issue #478): Google adds no traffic on foot, its keyless
        // walking steps are abbreviated, and snapping a foot route through points on its line forces
        // crossings and double-backs (measured +20-110% on Davis, Sacramento and Dhaka walks). Only
        // the walking branch of directions() asks, to see whether Google's walk is much shorter.
        if (mode == TravelMode.WALK && !walkCompare) return emptyList()
        session.ensure()
        val cal = calibration.current()
        val pb = DirectionsPb.build(origin, destination, mode, cal.directionsPb, avoidTolls, avoidHighways, avoidFerries, waypoints)
        val url = "${cal.directionsEndpoint}&pb=${pb.enc()}"
        val routes = try {
            DirectionsParser.parse(GoogleResponse.parse(get(url)), cal.directionsPaths)
        } catch (e: CalibrationNeededException) {
            diag.record("drift", "directions parse drift: ${e.message}", url)
            throw e
        }
        return if (routes.all { it.polyline.size > 2 }) routes
        else withShortLinesDrawn(routes, origin, destination, mode)
    }

    /** [routes] where a route Google sent with a line of two points or fewer has its line drawn
     *  from elsewhere. Android asks the open router for the trip's geometry (`RouteGeometry`);
     *  here they are left as they came. */
    protected open suspend fun withShortLinesDrawn(routes: List<Route>, origin: LatLng, destination: LatLng, mode: TravelMode): List<Route> = routes

    /** Google Maps shared-list import (issue #1), fully keyless. The share link resolves
     *  logged-out to the list page, whose HTML embeds a READY-MADE prefetch URL for the
     *  `/maps/preview/entitylist/getlist` RPC (list id + page session token included):
     *  lift it verbatim, call it, parse. No pb construction, so a Google-side pb change
     *  can't break the URL builder (only the parser paths, which are documented in
     *  [EntityListParser]). Calibrated live 2026-07-08. */
    override suspend fun importList(shareUrl: String): app.vela.core.model.ImportedList? = io {
        // The link resolves on Google's own servers, so "Use Vela without Google" refuses it.
        if (app.vela.core.data.NoGoogle.enabled) return@io null
        runCatching {
            session.ensure()
            // The endpoint answers from the list id alone, with no token from the page (971 of
            // 971, 2026-10-12). The share page used to carry the request as a link; since
            // 2026-10 the shortener lands on a page that holds only the id, so the request is
            // built here, and the page is read only for a link whose form carries no id.
            val id = app.vela.core.data.ShortLinks.listId(shareUrl)
            val href = if (id != null) {
                "/maps/preview/entitylist/getlist?authuser=0&hl=en&gl=us&pb=" +
                    "!1m4!1s${id.enc()}!2e1!3m1!1e1!2e2!3e2!4i$LIST_PAGE_SIZE!28e2!16b1"
            } else {
                val html = get(shareUrl.trim(), kind = "shared list")
                Regex("""(/maps/preview/entitylist/getlist\?[^"'\s]+)""")
                    .find(html)?.groupValues?.get(1)
                    ?.replace("&amp;", "&")
                    // The page asks for the first 500 (`!4i500` in the pb); the endpoint answers a
                    // bigger count as asked (issue #755).
                    ?.replace("%214i500", "%214i$LIST_PAGE_SIZE")?.replace("!4i500", "!4i$LIST_PAGE_SIZE")
                    ?: return@runCatching null
            }
            EntityListParser.parse(get("https://www.google.com$href", kind = "shared list", client = largeReplyHttp, timeoutMillis = LARGE_REPLY_TIMEOUT_MS))
        }.getOrNull()
    }

    /** A My Maps custom map (issue #669): Google serves any map shared by link as KML at a fixed
     *  URL, with no key and no session (checked from a plain client, 2026-10-04). */
    override suspend fun importMyMap(mid: String): app.vela.core.model.ImportedList? = io {
        if (app.vela.core.data.NoGoogle.enabled) return@io null
        runCatching {
            val kml = get("https://www.google.com/maps/d/kml?mid=${mid.enc()}&forcekml=1", kind = "my map", client = largeReplyHttp, timeoutMillis = LARGE_REPLY_TIMEOUT_MS)
            // The viewer page names the map's marker icons; without it the pins keep their colors.
            val viewer = if (kml.contains("#icon-")) runCatching { get("https://www.google.com/maps/d/viewer?mid=${mid.enc()}", kind = "my map", client = largeReplyHttp, timeoutMillis = LARGE_REPLY_TIMEOUT_MS) }.getOrNull() else null
            app.vela.core.data.MyMapKml.parse(kml, mid, viewer)
        }.getOrNull()
    }

    // --- plumbing -----------------------------------------------------------

    /** The shared client: every Google request is counted and, on Android, goes through Cronet. */
    private val http: VelaHttp get() = graph.http

    /** [aged]: a per-place request (details, photos, the review feed) that rides the WebView's aged
     *  Google session when calibration `agedSession` is on (default 1), see `AgedSession`. */
    private fun tags(aged: Boolean, kind: String? = null): RequestTags = RequestTags(
        usageKind = kind,
        agedSession = aged && calibration.current().tune("agedSession", 1.0) >= 0.5,
    )

    private suspend fun get(url: String, aged: Boolean = false, kind: String? = null, client: VelaHttp = http, timeoutMillis: Long = 0): String {
        val resp = client.call(HttpRequest(url, headers = identity.xhr(MAPS_REFERER), tags = tags(aged, kind), timeoutMillis = timeoutMillis))
        if (!resp.isSuccessful) {
            throw CalibrationNeededException("HTTP ${resp.code} from ${encodedPath(url)}")
        }
        return resp.bodyText()
    }

    private suspend fun post(url: String, body: String, aged: Boolean = false): String {
        val cal = calibration.current()
        val headers = identity.xhr(MAPS_REFERER) +
            HttpHeader("X-Same-Domain", "1") + // batchexecute expects this from a same-origin caller
            (if (cal.rpcContext.isNotBlank()) listOf(HttpHeader("x-maps-diversion-context-bin", cal.rpcContext)) else emptyList()) // the gate; see Calibration.rpcContext
        val resp = http.call(
            HttpRequest(
                url = url,
                method = "POST",
                headers = headers,
                body = body.encodeToByteArray(),
                contentType = "application/x-www-form-urlencoded;charset=UTF-8",
                tags = tags(aged),
            ),
        )
        if (!resp.isSuccessful) {
            throw CalibrationNeededException("HTTP ${resp.code} from ${encodedPath(url)}")
        }
        return resp.bodyText()
    }

    /** GET raw bytes (Street View tiles) with the Google referer the tile host requires. An
     *  image subresource, not a navigation, so the Sec-Fetch triple says so. */
    private suspend fun getBytes(url: String): ByteArray? {
        val resp = http.call(HttpRequest(url, headers = identity.image(referer = "https://www.google.com/", accept = "image/avif,image/webp,image/apng,*/*;q=0.8")))
        return if (resp.isSuccessful) resp.body else null
    }

    /** Nominatim is a COMMUNITY service: it gets the honest, contactable identifier its usage
     *  policy asks for, never the browser UA. Was a hardcoded "VelaMaps/0.1" that drifted from
     *  the app's real version; [VelaConfig.VELA_UA] is now the single source. */
    private suspend fun getNominatim(url: String): String =
        http.call(
            HttpRequest(url, headers = listOf(HttpHeader("User-Agent", VelaConfig.VELA_UA), HttpHeader("Accept-Language", "en"))),
        ).bodyText()

    /** The path of [url] as OkHttp's `encodedPath` gives it, for an error message. */
    private fun encodedPath(url: String): String {
        val rest = url.substringAfter("://")
        val slash = rest.indexOf('/')
        return if (slash < 0) "/" else rest.substring(slash).substringBefore('?').substringBefore('#')
    }

    protected suspend fun <T> io(block: suspend () -> T): T = withContext(ioDispatcher) { block() }

    private fun String.enc(): String = UrlCodec.encode(this)

    /** Rewrite the endpoint's `hl=en` to the app/system language so Google returns categories, hours
     *  and open/closed status IN THE USER'S LANGUAGE (Google-Maps-style). The open/closed BOOLEAN is
     *  parsed from that localized status text against the same language's keyword table
     *  (every `SearchParser.parse` call here passes the default locale's language this rewrite
     *  reads), so text and boolean can't disagree. The default locale reflects the in-app language
     *  override (AppLocale sets it on Android) or the system locale. **No-op for English: English
     *  users are byte-for-byte unchanged.** */
    private fun String.localized(force: String? = null): String {
        val out = regionalized()
        // A caller's own language (the tap resolve, for a label in another script) wins outright;
        // its status text is parsed against that language's table where there is one.
        if (force != null) return out.replace("hl=en", "hl=$force")
        val lang = graph.locale.defaultLanguage().lowercase()
        // Only rewrite to a language the STATUS parser can read (SearchParser.STATUS_LANGS). For any
        // other locale, keep hl=en: an unparseable status string leaves openNow null forever and the
        // UI can't color open/closed. English status text the English table handles is the safer
        // fallback than localized-but-unparseable (audit 2026-07-06).
        if (lang == "en" || lang !in SearchParser.STATUS_LANGS) return out
        // Chinese needs the SCRIPT in the hl tag: hl=zh-TW answers Traditional, hl=zh-CN Simplified
        // (bare hl=zh is treated as Simplified). parseOpenNow keys on the bare "zh" either way:
        // its keyword table carries both scripts.
        val hl = if (lang == "zh") {
            val (script, country) = scriptAndRegion(graph.locale.defaultTag())
            val hant = script.equals("Hant", ignoreCase = true) ||
                country.uppercase() in setOf("TW", "HK", "MO")
            if (hant) "zh-TW" else "zh-CN"
        } else lang
        return out.replace("hl=en", "hl=$hl")
    }

    /** The script and region subtags of a BCP 47 [tag] (`Locale.getScript`, `Locale.getCountry`),
     *  each empty when absent. */
    private fun scriptAndRegion(tag: String): Pair<String, String> {
        val subtags = tag.split('-', '_').drop(1).takeWhile { it.length > 1 } // a singleton opens an extension
        val script = subtags.firstOrNull { it.length == 4 && it.all { c -> c.isLetter() } }.orEmpty()
        val region = subtags.firstOrNull { (it.length == 2 && it.all { c -> c.isLetter() }) || (it.length == 3 && it.all { c -> c.isDigit() }) }.orEmpty()
        return script to region
    }

    /** Rewrite `gl=us` to the REGION the phone is actually in ([glRegion], set by the app layer
     *  from the cell network's country, falling back to the locale's) so results are biased to
     *  where the user is, not to the US: the "US-shaped results in Jerusalem" half of issue #71.
     *  Region only tunes ranking/bias, not the response SHAPE (hl already varies per language and
     *  the parsers are shape-searched), so this is safe for any 2-letter code; anything else is
     *  ignored and gl=us stays. No-op for US users: byte-for-byte unchanged. */
    private fun String.regionalized(): String {
        val region = glRegion?.lowercase()?.takeIf { it.length == 2 && it.all { c -> c in 'a'..'z' } }
            ?: return this
        if (region == "us") return this
        return replace("gl=us", "gl=$region")
    }
    protected companion object {
        /** The autocomplete window when the caller has no viewport: a town, like the web page's default. */
        const val SUGGEST_SPAN_M = 20_000.0
        /** The whole call for a reply of megabytes ([largeReplyHttp]). */
        const val LARGE_REPLY_TIMEOUT_MS = 90_000L
        /** How many places a shared list is asked for in one reply; the page itself asks for 500. */
        const val LIST_PAGE_SIZE = 5000
        // Fallback viewport when no user location is available: search is
        // viewport-driven and needs one. Callers normally pass the real location.
        val DEFAULT_VIEWPORT = LatLng(37.7749, -122.4194)
        const val PHOTO_COUNT = 50 // gallery page size for the hspqX request
        // Radii (m) to probe out toward the street when the geocode is set-back from it. Two rings
        // cover the usual sidewalk+setback distance; each ring probes both perpendiculars: 4 probes.
        val STREET_PROBE_RADII_M = doubleArrayOf(24.0, 40.0)
    }
}
