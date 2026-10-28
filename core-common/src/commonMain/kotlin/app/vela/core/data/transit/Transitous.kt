package app.vela.core.data.transit

import app.vela.core.model.StopDeparture
import app.vela.core.model.distanceTo
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitLine
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import app.vela.core.model.TransitItinerary
import app.vela.core.model.LatLng
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.NormalForm
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.TextNormalizer
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.util.UrlCodec
import app.vela.core.util.decodeFromBytes
import app.vela.core.util.toRadians
import kotlin.concurrent.Volatile
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sqrt
import kotlin.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

/** What every [Transitous] request goes through: the client, and the app language each request
 *  asks for ([PlatformLocale.defaultLanguage]). [text] folds stop names ([Transitous.stopKey]). */
class TransitousHttp(val http: VelaHttp, val locale: PlatformLocale, val text: TextNormalizer)

/**
 * **Transitous** (transitous.org) - the community-run, keyless public-transit API over the world's
 * open GTFS + GTFS-Realtime feeds (MOTIS server). It is to transit what FOSSGIS OSRM is to road
 * routing: canonical agency data, no account, fair-use community hosting.
 *
 * This client covers Vela's DEPARTURE BOARDS (phase 1 of the Transitous adoption): [board] finds the
 * stop(s) at a coordinate via `map/stops` and reads `stoptimes` - which, unlike Google's anonymous
 * place page, returns EVERY route serving the stop, with realtime flags and the agency's own route
 * colors. Querying a stop's PARENT station id aggregates all its child stops/bays (verified live),
 * so a multi-bay transit center gets one complete merged board for free.
 *
 * Google's blob parse stays as the FALLBACK where Transitous has no coverage. Fair use: one fetch
 * per opened stop plus a 30 s refresh while its sheet stays open (the VM's startBoardRefresh, same
 * cadence as the countdown clock, self-canceling on selection change); the User-Agent identifies
 * the app per the Transitous policy.
 */
object Transitous {
    // The community instance. A self-hosted MOTIS is a drop-in swap if Vela ever outgrows fair use.
    const val BASE = "https://api.transitous.org"
    // Single-sourced: Transitous is community infrastructure under fair use, so its contact string
    // must not drift from the app's real version the way the Overpass/Nominatim copies had.
    private val UA: String get() = app.vela.core.VelaConfig.VELA_UA
    private val json = Json { ignoreUnknownKeys = true }

    // --- wire DTOs (only the fields Vela reads) --------------------------------------------------

    @Serializable
    data class MapStop(
        val name: String = "",
        val stopId: String = "",
        val parentId: String? = null,
        val lat: Double = 0.0,
        val lon: Double = 0.0,
        // What stops here ("BUS", "SUBWAY", "TRAM", "REGIONAL_RAIL", ...), as the service names them.
        val modes: List<String> = emptyList(),
        // Same-named directional siblings folded into this icon (never on the wire - filled by
        // mergeDirectionalPairs). Their boards merge into this stop's board.
        val siblingIds: List<String> = emptyList(),
    )

    @Serializable
    private data class StopTimesResp(val stopTimes: List<StopTime> = emptyList())

    @Serializable
    data class StopTime(
        val place: StPlace = StPlace(),
        val mode: String? = null,
        val realTime: Boolean = false,
        val headsign: String? = null,
        val routeShortName: String? = null,
        val routeColor: String? = null,
        val tripId: String? = null,       // keys the /trip stop-sequence fetch
        val cancelled: Boolean = false,   // this stop's call is canceled (MOTIS spells the wire field with two Ls - do not Americanize these four)
        val tripCancelled: Boolean = false, // the whole run is canceled
    )

    @Serializable
    data class StPlace(
        val departure: String? = null,
        val scheduledDeparture: String? = null,
        val tz: String? = null,
        val cancelled: Boolean = false,
    )

    // --- API --------------------------------------------------------------------------------------

    /** All transit stops inside the bbox. Null on FAILURE (network/decode) vs empty on a clean
     *  "no stops here" - callers area-cache success only, like the traffic-controls layer. */
    suspend fun stopsInBox(http: TransitousHttp, south: Double, west: Double, north: Double, east: Double): List<MapStop>? {
        val body = get(http, "$BASE/api/v1/map/stops?min=$south,$west&max=$north,$east") ?: return null
        return runCatching { json.decodeFromString<List<MapStop>>(body.decodeToString()) }.getOrNull()
    }

    /** Which of the three kinds the map lets a rider pick a stop or a line belongs to. */
    enum class Kind { BUS, METRO, TRAIN }

    /** The kind a service mode name is: metro covers subway, tram, light rail, funicular and
     *  cable car; train every kind of rail; everything on a road is a bus. Null for boats and air. */
    fun kindOf(mode: String): Kind? = when {
        mode == "SUBWAY" || mode == "METRO" || mode == "TRAM" || mode == "FUNICULAR" || mode == "CABLE_CAR" || mode == "AERIAL_LIFT" -> Kind.METRO
        mode.contains("RAIL") || mode == "SUBURBAN" || mode == "LONG_DISTANCE" || mode == "TRANSIT" -> Kind.TRAIN
        mode == "BUS" || mode == "COACH" || mode == "ODM" || mode == "FLEX" -> Kind.BUS
        else -> null
    }

    /** One stretch of track with the colors of the lines that run on it. */
    data class MapLine(
        val points: List<LatLng>,
        val colors: List<String>,
        val kind: Kind,
        /** The metro lines on this stretch as (short name, "#rrggbb"), sorted the way a station
         *  sign lists them (numbers, then letters). Empty for trains. */
        val labels: List<Pair<String, String>> = emptyList(),
    )

    @Serializable private data class RoutesReply(val routes: List<RouteDto> = emptyList(), val polylines: List<PolyDto> = emptyList())
    // pathSource: where the route's drawn path came from. "NONE" is a straight line from stop to stop.
    @Serializable private data class RouteDto(val mode: String = "", val transitRoutes: List<RouteNameDto> = emptyList(), val pathSource: String? = null)
    @Serializable private data class RouteNameDto(val color: String? = null, val shortName: String? = null)
    @Serializable private data class PolyDto(val polyline: EncodedDto = EncodedDto(), val routeIndexes: List<Int> = emptyList())
    @Serializable private data class EncodedDto(val points: String = "", val precision: Int = 6)

    /**
     * The rail lines in a box, each stretch with its lines' own colors (discussion #648): the
     * service's `map/routes`, which answers every route's shape in the box. Buses, coaches and
     * boats are dropped here (most of the answer); what is left is metro and train track,
     * thinned to [LINE_SIMPLIFY_M]. [zoom] is the service's own filter: under about 9 it sends
     * long-distance rail only, which keeps a wide view's answer small. Null on any failure.
     * The endpoint is marked experimental upstream, so a changed shape reads as "no lines" and
     * the map keeps its plain rail highlight. A call has [LINES_TIMEOUT_MS], no language.
     */
    suspend fun linesInBox(http: TransitousHttp, south: Double, west: Double, north: Double, east: Double, zoom: Int): List<MapLine>? {
        val body = fetch(http, "$BASE/api/experimental/map/routes?min=$south,$west&max=$north,$east&zoom=$zoom", LINES_TIMEOUT_MS) ?: return null
        // Decoded from the bytes: a city's answer is megabytes, and no String copy is made.
        return runCatching { linesOf(json.decodeFromBytes(RoutesReply.serializer(), body)) }.getOrNull()
    }

    /** The call deadline of [linesInBox]: a city cell is 2 to 4 MB. */
    const val LINES_TIMEOUT_MS = 40_000L

    /** Public for the parser test. */
    fun parseLines(text: String): List<MapLine> = runCatching { linesOf(json.decodeFromString(RoutesReply.serializer(), text)) }.getOrDefault(emptyList())

