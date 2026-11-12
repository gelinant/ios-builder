package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.distanceTo
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.time.TimeSource

/**
 * The one search field answers for more than places (UNIFIED-SEARCH): the user's saved places and
 * lists, their recents, the app's settings rows, a typed coordinate, transit stops and lines, a
 * Wikivoyage or Wikipedia article, and, through the existing [SearchStore], the online place and
 * address sources.
 *
 * The local part is a snapshot Swift pushes after a store change (saved, transit board, settings),
 * so a keystroke ranks it synchronously with no request and no coroutine. The online part runs
 * [UnifiedSource] implementations in parallel, each under its own deadline, and publishes every
 * answer as it lands. No source can hold the list: the field never waits on the slowest host.
 */
object UnifiedKinds {
    const val PLACE = "place"
    const val ADDRESS = "address"
    const val SAVED = "saved"
    const val LIST = "list"
    const val STOP = "stop"
    const val LINE = "line"
    const val WIKI = "wiki"
    const val SETTING = "setting"
    const val COORDINATE = "coord"

    /** A "search for this text" row: Google's own query suggestion, never a place. */
    const val QUERY = "query"
}

/**
 * One row of the unified list, as both the ranking and Swift read it. [score] is the kind's own
 * relevance (a recent place beats a wiki article), [online] decides the second tier of the order,
 * and the identity fields let the action behind the row do its work.
 */
data class UnifiedHit(
    val kind: String,
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val icon: String = "mappin",
    val score: Int = 0,
    val online: Boolean = false,
    /** Title, subtitle and extra keywords, lowercased on match. */
    val keywords: String = "",
    /** Position in [SearchStore]'s suggestion list, or -1. */
    val index: Int = -1,
    /** The text a query row searches for. */
    val query: String? = null,
    val placeId: String? = null,
    val featureId: String? = null,
    val listId: String? = null,
    val lat: Double? = null,
    val lng: Double? = null,
    val stopId: String? = null,
    /** The transit line label a line row opens. */
    val line: String? = null,
    /** The stop a line row belongs to, so its board can be opened again. */
    val stopName: String? = null,
    /** The Settings form anchor a setting row jumps to ([SettingsIndex]). */
    val anchor: String? = null,
    /** The article URL a wiki row opens. */
    val url: String? = null,
    /** The article's own description, shown in the reader. */
    val detail: String? = null,
) {
    /** What the UI test reads back: the kind, so each source can be proven separately. */
    val debugLine: String get() = "$kind|$id"
}

/** The query a source sees: the words, a bias for ranking, and the visible box for nearby data. */
data class UnifiedQuery(
    val text: String,
    val near: LatLng? = null,
    val south: Double? = null,
    val west: Double? = null,
    val north: Double? = null,
    val east: Double? = null,
    val language: String = "en",
)

/** One online source. [deadlineMs] bounds the wait; a slower answer is dropped, never awaited. */
interface UnifiedSource {
    val name: String
    val deadlineMs: Long

    suspend fun search(query: UnifiedQuery): List<UnifiedHit>
}

/** The unified field's state, mirrored by `UnifiedSearchModel` in Swift. */
data class UnifiedState(
    val query: String = "",
    val rows: List<UnifiedHit> = emptyList(),
    val localCount: Int = 0,
    /** Online sources still running; 0 once every answer landed or timed out. */
    val loading: Int = 0,
    /** Sources that hit their own deadline, comma separated, for the debug line. */
    val timedOut: String = "",
    /** Sources that failed outright, comma separated. */
    val failed: String = "",
    /** Kinds whose source finished with no match, so the panel can say why, not just "nothing". */
    val empty: List<String> = emptyList(),
    /** How long the synchronous local ranking took, in milliseconds. */
    val localMillis: Long = 0,
    /** Completed online rounds, so a test can tell a refresh from a list that never reloaded. */
    val rounds: Int = 0,
) {
    val isEmpty: Boolean get() = rows.isEmpty()
}

/**
 * Ordering and dedup across every source. The rules are SRCH-CARDS' own, extended:
 *
 * 1. exact local matches (a typed coordinate, a recent place, a saved place, a list, a setting)
 *    before every fuzzy one;
 * 2. local fuzzy matches before every online row, even an exact online one;
 * 3. inside a tier the kind's [UnifiedHit.score] decides, then the source's own order;
 * 4. a place already named by a saved place never appears a second time;
 * 5. ten local and eight online rows at most.
 */
