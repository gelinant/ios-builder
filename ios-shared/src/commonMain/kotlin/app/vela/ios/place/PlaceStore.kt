package app.vela.ios.place

import app.vela.core.config.Calibration
import app.vela.core.data.LowDataMode
import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.ReviewWords
import app.vela.core.data.google.SearchPb
import app.vela.core.data.google.StreetViewParser
import app.vela.core.data.google.parse.PhotoPage
import app.vela.core.data.google.parse.PopularTimesParser
import app.vela.core.data.google.parse.ReviewFeed
import app.vela.core.data.google.parse.ReviewsWebParser
import app.vela.core.model.LatLng
import app.vela.core.model.Photo
import app.vela.core.model.bearingTo
import app.vela.core.model.Place
import app.vela.core.model.PlaceDetails
import app.vela.core.model.Review
import app.vela.core.platform.Cancellable
import app.vela.core.platform.Log
import app.vela.core.platform.i
import app.vela.core.util.Jitter
import app.vela.core.util.UrlCodec
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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
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
    /** A tap on More reviews may walk the hidden page when the feed has no cursor. */
    val reviewsCanScrapeMore: Boolean = false,
    /** Where the shown reviews came from, null while none. */
    val reviewsSource: ReviewsSource? = null,
    val photosLoading: Boolean = false,
    val photosNextToken: String? = null,
    /** A user-initiated page walk can add categories and photos the RPC did not serve. */
    val photosCanWalk: Boolean = false,
    /** null, loading, empty, details, popular, or unavailable; for diagnostics, not presentation. */
    val detailsFallback: String? = null,
    /** The process-wide limited-view mark, shown where popular times would be. */
    val limitedView: Boolean = false,
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
 * the `qv9Egd` feed), retried while Google answers a fresh session stripped. Hidden pages provide
 * reviews when the feed gives nothing, more reviews on demand, the categorized gallery, and the
 * details fallback when popular times are still absent. Transit departures are not here yet.
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
    /** The response language of the focused details search. */
    private val detailsLanguage: () -> String = { reviewsHl().substringBefore('-') },
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
    private var moreReviewsJob: Job? = null
    private var photosJob: Job? = null
    private var detailsJob: Job? = null
    private var streetViewJob: Job? = null

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

    /** Opens a place an external link named, anchored at its own point. The link has no search
     *  result and no Google id beyond [featureId], so the details fetch fills the rest. */
    fun selectIncoming(name: String, lat: Double, lng: Double, featureId: String?) {
        if (name.isBlank() || lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        select(Place(
            id = "link:$lat,$lng", name = name,
            location = LatLng(lat, lng), featureId = featureId))
    }

    /** Port of `MapViewModel.clearSelection`, the sheet's part. */
    fun close() {
        cancelLoads()
        reviewsPendingFor = null
        _state.value = PlaceState()
    }

    private fun cancelLoads() {
        reviewsJob?.cancel()
        moreReviewsJob?.cancel()
        photosJob?.cancel()
        detailsJob?.cancel()
        streetViewJob?.cancel()
        reviewsJob = null
        moreReviewsJob = null
        photosJob = null
        detailsJob = null
        streetViewJob = null
    }

    private fun googleOff() = NoGoogle.enabled

    private fun tune(key: String, def: Double) = calibration().tune(key, def)

    private fun tuneOn(key: String, default: Boolean = true) = tune(key, if (default) 1.0 else 0.0) >= 0.5

    private fun still(fid: String) = _state.value.selected?.featureId == fid

    // --- details ------------------------------------------------------------

    /** Plain focused searches first. The warmed details page runs only after those replies still
     *  lack popular times, and only on demand from the sheet's initial details load. */
    private fun fetchPlaceDetails(p: Place) {
        if (p.name.isBlank() || googleOff()) return
        val complete = p.popularTimes != null && p.reviewCount != null && !p.address.isNullOrBlank() && p.hours.size >= 2
        if (complete) {
            thumbnailPano(p)
            return
        }
        val fidKey = p.featureId
        val cached = fidKey?.let { detailsCache.get(it, now(), DETAILS_CACHE_MS) }
        val nativeEnabled = tuneOn("nativeDetails")
        _state.update { if (it.selected?.id == p.id) it.copy(loadingDetails = true, detailsFallback = null) else it }
        detailsJob = scope.launch {
            suspend fun focusedSearch() = try {
                source().placeDetails(p)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            fun complete(f: PlaceDetails?) = f != null && (f.popularTimes != null || f.reviewCount != null)
            var focused = if (cached == null && nativeEnabled) focusedSearch()?.also { mergeDetails(p, it) } else null
            if (placeTries() >= 2 && cached == null && nativeEnabled && focused?.popularTimes == null) {
                delay(placeRetryWait(1))
                if (_state.value.selected?.id != p.id) return@launch
                focused = focusedSearch()?.also { mergeDetails(p, it) } ?: focused
            }
            if (placeTries() >= 3 && cached == null && nativeEnabled && focused?.popularTimes == null) {
                delay(placeRetryWait(2))
                if (_state.value.selected?.id != p.id) return@launch
                focused = focusedSearch()?.also { mergeDetails(p, it) } ?: focused
            }
            val native = focused?.takeIf { complete(it) }
            log?.i(TAG, "details: ${when { cached != null -> "cache"; native != null -> "plain search${if (native.popularTimes == null) " (no popular times)" else ""}"; else -> "nothing" }}")
            val plain = cached ?: native
            if (plain != null) {
                mergeDetails(p, plain)
                if (fidKey != null && cached == null) detailsCache.put(fidKey, plain, now())
            }
            val current = _state.value.selected
            if (current?.id == p.id && current.popularTimes == null) {
                val (pageDetails, outcome) = detailsPage(current)
                if (pageDetails != null) mergeDetails(p, pageDetails)
                if (pageDetails?.popularTimes != null && fidKey != null) {
                    detailsCache.put(fidKey, pageDetails, now())
                }
                _state.update {
                    if (it.selected?.id != p.id) it else it.copy(detailsFallback = outcome)
                }
            }
            _state.update { if (it.selected?.id != p.id) it else it.copy(loadingDetails = false) }
            _state.value.selected?.let { if (it.id == p.id) thumbnailPano(it) }
        }
    }

    /** The search reply often names Google's own panorama. Otherwise one nearest-panorama lookup
     *  through the common `StreetViewParser` supplies the static thumbnail, as on Android. */
    private fun thumbnailPano(p: Place) {
        if (p.svPanoId != null || !isListing(p) || p.featureId?.contains(':') != true || googleOff() || LowDataMode.enabled) return
        streetViewJob?.cancel()
        streetViewJob = scope.launch {
            val pano = try {
                source().streetView(p.location, StreetViewParser.streetOf(p.address))
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            } ?: return@launch
            _state.update { st ->
                val sel = st.selected
                if (sel?.id != p.id || sel.svPanoId != null) st
                else st.copy(
                    selected = sel.copy(
                        svPanoId = pano.panoId,
                        svYawDeg = LatLng(pano.lat, pano.lng).bearingTo(sel.location),
                    )
                )
            }
        }
    }

    /** The raw reply and its diagnostic outcome. No page is loaded when [web] is absent. */
    private suspend fun detailsPage(p: Place): Pair<PlaceDetails?, String> {
        val web = web ?: return null to "unavailable"
        val cal = calibration()
        val address = p.address?.replace(',', ' ')?.replace(WHITESPACE, " ")?.trim()
        val query = if (address.isNullOrBlank()) p.name else "${p.name} $address"
        val pb = SearchPb.build(query, p.location, cal.searchPb)
        val url = "${cal.searchEndpoint}&q=${UrlCodec.encode(query)}&pb=${UrlCodec.encode(pb)}"
        val request = WebDetailsRequest(p.featureId.orEmpty(), url, cal.sessionWarmUrl)
        _state.update { if (it.selected?.id == p.id) it.copy(detailsFallback = "loading") else it }
        val raw = withTimeoutOrNull(DETAILS_WEB_TIMEOUT_MS) {
            suspendCancellableCoroutine<String?> { cont ->
                val sink = object : WebDetailsSink {
                    override fun onResult(payload: String?) {
                        if (cont.isActive) cont.resume(payload)
                    }
                }
                val handle = web.details(request, sink)
                cont.invokeOnCancellation { handle.cancel() }
            }
        }
        val details = if (raw.isNullOrEmpty()) null else runCatching {
            PopularTimesParser.parse(raw, p.featureId, cal.paths, detailsLanguage().lowercase())
        }.getOrNull()
        log?.i(TAG, "details: page raw=${raw?.length ?: -1} parsed=${details != null} times=${details?.popularTimes != null}")
        val outcome = when {
            details?.popularTimes != null -> "popular"
            details != null -> "details"
            else -> "empty"
        }
        return details to outcome
    }

    /** Port of `MapViewModel.mergeDetails`, the fields' part. */
    private fun mergeDetails(p: Place, d: PlaceDetails) {
        _state.update { st ->
            val sel = st.selected
            if (sel?.id != p.id) st else st.copy(selected = merged(sel, d))
        }
    }

    // --- photos -------------------------------------------------------------

    /** The first gallery page comes from `hspqX`. A page walk stays user-initiated. */
    private fun fetchPhotos(p: Place) {
        if (googleOff() || LowDataMode.enabled) return
        val fid = p.featureId
        if (fid.isNullOrBlank() || !fid.contains(":")) return
        if (!tuneOn("nativePlacePhotos")) return
        val photoWorthy = p.rating != null || p.reviewCount != null || p.photoUrls.isNotEmpty()
        _state.update {
            it.copy(
                photosNextToken = null,
                photosCanWalk = true,
                photosLoading = photoWorthy && it.selected?.featureId == fid,
            )
        }
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
                _state.update {
                    if (still(fid)) it.copy(
                        photosLoading = false,
                        photosNextToken = null,
                        limitedView = standing.limited.value,
                    ) else it
                }
                return@launch
            }
            if (cached == null) photoCache.put(fid, page, now())
            _state.update { st ->
                val sel = st.selected
                if (sel?.featureId != fid) st else st.copy(
                    selected = sel.copy(photoUrls = native.map { it.url }, photoDates = native.map { it.postedText }, photoCategories = native.map { null }),
                    photosLoading = false,
                    photosNextToken = page.nextToken,
                    limitedView = standing.limited.value,
                )
            }
        }
    }

    /** "More photos": the next RPC cursor. An empty cursor response or an explicit category
     *  request falls back to the same gallery walk as Android. */
    fun loadMorePhotos() {
        val st = _state.value
        val p = st.selected ?: return
        val fid = p.featureId ?: return
        if (st.photosLoading) return
        val token = st.photosNextToken
        if (token == null) {
            if (st.photosCanWalk) walkPhotos(p)
            return
        }
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
            if (page?.photos.isNullOrEmpty()) {
                log?.i(TAG, "photos: next page empty, walking the page")
                _state.update {
                    if (still(fid)) it.copy(photosLoading = false, photosNextToken = null, photosCanWalk = true) else it
                }
                _state.value.selected?.let { if (it.featureId == fid) walkPhotos(it) }
                return@launch
            }
            val answered = page
            _state.update {
                val sel = it.selected
                if (sel?.featureId != fid) it.copy(photosLoading = false)
                else {
                    val have = sel.photoUrls.toSet()
                    val add = answered.photos.filter { ph -> ph.url !in have }
                    it.copy(
                        selected = sel.copy(
                            photoUrls = sel.photoUrls + add.map { ph -> ph.url },
                            photoDates = sel.photoDates + add.map { ph -> ph.postedText },
                            photoCategories = sel.photoCategories + add.map { null },
                        ),
                        photosLoading = false,
                        photosNextToken = answered.nextToken?.takeIf { add.isNotEmpty() },
                    )
                }
            }
        }
    }

    /** The Photos grid's category action. One full page walk per sheet opening. */
    fun loadPhotoCategories() {
        val p = _state.value.selected ?: return
        if (_state.value.photosCanWalk) walkPhotos(p)
    }

    private fun walkPhotos(p: Place) {
        val web = web ?: return
        val fid = p.featureId ?: return
        val cid = cidOf(fid) ?: return
        if (_state.value.photosLoading || !_state.value.photosCanWalk) return
        _state.update { it.copy(photosLoading = true, photosNextToken = null) }
        photosJob = scope.launch {
            var streamed = emptyList<Photo>()
            val minedDates = mutableMapOf<String, String>()
            fun applyGallery(gallery: List<Photo>, partial: Boolean) {
                if (gallery.isEmpty()) return
                _state.update { st ->
                    val sel = st.selected
                    if (sel?.featureId != fid || (partial && gallery.size <= sel.photoUrls.size)) st
                    else {
                        val oldDates = sel.photoUrls.indices.mapNotNull { i ->
                            sel.photoDates.getOrNull(i)?.let { photoKey(sel.photoUrls[i]) to it }
                        }.toMap()
                        val dates = gallery.map { ph -> ph.postedText ?: minedDates[photoKey(ph.url)] ?: oldDates[photoKey(ph.url)] }
                        st.copy(
                            selected = sel.copy(
                                photoUrls = gallery.map { it.url },
                                photoDates = dates,
                                photoCategories = gallery.map { it.category },
                            ),
                            photosLoading = if (partial) true else false,
                            photosCanWalk = if (partial) st.photosCanWalk else false,
                        )
                    }
                }
            }
            val request = WebPhotosRequest(fid, "https://www.google.com/maps?cid=$cid&hl=en&gl=us", FULL_PHOTOS)
            val raw = withTimeoutOrNull(PHOTO_WEB_TIMEOUT_MS) {
                suspendCancellableCoroutine<String?> { cont ->
                    val sink = object : WebPhotosSink {
                        override fun onPartial(payload: String) {
                            val photos = parsePhotos(payload)
                            if (photos.isNotEmpty()) {
                                streamed = photos
                                applyGallery(photos, partial = true)
                            }
                        }

                        override fun onDates(json: String) {
                            for ((url, date) in parsePhotoDates(json)) minedDates[photoKey(url)] = date
                        }

                        override fun onHistogram(json: String) = applyHistogram(fid, json)

                        override fun onResult(payload: String?) {
                            if (cont.isActive) cont.resume(payload)
                        }
                    }
                    val handle = web.photos(request, sink)
                    cont.invokeOnCancellation { handle.cancel() }
                }
            }
            val gallery = raw?.let(::parsePhotos).orEmpty().ifEmpty { streamed }
            applyGallery(gallery, partial = false)
            log?.i(TAG, "photos: page ${gallery.size}, categories=${gallery.count { it.category != null }}")
            _state.update {
                if (still(fid)) it.copy(photosLoading = false, photosNextToken = null, photosCanWalk = false) else it
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

    private fun parsePhotos(raw: String): List<Photo> = raw.lineSequence().mapNotNull { line ->
        if (line.isBlank()) return@mapNotNull null
        val tab = line.indexOf('\t')
        if (tab < 0) Photo(upsizePhoto(line.trim()))
        else Photo(
            upsizePhoto(line.substring(tab + 1).trim()),
            category = line.substring(0, tab).trim().ifBlank { null },
        )
    }.toList()

    private fun parsePhotoDates(raw: String): List<Pair<String, String>> = runCatching {
        Json.parseToJsonElement(raw).jsonArray.mapNotNull { entry ->
            val values = entry.jsonArray
            val url = values.getOrNull(0)?.jsonPrimitive?.contentOrNull
            val date = values.getOrNull(1)?.jsonPrimitive?.contentOrNull
            if (!url.isNullOrBlank() && !date.isNullOrBlank()) url to date else null
        }
    }.getOrDefault(emptyList())

    // --- reviews ------------------------------------------------------------

    /** Arms the reviews of [p] for [ensureReviews], shown as loading (Android loads them once the
     *  Reviews tab is on screen: the page scrape is most of Vela's Google traffic). */
    private fun requestReviews(p: Place) {
        if (googleOff()) return
        reviewsJob?.cancel()
        reviewsPendingFor = p
        val google = !p.featureId.isNullOrBlank() && isListing(p)
        _state.update {
            it.copy(
                reviews = emptyList(), reviewsLoading = google, reviewsFound = 0, reviewsLimited = false,
                reviewsNextToken = null, reviewsMoreLoading = false, reviewsCanScrapeMore = false, reviewsSource = null,
            )
        }
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
        _state.update {
            it.copy(
                reviewsLoading = true, reviewsFound = 0, reviewsLimited = false,
                reviewsNextToken = null, reviewsMoreLoading = false, reviewsCanScrapeMore = false,
            )
        }
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
                                reviewsNextToken = feed.nextToken, reviewsCanScrapeMore = feed.reviews.size < expected,
                                reviewsSource = if (cached != null) ReviewsSource.CACHE else ReviewsSource.FEED,
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
                _state.update {
                    it.copy(
                        reviews = revs,
                        reviewsLoading = false,
                        reviewsFound = 0,
                        reviewsLimited = revs.isNotEmpty() && revs.size < minOf(FIRST_REVIEWS, expected),
                        reviewsCanScrapeMore = revs.isNotEmpty() && revs.size < expected,
                        reviewsSource = if (revs.isEmpty()) null else ReviewsSource.PAGE,
                    )
                }
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

    /** "More reviews": the feed cursor when there is one. Otherwise a user tap asks the hidden
     *  page for up to [FULL_REVIEWS], including the limited five-review feed's More reviews path. */
    fun loadMoreReviews() {
        val st = _state.value
        val p = st.selected ?: return
        val fid = p.featureId ?: return
        val token = st.reviewsNextToken
        if (st.reviewsMoreLoading || (token == null && !st.reviewsCanScrapeMore)) return
        _state.update { it.copy(reviewsMoreLoading = true) }
        moreReviewsJob = scope.launch {
            if (token != null) {
                val page = feed(fid, token)
                log?.i(TAG, "reviews: next page ${page?.reviews?.size ?: -1}")
                _state.update {
                    if (it.selected?.featureId != fid) it.copy(reviewsMoreLoading = false)
                    else {
                        val merged = (it.reviews + page?.reviews.orEmpty()).distinctBy { r -> r.author to r.text }
                        it.copy(
                            reviews = merged,
                            reviewsNextToken = page?.nextToken ?: token.takeIf { page == null },
                            reviewsCanScrapeMore = merged.size < (p.reviewCount ?: 0),
                            reviewsMoreLoading = false,
                        )
                    }
                }
                return@launch
            }
            var streamed = emptyList<Review>()
            val onPartial: (List<Review>) -> Unit = { list ->
                streamed = list
                _state.update {
                    if (it.selected?.featureId == fid && it.reviewsMoreLoading) {
                        it.copy(reviews = (it.reviews + list).distinctBy { r -> r.author to r.text })
                    } else it
                }
            }
            val answer = scrape(fid, onPartial, FULL_REVIEWS)
            val scraped = answer.ifEmpty { streamed }
            ensureActive()
            log?.i(TAG, "reviews: more from page ${scraped.size}")
            var stalled = false
            _state.update {
                if (it.selected?.featureId != fid) it.copy(reviewsMoreLoading = false)
                else {
                    val merged = (it.reviews + scraped).distinctBy { r -> r.author to r.text }
                    stalled = merged.size <= st.reviews.size
                    if (stalled) standing.onMoreReviewsStalled()
                    val expected = p.reviewCount ?: 0
                    it.copy(
                        reviews = merged,
                        reviewsMoreLoading = false,
                        reviewsFound = 0,
                        reviewsLimited = stalled || merged.size < minOf(FIRST_REVIEWS, expected),
                        reviewsCanScrapeMore = false,
                        limitedView = it.limitedView || standing.limited.value,
                        reviewsSource = if (scraped.isEmpty()) it.reviewsSource else ReviewsSource.PAGE,
                    )
                }
            }
            if (stalled) log?.i(TAG, "reviews: limited view, More reviews loaded nothing")
        }
    }

    /** One page scrape through [web], as Android's `WebReviewsFetcher.fetch`: empty on any
     *  failure or after [WEB_TIMEOUT_MS]. */
    private suspend fun scrape(fid: String, onPartial: (List<Review>) -> Unit, cap: Int = FIRST_REVIEWS): List<Review> {
        val web = web ?: return emptyList()
        val cid = cidOf(fid) ?: return emptyList()
        val cal = calibration()
        val reviewPattern = cal.reviewWords?.get("review") ?: ReviewWords.REVIEW_PATTERN
        val morePattern = cal.reviewWords?.get("more") ?: ReviewWords.MORE_PATTERN
        val selectors = cal.reviewSelectors.orEmpty()
        val request = WebReviewsRequest(fid, "https://www.google.com/maps?cid=$cid&hl=${reviewsHl()}&gl=us") { id ->
            ReviewScripts.reviews(id, cap, reviewPattern, morePattern, selectors)
        }
        val raw = withTimeoutOrNull(WEB_TIMEOUT_MS) {
            suspendCancellableCoroutine { cont ->
                val sink = object : WebReviewsSink {
                    override fun onProgress(count: Int) {
                        _state.update { if (it.selected?.featureId == fid) it.copy(reviewsFound = count) else it }
                    }

                    override fun onPartial(payload: String) {
                        parse(payload).takeIf { it.isNotEmpty() }?.let(onPartial)
                    }

                    override fun onHistogram(json: String) = applyHistogram(fid, json)

                    override fun onResult(payload: String?) {
                        if (cont.isActive) cont.resume(payload)
                    }
                }
                val handle = web.reviews(request, sink)
                cont.invokeOnCancellation { handle.cancel() }
            }
        }
        return if (raw.isNullOrEmpty()) emptyList() else parse(raw)
    }

    private fun parse(payload: String): List<Review> = try {
        ReviewsWebParser.parse(payload)
    } catch (_: Exception) {
        emptyList()
    }

    private fun applyHistogram(fid: String, json: String) {
        val counts = json.trim().removePrefix("[").removeSuffix("]").split(',').mapNotNull { it.trim().toIntOrNull() }
        if (counts.size != 5 || counts.sum() <= 0) return
        _state.update { st ->
            val sel = st.selected
            if (sel?.featureId == fid && sel.ratingHistogram == null) st.copy(selected = sel.copy(ratingHistogram = counts)) else st
        }
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
        const val FULL_REVIEWS = 50
        const val FULL_PHOTOS = 80
        const val PHOTOS_CACHE_MS = 6 * 3_600_000L
        const val REVIEWS_CACHE_MS = 6 * 3_600_000L
        const val DETAILS_CACHE_MS = 15 * 60_000L

        /** Outlasts the scripts' own hard stops plus the page loads. */
        const val WEB_TIMEOUT_MS = 45_000L
        const val PHOTO_WEB_TIMEOUT_MS = 55_000L
        const val DETAILS_WEB_TIMEOUT_MS = 22_000L

        private val WHITESPACE = Regex("\\s+")
        private val PHOTO_WIDTH = Regex("=w\\d+-h\\d+[^=]*$")
        private val PHOTO_SIZE = Regex("=s\\d+[^=]*$")

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

        private fun upsizePhoto(url: String): String =
            url.replace(PHOTO_WIDTH, "=w600-h450").replace(PHOTO_SIZE, "=s600")

        private fun photoKey(url: String): String = url.substringBefore('=')

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