    private fun linesOf(reply: RoutesReply): List<MapLine> {
        val out = ArrayList<MapLine>()
        for (p in reply.polylines) {
            val routes = p.routeIndexes.mapNotNull { reply.routes.getOrNull(it) }
            val rail = routes.filter { kindOf(it.mode).let { k -> k == Kind.METRO || k == Kind.TRAIN } }
            if (rail.isEmpty()) continue
            val kind = if (rail.any { kindOf(it.mode) == Kind.METRO }) Kind.METRO else Kind.TRAIN
            val colors = rail.mapNotNull { r -> r.transitRoutes.firstOrNull()?.color?.trim()?.lowercase()?.takeIf { c -> c.length == 6 && c.all { it in '0'..'9' || it in 'a'..'f' } } }
                .distinct().take(MAX_LINE_COLORS).map { "#$it" }
            // Line letters for the metro stretches (#648: same-color lines like the M and F could
            // not be told apart; shared colors are one strand, so only a name tells them apart).
            val labels = rail.filter { kindOf(it.mode) == Kind.METRO }.mapNotNull { r ->
                val t = r.transitRoutes.firstOrNull() ?: return@mapNotNull null
                val name = t.shortName?.trim()?.takeIf { it.isNotEmpty() && it.length <= MAX_LABEL_CHARS } ?: return@mapNotNull null
                val c = t.color?.trim()?.lowercase()?.takeIf { c -> c.length == 6 && c.all { it in '0'..'9' || it in 'a'..'f' } }
                name to (if (c != null) "#$c" else "#9AA0A6")
            }.distinctBy { it.first }
                // An express variant ("6X", "FX") is the same line as its base: list the base once.
                .let { all -> val names = all.map { it.first }.toSet(); all.filterNot { it.first.length > 1 && it.first.endsWith("X") && it.first.dropLast(1) in names } }
                .sortedWith(compareBy<Pair<String, String>>({ it.first.toIntOrNull() == null }, { it.first.toIntOrNull() ?: 0 }, { it.first }))
                .take(MAX_LABELS)
            val pts = runCatching { app.vela.core.data.google.PolylineCodec.decode(p.polyline.points, p.polyline.precision) }.getOrNull() ?: continue
            if (pts.size < 2) continue
            // A feed with no shapes gives a straight chord from stop to stop. Between two subway
            // stations that is close enough; between two cities it is a ruler line across the
            // map (a first look at Manhattan was a fan of them), so sparse long ones are left out.
            // A shape can also be dense through the city and one ruler jump out to the suburbs,
            // which the average hides (discussion #648: commuter rail drew straight lines out of
            // Manhattan). Cut it at every gap over CHORD_SPLIT_M and judge each run on its own.
            // The spacing test is for trains, and for a metro stretch the service has no path
            // for. The service answers one polyline per pair of stops, so straight metro track
            // between two stations is two points, the same as a chord. Dropping it leaves a hole:
            // the plain highlight is hidden for the whole kind while colored lines are in view.
            val spacingTest = kind == Kind.TRAIN || rail.all { it.pathSource == PATH_NONE }
            var run = ArrayList<LatLng>()
            fun flush() {
                if (run.size >= 2) {
                    var len = 0.0
                    for (i in 1 until run.size) len += distM(run[i - 1].lat, run[i - 1].lng, run[i].lat, run[i].lng)
                    if (!spacingTest || len / (run.size - 1) <= CHORD_MAX_M) out += MapLine(simplify(run, LINE_SIMPLIFY_M), colors, kind, labels)
                }
                run = ArrayList()
            }
            for (i in pts.indices) {
                if (i > 0 && distM(pts[i - 1].lat, pts[i - 1].lng, pts[i].lat, pts[i].lng) > CHORD_SPLIT_M) flush()
                run.add(pts[i])
            }
            flush()
        }
        return out
    }

    const val MAX_LINE_COLORS = 4
    /** Line letters shown per stretch, and the longest short name that counts as a letter. */
    const val MAX_LABELS = 6
    private const val MAX_LABEL_CHARS = 3
    private const val LINE_SIMPLIFY_M = 4.0
    /** Average spacing of a shape's points above which it is a chord, not a drawn track. Applied
     *  to trains, and to a metro stretch whose routes all report [PATH_NONE]. */
    private const val CHORD_MAX_M = 700.0
    /** The service's `pathSource` for a route with no path: straight lines from stop to stop. */
    private const val PATH_NONE = "NONE"
    /** A single gap this long between two points of a shape is a chord: the shape is cut there.
     *  Above a long bridge's one straight hop (2 to 2.5 km over the East River: at 2 km the subway
     *  lines stopped at the water, #648), far below a ruler line between towns (15 km and more). */
    private const val CHORD_SPLIT_M = 4000.0

    /** Douglas-Peucker: drops points that sit within [tolM] of the line through their neighbors. */
    internal fun simplify(pts: List<LatLng>, tolM: Double): List<LatLng> {
        if (pts.size <= 2) return pts
        val keep = BooleanArray(pts.size); keep[0] = true; keep[pts.lastIndex] = true
        val stack = ArrayDeque<Pair<Int, Int>>(); stack.addLast(0 to pts.lastIndex)
        val k = cos(pts[0].lat.toRadians())
        fun off(p: LatLng, a: LatLng, b: LatLng): Double {
            val ax = (a.lng - p.lng) * k * 111_320.0; val ay = (a.lat - p.lat) * 111_320.0
            val bx = (b.lng - p.lng) * k * 111_320.0; val by = (b.lat - p.lat) * 111_320.0
            val dx = bx - ax; val dy = by - ay; val l2 = dx * dx + dy * dy
            val t = if (l2 == 0.0) 0.0 else (-(ax * dx + ay * dy) / l2).coerceIn(0.0, 1.0)
            return hypot(ax + t * dx, ay + t * dy)
        }
        while (stack.isNotEmpty()) {
            val (i, j) = stack.removeLast()
            var worst = -1; var worstD = tolM
            for (m in i + 1 until j) { val d = off(pts[m], pts[i], pts[j]); if (d > worstD) { worstD = d; worst = m } }
            if (worst >= 0) { keep[worst] = true; stack.addLast(i to worst); stack.addLast(worst to j) }
        }
        return pts.filterIndexed { idx, _ -> keep[idx] }
    }

    /** Transit stops within roughly [radiusM] of the point, nearest first. Empty on any failure. */
    suspend fun stopsNear(http: TransitousHttp, lat: Double, lng: Double, radiusM: Double = 200.0): List<MapStop> {
        val dLat = radiusM / 111_320.0
        val dLng = radiusM / (111_320.0 * cos(lat.toRadians()))
        return stopsInBox(http, lat - dLat, lng - dLng, lat + dLat, lng + dLng).orEmpty()
            .sortedBy { distM(lat, lng, it.lat, it.lon) }
    }

    /** The board for a KNOWN stop (a tapped map icon) - no proximity lookup needed. Queries the
     *  parent station when the stop has one, so a hub icon shows the whole merged board. */
    suspend fun boardFor(http: TransitousHttp, stop: MapStop, timeEpochSec: Long? = null): StopDepartures? {
        val ids = (listOf(stop.parentId ?: stop.stopId) + stop.siblingIds).distinct()
        val times = timesFor(http, ids, timeEpochSec).ifEmpty { return null }
        return buildBoard(times, stationName = stop.name)
    }

    /** Departures for every id, all fetched at once, in id order. */
    private suspend fun timesFor(http: TransitousHttp, ids: List<String>, timeEpochSec: Long? = null): List<StopTime> =
        if (ids.size <= 1) ids.flatMap { stopTimes(http, it, timeEpochSec = timeEpochSec) }
        else coroutineScope { ids.map { id -> async { stopTimes(http, id, timeEpochSec = timeEpochSec) } }.awaitAll().flatten() }

    /** The next [n] departures at [stopId] (a parent-station id aggregates all its child stops),
     *  from now or from [timeEpochSec]. */
    suspend fun stopTimes(http: TransitousHttp, stopId: String, n: Int = 50, timeEpochSec: Long? = null): List<StopTime> {
        val url = "$BASE/api/v1/stoptimes?stopId=${UrlCodec.encode(stopId)}&n=$n" +
            (timeEpochSec?.let { "&time=" + instantText(it) } ?: "")
        val body = get(http, url) ?: return emptyList()
        return runCatching { json.decodeFromString<StopTimesResp>(body.decodeToString()).stopTimes }.getOrDefault(emptyList())
    }

