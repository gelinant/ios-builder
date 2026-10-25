package app.vela.ios.place

import app.vela.core.config.Calibration
import app.vela.core.data.LowDataMode
import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.ReviewWords
import app.vela.core.data.google.parse.PhotoPage
import app.vela.core.data.google.parse.ReviewFeed
import app.vela.core.data.google.parse.ReviewsWebParser
import app.vela.core.model.Place
import app.vela.core.model.PlaceDetails
import app.vela.core.model.Review
import app.vela.core.platform.Cancellable
import app.vela.core.platform.Log
import app.vela.core.platform.i
import app.vela.core.util.Jitter
import app.vela.core.web.ReviewScripts
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

data class PlaceState(
    val selected: Place? = null,
    val loadingDetails: Boolean = false,
    val reviews: List<Review> = emptyList(),
    val reviewsLoading: Boolean = false,
    /** The running count of a page scrape in flight. */
    val reviewsFound: Int = 0,
    /** The feed ended after a short list for a place that has more: Google's limited view. */
    val reviewsLimited: Boolean = false,
    val reviewsNextToken: String? = null,
    val reviewsMoreLoading: Boolean = false,
    /** Where the shown reviews came from, null while none. */
    val reviewsSource: ReviewsSource? = null,
    val photosLoading: Boolean = false,
    val photosNextToken: String? = null,
) {
    /** [reviewsSource] in lower case (`feed`, `page`, `cache`), for the Swift side and the logs. */
    val reviewsFrom: String? get() = reviewsSource?.name?.lowercase()
}

enum class ReviewsSource { FEED, PAGE, CACHE }

/**
 * The place sheet's facet of the map (docs/ios/PRESENTATION-MAP.md 3.2): the sheet's loads after
 * a pick, ported from Android's `MapViewModel` (`selectPlace`, `fetchPlaceDetails`,
 * `mergeDetails`, `fetchPhotos`, `loadAllPhotos`, `requestReviews`, `ensureReviews`,
 * `fetchReviews`, `loadMoreReviews`, the place caches and retries).
 *
 * Each load is one request first (details by the focused search, photos by `hspqX`, reviews by
 * the `qv9Egd` feed), retried while Google answers a fresh session stripped; the reviews fall back
 * to the hidden page scrape ([web]) when the feed gives nothing or is dialed off. Not here yet:
 * the details page (Android's `WebPopularTimesFetcher`), the photo page walk and its categories,
 * the Street View thumbnail, transit departures.
 *
 * The constructor does nothing; [start] arms the store. Every intent is meant for the [scope]'s
 * thread (the main thread on iOS), and every reply checks that its place is still the one open.
 */