internal object UnifiedRanking {
    const val LOCAL_LIMIT = 10
    const val ONLINE_LIMIT = 8
    private const val SAME_PLACE_M = 60.0
    private val NON_WORD = Regex("""[^\p{L}\p{N}]+""")

    /** 3 = the title is the query, 2 = a word starts with it, 1 = it appears inside. */
    fun tier(hit: UnifiedHit, query: String): Int? {
        val needle = normalize(query)
        if (needle.isEmpty()) return null
        if (hit.kind == UnifiedKinds.COORDINATE) return 3
        val title = normalize(hit.title)
        val hay = normalize("${hit.title} ${hit.subtitle.orEmpty()} ${hit.keywords}")
        if (!hay.contains(needle)) return null
        if (title == needle) return 3
        if (title.startsWith(needle) || title.contains(" $needle")) return 2
        return 1
    }

    fun rank(hits: List<UnifiedHit>, query: String, limit: Int = LOCAL_LIMIT + ONLINE_LIMIT): List<UnifiedHit> {
        val scored = hits.mapIndexedNotNull { index, hit -> tier(hit, query)?.let { Triple(hit, it, index) } }
        // A saved place wins the duplicate against any online listing, before the caps apply.
        val saved = scored.filter { it.first.kind == UnifiedKinds.SAVED }
        val kept = scored.filterNot { (hit, _, _) -> hit.online && duplicateOfSaved(hit, saved.map { it.first }) }
        val sorted = kept.sortedWith(
            compareByDescending<Triple<UnifiedHit, Int, Int>> { !it.first.online }
                .thenByDescending { it.second }
                .thenByDescending { it.first.score }
                .thenBy { it.third },
        ).distinctBy { it.first.id }
            // A stop known locally and returned by the feed is one stop, not two rows.
            .distinctBy { row ->
                val hit = row.first
                if (hit.kind == UnifiedKinds.STOP || hit.kind == UnifiedKinds.LINE) {
                    "${hit.kind}|${normalize(hit.title)}|" +
                        "${safe(hit.lat)},${safe(hit.lng)}"
                } else {
                    hit.id
                }
            }
        val local = sorted.filterNot { it.first.online }.take(LOCAL_LIMIT)
        val online = sorted.filter { it.first.online }.take(ONLINE_LIMIT)
        return (local + online).take(limit).map { it.first }
    }

    /** True when an online place is the same place a saved row already names. */
    private fun duplicateOfSaved(place: UnifiedHit, saved: List<UnifiedHit>): Boolean {
        if (place.kind != UnifiedKinds.PLACE && place.kind != UnifiedKinds.ADDRESS) return false
        val feature = place.featureId?.takeUnless { it.isBlank() }
        val name = normalize(place.title)
        return saved.any { own ->
            val ownFeature = own.featureId?.takeUnless { it.isBlank() }
            if (feature != null && ownFeature != null && feature == ownFeature) return@any true
            if (normalize(own.title) != name || name.isEmpty()) return@any false
            val lat = place.lat
            val lng = place.lng
            val ownLat = own.lat
            val ownLng = own.lng
            if (lat == null || lng == null || ownLat == null || ownLng == null) return@any true
            LatLng(lat, lng).distanceTo(LatLng(ownLat, ownLng)) < SAME_PLACE_M
        }
    }

    private fun normalize(value: String): String = value.lowercase().replace(NON_WORD, " ").trim()

    private fun safe(value: Double?): Int = ((value ?: 0.0) * 1_000.0).roundToInt()
}

/**
 * The unified field's store. Construction does nothing. [setLocal] is called by Swift whenever the
 * saved, transit or settings snapshot changes; [setQuery] on every keystroke. The local ranking is
 * synchronous, the online sources run after the same 320 ms pause as the place search.
 */