    /**
     * The full departure board for the stop at ([lat], [lng]): nearest stop GROUP within ~200 m
     * (grouped by parent station so a hub's bays merge into one board), grouped by (route, headsign)
     * into the same [StopDepartures] model the Google-blob parser feeds - the whole board UI (pills,
     * countdowns, day markers) renders it unchanged. Null when Transitous has nothing here (no
     * coverage, no stop, network failure) - the caller falls back to the Google path.
     */
    suspend fun board(http: TransitousHttp, lat: Double, lng: Double, timeEpochSec: Long? = null): StopDepartures? {
        val stops = stopsNear(http, lat, lng)
        if (stops.isEmpty()) return null
        // Prefer the nearest stop's PARENT station (aggregates every bay), and fold in any
        // same-named sibling nearby - the two curbs of a directional pair - so one board carries
        // both directions, told apart by their headsigns (Google's treatment).
        val nearest = stops.first()
        val key = stopKey(nearest.name, http.text)
        val ids = stops
            .filter { (stopKey(it.name, http.text) == key && distM(nearest.lat, nearest.lon, it.lat, it.lon) < PAIR_MERGE_M) ||
                distM(nearest.lat, nearest.lon, it.lat, it.lon) < COLOCATED_M }
            .map { it.parentId ?: it.stopId }
            .distinct()
        val times = timesFor(http, ids, timeEpochSec).ifEmpty { return null }
        return buildBoard(times, stationName = nearest.name)
    }

    /** Fold same-named stops within [radiusM] into ONE map icon at the cluster midpoint, carrying
     *  the rest as [MapStop.siblingIds] - the two curbs of a directional pair become one stop like
     *  Google's POI, and the merged board's headsigns tell the directions apart. Distinct names
     *  (a "NB Station"/"SB Station" pair) and far-apart same names both stay separate. */
    fun mergeDirectionalPairs(stops: List<MapStop>, text: TextNormalizer, radiusM: Double = PAIR_MERGE_M): List<MapStop> =
        mergeColocated(stops).groupBy { stopKey(it.name, text) }.flatMap { (_, group) ->
            if (group.size < 2) return@flatMap group
            val clusters = mutableListOf<MutableList<MapStop>>()
            for (st in group) {
                val home = clusters.firstOrNull { cl ->
                    cl.any { distM(it.lat, it.lon, st.lat, st.lon) < radiusM }
                }
                if (home != null) home.add(st) else clusters.add(mutableListOf(st))
            }
            clusters.map { cl ->
                if (cl.size == 1) cl.first()
                else cl.first().copy(
                    name = displayName(cl.map { it.name }),
                    lat = cl.sumOf { it.lat } / cl.size,
                    lon = cl.sumOf { it.lon } / cl.size,
                    siblingIds = (cl.drop(1).map { it.stopId } + cl.flatMap { it.siblingIds }).distinct(),
                )
            }
        }.map { if (it.name == it.name.uppercase() && it.name.any(Char::isLetter)) it.copy(name = displayName(listOf(it.name))) else it }

    /**
     * ONE PHYSICAL STOP, SEVERAL FEEDS (2026-09-22, user: "bus icons right next to each other on the
     * same side of the same block" in Midtown). MTA publishes a GTFS feed per borough plus MTA Bus
     * Company, and a Manhattan corner served by an express route appears in two or three of them at
     * the SAME coordinate; NY Waterway lists it again under "E 42nd St & Madison Ave", and Times
     * Square is four subway stations on one point. Stops within [COLOCATED_M] fold whatever their
     * names (132 stops around Bryant Park, 107 pairs within 30 m). The radius stays tiny on purpose:
     * a BRT's NB and SB platforms ~11 m apart are separate stops with separate names.
     */
    fun mergeColocated(stops: List<MapStop>): List<MapStop> {
        val clusters = mutableListOf<MutableList<MapStop>>()
        for (st in stops) {
            val home = clusters.firstOrNull { cl -> cl.any { distM(it.lat, it.lon, st.lat, st.lon) < COLOCATED_M } }
            if (home != null) home.add(st) else clusters.add(mutableListOf(st))
        }
        return clusters.map { cl ->
            if (cl.size == 1) cl.first()
            else cl.first().copy(
                name = displayName(cl.map { it.name }),
                siblingIds = (cl.drop(1).map { it.stopId } + cl.flatMap { it.siblingIds }).distinct(),
            )
        }
    }

    /** The comparison key for a stop name: case, "42nd" / "42", "&" / "/" / "at", street-type and
     *  compass abbreviations, and the ORDER of the two cross streets all stop mattering, so
     *  "E 42nd St & Madison Ave" and "MADISON AV/E 42 ST" are one corner. Direction suffixes
     *  ("NB", "SB") are kept, so a directional pair with distinct names stays two stops. */
    fun stopKey(name: String, text: TextNormalizer): String {
        var s = text.normalize(name, NormalForm.NFKD).replace(MARKS, "").lowercase()
        s = s.replace(JOINERS, "/")
        s = s.replace(ORDINAL, "$1")
        return s.split('/').map { part ->
            part.replace(NON_WORD, " ").split(SPACES).filter { it.isNotEmpty() }
                .joinToString(" ") { STOP_ABBREV[it] ?: it }
        }.filter { it.isNotEmpty() }.sorted().joinToString("|")
    }

    private val MARKS = Regex("\\p{M}+")
    private val JOINERS = Regex("\\s*(&|@|/|\\+)\\s*|\\s+(and|at)\\s+")
    private val ORDINAL = Regex("\\b(\\d+)(st|nd|rd|th)\\b")
    private val NON_WORD = Regex("[^\\p{L}\\p{N} ]")
    private val SPACES = Regex("\\s+")
    private val AFTER_SLASH = Regex("/(\\p{Ll})")
    private val STOP_ABBREV = mapOf(
        "street" to "st", "avenue" to "av", "ave" to "av", "boulevard" to "blvd", "road" to "rd", "place" to "pl",
        "drive" to "dr", "parkway" to "pkwy", "square" to "sq", "east" to "e", "west" to "w", "north" to "n", "south" to "s",
    )

    /** The name to show for a merged stop: a mixed-case name when any feed has one (the MTA's bus
     *  feeds are ALL CAPS), else the first name in title case ("W 42 ST/5 AV" -> "W 42 St/5 Av"). */
    fun displayName(names: List<String>): String {
        val mixed = names.firstOrNull { n -> n != n.uppercase() && n.any(Char::isLetter) }
        if (mixed != null) return mixed
        val n = names.first()
        return n.lowercase().split(' ').joinToString(" ") { w -> w.replaceFirstChar { it.titlecase() } }
            .replace(AFTER_SLASH) { "/" + it.groupValues[1].uppercase() }
    }

    private const val PAIR_MERGE_M = 160.0
    private const val LAP_SAME_STOP_M = 30.0
    private const val COLOCATED_M = 3.0

    /** Pure grouping of raw stop times into the board model (unit-tested; no network). */
    internal fun buildBoard(times: List<StopTime>, stationName: String?): StopDepartures? {
        data class Key(val label: String?, val headsign: String?)
        val groups = LinkedHashMap<Key, MutableList<StopTime>>()
        for (t in times) {
            if (t.place.cancelled || t.cancelled || t.tripCancelled) continue
            groups.getOrPut(Key(t.routeShortName, t.headsign)) { mutableListOf() }.add(t)
        }
        if (groups.isEmpty()) return null
        val lines = groups.map { (k, ts) ->
            val deps = ts.mapNotNull { t ->
                val iso = t.place.departure ?: t.place.scheduledDeparture ?: return@mapNotNull null
                val epoch = parseIso(iso) ?: return@mapNotNull null
                StopDeparture(
                    clockText = clockText(epoch, t.place.tz),
                    epochSec = epoch,
                    // realTime = the feed is live-tracking this run; that's the green-dot signal.
                    realtime = t.realTime,
                    tripId = t.tripId,
                )
            }.sortedBy { it.epochSec ?: Long.MAX_VALUE }
                // Two agencies (or a parent + its curb twin) can both publish the same physical
                // stop, and the sibling merge then feeds the same run in twice - every departure
                // showed doubled (7:25, 7:25, 8:23, 8:23; device-seen 2026-07-13). Same line +
                // same departure minute is the same bus regardless of which feed copy it rode in
                // on, so collapse on the epoch (tripIds differ across agency copies - can't key
                // on those).
                .distinctBy { it.epochSec }
            StopDepartureLine(
                label = k.label,
                mode = modeOf(ts.firstOrNull()?.mode),
                headsign = k.headsign,
                colorHex = ts.firstOrNull()?.routeColor?.takeIf { it.isNotBlank() }?.let { if (it.startsWith("#")) it else "#$it" },
                headwayText = null,
                upcoming = deps,
            )
        }
            .filter { it.upcoming.isNotEmpty() }
            .sortedBy { it.upcoming.firstOrNull()?.epochSec ?: Long.MAX_VALUE }
        if (lines.isEmpty()) return null
        return StopDepartures(stationName = stationName?.takeIf { it.isNotBlank() }, lines = lines)
    }

