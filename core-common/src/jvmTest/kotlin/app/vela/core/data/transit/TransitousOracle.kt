package app.vela.core.data.transit

import app.vela.core.model.LatLng
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitLine
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import app.vela.core.model.distanceTo
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * The plan parser, ISO parse and clock text of [Transitous] as they were before the client moved
 * to `:core-common` (org.json, `SimpleDateFormat`, `java.time`), kept unchanged as the oracle of
 * `TransitousJvmParityTest`. The duration formatter hook is left out (the English form only).
 */
object TransitousOracle {
    fun legPath(leg: org.json.JSONObject): List<LatLng>? {
        val g = leg.optJSONObject("legGeometry") ?: return null
        val pts = g.optString("points", "").takeIf { it.isNotBlank() } ?: return null
        val precision = g.optInt("precision", 6).coerceIn(5, 7)
        return runCatching { app.vela.core.data.google.PolylineCodec.decode(pts, precision) }.getOrNull()
            ?.filter { it.lat in -90.0..90.0 && it.lng in -180.0..180.0 }?.takeIf { it.size >= 2 }
    }

    fun pickLegShape(json: String, board: LatLng, alight: LatLng): List<LatLng>? {
        val its = org.json.JSONObject(json).optJSONArray("itineraries") ?: return null
        val chord = board.distanceTo(alight)
        var best: List<LatLng>? = null
        for (i in 0 until its.length()) {
            val legs = its.getJSONObject(i).optJSONArray("legs") ?: continue
            for (k in 0 until legs.length()) {
                val leg = legs.getJSONObject(k)
                if (leg.optString("mode", "") in setOf("WALK", "BIKE", "CAR", "RENTAL")) continue
                val from = leg.optJSONObject("from")?.let { point(it) } ?: continue
                val to = leg.optJSONObject("to")?.let { point(it) } ?: continue
                if (from.distanceTo(board) > LEG_SHAPE_STOP_M || to.distanceTo(alight) > LEG_SHAPE_STOP_M) continue
                val path = legPath(leg) ?: continue
                // A path that is only the stops again adds nothing over the chords already drawn,
                // and one far longer than the ride is some other way round.
                val stops = (leg.optJSONArray("intermediateStops")?.length() ?: 0) + 2
                var len = 0.0
                for (p in 1 until path.size) len += path[p - 1].distanceTo(path[p])
                if (path.size <= stops + 1 || len > chord * LEG_SHAPE_MAX_RATIO + 500) continue
                if (best == null || path.size > best.size) best = path
            }
        }
        return best
    }

    /** A planner leg counts as "this ride" when both its ends are within this of the stops. */
    const val LEG_SHAPE_STOP_M = 300.0
    const val LEG_SHAPE_MAX_RATIO = 4.0

    fun parsePlan(json: String, origin: LatLng, destination: LatLng): List<TransitItinerary> {
        val root = JSONObject(json)
        val its = root.optJSONArray("itineraries") ?: return emptyList()
        return (0 until its.length()).mapNotNull { i -> runCatching { parseItinerary(its.getJSONObject(i), origin, destination) }.getOrNull() }
    }