class UnifiedSearchStore(
    private val scope: CoroutineScope,
    private val sources: List<UnifiedSource> = emptyList(),
    private val debounceMs: Long = SUGGEST_DEBOUNCE_MS,
) {
    private val _state = MutableStateFlow(UnifiedState())
    val state: StateFlow<UnifiedState> = _state.asStateFlow()

    private var local: List<UnifiedHit> = emptyList()
    private var remote: List<UnifiedHit> = emptyList()
    private var online = HashMap<String, List<UnifiedHit>>()
    private var succeeded = HashSet<String>()
    private var timedOut = HashSet<String>()
    private var failed = HashSet<String>()
    private var job: Job? = null
    private var generation = 0
    private var lastQuery = ""
    private var near: LatLng? = null
    private var box: DoubleArray? = null
    private val marks = TimeSource.Monotonic

    /** The bias and the visible box the next query ranks and queries with. */
    fun setArea(nearLat: Double, nearLng: Double, south: Double, west: Double, north: Double, east: Double) {
        near = LatLng(nearLat, nearLng)
        box = doubleArrayOf(south, west, north, east)
    }

    fun clearArea() {
        near = null
        box = null
    }

    /** The saved, settings, coordinate, stop and line rows. Called on the store's thread. */
    fun setLocal(items: List<UnifiedHit>) {
        if (items == local) return
        local = items
        if (lastQuery.length >= MIN_QUERY) publish()
    }

    /** The place and query rows the existing [SearchStore] answered. */
    fun setRemote(items: List<UnifiedHit>) {
        if (items == remote) return
        remote = items
        if (lastQuery.length >= MIN_QUERY) publish()
    }

    fun setQuery(text: String) {
        val term = text.trim()
        if (term == lastQuery && job?.isActive == true) return
        lastQuery = term
        job?.cancel()
        job = null
        val gen = ++generation
        online = HashMap()
        succeeded = HashSet()
        timedOut = HashSet()
        failed = HashSet()
        if (term.length < MIN_QUERY) {
            _state.update {
                it.copy(
                    query = term, rows = emptyList(), localCount = 0, loading = 0,
                    timedOut = "", failed = "", empty = emptyList(),
                )
            }
            return
        }
        val mark = marks.markNow()
        publish()
        _state.update { it.copy(localMillis = mark.elapsedNow().inWholeMilliseconds) }
        // A typed coordinate is answered locally and completely; no host is asked for it.
        if (sources.isEmpty() || UnifiedCoordinates.parse(term) != null) return
        job = scope.launch {
            delay(debounceMs)
            if (gen != generation) return@launch
            runSources(gen, queryOf(term))
        }
    }

    /** Re-runs the online sources for the current words, without waiting for a keystroke. */
    fun refreshOnline() {
        val term = lastQuery
        if (term.length < MIN_QUERY || sources.isEmpty() || UnifiedCoordinates.parse(term) != null) return
        val gen = ++generation
        job?.cancel()
        online = HashMap()
        succeeded = HashSet()
        timedOut = HashSet()
        failed = HashSet()
        job = scope.launch { runSources(gen, queryOf(term)) }
    }

    private fun queryOf(term: String): UnifiedQuery = UnifiedQuery(
        text = term,
        near = near,
        south = box?.getOrNull(0),
        west = box?.getOrNull(1),
        north = box?.getOrNull(2),
        east = box?.getOrNull(3),
    )

    fun clear() {
        job?.cancel()
        job = null
        generation++
        lastQuery = ""
        remote = emptyList()
        online = HashMap()
        succeeded = HashSet()
        timedOut = HashSet()
        failed = HashSet()
        _state.value = UnifiedState()
    }

    /**
     * The online round: every source in parallel, each under its own deadline, and each answer
     * published the moment it lands. A slow host therefore adds rows late; it never holds the
     * rows of the sources that already answered.
     */
    private suspend fun runSources(gen: Int, query: UnifiedQuery) = coroutineScope {
        val active = sources.map { it.name }.toHashSet()
        _state.update {
            it.copy(loading = active.size, timedOut = "", failed = "", empty = emptyList())
        }
        for (source in sources) {
            launch {
                var threw = false
                val hits = try {
                    // A null here is the deadline firing; a thrown error is the source failing.
                    withTimeoutOrNull(source.deadlineMs) { source.search(query) }
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    threw = true
                    null
                }
                if (gen != generation) return@launch
                when {
                    threw -> failed += source.name
                    hits == null -> timedOut += source.name
                    else -> {
                        online[source.name] = hits.filter { it.online }
                        succeeded += source.name
                    }
                }
                active.remove(source.name)
                publish()
                _state.update {
                    it.copy(
                        loading = active.size,
                        timedOut = timedOut.sorted().joinToString(","),
                        failed = failed.sorted().joinToString(","),
                        rounds = if (active.isEmpty()) it.rounds + 1 else it.rounds,
                    )
                }
            }
        }
    }

    private fun publish() {
        // The coordinate row needs no source: it is the query itself.
        val coordinate = UnifiedCoordinates.parse(lastQuery)?.let {
            listOf(UnifiedHits.coordinate(it.lat, it.lng))
        }.orEmpty()
        val merged = local + remote + online.values.flatten() + coordinate
        val rows = UnifiedRanking.rank(merged, lastQuery)
        val empty = ArrayList<String>()
        if (lastQuery.length >= MIN_QUERY && UnifiedCoordinates.parse(lastQuery) == null) {
            if (local.any { it.kind == UnifiedKinds.SAVED || it.kind == UnifiedKinds.LIST } &&
                rows.none { it.kind == UnifiedKinds.SAVED || it.kind == UnifiedKinds.LIST }
            ) {
                empty += UnifiedKinds.SAVED
            }
            if (succeeded.contains(UnifiedSources.TRANSIT) && rows.none { it.kind == UnifiedKinds.STOP }) {
                empty += UnifiedKinds.STOP
            }
            if (succeeded.contains(UnifiedSources.WIKI) && rows.none { it.kind == UnifiedKinds.WIKI }) {
                empty += UnifiedKinds.WIKI
            }
        }
        val localCount = rows.count { !it.online }
        _state.update {
            it.copy(query = lastQuery, rows = rows, localCount = localCount, empty = empty)
        }
    }

    companion object {
        internal const val MIN_QUERY = 2
        internal const val SUGGEST_DEBOUNCE_MS = 320L
    }
}