    // --- trip stop sequence (the "Stops" timeline) -------------------------------------------------

    @Serializable
    private data class TripResp(val legs: List<TripLeg> = emptyList())

    @Serializable
    data class TripLeg(
        val from: TripStop = TripStop(),
        val to: TripStop = TripStop(),
        val intermediateStops: List<TripStop> = emptyList(),
        val mode: String? = null,
        val headsign: String? = null,
        val routeShortName: String? = null,
        val displayName: String? = null,
        val routeColor: String? = null,
        val routeTextColor: String? = null,
        val realTime: Boolean = false,
        val cancelled: Boolean = false,
    )

    @Serializable
    data class TripStop(
        val name: String = "",
        val stopId: String = "",
        val lat: Double = 0.0,
        val lon: Double = 0.0,
        val arrival: String? = null,
        val departure: String? = null,
        val scheduledArrival: String? = null,
        val scheduledDeparture: String? = null,
        val cancelled: Boolean = false,
        val tz: String? = null,
        val stopCode: String? = null,
    )

    /**
     * The FULL stop sequence of one GTFS run - the "Stops" timeline behind a departure-board line.
     * `/api/v1/trip` returns the actual trip the tapped departure belongs to: every stop it calls at,
     * with per-stop realtime vs timetable times AND per-stop/-run CANCELED flags straight from the
     * agency feed - none of which the Google itinerary reuse could provide. The result is trimmed to
     * start at the stop nearest ([atLat],[atLng]) (the stop whose board was tapped), mapped into the
     * SAME [TransitStep] the timeline UI already renders. Null on any failure - the caller falls back
     * to the itinerary-reuse path.
     */
    suspend fun tripStops(http: TransitousHttp, tripId: String, atLat: Double, atLng: Double, atEpochSec: Long? = null): TransitStep? {
        val body = get(http, "$BASE/api/v1/trip?tripId=${UrlCodec.encode(tripId)}") ?: return null
        val leg = runCatching { json.decodeFromString<TripResp>(body.decodeToString()).legs.firstOrNull() }.getOrNull() ?: return null
        return buildTripStep(leg, atLat, atLng, atEpochSec)
    }

    /** Pure mapping of a trip leg into the timeline's [TransitStep] (unit-tested; no network).
     *  [atEpochSec] is the tapped departure's time: on a LOOPING trip (one GTFS trip for a whole
     *  day of laps, which some agencies publish) the tapped stop recurs every lap, and the time
     *  picks the lap. */
    internal fun buildTripStep(leg: TripLeg, atLat: Double, atLng: Double, atEpochSec: Long? = null): TransitStep? {
        val all = buildList {
            add(leg.from)
            addAll(leg.intermediateStops)
            add(leg.to)
        }.filter { it.name.isNotBlank() }
        if (all.size < 2) return null
        // The timeline BOARDS at the tapped stop (nearest-by-distance, so it works from a canonical
        // GTFS stop AND from a Google-resolved listing on a different corner); the stops the run
        // already called at go into priorStops so the view can show them grayed above, Google-style.
        // A terminus tap boards at the origin instead (an arrivals-only view has no ride left).
        val dist = all.map { distM(atLat, atLng, it.lat, it.lon) }
        val nearest = dist.minOrNull() ?: 0.0
        // Every pass the trip makes at the tapped stop (a loop calls there once per lap).
        val passes = all.indices.filter { dist[it] <= nearest + LAP_SAME_STOP_M }
        val epochOf = { st: TripStop -> (st.departure ?: st.arrival ?: st.scheduledDeparture ?: st.scheduledArrival)?.let { parseIso(it) } }
        val pick = if (atEpochSec != null && passes.size > 1)
            passes.minByOrNull { i -> epochOf(all[i])?.let { kotlin.math.abs(it - atEpochSec) } ?: Long.MAX_VALUE } ?: passes.first()
        else passes.firstOrNull() ?: 0
        val idx = if (pick >= all.size - 1) 0 else pick
        // One lap: from the previous pass (where this lap began) to the next one (where it ends).
        val lapStart = passes.lastOrNull { it < idx } ?: 0
        val lapEnd = passes.firstOrNull { it > idx }?.let { it + 1 } ?: all.size
        val prior = all.subList(lapStart, idx).map { st -> stopTime(st, legCanceled = leg.cancelled) }
        val mapped = all.subList(idx, lapEnd).map { st -> stopTime(st, legCanceled = leg.cancelled) }
        return TransitStep(
            mode = modeOf(leg.mode),
            line = TransitLine(
                name = leg.routeShortName ?: leg.displayName ?: "",
                mode = modeOf(leg.mode),
                colorHex = leg.routeColor?.takeIf { it.isNotBlank() }?.let { if (it.startsWith("#")) it else "#$it" },
                textColorHex = leg.routeTextColor?.takeIf { it.isNotBlank() }?.let { if (it.startsWith("#")) it else "#$it" },
            ),
            headsign = leg.headsign,
            boardStop = mapped.first(),
            alightStop = mapped.last(),
            intermediateStops = mapped.drop(1).dropLast(1),
            numStops = mapped.size - 1,
            departText = mapped.first().timeText,
            arriveText = mapped.last().timeText,
            priorStops = prior,
        )
    }

    private fun stopTime(st: TripStop, legCanceled: Boolean): TransitStopTime {
        val shown = st.departure ?: st.arrival ?: st.scheduledDeparture ?: st.scheduledArrival
        val sched = st.scheduledDeparture ?: st.scheduledArrival
        val shownEpoch = shown?.let { parseIso(it) }
        val schedEpoch = sched?.let { parseIso(it) }
        val moved = schedEpoch != null && shownEpoch != null && schedEpoch != shownEpoch
        return TransitStopTime(
            name = st.name,
            code = st.stopCode,
            stopId = st.stopId.takeIf { it.isNotBlank() },
            timeText = shownEpoch?.let { clockText(it, st.tz) },
            // The timetable time, kept ONLY when realtime moved the shown time - the row UI reads
            // "scheduled differs" as the live signal, same contract as the itinerary parser.
            scheduledText = if (moved) clockText(schedEpoch!!, st.tz) else null,
            location = app.vela.core.model.LatLng(st.lat, st.lon),
            canceled = st.cancelled || legCanceled,
            // Signed minutes off the timetable (negative = early) so the row can color a late
            // call differently from an early one - the feed carries both (verified live).
            delayMin = if (moved) (((shownEpoch!! - schedEpoch!!) / 60).toInt()) else null,
        )
    }

    // --- reachability, map trips and via searches (T-2) -------------------------------------------

    /** One stop the planner says is reachable, with the travel time it measured from the origin. */
    data class ReachableStop(
        val name: String,
        val stopId: String,
        val lat: Double,
        val lon: Double,
        /** Minutes from the request's origin, as the reply's `duration` gave them. */
        val minutes: Int,
        /** Interchanges on the fastest way there (`k`); -1 when the reply did not send it. */
        val transfers: Int = -1,
        /** The arrival epoch the reply sent, or null when it sent none. */
        val arrivalEpochSec: Long? = null,
        val modes: List<String> = emptyList(),
    )

    /** The origin and every stop `one-to-all` reached within its budget. */
    data class ReachResult(
        val originName: String,
        val originLat: Double,
        val originLon: Double,
        /** The reply's own departure (or arrival, for `arriveBy`) epoch, when it sent one. */
        val originEpochSec: Long? = null,
        val stops: List<ReachableStop> = emptyList(),
    )

    /** A reachability answer; [rateLimited] is true on the service's 429, which is not a failure
     *  of the request but the moment to stop asking. */
    data class OneToAllReply(val result: ReachResult? = null, val rateLimited: Boolean = false)

    @Serializable private data class OneToAllResp(val one: OaPlace = OaPlace(), val all: List<OaEntry> = emptyList())
    @Serializable private data class OaEntry(val place: OaPlace = OaPlace(), val duration: Int = 0, val k: Int = -1)
    @Serializable private data class OaPlace(
        val name: String = "",
        val stopId: String? = null,
        val lat: Double = 0.0,
        val lon: Double = 0.0,
        val tz: String? = null,
        val arrival: String? = null,
        val departure: String? = null,
        val vertexType: String? = null,
        val modes: List<String> = emptyList(),
    )

    /** The reachability call's deadline: the planner explores every stop in the budget. */
    const val ONE_TO_ALL_TIMEOUT_MS = 45_000L