    fun parseItinerary(it: JSONObject, origin: LatLng, destination: LatLng): TransitItinerary? {
        val legs = it.optJSONArray("legs") ?: return null
        val steps = ArrayList<TransitStep>()
        for (i in 0 until legs.length()) {
            val leg = legs.getJSONObject(i)
            val mode = leg.optString("mode", "")
            val from = leg.optJSONObject("from"); val to = leg.optJSONObject("to")
            val start = parseIso(leg.optString("startTime", "")); val end = parseIso(leg.optString("endTime", ""))
            val secs = leg.optLong("duration", if (start != null && end != null) end - start else 0L)
            if (mode == "WALK" || mode == "BIKE" || mode == "CAR" || mode == "RENTAL") {
                // A transfer walk between two stops, or the first/last mile: the app fetches the
                // turn-by-turn steps for it on demand from the walk router, like the Google legs.
                steps += TransitStep(
                    mode = TransitMode.WALK, durationText = durationText(secs),
                    walkFrom = from?.let { point(it) } ?: origin, walkTo = to?.let { point(it) } ?: destination,
                    path = legPath(leg), modeName = mode,
                    departEpochSec = start, arriveEpochSec = end,
                )
                continue
            }
            val tz = from?.optString("tz", null)
            val line = TransitLine(
                name = leg.optString("routeShortName", "").ifBlank { leg.optString("displayName", "") }.ifBlank { leg.optString("routeLongName", "") },
                mode = modeOf(mode),
                colorHex = leg.optString("routeColor", "").takeIf { it.isNotBlank() }?.let { "#" + it.removePrefix("#") },
                textColorHex = leg.optString("routeTextColor", "").takeIf { it.isNotBlank() }?.let { "#" + it.removePrefix("#") },
            )
            val board = from?.let { stopTime(it, "departure", "scheduledDeparture", tz) }
            val alight = to?.let { stopTime(it, "arrival", "scheduledArrival", to.optString("tz", null) ?: tz) }
            val mids = leg.optJSONArray("intermediateStops")?.let { a ->
                (0 until a.length()).mapNotNull { k -> a.optJSONObject(k)?.let { stopTime(it, "arrival", "scheduledArrival", it.optString("tz", null) ?: tz) } }
            }.orEmpty()
            val startSched = parseIso(leg.optString("scheduledStartTime", ""))
            val delayMin = if (start != null && startSched != null && leg.optBoolean("realTime", false)) ((start - startSched) / 60).toInt() else null
            steps += TransitStep(
                mode = line.mode, durationText = durationText(secs), line = line,
                departText = start?.let { clockText(it, tz) }, arriveText = end?.let { clockText(it, to?.optString("tz", null) ?: tz) },
                headsign = leg.optString("headsign", "").takeIf { it.isNotBlank() },
                boardStop = board, alightStop = alight, numStops = mids.size + 1,
                delayText = delayMin?.let { delayText(it) }, intermediateStops = mids,
                path = legPath(leg), modeName = mode,
                agencyName = leg.optString("agencyName", "").takeIf { it.isNotBlank() },
                departEpochSec = start, arriveEpochSec = end,
            )
        }
        if (steps.none { it.line != null }) return null // a walk-only answer is not a transit trip
        val startEp = parseIso(it.optString("startTime", "")); val endEp = parseIso(it.optString("endTime", ""))
        val firstTz = legs.getJSONObject(0).optJSONObject("from")?.optString("tz", null)
        val lastTz = legs.getJSONObject(legs.length() - 1).optJSONObject("to")?.optString("tz", null) ?: firstTz
        var agency: String? = null
        for (i in 0 until legs.length()) legs.getJSONObject(i).optString("agencyName", "").takeIf { it.isNotBlank() }?.let { if (agency == null) agency = it }
        return TransitItinerary(
            departureEpochSec = startEp, arrivalEpochSec = endEp,
            departureText = startEp?.let { clockText(it, firstTz) }, arrivalText = endEp?.let { clockText(it, lastTz) },
            durationText = durationText(it.optLong("duration", if (startEp != null && endEp != null) endEp - startEp else 0L)),
            agency = agency, lines = steps.mapNotNull { s -> s.line }, steps = steps,
        )
    }

    fun point(o: JSONObject): LatLng? {
        val lat = o.optDouble("lat", Double.NaN); val lng = o.optDouble("lon", Double.NaN)
        return if (lat.isNaN() || lng.isNaN()) null else LatLng(lat, lng)
    }

    fun stopTime(o: JSONObject, liveKey: String, schedKey: String, tz: String?): TransitStopTime {
        val live = parseIso(o.optString(liveKey, "")); val sched = parseIso(o.optString(schedKey, ""))
        val shown = live ?: sched
        return TransitStopTime(
            name = o.optString("name", ""), code = o.optString("stopCode", "").takeIf { it.isNotBlank() },
            stopId = o.optString("stopId", "").takeIf { it.isNotBlank() },
            timeText = shown?.let { clockText(it, tz) },
            scheduledText = if (live != null && sched != null && live != sched) clockText(sched, tz) else null,
            location = point(o), canceled = o.optBoolean("cancelled", false),
            delayMin = if (live != null && sched != null && live != sched) ((live - sched) / 60).toInt() else null,
        )
    }

    /** "45 min" / "1 h 5 min", the shape the chooser's chips already fold. */
    fun durationText(secs: Long): String {
                val m = ((secs + 30) / 60).coerceAtLeast(1)
        return if (m < 60) "$m min" else if (m % 60 == 0L) "${m / 60} h" else "${m / 60} h ${m % 60} min"
    }

    fun delayText(min: Int): String? = app.vela.core.i18n.DelayText.of(min)

    fun parseIso(iso: String): Long? = runCatching { java.time.Instant.parse(iso).epochSecond }.getOrNull()

    /** Clock text in the STOP's timezone (falls back to the device zone): 12-hour like the
     *  Google boards, or 24-hour when the device's clock setting says so ([ClockFormat],
     *  issue #357). */
    fun clockText(epochSec: Long, tz: String?): String {
        val fmt = SimpleDateFormat(if (app.vela.core.data.ClockFormat.use24h) "HH:mm" else "h:mm a", Locale.US)
        fmt.timeZone = tz?.let { runCatching { TimeZone.getTimeZone(it) }.getOrNull() } ?: TimeZone.getDefault()
        return fmt.format(Date(epochSec * 1000))
    }

    fun modeOf(mode: String?): TransitMode = when (mode?.uppercase()) {
        "BUS", "COACH" -> TransitMode.BUS
        "TRAM" -> TransitMode.TRAM
        "SUBWAY", "METRO" -> TransitMode.SUBWAY
        "RAIL", "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL" -> TransitMode.TRAIN
        "FERRY" -> TransitMode.FERRY
        else -> TransitMode.GENERIC
    }

    fun instantText(epochSec: Long): String = java.time.Instant.ofEpochSecond(epochSec).toString()
}