class PlaceStore(
    private val source: () -> MapDataSource,
    private val scope: CoroutineScope,
    private val calibration: () -> Calibration = { Calibration.DEFAULT },
    private val now: () -> Long = { 0L },
    /** The page language of the reviews (`reviewsHl`). */
    private val reviewsHl: () -> String = { "en" },
    private val log: Log? = null,
) {
    constructor(source: MapDataSource, scope: CoroutineScope) : this({ source }, scope)

    private val _state = MutableStateFlow(PlaceState())
    val state: StateFlow<PlaceState> = _state.asStateFlow()

    /** The hidden page for the reviews; null leaves the sheet with what the feed gives. */
    var web: PlaceWebFallback? = null

    val standing = GoogleStanding()

    private var started = false
    private var reviewsPendingFor: Place? = null
    private var reviewsJob: Job? = null
    private var photosJob: Job? = null
    private var detailsJob: Job? = null

    private val photoCache = PlaceCache<PhotoPage>()
    private val feedCache = PlaceCache<ReviewFeed>()
    private val detailsCache = PlaceCache<PlaceDetails>()

    fun start() {
        started = true
    }

    /** Opens [p]'s sheet: its details, photos, and the reviews armed for [ensureReviews].
     *  Port of `MapViewModel.selectPlace` (the browse branch). */
    fun select(p: Place) {
        if (!started) return
        cancelLoads()
        _state.value = PlaceState(selected = p)
        requestReviews(p)
        fetchPhotos(p)
        fetchPlaceDetails(p)
    }

    /** Port of `MapViewModel.clearSelection`, the sheet's part. */
    fun close() {
        cancelLoads()
        reviewsPendingFor = null
        _state.value = PlaceState()
    }

    private fun cancelLoads() {
        reviewsJob?.cancel()
        photosJob?.cancel()
        detailsJob?.cancel()
        reviewsJob = null
        photosJob = null
        detailsJob = null
    }

    private fun googleOff() = NoGoogle.enabled

    private fun tune(key: String, def: Double) = calibration().tune(key, def)

    private fun tuneOn(key: String, default: Boolean = true) = tune(key, if (default) 1.0 else 0.0) >= 0.5

    private fun still(fid: String) = _state.value.selected?.featureId == fid

    // --- details ------------------------------------------------------------

    /** Port of `MapViewModel.fetchPlaceDetails`, without the details page fallback. */
    private fun fetchPlaceDetails(p: Place) {
        if (p.name.isBlank() || googleOff()) return
        val complete = p.popularTimes != null && p.reviewCount != null && !p.address.isNullOrBlank() && p.hours.size >= 2
        if (complete) return
        val fidKey = p.featureId
        val cached = fidKey?.let { detailsCache.get(it, now(), DETAILS_CACHE_MS) }
        if (cached == null && !tuneOn("nativeDetails")) return
        _state.update { if (it.selected?.id == p.id) it.copy(loadingDetails = true) else it }
        detailsJob = scope.launch {
            suspend fun focusedSearch() = try {
                source().placeDetails(p)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            fun complete(f: PlaceDetails?) = f != null && (f.popularTimes != null || f.reviewCount != null)
            var focused = if (cached == null) focusedSearch()?.also { mergeDetails(p, it) } else null
            if (placeTries() >= 2 && cached == null && focused?.popularTimes == null) {
                delay(placeRetryWait(1))
                if (_state.value.selected?.id != p.id) return@launch
                focused = focusedSearch()?.also { mergeDetails(p, it) } ?: focused
            }
            if (placeTries() >= 3 && cached == null && focused?.popularTimes == null) {
                delay(placeRetryWait(2))
                if (_state.value.selected?.id != p.id) return@launch
                focused = focusedSearch()?.also { mergeDetails(p, it) } ?: focused
            }
            val native = focused?.takeIf { complete(it) }
            log?.i(TAG, "details: ${when { cached != null -> "cache"; native != null -> "plain search${if (native.popularTimes == null) " (no popular times)" else ""}"; else -> "nothing" }}")
            val d = cached ?: native?.also { if (fidKey != null) detailsCache.put(fidKey, it, now()) }
            if (d != null) mergeDetails(p, d)
            _state.update { if (it.selected?.id != p.id) it else it.copy(loadingDetails = false) }
        }
    }

    /** Port of `MapViewModel.mergeDetails`, the fields' part. */
    private fun mergeDetails(p: Place, d: PlaceDetails) {
        _state.update { st ->
            val sel = st.selected
            if (sel?.id != p.id) st else st.copy(selected = merged(sel, d))
        }
    }

    // --- photos -------------------------------------------------------------

    /** Port of `MapViewModel.fetchPhotos`, its one-request branch (the page walk is not on iOS). */
    private fun fetchPhotos(p: Place) {
        if (googleOff() || LowDataMode.enabled) return
        val fid = p.featureId
        if (fid.isNullOrBlank() || !fid.contains(":")) return
        if (!tuneOn("nativePlacePhotos")) return
        val photoWorthy = p.rating != null || p.reviewCount != null || p.photoUrls.isNotEmpty()
        _state.update { it.copy(photosNextToken = null, photosLoading = photoWorthy && it.selected?.featureId == fid) }
        photosJob = scope.launch {
            val cached = photoCache.get(fid, now(), PHOTOS_CACHE_MS)
            var page = cached ?: photoPage(fid)
            if (placeTries() >= 2 && page?.photos.isNullOrEmpty()) {
                delay(placeRetryWait(1))
                if (!still(fid)) return@launch
                page = photoPage(fid)
            }
            if (placeTries() >= 3 && page?.photos.isNullOrEmpty()) {
                delay(placeRetryWait(2))
                if (!still(fid)) return@launch
                page = photoPage(fid)
            }
            val native = page?.photos.orEmpty()
            if (cached == null && page != null) standing.onPhotoPage(native.size, page.nextToken != null)
            log?.i(TAG, "photos: ${if (cached != null) "cache" else "rpc"} ${native.size}")
            if (page == null || native.isEmpty()) {
                _state.update { if (still(fid)) it.copy(photosLoading = false, photosNextToken = null) else it }
                return@launch
            }
            if (cached == null) photoCache.put(fid, page, now())
            _state.update { st ->
                val sel = st.selected
                if (sel?.featureId != fid) st else st.copy(
                    selected = sel.copy(photoUrls = native.map { it.url }, photoDates = native.map { it.postedText }, photoCategories = native.map { null }),
                    photosLoading = false,
                    photosNextToken = page.nextToken,
                )
            }
        }
    }

    /** "More photos": the next gallery page. Port of `MapViewModel.loadAllPhotos`, paging only. */
    fun loadMorePhotos() {
        val st = _state.value
        val p = st.selected ?: return
        val fid = p.featureId ?: return
        val token = st.photosNextToken ?: return
        if (st.photosLoading) return
        _state.update { it.copy(photosLoading = true) }
        photosJob = scope.launch {
            var page = photoPage(fid, token)
            if (page?.photos.isNullOrEmpty()) {
                delay(placeRetryWait(1))
                if (!still(fid)) {
                    _state.update { it.copy(photosLoading = false) }
                    return@launch
                }
                page = photoPage(fid, token)
            }
            _state.update {
                val sel = it.selected
                if (sel?.featureId != fid) it.copy(photosLoading = false)
                else {
                    val have = sel.photoUrls.toSet()
                    val add = page?.photos.orEmpty().filter { ph -> ph.url !in have }
                    it.copy(
                        selected = sel.copy(
                            photoUrls = sel.photoUrls + add.map { ph -> ph.url },
                            photoDates = sel.photoDates + add.map { ph -> ph.postedText },
                            photoCategories = sel.photoCategories + add.map { null },
                        ),
                        photosLoading = false,
                        photosNextToken = page?.nextToken?.takeIf { add.isNotEmpty() },
                    )
                }
            }
        }
    }

    private suspend fun photoPage(fid: String, token: String = ""): PhotoPage? = try {
        source().placePhotoPage(fid, token)
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        null
    }

    // --- reviews ------------------------------------------------------------

    /** Arms the reviews of [p] for [ensureReviews], shown as loading (Android loads them once the
     *  Reviews tab is on screen: the page scrape is most of Vela's Google traffic). */
    private fun requestReviews(p: Place) {
        if (googleOff()) return
        reviewsJob?.cancel()
        reviewsPendingFor = p
        val google = !p.featureId.isNullOrBlank() && isListing(p)
        _state.update { it.copy(reviews = emptyList(), reviewsLoading = google, reviewsFound = 0, reviewsLimited = false, reviewsNextToken = null, reviewsMoreLoading = false, reviewsSource = null) }
    }

    /** The reviews section is on screen: start the reviews armed for the place still open.
     *  Idempotent. */
    fun ensureReviews() {
        val p = reviewsPendingFor ?: return
        val sel = _state.value.selected
        reviewsPendingFor = null
        if (sel == null || (sel.id != p.id && sel.featureId != p.featureId)) return
        fetchReviews(sel)
    }

    /** Port of `MapViewModel.fetchReviews`: the feed first when dialed on, then the page. */
    private fun fetchReviews(p: Place) {
        if (googleOff() || !isListing(p)) return
        reviewsJob?.cancel()
        val fid = p.featureId
        if (fid.isNullOrBlank()) {
            _state.update { it.copy(reviews = emptyList(), reviewsLoading = false, reviewsFound = 0) }
            return
        }
        _state.update { it.copy(reviewsLoading = true, reviewsFound = 0, reviewsLimited = false, reviewsNextToken = null, reviewsMoreLoading = false) }
        var streamed: List<Review> = emptyList()
        reviewsJob = scope.launch {
            val expected = p.reviewCount ?: 0
            fun settle(r: List<Review>) = if (r.isEmpty()) streamed else r
            fun tooFew(r: List<Review>) = r.size < minOf(4, expected)
            if (feedFirst()) {
                val cached = feedCache.get(fid, now(), REVIEWS_CACHE_MS)
                var feed = cached ?: feed(fid)
                if (placeTries() >= 2 && feed?.reviews.isNullOrEmpty() && p.reviewCount != 0) {
                    delay(placeRetryWait(1))
                    if (!still(fid)) return@launch
                    feed = feed(fid)
                }
                if (placeTries() >= 3 && feed?.reviews.isNullOrEmpty() && p.reviewCount != 0) {
                    delay(placeRetryWait(2))
                    if (!still(fid)) return@launch
                    feed = feed(fid)
                }
                val limited = feed != null && feed.end && feed.reviews.isNotEmpty() && feed.reviews.size < minOf(FIRST_REVIEWS, expected)
                log?.i(TAG, "reviews: ${if (cached != null) "cache" else "feed"} ${feed?.reviews?.size ?: -1}${if (limited) " (limited view)" else ""}${if (feed?.reviews.isNullOrEmpty()) ", scraping the page" else ""}")
                if (feed != null && feed.reviews.isNotEmpty()) {
                    if (cached == null) feedCache.put(fid, feed, now())
                    if (still(fid)) {
                        _state.update {
                            it.copy(
                                reviews = feed.reviews, reviewsLoading = false, reviewsFound = 0, reviewsLimited = limited,
                                reviewsNextToken = feed.nextToken, reviewsSource = if (cached != null) ReviewsSource.CACHE else ReviewsSource.FEED,
                            )
                        }
                    }
                    return@launch
                }
            }
            if (web == null) {
                _state.update { if (still(fid)) it.copy(reviewsLoading = false) else it }
                return@launch
            }
            val onPartial: (List<Review>) -> Unit = { list ->
                streamed = list
                _state.update { if (it.selected?.featureId == fid && it.reviewsLoading) it.copy(reviews = list) else it }
            }
            var revs = settle(scrape(fid, onPartial))
            ensureActive()
            var attempt = 1
            while (tooFew(revs) && expected > 0 && attempt <= 2) {
                delay(Jitter.around(500L * attempt))
                if (!still(fid)) return@launch
                _state.update { it.copy(reviewsFound = 0) }
                revs = settle(scrape(fid, onPartial))
                ensureActive()
                attempt++
            }
            log?.i(TAG, "reviews: page ${revs.size}")
            if (still(fid)) {
                _state.update { it.copy(reviews = revs, reviewsLoading = false, reviewsFound = 0, reviewsSource = if (revs.isEmpty()) null else ReviewsSource.PAGE) }
            }
        }
    }

    /** The feed RPC unless calibration turns it off. Android's `nativeReviewFeed` is off by
     *  default because its feed rode a session Google kept limited; on iOS the feed answered over
     *  plain HTTP (W-1), so it leads unless `iosNativeReviewFeed` (else `nativeReviewFeed`) is 0. */
    private fun feedFirst(): Boolean = tune("iosNativeReviewFeed", tune("nativeReviewFeed", 1.0)) >= 0.5

    private suspend fun feed(fid: String, token: String = ""): ReviewFeed? = try {
        source().reviewFeed(fid, reviewsHl(), token)
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        null
    }

    /** "More reviews": the next page of the feed, appended. Port of `MapViewModel.loadMoreReviews`. */
    fun loadMoreReviews() {
        val st = _state.value
        val p = st.selected ?: return
        val fid = p.featureId ?: return
        val token = st.reviewsNextToken ?: return
        if (st.reviewsMoreLoading) return
        _state.update { it.copy(reviewsMoreLoading = true) }
        scope.launch {
            val page = feed(fid, token)
            log?.i(TAG, "reviews: next page ${page?.reviews?.size ?: -1}")
            _state.update {
                if (it.selected?.featureId != fid) it.copy(reviewsMoreLoading = false)
                else it.copy(
                    reviews = (it.reviews + page?.reviews.orEmpty()).distinctBy { r -> r.author to r.text },
                    reviewsNextToken = page?.nextToken,
                    reviewsMoreLoading = false,
                )
            }
        }
    }

    /** One page scrape through [web], as Android's `WebReviewsFetcher.fetch`: empty on any
     *  failure or after [WEB_TIMEOUT_MS]. */
    private suspend fun scrape(fid: String, onPartial: (List<Review>) -> Unit): List<Review> {
        val web = web ?: return emptyList()
        val cid = cidOf(fid) ?: return emptyList()
        val cal = calibration()
        val reviewPattern = cal.reviewWords?.get("review") ?: ReviewWords.REVIEW_PATTERN
        val morePattern = cal.reviewWords?.get("more") ?: ReviewWords.MORE_PATTERN
        val selectors = cal.reviewSelectors.orEmpty()
        val cap = FIRST_REVIEWS
        val request = WebReviewsRequest(fid, "https://www.google.com/maps?cid=$cid&hl=${reviewsHl()}&gl=us") { id ->
            ReviewScripts.reviews(id, cap, reviewPattern, morePattern, selectors)
        }
        val raw = withTimeoutOrNull(WEB_TIMEOUT_MS) {
            suspendCancellableCoroutine { cont ->
                var handle: Cancellable? = null
                val sink = object : WebReviewsSink {
                    override fun onProgress(count: Int) {
                        _state.update { if (it.selected?.featureId == fid) it.copy(reviewsFound = count) else it }
                    }

                    override fun onPartial(payload: String) {
                        parse(payload).takeIf { it.isNotEmpty() }?.let(onPartial)
                    }

                    override fun onHistogram(json: String) {
                        val counts = json.trim().removePrefix("[").removeSuffix("]").split(',').mapNotNull { it.trim().toIntOrNull() }
                        if (counts.size != 5 || counts.sum() <= 0) return
                        _state.update { st ->
                            val sel = st.selected
                            if (sel?.featureId == fid && sel.ratingHistogram == null) st.copy(selected = sel.copy(ratingHistogram = counts)) else st
                        }
                    }

                    override fun onResult(payload: String?) {
                        if (cont.isActive) cont.resume(payload)
                    }
                }
                handle = web.reviews(request, sink)
                cont.invokeOnCancellation { handle?.cancel() }
            }
        }
        return if (raw.isNullOrEmpty()) emptyList() else parse(raw)
    }

    private fun parse(payload: String): List<Review> = try {
        ReviewsWebParser.parse(payload)
    } catch (_: Exception) {
        emptyList()
    }

    // --- retries ------------------------------------------------------------

    /** Port of `MapViewModel.placeTries`. */
    private fun placeTries(): Int = tune("placeTries", 3.0).toInt().coerceIn(1, 5)

    /** Port of `MapViewModel.placeRetryWait`. */
    private fun placeRetryWait(n: Int): Long =
        Jitter.around((tune("placeRetryMs", 2500.0) + (n - 1) * tune("placeRetryStepMs", 1000.0)).toLong().coerceIn(0L, 20_000L))

    /**
     * Calls [onChange] with the current state, then with each change, on the store's thread, until
     * the returned handle is cancelled. For Swift code that cannot iterate [state] through SKIE.
     */
    fun watch(onChange: (PlaceState) -> Unit): Cancellable {
        val job = scope.launch { state.collect { onChange(it) } }
        return Cancellable { job.cancel() }
    }

    companion object {
        const val TAG = "PlaceLoad"
        const val FIRST_REVIEWS = 10
        const val PHOTOS_CACHE_MS = 6 * 3_600_000L
        const val REVIEWS_CACHE_MS = 6 * 3_600_000L
        const val DETAILS_CACHE_MS = 15 * 60_000L

        /** Outlasts the script's own hard stop (130 ticks of 250 ms plus the page load). */
        const val WEB_TIMEOUT_MS = 45_000L

        /** Languages the review scraper's words cover (Android's `WebReviewsFetcher.SUPPORTED_HL`). */
        val SUPPORTED_HL = setOf("en", "fr", "de", "es", "it", "pt", "nl", "ru", "pl", "sv", "uk", "hu", "ro", "zh", "ja", "he", "iw")

        /** A business or landmark rather than a bare address (Android's `Place.isListing`). */
        fun isListing(p: Place): Boolean =
            !p.category.isNullOrBlank() || p.rating != null || p.reviewCount != null || p.featuredReview != null

        /** The page language for the reviews, port of `WebReviewsFetcher.reviewsHl`: the app
         *  language when the scraper's words cover it, English otherwise; Chinese keeps its script. */
        fun reviewsHl(language: String, tag: String): String {
            val lang = language.lowercase()
            if (lang !in SUPPORTED_HL) return "en"
            if (lang == "he") return "iw"
            if (lang == "zh") {
                val parts = tag.split('-', '_')
                val hant = parts.any { it.equals("Hant", ignoreCase = true) } || parts.any { it.uppercase() in setOf("TW", "HK", "MO") }
                return if (hant) "zh-TW" else "zh-CN"
            }
            return lang
        }

        /** The `?cid=` of a `0xHIGH:0xLOW` feature id: the low half as an unsigned decimal. */
        fun cidOf(featureId: String): String? {
            val low = featureId.substringAfter(":", "").removePrefix("0x").ifBlank { return null }
            return low.toULongOrNull(16)?.toString()
        }

        /** What [sel] is missing, filled from [d]; the fuller hours list wins. */
        fun merged(sel: Place, d: PlaceDetails): Place = sel.copy(
            popularTimes = sel.popularTimes ?: d.popularTimes,
            editorialSummary = sel.editorialSummary ?: d.editorialSummary,
            ownerDescription = sel.ownerDescription ?: d.ownerDescription,
            rating = sel.rating ?: d.rating,
            reviewCount = sel.reviewCount ?: d.reviewCount,
            hours = if (d.hours.size > sel.hours.size) d.hours else sel.hours,
            address = sel.address?.ifBlank { null } ?: d.address,
            phone = sel.phone ?: d.phone,
            website = sel.website ?: d.website,
            statusText = sel.statusText ?: d.statusText,
            openNow = sel.openNow ?: d.openNow,
            priceText = sel.priceText ?: d.priceText,
            priceLevel = sel.priceLevel ?: d.priceLevel,
            about = sel.about.ifEmpty { d.about },
            featuredReview = sel.featuredReview ?: d.featuredReview,
            updates = sel.updates.ifEmpty { d.updates },
            svPanoId = sel.svPanoId ?: d.svPanoId,
            svYawDeg = if (sel.svPanoId != null) sel.svYawDeg else d.svYawDeg,
        )
    }
}

/** The per-place cache of the sheet's loads (Android's `placeCacheGet`/`placeCachePut`): process
 *  lifetime, [capacity] places, the least recently used dropped first. */
internal class PlaceCache<T>(private val capacity: Int = 80) {
    private class Entry<T>(val value: T, val at: Long)

    private val map = LinkedHashMap<String, Entry<T>>()

    fun get(key: String, now: Long, ttlMs: Long): T? {
        val e = map.remove(key) ?: return null
        map[key] = e
        return e.value.takeIf { now - e.at < ttlMs }
    }

    fun put(key: String, value: T, now: Long) {
        map.remove(key)
        map[key] = Entry(value, now)
        while (map.size > capacity) map.remove(map.keys.first())
    }
}
