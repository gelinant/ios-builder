package app.vela.ios.search

import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.OfflineAddressStore
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo
import app.vela.core.platform.Cancellable
import kotlin.math.abs
import kotlinx.datetime.LocalDateTime
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** The offline facet's search hook, installed by MapSession without coupling this store to files. */
interface OfflineSearch {
    fun offlineOnly(): Boolean
    suspend fun search(query: String, near: LatLng?): List<Place>
}

data class SearchState(
    val query: String = "",
    val searching: Boolean = false,
    val results: List<Place> = emptyList(),
    val suggestions: List<Place> = emptyList(),
    val querySuggestions: List<String> = emptyList(),
    val error: SearchError? = null,
    val usedOffline: Boolean = false,
    /** Number of accepted submissions, including one that replaces a search in flight. */
    val submissions: Int = 0,
    /** Leading rows of [suggestions] that come from the user's own places, as Android shows them. */
    val localSuggestionCount: Int = 0,
    /** Google holds further pages of the current query ("More results" at the end of the list). */
    val moreAvailable: Boolean = false,
    val loadingMore: Boolean = false,
    /** The filters and sort the results above already honour (SRCH-FILTER). */
    val filters: SearchFilters = SearchFilters(),
    /** What the active source can answer, so the sheet hides the rest instead of lying. */
    val filterSupport: SearchFilterSupport = SearchFilterSupportMatrix.of(NoGoogle.enabled),
    /** The view moved beyond Android's pan step: the results header offers "Search this area". */
    val searchAreaAvailable: Boolean = false,
    /** Rows the merge or "More results" dropped as duplicates of a row already shown. */
    val droppedDuplicates: Int = 0,
)

sealed interface SearchError {
    /** `mapvm_no_results`. */
    data object NoResults : SearchError

    /** `mapvm_search_needs_recalibration`. */
    data class NeedsRecalibration(val where: String?) : SearchError

    /** `mapvm_search_failed_reason`. */
    data class Failed(val reason: String?) : SearchError
}

/**
 * The search facet of the map (docs/ios/PRESENTATION-MAP.md 4.2): the online Google branch of
 * Android's `runSearch`. The bias is the viewport center, else the user's location, each only
 * when plausible; the window is the viewport height; results are ranked from the user when they
 * are within 50 km of the bias.
 *
 * The constructor does nothing; [start] arms the store (PRESENTATION-MAP.md 5, trap 1). Every
 * intent is meant for the [scope]'s thread (the main thread on iOS).
 */