    /**
     * Every stop reachable from [origin] within [maxTravelTimeMin] minutes, from the service's
     * `one-to-all`. It is one request per user action; the caller caches the answer. The budget is
     * clamped to [MIN_REACH_MIN]..[MAX_REACH_MIN], the range the UI offers. The reply carries a
     * travel time per stop, never a polygon: the hull is the app's own, built in TransitReach.
     */
    suspend fun oneToAll(
        http: TransitousHttp,
        origin: LatLng,
        maxTravelTimeMin: Int = 30,
        timeEpochSec: Long? = null,
        arriveBy: Boolean = false,
    ): OneToAllReply {
        val url = oneToAllUrl(origin, maxTravelTimeMin, timeEpochSec, arriveBy)
        val (body, code) = fetchWithStatus(http, url, ONE_TO_ALL_TIMEOUT_MS)
        if (code == RATE_LIMIT_STATUS) return OneToAllReply(rateLimited = true)
        if (body == null) return OneToAllReply()
        return OneToAllReply(runCatching { parseOneToAll(body.decodeToString()) }.getOrNull())
    }

    const val MIN_REACH_MIN = 5
    const val MAX_REACH_MIN = 60

    internal fun oneToAllUrl(origin: LatLng, maxTravelTimeMin: Int, timeEpochSec: Long?, arriveBy: Boolean): String = buildString {
        append(BASE).append("/api/v1/one-to-all?one=").append(coord(origin))
        append("&maxTravelTime=").append(maxTravelTimeMin.coerceIn(MIN_REACH_MIN, MAX_REACH_MIN))
        if (timeEpochSec != null) append("&time=").append(instantText(timeEpochSec))
        if (arriveBy) append("&arriveBy=true")
    }

    /** Pure parser for the captured `one-to-all` reply: stops with a name and an id only. */
    internal fun parseOneToAll(text: String): ReachResult? {
        val reply = runCatching { json.decodeFromString<OneToAllResp>(text) }.getOrNull() ?: return null
        if (reply.all.isEmpty() && reply.one.lat == 0.0 && reply.one.lon == 0.0) return null
        val seen = HashSet<String>()
        val stops = reply.all.mapNotNull { entry ->
            val p = entry.place
            if (p.stopId.isNullOrBlank() || p.name.isBlank()) return@mapNotNull null
            if (p.vertexType != null && p.vertexType != "TRANSIT") return@mapNotNull null
            if (!seen.add(p.stopId)) return@mapNotNull null
            ReachableStop(
                name = p.name,
                stopId = p.stopId,
                lat = p.lat,
                lon = p.lon,
                minutes = entry.duration.coerceAtLeast(0),
                transfers = entry.k,
                arrivalEpochSec = p.arrival?.let { parseIso(it) },
                modes = p.modes,
            )
        }.sortedWith(compareBy({ it.minutes }, { it.name }))
        return ReachResult(
            originName = reply.one.name,
            originLat = reply.one.lat,
            originLon = reply.one.lon,
            originEpochSec = (reply.one.departure ?: reply.one.arrival)?.let { parseIso(it) },
            stops = stops,
        )
    }

    /** One drawn line of `map/trips`: every stretch of the same route and destination, one color,
     *  one delay, and the mode the feed gave. [colorHex] is the feed's `routeColor`, or null. */
    data class MapTripLine(
        val label: String,
        val mode: TransitMode,
        val colorHex: String? = null,
        val destination: String? = null,
        val segmentCount: Int = 0,
        /** Median lateness in minutes over the live stretches that carried both times. Null when
         *  not one stretch did: no time, no delay, and the UI draws no color for it. */
        val delayMinutes: Int? = null,
        /** True when at least one stretch carried `realTime`. */
        val live: Boolean = false,
        val paths: List<List<LatLng>> = emptyList(),
    )

    /** A `map/trips` answer; [truncated] is true when some stretches were left out at the cap. */
    data class MapTripsReply(
        val lines: List<MapTripLine> = emptyList(),
        val rateLimited: Boolean = false,
        val truncated: Boolean = false,
        val segmentCount: Int = 0,
    )

    @Serializable private data class MapTripDto(
        val trips: List<MapTripIdDto> = emptyList(),
        val mode: String = "",
        val routeColor: String? = null,
        val from: MapTripPlaceDto = MapTripPlaceDto(),
        val to: MapTripPlaceDto = MapTripPlaceDto(),
        val departure: String? = null,
        val scheduledDeparture: String? = null,
        val arrival: String? = null,
        val scheduledArrival: String? = null,
        val realTime: Boolean = false,
        val polyline: String? = null,
    )

    @Serializable private data class MapTripIdDto(val tripId: String = "", val routeShortName: String? = null)

    @Serializable private data class MapTripPlaceDto(val name: String = "", val stopId: String? = null, val lat: Double = 0.0, val lon: Double = 0.0)

    /** The drawn-stretch cap of one view: a city block at z16 is below it, a whole city is not. */
    const val MAX_MAP_TRIPS = 800

    /** The map-trips deadline: a central Berlin answer at z14 is several megabytes. */
    const val MAP_TRIPS_TIMEOUT_MS = 40_000L

    /**
     * The service's in-service stretches in a box, grouped by route and destination. [precision]
     * is the polyline precision the service is asked for (4..6) and must be the one the reply was
     * drawn with; the default matches the service. [zoom] is its own filter. Only bus, tram,
     * subway, train and ferry stretches are kept; a line without a short name is left out rather
     * than given an invented one.
     */
    suspend fun mapTrips(
        http: TransitousHttp,
        south: Double, west: Double, north: Double, east: Double,
        zoom: Int,
        startEpochSec: Long, endEpochSec: Long,
        precision: Int = 5,
        maxSegments: Int = MAX_MAP_TRIPS,
    ): MapTripsReply {
        val url = mapTripsUrl(south, west, north, east, zoom, startEpochSec, endEpochSec, precision)
        val (body, code) = fetchWithStatus(http, url, MAP_TRIPS_TIMEOUT_MS)
        if (code == RATE_LIMIT_STATUS) return MapTripsReply(rateLimited = true)
        if (body == null) return MapTripsReply()
        val raw = runCatching { json.decodeFromString<List<MapTripDto>>(body.decodeToString()) }.getOrNull()
            ?: return MapTripsReply()
        val parsed = parseMapTripDtos(raw, precision.coerceIn(4, 6), maxSegments)
        return MapTripsReply(
            lines = parsed,
            truncated = raw.size > maxSegments,
            segmentCount = minOf(raw.size, maxSegments),
        )
    }

    internal fun mapTripsUrl(
        south: Double, west: Double, north: Double, east: Double,
        zoom: Int, startEpochSec: Long, endEpochSec: Long, precision: Int = 5,
    ): String = buildString {
        append(BASE).append("/api/v1/map/trips?min=").append(south).append(',').append(west)
        append("&max=").append(north).append(',').append(east)
        append("&zoom=").append(zoom.coerceIn(0, 22))
        append("&startTime=").append(instantText(startEpochSec))
        append("&endTime=").append(instantText(endEpochSec))
        append("&precision=").append(precision.coerceIn(4, 6))
    }

    /** Public for the fixture test; [precision] is the one the captured reply was drawn with. */
    fun parseMapTrips(text: String, precision: Int = 5, maxSegments: Int = MAX_MAP_TRIPS): List<MapTripLine> {
        val raw = runCatching { json.decodeFromString<List<MapTripDto>>(text) }.getOrNull() ?: return emptyList()
        return parseMapTripDtos(raw, precision.coerceIn(4, 6), maxSegments)
    }

    private data class MapLineKey(val label: String, val destination: String)

