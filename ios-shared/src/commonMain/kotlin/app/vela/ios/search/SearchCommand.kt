package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.search.QueryIntent
import app.vela.core.search.QueryIntents
import kotlin.math.cos
import kotlin.math.hypot

/**
 * One typed or spoken command, already read by the same vocabulary Android uses plus the two
 * commands iOS adds: "search along the route" and "call X".
 *
 * [kind] is the contract with Swift: home, work, directions, along, call, search, route, eta.
 * Anything that reads as an ordinary place or address query is null, so it stays a plain search
 * and can never become a keyword-only action.
 */
data class SearchCommandPlan(
    val kind: String,
    val query: String = "",
    val from: String? = null,
    val to: String? = null,
)

/**
 * Reads commands for the search field and for dictation. The shared [QueryIntents] parser owns
 * home, work, directions, routes and ETA; this object only adds the two shapes it does not know,
 * and both platforms reach it through the same call.
 */
object SearchCommands {
    const val HOME = "home"
    const val WORK = "work"
    const val DIRECTIONS = "directions"
    const val ALONG = "along"
    const val CALL = "call"
    const val SEARCH = "search"
    const val ROUTE = "route"
    const val ETA = "eta"

    /**
     * The command in [text] for language [lang], or null when the text is an ordinary query.
     * "Call" runs before the shared parser because "call Ada" would otherwise be a place search;
     * "along the route" runs before it because the parser would strip "search" and keep the rest
     * of the command as a place name.
     */
    fun parse(text: String, lang: String): SearchCommandPlan? {
        val clean = clean(text)
        if (clean.isEmpty()) return null
        val lower = clean.lowercase()
        call(clean, lower)?.let { return it }
        along(clean, lower)?.let { return it }
        return when (val intent = QueryIntents.parse(clean, lang)) {
            null -> null
            QueryIntent.Home -> SearchCommandPlan(HOME)
            QueryIntent.Work -> SearchCommandPlan(WORK)
            is QueryIntent.NavigateTo -> SearchCommandPlan(DIRECTIONS, intent.query)
            is QueryIntent.Search -> SearchCommandPlan(SEARCH, intent.query)
            is QueryIntent.Route -> SearchCommandPlan(ROUTE, from = intent.from, to = intent.to)
            QueryIntent.Eta -> SearchCommandPlan(ETA)
        }
    }

    private val callPrefixes = listOf(
        "call up", "call", "dial", "phone", "ring",
        "appelle", "appeler", "téléphone", "telephone",
        "llama a", "llamar a", "chiama", "chiamare",
        "liga para", "ligar para", "anrufen", "ruf an",
    )

    private fun call(original: String, t: String): SearchCommandPlan? {
        for (prefix in callPrefixes.sortedByDescending { it.length }) {
            if (t == prefix) return SearchCommandPlan(CALL)
            if (t.startsWith("$prefix ")) {
                val name = original.substring(prefix.length).trim()
                if (name.isNotEmpty()) return SearchCommandPlan(CALL, query = name)
            }
        }
        return null
    }

    private val alongPrefixes = listOf(
        "search along the route for", "search along the route",
        "search along route for", "search along route",
        "search along my route for", "search along my route",
        "along the route for", "along the route",
        "along my route for", "along my route",
        "along route for", "along route",
        "cherche le long de l'itinéraire", "chercher le long de l'itinéraire",
        "recherche le long de l'itinéraire",
        "le long de l'itinéraire", "le long du trajet",
    )
    private val alongSuffixes = listOf(
        " along the route", " along my route", " along route",
        " le long de l'itinéraire", " le long du trajet",
    )
    private val alongForPrefixes = listOf(
        "search for ", "find ", "cherche ", "recherche ", "trouve ",
    )

    private fun along(original: String, t: String): SearchCommandPlan? {
        for (prefix in alongPrefixes.sortedByDescending { it.length }) {
            if (t == prefix) return SearchCommandPlan(ALONG)
            if (t.startsWith("$prefix ")) {
                val q = original.substring(prefix.length).trim()
                if (q.isNotEmpty()) return SearchCommandPlan(ALONG, query = q)
            }
        }
        for (suffix in alongSuffixes.sortedByDescending { it.length }) {
            if (!t.endsWith(suffix)) continue
            var q = original.substring(0, original.length - suffix.length).trim()
            if (q.isEmpty()) return SearchCommandPlan(ALONG)
            val lower = q.lowercase()
            for (prefix in alongForPrefixes) {
                if (lower.startsWith(prefix)) {
                    q = q.substring(prefix.length).trim()
                    break
                }
            }
            if (q.isNotEmpty()) return SearchCommandPlan(ALONG, query = q)
        }
        return null
    }

    /** Straight quotes, no trailing sentence punctuation, single spaces; case kept for the name. */
    private fun clean(text: String): String =
        text.trim()
            .replace(Regex("[“”«»‘’`]"), "'")
            .replace(Regex("[!?.,;:]+$"), "")
            .replace(Regex("\\s+"), " ")
            .trim()
}

/** Swift cannot call [Place]'s full generated initializer for a debug fixture; this keeps the
 *  construction in common code where the defaults stay in one place. */