class SearchStore(
    private val source: () -> MapDataSource,
    private val scope: CoroutineScope,
    /** Local time for the Open now fallback on weekly hours; injectable for tests. */
    private val now: () -> LocalDateTime = ::currentLocalTime,
) {
    constructor(source: MapDataSource, scope: CoroutineScope) : this({ source }, scope)

    private val _state = MutableStateFlow(SearchState())
    val state: StateFlow<SearchState> = _state.asStateFlow()

    private var started = false
    private var viewport: DoubleArray? = null
    private var myLocation: LatLng? = null
    private var searchJob: Job? = null
    private var suggestJob: Job? = null
    private var moreJob: Job? = null
    private var generation = 0
    private var suggestGeneration = 0
    internal var offline: OfflineSearch? = null

    /** The user's own places, pushed by Swift from the saved facet; suggestions lead with these. */
    private var localPool: List<Place> = emptyList()
    private var localKeys: List<String> = emptyList()
    private var networkSuggestions: List<Place> = emptyList()

    /** The last submitted query, kept for its "More results" pages. */
    private var lastQuery = ""
    private var lastNear: LatLng? = null
    private var lastSpan: Double? = null
    private var lastRankFrom: LatLng? = null
    private var nextPage = FIRST_MORE_PAGE

    /** The viewport the results on screen were searched in, for "Search this area". */
    private var searchedArea: DoubleArray? = null

    /** The view the area search keeps its one answer to, consumed by [submit]. */
    private var narrowToArea: DoubleArray? = null

    /** The unfiltered answer, so turning a filter off restores rows without a second search. */
    private var rawResults: List<Place> = emptyList()

    /** The app language's "open now" phrase, pushed by Swift; Android does the same. */
    private var openNowPhrase = "open now"

    /** Photon, wired to the process HTTP client and app language by MapSession. */
    internal var photon: (suspend (query: String, near: LatLng?, limit: Int, hardBox: Boolean) -> List<Place>)? = null

    fun start() {
        started = true
    }

    /** Android's typing pause: one autocomplete request after 320 ms, never one per character. */
    fun setQuery(q: String) {
        _state.update { it.copy(query = q) }
        suggestJob?.cancel()
        val gen = ++suggestGeneration
        val term = q.trim()
        networkSuggestions = emptyList()
        if (!started || term.length < 2) {
            _state.update {
                it.copy(suggestions = emptyList(), querySuggestions = emptyList(), localSuggestionCount = 0)
            }
            return
        }
        // Android matches the user's own history and lists synchronously, so those rows land at
        // once and the debounced network answer appends behind them.
        val ownNow = SuggestionPriority.select(localPool, term)
        _state.update {
            it.copy(
                suggestions = ownNow, querySuggestions = emptyList(), localSuggestionCount = ownNow.size,
            )
        }
        suggestJob = scope.launch {
            delay(SUGGEST_DEBOUNCE_MS)
            val vp = viewport
            val center = vp?.let { LatLng((it[0] + it[2]) / 2, (it[1] + it[3]) / 2) }
            val near = plausibleBias(center) ?: plausibleBias(myLocation)
            val viewSpan = vp?.let { LatLng(it[0], it[1]).distanceTo(LatLng(it[2], it[1])) }
            val isAddress = AddressQuery.parse(term) != null
            val span = if (isAddress) maxOf(viewSpan ?: 0.0, ADDRESS_SEARCH_SPAN_M) else viewSpan
            val local = offline
            val wantsLocalAddress = OfflineAddressStore.looksLikeAddress(term)

            // NoGoogle is not offline: Photon is an open geocoder, so the online path still runs
            // without Google (the source's own NoGoogle branch). Only a missing network path or a
            // forced offline mode keeps the existing local-only contract. Installed house numbers
            // still autocomplete without a network request.
            if (localOnly(local)) {
                val addresses = if (wantsLocalAddress) local?.let { localResults(it, term, near) }.orEmpty()
                    .filter { it.category.equals("Address", ignoreCase = true) }
                    .filter { near == null || it.location.distanceTo(near) <= SUGGEST_NEAR_M }
                    .take(LOCAL_ADDRESS_LIMIT) else emptyList()
                if (gen != suggestGeneration || _state.value.query.trim() != term) return@launch
                val network = SearchMerge.merge(emptyList(), addresses, term, near, emptyList())
                networkSuggestions = network
                val own = SuggestionPriority.select(localPool, term)
                _state.update {
                    it.copy(
                        suggestions = SuggestionPriority.mergeOwn(own, network),
                        querySuggestions = emptyList(),
                        localSuggestionCount = own.size,
                    )
                }
                return@launch
            }

            // Android races local and Photon address lookups with Google autocomplete. A useful
            // Google answer wins the autocomplete path; when it is empty or fails, Photon answers.
            val localDeferred = async {
                if (wantsLocalAddress && local != null) localResults(local, term, near)
                    .filter { it.category.equals("Address", ignoreCase = true) }
                    .filter { near == null || it.location.distanceTo(near) <= SUGGEST_NEAR_M }
                    .take(LOCAL_ADDRESS_LIMIT) else emptyList()
            }
            val photonDeferred = async {
                if (isAddress) photonResults(term, near, PHOTON_SUGGEST_LIMIT, hardBox = true) else emptyList()
            }
            val result = try {
                source().suggest(term, near, span)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            val hasGoogleRows = result != null && (result.places.isNotEmpty() || result.queries.isNotEmpty())
            if (hasGoogleRows) photonDeferred.cancel()
            val localAddresses = localDeferred.await()
            val autoPlaces = result?.places.orEmpty().let { places ->
                if (term.all { it.isDigit() } && near != null) {
                    places.filter { it.location.distanceTo(near) <= SUGGEST_NEAR_M }.ifEmpty { places }
                } else places
            }
            val network = if (hasGoogleRows) {
                SearchMerge.merge(autoPlaces, localAddresses, term, near, emptyList())
            } else if (isAddress) {
                val photon = photonDeferred.await().filter { near == null || it.location.distanceTo(near) <= SUGGEST_NEAR_M }
                SearchMerge.merge(emptyList(), localAddresses, term, near, photon)
            } else {
                emptyList()
            }
            if (gen != suggestGeneration || _state.value.query.trim() != term) return@launch
            networkSuggestions = network
            val own = SuggestionPriority.select(localPool, term)
            _state.update {
                it.copy(
                    suggestions = SuggestionPriority.mergeOwn(own, network),
                    querySuggestions = if (hasGoogleRows) result.queries.take(MAX_QUERY_SUGGESTIONS) else emptyList(),
                    localSuggestionCount = own.size,
                )
            }
        }
    }

    /** A query row or category runs directly, without starting another autocomplete request. */
    fun search(query: String) {
        _state.update { it.copy(query = query) }
        submit()
    }

    /** The place row at [index], or null after the suggestions changed. */
    fun suggestion(index: Int): Place? = _state.value.suggestions.getOrNull(index)

    /**
     * The user's own places, in Android's order (recently viewed, list places, saved shortlist),
     * pushed by Swift from the saved facet. Their matching rows lead the suggestions at once, and
     * [suggestion] keeps returning them by index, so the map screen opens one like any other row.
     * The live suggestion list is recomposed here rather than waiting for the next keystroke.
     */
    fun setLocalPlaces(places: List<Place>) {
        val keys = places.map { SearchMerge.placeKey(it) }
        if (keys == localKeys) return
        localKeys = keys
        localPool = places
        val term = _state.value.query.trim()
        if (!started || term.length < 2) return
        val own = SuggestionPriority.select(places, term)
        _state.update {
            it.copy(
                suggestions = SuggestionPriority.mergeOwn(own, networkSuggestions),
                localSuggestionCount = own.size,
            )
        }
    }

    /** The localized phrase Android appends to the query for Open now (e.g. "jetzt geöffnet"). */
    fun setOpenNowPhrase(phrase: String) {
        openNowPhrase = phrase.trim().ifEmpty { "open now" }
    }

    /**
     * The results header's filters and sort. Rating, price, accessibility and sort only re-thin the
     * answer already held, like Android; Open now additionally re-runs the same query with the
     * phrase, because Google then answers with places that are open instead of the closed majority
     * a late search returns. A source that cannot honour a control (Photon without Google) drops it
     * here as well as hiding it in the sheet, so no list is wrongly emptied.
     */
    fun setFilters(openNow: Boolean, minRating: Double, priceMax: Int, accessibleOnly: Boolean, sort: Int) {
        val support = SearchFilterSupportMatrix.of(NoGoogle.enabled)
        val wanted = SearchFilters(
            openNow = openNow,
            minRating = minRating.coerceIn(0.0, 5.0),
            priceMax = priceMax.coerceIn(0, 4),
            accessibleOnly = accessibleOnly,
            sort = sort.coerceIn(SearchFilters.SORT_RELEVANCE, SearchFilters.SORT_DISTANCE),
        )
        val next = wanted.supportedBy(support)
        val previous = _state.value
        if (next == previous.filters && support == previous.filterSupport) return
        _state.update {
            it.copy(
                filters = next,
                filterSupport = support,
                results = SearchFiltering.apply(rawResults, next, now),
            )
        }
        // Android re-asks Google only when it is the source, a list is showing, and a query exists.
        val local = offline
        if (previous.filters.openNow != next.openNow && !NoGoogle.enabled && !localOnly(local) &&
            rawResults.isNotEmpty() && previous.query.trim().isNotEmpty()
        ) {
            submit()
        }
    }

    /** A selection owns the screen now: cancel autocomplete and drop its rows. */
    fun dismissSuggestions() {
        suggestJob?.cancel()
        suggestJob = null
        suggestGeneration++
        networkSuggestions = emptyList()
        _state.update {
            it.copy(suggestions = emptyList(), querySuggestions = emptyList(), localSuggestionCount = 0)
        }
    }

    /** Runs the current query. One search at a time: a new one cancels the one in flight. */
    fun submit() {
        dismissSuggestions()
        if (!started) return
        val q = _state.value.query.trim()
        if (q.isEmpty()) return
        val filters = _state.value.filters
        // Android's Open now chip rewords the same Google search; with NoGoogle the phrase would
        // only pollute a Photon query that cannot honour it, so the plain words stay.
        val requestQuery = if (NoGoogle.enabled) q
        else SearchQueryParameters.googleQuery(q, filters, openNowPhrase)
        searchJob?.cancel()
        val gen = ++generation
        val vp = viewport
        val center = vp?.let { LatLng((it[0] + it[2]) / 2, (it[1] + it[3]) / 2) }
        val near = plausibleBias(center) ?: plausibleBias(myLocation)
        val viewSpan = vp?.let { LatLng(it[0], it[1]).distanceTo(LatLng(it[2], it[1])) }
        val isAddress = AddressQuery.parse(q) != null
        val span = if (isAddress) maxOf(viewSpan ?: 0.0, ADDRESS_SEARCH_SPAN_M) else viewSpan
        val rankFrom = rankBias(near)
        // "Search this area" owns exactly the answer to the view it asked for; a later plain
        // search must not keep it, and a failed one must not narrow a later answer.
        val narrow = narrowToArea
        narrowToArea = null
        searchedArea = vp?.copyOf(4)
        moreJob?.cancel()
        moreJob = null
        // "More results" walks the same reworded request Google just answered.
        lastQuery = requestQuery
        lastNear = near
        lastSpan = span
        lastRankFrom = rankFrom
        nextPage = FIRST_MORE_PAGE
        _state.update {
            it.copy(
                searching = true, error = null, submissions = it.submissions + 1,
                moreAvailable = false, loadingMore = false, searchAreaAvailable = false,
            )
        }
        searchJob = scope.launch {
            val local = offline
            if (localOnly(local)) {
                val merged = SearchMerge.mergeCounted(
                    emptyList(), local?.let { localResults(it, q, near) }.orEmpty(), q, near, emptyList(),
                )
                val places = narrow?.let { SearchArea.narrow(merged.places, it) } ?: merged.places
                if (gen != generation) return@launch
                rawResults = places
                _state.update {
                    it.copy(
                        searching = false,
                        results = SearchFiltering.apply(places, it.filters, now),
                        usedOffline = true,
                        error = if (places.isEmpty()) SearchError.NoResults else null,
                        moreAvailable = false,
                        filterSupport = SearchFilterSupportMatrix.of(NoGoogle.enabled),
                        droppedDuplicates = merged.dropped,
                    )
                }
                return@launch
            }
            val localDeferred = async { local?.let { localResults(it, q, near) }.orEmpty() }
            // With Google on, a typed address races the source (Google) with Photon's nearby
            // houses. With NoGoogle the source IS Photon (its own NoGoogle branch asks the ranked
            // and nearby variants), so a second lookup would only duplicate the request.
            val photonDeferred = async {
                if (isAddress && !NoGoogle.enabled) photonResults(q, near, PHOTON_SEARCH_LIMIT, hardBox = false)
                else emptyList()
            }
            try {
                val result = source().search(requestQuery, near, span, rankFrom = rankFrom)
                val localPlaces = localDeferred.await()
                val photonPlaces = photonDeferred.await()
                val merged = SearchMerge.mergeCounted(result.places, localPlaces, q, near, photonPlaces)
                // Android narrows the area search to the view it asked for; the fallback keeps
                // the whole answer when nothing falls inside, so the list is never falsely empty.
                val places = narrow?.let { SearchArea.narrow(merged.places, it) } ?: merged.places
                if (gen != generation) return@launch
                rawResults = places
                _state.update {
                    it.copy(
                        searching = false,
                        results = SearchFiltering.apply(places, it.filters, now),
                        usedOffline = false,
                        error = if (places.isEmpty()) SearchError.NoResults else null,
                        // Android offers "More results" from the size of the full answer, before
                        // the area narrowed it; the row hides itself when the pages add nothing.
                        moreAvailable = !NoGoogle.enabled && merged.places.size >= MORE_MIN_RESULTS,
                        filterSupport = SearchFilterSupportMatrix.of(NoGoogle.enabled),
                        droppedDuplicates = merged.dropped,
                    )
                }
            } catch (e: CancellationException) {
                // A replaced search must not write its error over the new one.
                throw e
            } catch (e: CalibrationNeededException) {
                localDeferred.cancel()
                photonDeferred.cancel()
                if (gen == generation) fail(SearchError.NeedsRecalibration(e.message))
            } catch (e: Exception) {
                photonDeferred.cancel()
                val localPlaces = localDeferred.await()
                val merged = SearchMerge.mergeCounted(emptyList(), localPlaces, q, near, emptyList())
                val places = narrow?.let { SearchArea.narrow(merged.places, it) } ?: merged.places
                if (gen == generation) {
                    if (places.isNotEmpty()) {
                        rawResults = places
                        _state.update {
                            it.copy(
                                searching = false,
                                results = SearchFiltering.apply(places, it.filters, now),
                                usedOffline = true, error = null,
                                filterSupport = SearchFilterSupportMatrix.of(NoGoogle.enabled),
                                droppedDuplicates = merged.dropped,
                            )
                        }
                    } else fail(SearchError.Failed(e.message))
                }
            }
        }
    }

    /**
     * Android's "Search this area": re-runs the current query from the view the user panned to and
     * keeps this one answer to that view. The bias comes from the live viewport, never from the
     * request behind the old list, so the new results cannot rank around a pre-pan center
     * (issue #670). With NoGoogle the same call re-runs the Photon query with this bias; a failed
     * one clears the list instead of keeping the stale rows.
     */
    fun searchThisArea() {
        val current = _state.value
        val vp = viewport ?: return
        if (!started || current.searching || current.results.isEmpty() || current.query.trim().isEmpty()) return
        narrowToArea = vp.copyOf(4)
        _state.update { it.copy(searchAreaAvailable = false) }
        submit()
    }

    /**
     * The "More results" row: pages [nextPage] onward of the same query, appended without a
     * duplicate. Android pulls three pages per tap; an empty answer hides the row.
     */
    fun loadMore() {
        val current = _state.value
        if (!started || current.loadingMore || !current.moreAvailable || lastQuery.isEmpty()) return
        val gen = generation
        val from = nextPage
        _state.update { it.copy(loadingMore = true) }
        moreJob = scope.launch {
            val got = try {
                source().searchMore(
                    query = lastQuery, near = lastNear, spanMeters = lastSpan,
                    rankFrom = lastRankFrom, fromPage = from, pages = MORE_PAGES,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                emptyList()
            }
            if (gen != generation) return@launch
            nextPage = from + MORE_PAGES
            val before = rawResults.size
            val appended = SearchMerge.appendCounted(rawResults, got)
            rawResults = appended.places
            _state.update {
                val results = SearchFiltering.apply(rawResults, it.filters, now)
                it.copy(
                    loadingMore = false, results = results,
                    // A pull that only repeated rows already on screen adds nothing to offer.
                    moreAvailable = appended.places.size > before,
                    droppedDuplicates = it.droppedDuplicates + appended.dropped,
                    error = if (rawResults.isEmpty()) SearchError.NoResults else it.error,
                )
            }
        }
    }

    fun clear() {
        searchJob?.cancel()
        suggestJob?.cancel()
        moreJob?.cancel()
        searchJob = null
        suggestJob = null
        moreJob = null
        networkSuggestions = emptyList()
        lastQuery = ""
        nextPage = FIRST_MORE_PAGE
        rawResults = emptyList()
        searchedArea = null
        narrowToArea = null
        generation++
        suggestGeneration++
        _state.value = SearchState(filterSupport = SearchFilterSupportMatrix.of(NoGoogle.enabled))
    }

    /** The visible map: `[south, west, north, east]` and the zoom, as Android's `onViewport`. */
    fun onViewport(south: Double, west: Double, north: Double, east: Double, zoom: Double) {
        viewport = doubleArrayOf(south, west, north, east, zoom)
        // Android offers the button only after a gesture settles, so the view must really have
        // moved from the one the results were searched in. The threshold rejects a framing, a
        // gesture wobble and the first callback of a programmatic camera.
        val current = _state.value
        val armed = current.results.isNotEmpty() && !current.searching &&
            SearchArea.moved(searchedArea, viewport)
        if (armed != current.searchAreaAvailable) {
            _state.update { it.copy(searchAreaAvailable = armed) }
        }
    }

    fun onLocation(lat: Double, lng: Double) {
        myLocation = LatLng(lat, lng)
    }

    /**
     * Calls [onChange] with the current state, then with each change, on the store's thread, until
     * the returned handle is cancelled. For Swift code that cannot iterate [state] through SKIE.
     */
    fun watch(onChange: (SearchState) -> Unit): Cancellable {
        val job = scope.launch { state.collect { onChange(it) } }
        return Cancellable { job.cancel() }
    }

    /**
     * Only the installed store may answer. [OfflineSearch.offlineOnly] also covers NoGoogle, but
     * NoGoogle is not an offline request: the source then answers through Photon, and its failure
     * path falls back to [localResults]. A device without a network path fails that request at
     * once, so the installed rows still show, and [SearchState.usedOffline] says so.
     */
    private fun localOnly(local: OfflineSearch?): Boolean =
        local != null && local.offlineOnly() && !NoGoogle.enabled

    private suspend fun localResults(local: OfflineSearch, query: String, near: LatLng?): List<Place> =
        try {
            local.search(query, near)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }

    private suspend fun photonResults(query: String, near: LatLng?, limit: Int, hardBox: Boolean): List<Place> {
        val geocoder = photon ?: return emptyList()
        return try {
            geocoder(query, near, limit, hardBox)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun fail(error: SearchError) {
        rawResults = emptyList()
        _state.update {
            it.copy(
                searching = false, results = emptyList(), error = error, usedOffline = false,
                searchAreaAvailable = false, droppedDuplicates = 0,
            )
        }
    }

    private fun rankBias(near: LatLng?): LatLng? {
        val me = plausibleBias(myLocation) ?: return null
        return me.takeIf { near == null || it.distanceTo(near) < RANK_FROM_MAX_M }
    }

    companion object {
        private const val RANK_FROM_MAX_M = 50_000.0
        internal const val ADDRESS_SEARCH_SPAN_M = 40_000.0
        private const val SUGGEST_NEAR_M = 80_000.0
        private const val LOCAL_ADDRESS_LIMIT = 3
        private const val PHOTON_SUGGEST_LIMIT = 4
        private const val PHOTON_SEARCH_LIMIT = 10
        internal const val SUGGEST_DEBOUNCE_MS = 320L
        private const val MAX_QUERY_SUGGESTIONS = 3

        /** The first fetch already holds pages 0..2; "More results" starts at page 3. */
        private const val FIRST_MORE_PAGE = 3
        private const val MORE_PAGES = 3

        /** A first fetch shorter than one Google page has nothing left to page through. */
        private const val MORE_MIN_RESULTS = 20

        /** Null for a point within half a degree of 0,0: an unset location, not a place. */
        fun plausibleBias(l: LatLng?): LatLng? =
            l?.takeUnless { abs(it.lat) < 0.5 && abs(it.lng) < 0.5 }

        /** Kept for the original non-address merge tests and callers. */
        internal fun mergeResults(online: List<Place>, local: List<Place>): List<Place> =
            SearchMerge.merge(online, local, query = null, near = null, photon = emptyList())
    }
}