    private fun parseMapTripDtos(raw: List<MapTripDto>, precision: Int, maxSegments: Int): List<MapTripLine> {
        val groups = LinkedHashMap<MapLineKey, MutableList<Pair<MapTripDto, List<LatLng>>>>()
        var accepted = 0
        for (dto in raw) {
            if (accepted >= maxSegments) break
            val mode = modeOf(dto.mode)
            if (mode !in MAP_TRIP_MODES) continue
            val label = dto.trips.firstOrNull { !it.routeShortName.isNullOrBlank() }?.routeShortName?.trim()
                ?: continue
            val path = dto.polyline?.takeIf { it.isNotBlank() }
                ?.let { runCatching { app.vela.core.data.google.PolylineCodec.decode(it, precision) }.getOrNull() }
                .orEmpty()
            if (path.size < 2) continue
            val key = MapLineKey(label, dto.to.name.trim())
            groups.getOrPut(key) { mutableListOf() }.add(dto to path)
            accepted += 1
        }
        return groups.map { (key, stretches) ->
            val delays = stretches.mapNotNull { (dto, _) -> segmentDelayMin(dto) }
            MapTripLine(
                label = key.label,
                // Every stretch of a line shares its mode; the first one the feed sent stands.
                mode = stretches.first().first.let { modeOf(it.mode) },
                colorHex = stretches.firstNotNullOfOrNull { (dto, _) -> routeColorOf(dto.routeColor) },
                destination = key.destination.takeIf { it.isNotEmpty() },
                segmentCount = stretches.size,
                delayMinutes = median(delays),
                live = stretches.any { (dto, _) -> dto.realTime },
                paths = stretches.map { it.second },
            )
        }.sortedWith(compareBy<MapTripLine>({ it.label.toIntOrNull() == null }, { it.label.toIntOrNull() ?: 0 }, { it.label }))
    }

    private val MAP_TRIP_MODES = setOf(TransitMode.BUS, TransitMode.TRAM, TransitMode.SUBWAY, TransitMode.TRAIN, TransitMode.FERRY)

    /** The signed lateness of one stretch, in whole minutes, only when the feed sent a live and a
     *  scheduled departure AND marked the stretch realtime. Anything else is unknown. */
    private fun segmentDelayMin(dto: MapTripDto): Int? {
        if (!dto.realTime) return null
        val live = (dto.departure ?: dto.arrival)?.let { parseIso(it) } ?: return null
        val scheduled = (dto.scheduledDeparture ?: dto.scheduledArrival)?.let { parseIso(it) } ?: return null
        return ((live - scheduled) / 60.0).toInt()
    }