object SearchCommandPlaces {
    fun place(id: String, name: String, address: String, lat: Double, lng: Double): Place =
        Place(id = id, name = name, location = LatLng(lat = lat, lng = lng), address = address)
}

/** What a corridor pass found: the kept places, the width used and both counts, for the debug line.
 *  [fromProgress] says the route was cut at the drive's current position, and [routeMeters] is the
 *  length the corridor actually ran on. */
data class CorridorSelection(
    val places: List<Place>,
    val corridorMeters: Double,
    val found: Int,
    val total: Int,
    val fromProgress: Boolean = false,
    val routeMeters: Double = 0.0,
)

/**
 * "Search along the route": keep the results within [maxMeters] of the active route and order them
 * by detour, the drive off the line and back (twice the perpendicular distance), then by how far
 * along the route they sit. The result's own distance is that detour, so the list reads in the
 * order a driver would add the stop. Above zero [select]'s [traveledMeters] also drops the places
 * whose projection lies behind the car, so a drive searches only the route left ahead. Android's
 * [app.vela.core.data.RouteCorridor] orders purely by travel order; this pass is the iOS command's
 * own ordering, and its numbers are what the debug line reports.
 */
object SearchCommandCorridor {
    const val DEFAULT_CORRIDOR_M = 3000.0

    fun select(
        places: List<Place>,
        route: List<LatLng>,
        maxMeters: Double = DEFAULT_CORRIDOR_M,
        /** The drive's monotonic progress; above zero the corridor starts at the car. */
        traveledMeters: Double = 0.0,
    ): CorridorSelection {
        if (route.size < 2) {
            return CorridorSelection(places, maxMeters, places.size, places.size)
        }
        val cumulative = DoubleArray(route.size)
        for (i in 1 until route.size) {
            cumulative[i] = cumulative[i - 1] + distanceMeters(route[i - 1], route[i])
        }
        val totalMeters = cumulative.last()
        // During a drive the corridor starts at the car: the route length left is what the corridor
        // runs on, and a place whose projection lies on the travelled part drops out. Both the
        // membership and the detour ordering therefore ignore what is already behind.
        val traveled = traveledMeters.coerceIn(0.0, totalMeters)
        val fromProgress = traveled > 0.0
        val routeMeters = totalMeters - traveled
        if (fromProgress && routeMeters < 1.0) {
            return CorridorSelection(
                emptyList(), maxMeters, 0, places.size, fromProgress, routeMeters)
        }
        val kept = places.mapNotNull { place ->
            var bestOff = Double.MAX_VALUE
            var bestAlong = 0.0
            for (i in 0 until route.size - 1) {
                val (off, t) = segmentDistance(place.location, route[i], route[i + 1])
                if (off < bestOff) {
                    bestOff = off
                    bestAlong = cumulative[i] + t * (cumulative[i + 1] - cumulative[i])
                }
            }
            val passed = fromProgress && bestAlong < traveled
            if (passed || bestOff > maxMeters) null else Triple(place, bestAlong, bestOff)
        }
            .sortedWith(compareBy<Triple<Place, Double, Double>> { it.third * 2.0 }.thenBy { it.second })
            .map { (place, _, off) -> place.copy(distanceMeters = off * 2.0) }
        return CorridorSelection(
            kept, maxMeters, kept.size, places.size, fromProgress, routeMeters)
    }

    /** Swift passes the route as the flat lat,lng array `RouteStore.line` already returns. */
    fun selectFlat(
        places: List<Place>,
        routeFlat: DoubleArray,
        maxMeters: Double = DEFAULT_CORRIDOR_M,
        traveledMeters: Double = 0.0,
    ): CorridorSelection {
        val route = ArrayList<LatLng>(routeFlat.size / 2)
        var i = 0
        while (i + 1 < routeFlat.size) {
            route.add(LatLng(routeFlat[i], routeFlat[i + 1]))
            i += 2
        }
        return select(places, route, maxMeters, traveledMeters)
    }

    private fun distanceMeters(a: LatLng, b: LatLng): Double {
        val lat = (a.lat + b.lat) / 2.0 * kotlin.math.PI / 180.0
        val dx = (b.lng - a.lng) * 111_320.0 * cos(lat)
        val dy = (b.lat - a.lat) * 111_320.0
        return hypot(dx, dy)
    }

    /** Distance from [p] to segment [a]–[b] and the fraction along it, on a local projection. */
    private fun segmentDistance(p: LatLng, a: LatLng, b: LatLng): Pair<Double, Double> {
        val mPerDegLat = 111_320.0
        val mPerDegLng = 111_320.0 * cos(((a.lat + b.lat) / 2.0) * kotlin.math.PI / 180.0)
        val bx = (b.lng - a.lng) * mPerDegLng
        val by = (b.lat - a.lat) * mPerDegLat
        val px = (p.lng - a.lng) * mPerDegLng
        val py = (p.lat - a.lat) * mPerDegLat
        val len2 = bx * bx + by * by
        val t = if (len2 == 0.0) 0.0 else ((px * bx + py * by) / len2).coerceIn(0.0, 1.0)
        return hypot(px - t * bx, py - t * by) to t
    }
}