/** The names the empty states and the debug line key on, one per online source. */
object UnifiedSources {
    const val TRANSIT = "transit"
    const val WIKI = "wiki"
}

/** Builders for the rows Swift pushes, so the Swift side never repeats a score or an icon. */
object UnifiedHits {
    fun recent(id: String, title: String, subtitle: String?, lat: Double, lng: Double, placeId: String, featureId: String?): UnifiedHit =
        UnifiedHit(
            kind = UnifiedKinds.SAVED, id = "recent:$id", title = title, subtitle = subtitle,
            icon = "clock.arrow.circlepath", score = 95, keywords = "recent history", placeId = placeId,
            featureId = featureId, lat = lat, lng = lng,
        )

    fun saved(
        id: String, title: String, subtitle: String?, lat: Double, lng: Double, placeId: String,
        featureId: String?, listId: String?,
    ): UnifiedHit = UnifiedHit(
        kind = UnifiedKinds.SAVED, id = "saved:$id", title = title, subtitle = subtitle,
        icon = "bookmark.fill", score = 90, keywords = "saved bookmark", placeId = placeId,
        featureId = featureId, listId = listId, lat = lat, lng = lng,
    )

    fun list(id: String, name: String, count: Int): UnifiedHit = UnifiedHit(
        kind = UnifiedKinds.LIST, id = "list:$id", title = name,
        subtitle = if (count == 1) "List, 1 place" else "List, $count places",
        icon = "list.bullet", score = 85, keywords = "list saved", listId = id,
    )

    fun setting(anchor: String, label: String, section: String, keywords: String): UnifiedHit = UnifiedHit(
        kind = UnifiedKinds.SETTING, id = "setting:$anchor", title = label,
        subtitle = "Settings > $section", icon = "gearshape", score = 80,
        keywords = "$section $keywords", anchor = anchor,
    )

    /** A stop the app already knows locally (a map pin or the last opened board). */
    fun localStop(id: String, name: String, subtitle: String?, lat: Double, lng: Double): UnifiedHit =
        UnifiedHit(
            kind = UnifiedKinds.STOP, id = "stop:$id", title = name, subtitle = subtitle,
            icon = "bus.fill", score = 70, keywords = "transit stop departures", lat = lat, lng = lng,
            stopId = id,
        )