    private fun median(values: List<Int>): Int? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 1) sorted[middle] else ((sorted[middle - 1] + sorted[middle]) / 2.0).toInt()
    }

    private fun routeColorOf(color: String?): String? {
        val hex = color?.trim()?.lowercase()?.removePrefix("#") ?: return null
        return "#$hex".takeIf { hex.length == 6 && hex.all { c -> c in '0'..'9' || c in 'a'..'f' } }
    }

    // --- via (an intermediate stop) ----------------------------------------------------------------

    /** A stop the planner found by name around the coordinate the current trip gave. */
    data class StopRef(
        val stopId: String,
        val parentId: String?,
        val name: String,
        val lat: Double,
        val lon: Double,
    )

    /** The stop in [stops] whose normalized name matches [name], nearest to ([lat],[lng]); null
     *  when no name matches, so a via request is never sent to another corner's stop. */
    internal fun pickStopByName(stops: List<MapStop>, name: String, text: TextNormalizer, lat: Double, lng: Double): MapStop? {
        val key = stopKey(name, text)
        if (key.isEmpty()) return null
        return stops.filter { stopKey(it.name, text) == key }
            .minByOrNull { distM(lat, lng, it.lat, it.lon) }
    }

    /**
     * Resolves a via stop by NAME through the same `map/stops` lookup the board uses, around the
     * coordinate the current trip gave for it. Null when the service lists no stop of that name
     * within [radiusM], or gives the same name at several corners and none within reach.
     */
    suspend fun resolveStop(
        http: TransitousHttp,
        name: String,
        lat: Double,
        lng: Double,
        radiusM: Double = 500.0,
    ): StopRef? {
        if (name.isBlank()) return null
        val found = stopsNear(http, lat, lng, radiusM)
        val match = pickStopByName(found, name, http.text, lat, lng) ?: return null
        return StopRef(match.stopId, match.parentId, match.name, match.lat, match.lon)
    }

    /**
     * A plan constrained through [viaStopId]. `/api/v1/plan` takes the via as a stop id only: a
     * coordinate is a 404 ("unknown feed id"), so the caller resolves the name first. The
     * signature and the answer shape of [plan] stay as they are.
     */
    suspend fun planVia(
        http: TransitousHttp,
        origin: LatLng,
        destination: LatLng,
        viaStopId: String,
        timeMode: Int = 0,
        timeEpochSec: Long? = null,
        prefer: Set<Int> = emptySet(),
        max: Int = PLAN_MAX,
    ): List<TransitItinerary> {
        if (viaStopId.isBlank()) return emptyList()
        val url = planViaUrl(origin, destination, viaStopId, timeMode, timeEpochSec, prefer, max)
        val body = get(http, url) ?: return emptyList()
        return runCatching { parsePlan(body.decodeToString(), origin, destination) }.getOrDefault(emptyList())
    }

    internal fun planViaUrl(
        origin: LatLng, destination: LatLng, viaStopId: String,
        timeMode: Int, timeEpochSec: Long?, prefer: Set<Int>, max: Int = PLAN_MAX,
    ): String = planUrl(origin, destination, timeMode, timeEpochSec, prefer, max) +
        "&via=" + UrlCodec.encode(viaStopId)

    private fun coord(p: LatLng): String = "${p.lat},${p.lng}"

    private const val RATE_LIMIT_STATUS = 429

    /** A GET whose HTTP status the caller sees, for the 429 the policy names. */
    private suspend fun fetchWithStatus(http: TransitousHttp, url: String, timeoutMs: Long): Pair<ByteArray?, Int> {
        val resp = try {
            http.http.call(HttpRequest(url, headers = listOf(HttpHeader("User-Agent", UA)), timeoutMillis = timeoutMs))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            return null to -1
        }
        return (if (resp.isSuccessful) resp.body else null) to resp.code
    }

    // --- directions (fallback) ---------------------------------------------------------------------

    /** The planner request. [timeMode] is the chooser's own numbering, the one every caller
     *  passes: 0 leave now, 1 depart at, 2 arrive by, 3 last available. Only the last two are
     *  "arrive by" to the planner. (It read 1 and 2 as arrive by, so "Depart at 08:30" listed the
     *  buses that ARRIVE before 08:30 whenever Google's answer was empty and this one was shown:
     *  issue #649.) */
    internal fun planUrl(origin: LatLng, destination: LatLng, timeMode: Int, timeEpochSec: Long?, prefer: Set<Int>, max: Int = PLAN_MAX): String = buildString {
        append(BASE).append("/api/v1/plan?fromPlace=").append(origin.lat).append(',').append(origin.lng)
        append("&toPlace=").append(destination.lat).append(',').append(destination.lng)
        append("&numItineraries=").append(max)
        if (timeEpochSec != null && timeMode != 0) {
            append("&time=").append(instantText(timeEpochSec))
            if (timeMode == 2 || timeMode == 3) append("&arriveBy=true")
        }
        val modes = prefer.mapNotNull { PLAN_MODES[it] }
        if (modes.isNotEmpty()) append("&transitModes=").append(modes.joinToString(","))
    }

    /**
     * Transit itineraries from Transitous' own planner (`/api/v1/plan`), 2026-09-28. The FALLBACK,
     * not the primary: Google's transit directions carry traffic-aware and history-aware times where
     * a GTFS planner knows only the timetable and current lateness, so this runs when Google is off
     * ("Use Vela without Google") or answered nothing. [timeMode] is the chooser's: 0 leave now, 1 depart
     * at, 2 arrive by, 3 last available (treated as arrive by). [prefer] is the chooser's vehicle numbering
     * (0 bus, 1 subway, 2 train, 3 tram); empty = every mode. Same [TransitItinerary] shape the
     * Google parser feeds, so the chooser, the map drawing and step-by-step guidance render it unchanged.
     */
    suspend fun plan(
        http: TransitousHttp, origin: LatLng, destination: LatLng,
        timeMode: Int = 0, timeEpochSec: Long? = null, prefer: Set<Int> = emptySet(), max: Int = PLAN_MAX,
    ): List<TransitItinerary> {
        val url = planUrl(origin, destination, timeMode, timeEpochSec, prefer, max)
        val body = get(http, url) ?: return emptyList()
        return runCatching { parsePlan(body.decodeToString(), origin, destination) }.getOrDefault(emptyList())
    }

    /** A leg's drawn path from the planner's `legGeometry` (an encoded polyline with its own
     *  precision, 7 on the public instance). Null when absent or shorter than two points. */
    internal fun legPath(leg: JsonObject): List<LatLng>? {
        val g = leg.optObject("legGeometry") ?: return null
        val pts = g.optString("points", "")?.takeIf { it.isNotBlank() } ?: return null
        val precision = g.optInt("precision", 6).coerceIn(5, 7)
        return runCatching { app.vela.core.data.google.PolylineCodec.decode(pts, precision) }.getOrNull()
            ?.filter { it.lat in -90.0..90.0 && it.lng in -180.0..180.0 }?.takeIf { it.size >= 2 }
    }

    /**
     * The real path of ONE ride between two stops, for an itinerary that has none of its own
     * (Google's): the planner is asked for a direct ride from [board] to [alight] around
     * [departEpochSec], and the path of a ride leg that starts and ends at those stops is
     * returned. Null when no such leg comes back or its path is only the stops again, so the
     * caller keeps its straight lines. One request; issue #677.
     */
    suspend fun legShape(http: TransitousHttp, board: LatLng, alight: LatLng, departEpochSec: Long?): List<LatLng>? {
        val url = buildString {
            append(BASE).append("/api/v1/plan?fromPlace=").append(board.lat).append(',').append(board.lng)
            append("&toPlace=").append(alight.lat).append(',').append(alight.lng)
            // No maxTransfers: the public instance answers nothing at all with maxTransfers=0
            // (seen 2026-10-07); a leg is matched by its two stops instead.
            append("&numItineraries=5")
            // A little before the departure, so the run itself is among the answers.
            if (departEpochSec != null) append("&time=").append(instantText(departEpochSec - 120))
        }
        val body = get(http, url) ?: return null
        return runCatching { pickLegShape(body.decodeToString(), board, alight) }.getOrNull()
    }

    /** Pure half of [legShape]: the best matching ride leg's path in a plan reply. */
    internal fun pickLegShape(json: String, board: LatLng, alight: LatLng): List<LatLng>? {
        val its = parseObject(json).optArray("itineraries") ?: return null
        val chord = board.distanceTo(alight)
        var best: List<LatLng>? = null
        for (i in 0 until its.size) {
            val legs = its.getObject(i).optArray("legs") ?: continue
            for (k in 0 until legs.size) {
                val leg = legs.getObject(k)
                if (leg.optString("mode", "") in setOf("WALK", "BIKE", "CAR", "RENTAL")) continue
                val from = leg.optObject("from")?.let { point(it) } ?: continue
                val to = leg.optObject("to")?.let { point(it) } ?: continue
                if (from.distanceTo(board) > LEG_SHAPE_STOP_M || to.distanceTo(alight) > LEG_SHAPE_STOP_M) continue
                val path = legPath(leg) ?: continue
                // A path that is only the stops again adds nothing over the chords already drawn,
                // and one far longer than the ride is some other way round.
                val stops = (leg.optArray("intermediateStops")?.size ?: 0) + 2
                var len = 0.0
                for (p in 1 until path.size) len += path[p - 1].distanceTo(path[p])
                if (path.size <= stops + 1 || len > chord * LEG_SHAPE_MAX_RATIO + 500) continue
                if (best == null || path.size > best.size) best = path
            }
        }
        return best
    }

    /** A planner leg counts as "this ride" when both its ends are within this of the stops. */
    private const val LEG_SHAPE_STOP_M = 300.0
    private const val LEG_SHAPE_MAX_RATIO = 4.0

    /** The plan reply's itineraries, in the planner's order. Pure; fixture-tested. */
    internal fun parsePlan(json: String, origin: LatLng, destination: LatLng): List<TransitItinerary> {
        val root = parseObject(json)
        val its = root.optArray("itineraries") ?: return emptyList()
        return (0 until its.size).mapNotNull { i -> runCatching { parseItinerary(its.getObject(i), origin, destination) }.getOrNull() }
    }

    private fun parseItinerary(it: JsonObject, origin: LatLng, destination: LatLng): TransitItinerary? {
        val legs = it.optArray("legs") ?: return null
        val steps = ArrayList<TransitStep>()
        for (i in 0 until legs.size) {
            val leg = legs.getObject(i)
            val mode = leg.optString("mode", "")
            val from = leg.optObject("from"); val to = leg.optObject("to")
            val start = parseIso(leg.optString("startTime", "")!!); val end = parseIso(leg.optString("endTime", "")!!)
            val secs = leg.optLong("duration", if (start != null && end != null) end - start else 0L)
            if (mode == "WALK" || mode == "BIKE" || mode == "CAR" || mode == "RENTAL") {
                // A transfer walk between two stops, or the first/last mile: the app fetches the
                // turn-by-turn steps for it on demand from the walk router, like the Google legs.
                steps += TransitStep(
                    mode = TransitMode.WALK, durationText = durationText(secs),
                    walkFrom = from?.let { point(it) } ?: origin, walkTo = to?.let { point(it) } ?: destination,
                    path = legPath(leg),
                )
                continue
            }
            val tz = from?.optString("tz", null)
            val line = TransitLine(
                name = leg.optString("routeShortName", "")!!.ifBlank { leg.optString("displayName", "")!! }.ifBlank { leg.optString("routeLongName", "")!! },
                mode = modeOf(mode),
                colorHex = leg.optString("routeColor", "")?.takeIf { it.isNotBlank() }?.let { "#" + it.removePrefix("#") },
                textColorHex = leg.optString("routeTextColor", "")?.takeIf { it.isNotBlank() }?.let { "#" + it.removePrefix("#") },
            )
            val board = from?.let { stopTime(it, "departure", "scheduledDeparture", tz) }
            val alight = to?.let { stopTime(it, "arrival", "scheduledArrival", to.optString("tz", null) ?: tz) }
            val mids = leg.optArray("intermediateStops")?.let { a ->
                (0 until a.size).mapNotNull { k -> (a[k] as? JsonObject)?.let { stopTime(it, "arrival", "scheduledArrival", it.optString("tz", null) ?: tz) } }
            }.orEmpty()
            val startSched = parseIso(leg.optString("scheduledStartTime", "")!!)
            val delayMin = if (start != null && startSched != null && leg.optBoolean("realTime", false)) ((start - startSched) / 60).toInt() else null
            steps += TransitStep(
                mode = line.mode, durationText = durationText(secs), line = line,
                departText = start?.let { clockText(it, tz) }, arriveText = end?.let { clockText(it, to?.optString("tz", null) ?: tz) },
                headsign = leg.optString("headsign", "")?.takeIf { it.isNotBlank() },
                boardStop = board, alightStop = alight, numStops = mids.size + 1,
                delayText = delayMin?.let { delayText(it) }, intermediateStops = mids,
                path = legPath(leg),
            )
        }
        if (steps.none { it.line != null }) return null // a walk-only answer is not a transit trip
        val startEp = parseIso(it.optString("startTime", "")!!); val endEp = parseIso(it.optString("endTime", "")!!)
        val firstTz = legs.getObject(0).optObject("from")?.optString("tz", null)
        val lastTz = legs.getObject(legs.size - 1).optObject("to")?.optString("tz", null) ?: firstTz
        var agency: String? = null
        for (i in 0 until legs.size) legs.getObject(i).optString("agencyName", "")?.takeIf { it.isNotBlank() }?.let { if (agency == null) agency = it }
        val alerts = buildList {
            addAll(alertsOf(it))
            for (i in 0 until legs.size) addAll(alertsOf(legs.getObject(i)))
        }.distinct()
        return TransitItinerary(
            departureEpochSec = startEp, arrivalEpochSec = endEp,
            departureText = startEp?.let { clockText(it, firstTz) }, arrivalText = endEp?.let { clockText(it, lastTz) },
            durationText = durationText(it.optLong("duration", if (startEp != null && endEp != null) endEp - startEp else 0L)),
            agency = agency, alerts = alerts, lines = steps.mapNotNull { s -> s.line }, steps = steps,
        )
    }

    /** Service alerts the plan reply may attach to an itinerary or one of its legs. A string is
     *  used as is; an object contributes its header and description. Missing fields add nothing,
     *  so a feed without alerts keeps the empty list rather than an invented notice. */
    private fun alertsOf(o: JsonObject): List<String> {
        val arr = o.optArray("alerts") ?: return emptyList()
        return (0 until arr.size).mapNotNull { i ->
            when (val item = arr[i]) {
                is JsonPrimitive -> item.contentOrNull?.takeIf { it.isNotBlank() }
                is JsonObject -> listOf("headerText", "descriptionText", "text", "alertHeaderText", "alertDescriptionText")
                    .mapNotNull { key -> item.optString(key, null)?.takeIf { it.isNotBlank() } }
                    .distinct()
                    .joinToString(": ")
                    .takeIf { it.isNotBlank() }
                else -> null
            }
        }
    }

    private fun point(o: JsonObject): LatLng? {
        val lat = o.optDouble("lat", Double.NaN); val lng = o.optDouble("lon", Double.NaN)
        return if (lat.isNaN() || lng.isNaN()) null else LatLng(lat, lng)
    }

    private fun stopTime(o: JsonObject, liveKey: String, schedKey: String, tz: String?): TransitStopTime {
        val live = parseIso(o.optString(liveKey, "")!!); val sched = parseIso(o.optString(schedKey, "")!!)
        val shown = live ?: sched
        return TransitStopTime(
            name = o.optString("name", "")!!, code = o.optString("stopCode", "")?.takeIf { it.isNotBlank() },
            stopId = o.optString("stopId", "")?.takeIf { it.isNotBlank() },
            timeText = shown?.let { clockText(it, tz) },
            scheduledText = if (live != null && sched != null && live != sched) clockText(sched, tz) else null,
            location = point(o), canceled = o.optBoolean("cancelled", false),
            delayMin = if (live != null && sched != null && live != sched) ((live - sched) / 60).toInt() else null,
        )
    }

    /** Set by the app to its own duration formatter, so a planned trip's times read in the app's
     *  language like every other duration on screen. Null (unit tests) = the English form below. */
    @Volatile var durationFormatter: ((Long) -> String)? = null

    /** "45 min" / "1 h 5 min", the shape the chooser's chips already fold. */
    internal fun durationText(secs: Long): String {
        durationFormatter?.let { f -> runCatching { return f(secs.coerceAtLeast(60)) } }
        val m = ((secs + 30) / 60).coerceAtLeast(1)
        return if (m < 60) "$m min" else if (m % 60 == 0L) "${m / 60} h" else "${m / 60} h ${m % 60} min"
    }

    private fun delayText(min: Int): String? = app.vela.core.i18n.DelayText.of(min)

    private const val PLAN_MAX = 5
    /** The chooser's vehicle numbers (Google's, issue #431) as the planner's mode names. */
    private val PLAN_MODES = mapOf(0 to "BUS", 1 to "SUBWAY", 2 to "RAIL", 3 to "TRAM")

    // --- helpers ----------------------------------------------------------------------------------

    /** Names in the app's language where the feed has them (issue #674): the service takes a bare
     *  language code and falls back to the feed's own names for one it does not have. Without it
     *  a Tokyo rail stop reads "新宿 Shinjuku" in every language. */
    internal fun withLanguage(url: String, language: String): String {
        val lang = when (val l = language.lowercase()) { "iw" -> "he"; "in" -> "id"; "ji" -> "yi"; else -> l }
        if (lang.length !in 2..3 || "language=" in url) return url
        return url + (if ('?' in url) "&" else "?") + "language=" + lang
    }

    /** A GET in the app's language ([withLanguage]). */
    private suspend fun get(http: TransitousHttp, url: String): ByteArray? = fetch(http, withLanguage(url, http.locale.defaultLanguage()))

    /** The body of a successful GET of [url], null on any failure. Only cancellation is thrown. */
    private suspend fun fetch(http: TransitousHttp, url: String, timeoutMs: Long = 0): ByteArray? {
        val resp = try {
            http.http.call(HttpRequest(url, headers = listOf(HttpHeader("User-Agent", UA)), timeoutMillis = timeoutMs))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            return null
        }
        return if (resp.isSuccessful) resp.body else null
    }

    /** ISO-8601 UTC ("2026-07-13T20:26:00Z") to epoch seconds. */
    internal fun parseIso(iso: String): Long? = isoEpochSec(iso)

    /** An epoch second as the planner's `time` parameter ("2026-07-13T20:26:00Z"). */
    internal fun instantText(epochSec: Long): String = Instant.fromEpochSeconds(epochSec).toString()

    /** Clock text in the STOP's timezone (falls back to the device zone): 12-hour like the
     *  Google boards, or 24-hour when the device's clock setting says so ([ClockFormat],
     *  issue #357). */
    internal fun clockText(epochSec: Long, tz: String?): String = stopClockText(epochSec, tz)

    private fun modeOf(mode: String?): TransitMode = when (mode?.uppercase()) {
        "BUS", "COACH" -> TransitMode.BUS
        "TRAM" -> TransitMode.TRAM
        "SUBWAY", "METRO" -> TransitMode.SUBWAY
        "RAIL", "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL" -> TransitMode.TRAIN
        "FERRY" -> TransitMode.FERRY
        else -> TransitMode.GENERIC
    }

    private fun distM(aLat: Double, aLng: Double, bLat: Double, bLng: Double): Double {
        val mPerLng = 111_320.0 * cos(aLat.toRadians())
        val dx = (aLng - bLng) * mPerLng
        val dy = (aLat - bLat) * 111_320.0
        return sqrt(dx * dx + dy * dy)
    }

    // --- the plan reply, read the way Android's org.json read it -------------------------------------

    private fun parseObject(text: String): JsonObject = Json.parseToJsonElement(text).jsonObject

    private fun JsonObject.optObject(key: String): JsonObject? = this[key] as? JsonObject

    private fun JsonObject.optArray(key: String): JsonArray? = this[key] as? JsonArray

    /** `getJSONObject(i)`: throws unless the element is an object. */
    private fun JsonArray.getObject(i: Int): JsonObject = this[i] as? JsonObject ?: throw IllegalArgumentException("not an object at $i")

    /** `optString(key, fallback)`: a missing key gives [fallback]; a JSON null reads "null". */
    private fun JsonObject.optString(key: String, fallback: String?): String? = this[key]?.let { OrgJson.string(it) } ?: fallback

    private fun JsonObject.optInt(key: String, fallback: Int): Int = this[key]?.let { OrgJson.int(it) } ?: fallback

    private fun JsonObject.optLong(key: String, fallback: Long): Long = this[key]?.let { OrgJson.long(it) } ?: fallback

    private fun JsonObject.optDouble(key: String, fallback: Double): Double = this[key]?.let { OrgJson.double(it) } ?: fallback

    private fun JsonObject.optBoolean(key: String, fallback: Boolean): Boolean = this[key]?.let { OrgJson.boolean(it) } ?: fallback
}