    fun stop(id: String, name: String, subtitle: String?, lat: Double, lng: Double): UnifiedHit =
        UnifiedHit(
            kind = UnifiedKinds.STOP, id = "stop:$id", title = name, subtitle = subtitle,
            icon = "bus.fill", score = 68, online = true, keywords = "transit stop departures",
            lat = lat, lng = lng, stopId = id,
        )

    fun line(
        id: String, label: String, headsign: String?, stopName: String, lat: Double, lng: Double,
        detail: String?,
    ): UnifiedHit = UnifiedHit(
        kind = UnifiedKinds.LINE, id = "line:$id", title = label,
        subtitle = listOfNotNull(headsign, stopName).joinToString(" · ").ifBlank { null },
        icon = "tram.fill", score = 65, keywords = "transit line departures $stopName",
        lat = lat, lng = lng, line = label, stopName = stopName, detail = detail,
    )

    fun wiki(
        title: String, detail: String?, url: String, language: String, lat: Double?, lng: Double?,
        score: Int = 60,
    ): UnifiedHit =
        UnifiedHit(
            kind = UnifiedKinds.WIKI, id = "wiki:$language:$title", title = title,
            subtitle = detail?.takeUnless { it.isBlank() },
            icon = "globe.europe.africa", score = score, online = true,
            keywords = "wikivoyage wikipedia article $language", lat = lat, lng = lng, url = url,
            detail = detail,
        )

    fun place(
        index: Int, title: String, subtitle: String?, lat: Double, lng: Double,
        featureId: String?, address: Boolean,
    ): UnifiedHit = UnifiedHit(
        kind = if (address) UnifiedKinds.ADDRESS else UnifiedKinds.PLACE, id = "place:$index:$title",
        title = title, subtitle = subtitle, icon = if (address) "mappin.and.ellipse" else "mappin.circle.fill",
        score = if (address) 48 else 50, online = true, keywords = "place address", index = index,
        featureId = featureId, lat = lat, lng = lng,
    )

    fun query(text: String): UnifiedHit = UnifiedHit(
        kind = UnifiedKinds.QUERY, id = "query:$text", title = text, subtitle = "Search",
        icon = "magnifyingglass", score = 40, online = true, query = text,
    )

    fun coordinate(lat: Double, lng: Double): UnifiedHit = UnifiedHit(
        kind = UnifiedKinds.COORDINATE, id = "coord:$lat,$lng",
        title = "${fixed(lat)}, ${fixed(lng)}", subtitle = "Coordinate · dropped pin",
        icon = "scope", score = 100, keywords = "coordinate gps", lat = lat, lng = lng,
    )

    private fun fixed(value: Double): String {
        val scaled = (value * 100_000).roundToLong()
        val sign = if (scaled < 0) "-" else ""
        val abs = abs(scaled)
        return "$sign${abs / 100_000}." + (abs % 100_000).toString().padStart(5, '0')
    }
}

/**
 * A coordinate typed or pasted. Decimal degrees only, with an optional `geo:` prefix, an optional
 * degree sign, a comma, semicolon or space between the pair, optional N/S/E/W letters and an
 * optional altitude. No degrees-minutes-seconds form: that would guess at a notation the user did
 * not mean.
 */
object UnifiedCoordinates {
    fun parse(text: String): LatLng? {
        val body = text.trim().removePrefix("geo:").removeSuffix("/")
        if (body.isEmpty()) return null
        val parts = body.replace("°", " ").split(Regex("[,\\s]+")).filter { it.isNotEmpty() }
        if (parts.size < 2 || parts.size > 4) return null
        var latSign = 1.0
        var lngSign = 1.0
        val numbers = ArrayList<Double>(2)
        for (part in parts) {
            when (part.uppercase()) {
                "N" -> latSign = 1.0
                "S" -> latSign = -1.0
                "E" -> lngSign = 1.0
                "W" -> lngSign = -1.0
                else -> numbers += part.toDoubleOrNull() ?: return null
            }
        }
        if (numbers.size !in 2..3) return null
        val lat = numbers[0] * latSign
        val lng = numbers[1] * lngSign
        if (lat !in -90.0..90.0 || lng !in -180.0..180.0) return null
        return LatLng(lat, lng)
    }
}