/**
 * The coercions of Android's `org.json` (`JSONTokener` and `JSON` in libcore) on a kotlinx tree, so
 * the plan reply reads as it did. A bare literal is what `JSONTokener` made of it: `true`, `false`,
 * `null`, an `Int` when it fits, else a `Long`, else a `Double`, else the text.
 */
internal object OrgJson {
    private object Null

    private fun literal(p: JsonPrimitive): Any {
        if (p.isString) return p.content
        val c = p.content
        when (c) {
            "true" -> return true
            "false" -> return false
            "null" -> return Null
        }
        if ('.' !in c) {
            var digits = c
            var base = 10
            if (digits.startsWith("0x") || digits.startsWith("0X")) {
                digits = digits.substring(2); base = 16
            } else if (digits.startsWith("0") && digits.length > 1) {
                digits = digits.substring(1); base = 8
            }
            digits.toLongOrNull(base)?.let { return if (it in Int.MIN_VALUE..Int.MAX_VALUE) it.toInt() else it }
        }
        return c.toDoubleOrNull() ?: c
    }

    private fun value(e: JsonElement): Any = if (e is JsonPrimitive) literal(e) else e

    /** `JSON.toString`: a JSON null is the text "null". */
    fun string(e: JsonElement): String = when (val v = value(e)) {
        is String -> v
        Null -> "null"
        else -> v.toString()
    }

    fun long(e: JsonElement): Long? = when (val v = value(e)) {
        is Int -> v.toLong()
        is Long -> v
        is Double -> v.toLong()
        is String -> v.toDoubleOrNull()?.toLong()
        else -> null
    }

    fun int(e: JsonElement): Int? = when (val v = value(e)) {
        is Int -> v
        is Long -> v.toInt()
        is Double -> v.toInt()
        is String -> v.toDoubleOrNull()?.toInt()
        else -> null
    }

    fun double(e: JsonElement): Double? = when (val v = value(e)) {
        is Int -> v.toDouble()
        is Long -> v.toDouble()
        is Double -> v
        is String -> v.toDoubleOrNull()
        else -> null
    }

    fun boolean(e: JsonElement): Boolean? = when (val v = value(e)) {
        is Boolean -> v
        is String -> if (v.equals("true", ignoreCase = true)) true else if (v.equals("false", ignoreCase = true)) false else null
        else -> null
    }
}
