package app.vela.ios.world

import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.sat.SatelliteFix
import app.vela.core.sat.Sgp4
import app.vela.core.sat.Tle
import kotlinx.coroutines.CancellationException
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.roundToInt
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.time.Clock

/**
 * One satellite above the horizon as the map draws it: sub-satellite point, altitude, inertial
 * speed, and where it sits in the observer's sky. [tleEpochMs] is the age of the element set, so
 * the card never presents an old TLE as a current position.
 */
data class SatelliteSky(
    val catalogNumber: Int,
    val name: String,
    val latDeg: Double,
    val lonDeg: Double,
    val altitudeKm: Double,
    val speedKmS: Double,
    val elevationDeg: Double,
    val azimuthDeg: Double,
    val tleEpochMs: Long,
)

/** One pass over an observer: rise, culmination, set and the peak elevation. */
data class SatellitePass(
    val startMs: Long,
    val maxElevationMs: Long,
    val endMs: Long,
    val maxElevationDeg: Double,
)

/** One row for the World layers sheet. [lat] and [lng] are null on the status row. */
data class SatelliteRow(
    val id: String,
    val title: String,
    val detail: String,
    val lat: Double?,
    val lng: Double?,
)

/**
 * What one refresh produced. [updatedAtMs] is the TLE fetch time, which the host compares with its
 * two-hour window; [fixedAtMs] is non-zero only for the debug fixture, whose positions are
 * computed at a fixed instant instead of the wall clock.
 */
data class SatelliteSnapshot(
    val updatedAtMs: Long,
    val satellites: List<SatelliteSky>,
    val rows: List<SatelliteRow>,
    val phase: String,
    val detail: String,
    val live: Boolean,
    val tleCount: Int,
    val skippedCount: Int,
    val observerLatDeg: Double,
    val observerLonDeg: Double,
    val fixedAtMs: Long,
)

/** One point of a ground track, used for the selected satellite's orbit. */
data class SatelliteTrackPoint(val latDeg: Double, val lonDeg: Double)

/**
 * Satellites for the G-3 layer, from CelesTrak GP (Dr T.S. Kelso).
 *
 * Politeness, as the usage policy asks and the lot accepts:
 * - one refresh cycle at most every [CACHE_MS] (two hours), whether it succeeded or not, so a
 *   camera move never turns into a request and a failing host is not hammered;
 * - inside a cycle, one request per group, in order: `stations`, `weather`, `science`;
 * - the first answer that is not 2xx stops the cycle at once; the previous cache stays and the
 *   layer says how old it is. No other group is asked;
 * - the TLE text and the fetch time are written to the shared key-value store, which iOS persists
 *   on disk, and a new process reads them instead of asking again.
 *
 * Propagation is local. A TLE older than [Sgp4.MAX_EPOCH_AGE_DAYS], a decayed orbit, an invalid
 * element set and a deep-space orbit (GPS, Molniya, geostationary: SDP4 is out of scope) are
 * dropped, never approximated. The map keeps the satellites above the horizon of the observer and
 * inside the viewport, at most [MAX_SATELLITES], nearest the top of the sky first.
 */
class SatelliteStore internal constructor(
    private val http: VelaHttp?,
    private val cache: KeyValueStore?,
    private val now: () -> Long = { Clock.System.now().toEpochMilliseconds() },
) {
    constructor(http: VelaHttp?, stores: KeyValueStores?) : this(http, stores?.open(STORE))

    private var tles: List<Tle> = emptyList()
    private var lastCycleAtMs = 0L

    /**
     * One refresh for this viewport. Inside the two-hour window it answers from the cache without
     * a request. [zoom] below 2 means the whole planet is the view, so the viewport box does not
     * cut the sky there.
     */
    suspend fun refresh(
        nowMs: Long = now(),
        observerLatDeg: Double,
        observerLonDeg: Double,
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        zoom: Double,
    ): SatelliteSnapshot {
        val cycleAt = cache?.getLong(KEY_CYCLE_AT, 0L) ?: lastCycleAtMs
        if (cycleAt > 0L && nowMs - cycleAt in 0 until CACHE_MS) {
            return build(
                atMs = nowMs, stampMs = nowMs, observerLatDeg, observerLonDeg,
                south, west, north, east, zoom, live = false, detail = "", fixedAtMs = 0L)
        }
        val client = http
        if (client == null) {
            lastCycleAtMs = nowMs
            return build(
                atMs = nowMs, stampMs = nowMs, observerLatDeg, observerLonDeg,
                south, west, north, east, zoom, live = false,
                detail = "No network client", fixedAtMs = 0L)
        }

        var failure: String? = null
        for (group in GROUPS) {
            val response = try {
                client.call(HttpRequest(
                    url = "$BASE_URL?GROUP=$group&FORMAT=tle",
                    headers = listOf(
                        HttpHeader("Accept", "text/plain"),
                        HttpHeader("User-Agent", "Vela/0.1 (iOS)"),
                    ),
                    timeoutMillis = 20_000,
                ))
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                failure = "CelesTrak unavailable"
                break
            }
            if (!response.isSuccessful) {
                failure = "CelesTrak unavailable (HTTP ${response.code})"
                break
            }
            cache?.edit()
                ?.putString(bodyKey(group), response.bodyText())
                ?.putLong(timeKey(group), nowMs)
                ?.apply()
        }
        // The attempt time is recorded even on failure: the usage policy allows one cycle per
        // two hours, not one per camera move.
        cache?.edit()?.putLong(KEY_CYCLE_AT, nowMs)?.apply()
        lastCycleAtMs = nowMs
        return build(
            atMs = nowMs, stampMs = nowMs, observerLatDeg, observerLonDeg,
            south, west, north, east, zoom,
            live = failure == null, detail = failure ?: "", fixedAtMs = 0L)
    }

    /**
     * Debug-only fixture path: the same parsing, horizon and viewport rules, propagated at
     * [atMs] instead of the wall clock. [stampMs] is what the sheet shows as the data time, so a
     * fixture captured now reads fresh while its positions stay reproducible. Never live.
     */
    fun parseFixture(
        text: String,
        atMs: Long,
        stampMs: Long,
        observerLatDeg: Double,
        observerLonDeg: Double,
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        zoom: Double,
    ): SatelliteSnapshot {
        tles = Sgp4.parseTles(text).distinctBy { it.catalogNumber }
        return build(
            atMs = atMs, stampMs = stampMs, observerLatDeg, observerLonDeg,
            south, west, north, east, zoom, live = false, detail = "", fixedAtMs = atMs,
            overrideTles = tles)
    }

    /**
     * The ground track from [fromMs] for [minutes], one point every [stepSeconds]. A null result
     * is an unknown catalogue number or a TLE the propagator refuses.
     */
    fun orbitTrack(
        catalogNumber: Int,
        fromMs: Long,
        minutes: Int = 100,
        stepSeconds: Int = 60,
    ): List<SatelliteTrackPoint> {
        val tle = tles.firstOrNull { it.catalogNumber == catalogNumber } ?: return emptyList()
        val out = ArrayList<SatelliteTrackPoint>(minutes * 60 / stepSeconds + 1)
        val stepMs = stepSeconds * 1_000L
        val end = fromMs + minutes * 60_000L
        var at = fromMs
        while (at <= end) {
            val fix = Sgp4.fix(tle, at)
            if (fix != null) out += SatelliteTrackPoint(fix.latDeg, fix.lonDeg)
            at += stepMs
        }
        return out
    }

    /**
     * The next pass of [catalogNumber] over the observer, starting at or after [fromMs]. When the
     * satellite is above the horizon at [fromMs] this is the next pass after it sets. A 48-hour
     * scan at 60 s with a 20-step rise refinement; null when there is no pass in that window.
     */
    fun nextPass(
        catalogNumber: Int,
        observerLatDeg: Double,
        observerLonDeg: Double,
        fromMs: Long,
    ): SatellitePass? {
        val tle = tles.firstOrNull { it.catalogNumber == catalogNumber } ?: return null
        val stepMs = 60_000L
        val end = fromMs + PASS_SCAN_MS
        var t = fromMs
        var previous = elevationDeg(tle, t, observerLatDeg, observerLonDeg) ?: return null
        var above = previous > 0.0
        var riseAt = -1L
        while (t < end) {
            val next = t + stepMs
            val elevation = elevationDeg(tle, next, observerLatDeg, observerLonDeg) ?: return null
            if (above) {
                if (elevation <= 0.0) above = false
            } else if (previous <= 0.0 && elevation > 0.0) {
                riseAt = refineRise(tle, t, next, observerLatDeg, observerLonDeg)
                break
            }
            previous = elevation
            t = next
        }
        if (riseAt < 0L) return null

        var maxElevation = -90.0
        var maxAt = riseAt
        var endAt = riseAt
        var at = riseAt
        while (at <= end) {
            val elevation = elevationDeg(tle, at, observerLatDeg, observerLonDeg) ?: break
            if (at > riseAt && elevation <= 0.0) {
                endAt = at
                break
            }
            if (elevation > maxElevation) {
                maxElevation = elevation
                maxAt = at
            }
            endAt = at
            at += 30_000L
        }
        return SatellitePass(
            startMs = riseAt,
            maxElevationMs = maxAt,
            endMs = endAt,
            maxElevationDeg = maxElevation,
        )
    }

    private fun build(
        atMs: Long,
        stampMs: Long,
        observerLatDeg: Double,
        observerLonDeg: Double,
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        zoom: Double,
        live: Boolean,
        detail: String,
        fixedAtMs: Long,
        overrideTles: List<Tle>? = null,
    ): SatelliteSnapshot {
        val bodies = GROUPS.mapNotNull { group -> cache?.getString(bodyKey(group), null) }
        val parsed = overrideTles ?: if (bodies.isEmpty()) {
            tles
        } else {
            Sgp4.parseTles(bodies.joinToString("\n")).distinctBy { it.catalogNumber }
        }
        if (bodies.isNotEmpty()) tles = parsed

        val newest = GROUPS.mapNotNull { group ->
            cache?.getLong(timeKey(group), 0L)?.takeIf { it > 0L }
        }.maxOrNull() ?: 0L
        val stamp = if (fixedAtMs > 0L) stampMs else newest
        val phase = when {
            stamp <= 0L -> WorldLayerStatuses.UNAVAILABLE
            stampMs - stamp > CACHE_MS -> WorldLayerStatuses.LATE
            else -> WorldLayerStatuses.FRESH
        }
        val wholePlanet = zoom < 2.0 || (east - west) >= 350.0
        val sky = ArrayList<SatelliteSky>(parsed.size)
        var skipped = 0
        for (tle in parsed) {
            val fix = Sgp4.fix(tle, atMs)
            if (fix == null) {
                skipped += 1
                continue
            }
            val (elevation, azimuth) = lookAngles(fix, observerLatDeg, observerLonDeg)
            if (elevation <= 0.0) continue
            if (!wholePlanet && !inViewport(fix, south, west, north, east)) continue
            sky += SatelliteSky(
                catalogNumber = tle.catalogNumber,
                name = tle.name,
                latDeg = fix.latDeg,
                lonDeg = fix.lonDeg,
                altitudeKm = fix.altitudeKm,
                speedKmS = fix.speedKmS,
                elevationDeg = elevation,
                azimuthDeg = azimuth,
                tleEpochMs = tle.epochMs,
            )
        }
        sky.sortWith(compareByDescending<SatelliteSky> { it.elevationDeg }
            .thenBy { it.catalogNumber })
        val visible = sky.take(MAX_SATELLITES)

        val rows = ArrayList<SatelliteRow>(visible.size + 1)
        rows += SatelliteRow(
            id = "sat-status",
            title = statusTitle(phase, visible.size),
            detail = buildString {
                append("Above the horizon of the view center, TLE cached two hours at most.")
                if (phase == WorldLayerStatuses.LATE) append(" Data is late.")
                if (detail.isNotEmpty()) append(" ").append(detail).append(".")
            },
            lat = null,
            lng = null,
        )
        for (satellite in visible) {
            rows += SatelliteRow(
                id = "satellite-${satellite.catalogNumber}",
                title = satellite.name,
                detail = "Alt ${satellite.altitudeKm.roundToInt()} km, " +
                    "${twoDecimals(satellite.speedKmS)} km/s, " +
                    "elev ${satellite.elevationDeg.roundToInt()} deg",
                lat = satellite.latDeg,
                lng = satellite.lonDeg,
            )
        }

        return SatelliteSnapshot(
            updatedAtMs = stamp,
            satellites = visible,
            rows = rows,
            phase = phase,
            detail = detail.ifEmpty { statusDetail(phase, parsed.size, visible.size, skipped) },
            live = live && phase == WorldLayerStatuses.FRESH,
            tleCount = parsed.size - skipped,
            skippedCount = skipped,
            observerLatDeg = observerLatDeg,
            observerLonDeg = observerLonDeg,
            fixedAtMs = fixedAtMs,
        )
    }

    private fun statusTitle(phase: String, count: Int): String = when (phase) {
        WorldLayerStatuses.FRESH ->
            if (count == 1) "1 satellite above the horizon" else "$count satellites above the horizon"
        WorldLayerStatuses.LATE -> "TLE older than two hours, still propagated"
        else -> "No TLE yet"
    }

    private fun statusDetail(phase: String, parsed: Int, visible: Int, skipped: Int): String {
        val head = when (phase) {
            WorldLayerStatuses.FRESH -> "CelesTrak GP, TLE cached at most two hours."
            WorldLayerStatuses.LATE -> "CelesTrak GP, TLE older than two hours."
            else -> "CelesTrak GP, no element set cached yet."
        }
        return "$head $parsed element sets, $skipped refused (decayed, invalid, too old or deep " +
            "space), $visible above the horizon."
    }

    private fun refineRise(
        tle: Tle,
        belowMs: Long,
        aboveMs: Long,
        observerLatDeg: Double,
        observerLonDeg: Double,
    ): Long {
        var low = belowMs
        var high = aboveMs
        repeat(20) {
            val mid = low + (high - low) / 2
            val elevation = elevationDeg(tle, mid, observerLatDeg, observerLonDeg) ?: return high
            if (elevation > 0.0) high = mid else low = mid
        }
        return high
    }

    private fun elevationDeg(
        tle: Tle,
        atMs: Long,
        observerLatDeg: Double,
        observerLonDeg: Double,
    ): Double? {
        val fix = Sgp4.fix(tle, atMs) ?: return null
        return lookAngles(fix, observerLatDeg, observerLonDeg).first
    }

    /** Topocentric elevation and azimuth in degrees for an ECEF fix and a WGS-84 observer. */
    private fun lookAngles(
        fix: SatelliteFix,
        observerLatDeg: Double,
        observerLonDeg: Double,
    ): Pair<Double, Double> {
        val lat = observerLatDeg * DEG
        val lon = observerLonDeg * DEG
        val sinLat = sin(lat)
        val cosLat = cos(lat)
        val sinLon = sin(lon)
        val cosLon = cos(lon)
        val n = WGS84_A / sqrt(1.0 - WGS84_E2 * sinLat * sinLat)
        val obsX = n * cosLat * cosLon
        val obsY = n * cosLat * sinLon
        val obsZ = n * (1.0 - WGS84_E2) * sinLat
        val dx = fix.ecefXKm - obsX
        val dy = fix.ecefYKm - obsY
        val dz = fix.ecefZKm - obsZ
        val range = sqrt(dx * dx + dy * dy + dz * dz)
        if (range < 1e-9) return 90.0 to 0.0
        val up = dx * cosLat * cosLon + dy * cosLat * sinLon + dz * sinLat
        val east = -dx * sinLon + dy * cosLon
        val north = -dx * sinLat * cosLon - dy * sinLat * sinLon + dz * cosLat
        val elevation = asin((up / range).coerceIn(-1.0, 1.0)) / DEG
        var azimuth = atan2(east, north) / DEG
        if (azimuth < 0.0) azimuth += 360.0
        return elevation to azimuth
    }

    private fun inViewport(
        fix: SatelliteFix,
        south: Double,
        west: Double,
        north: Double,
        east: Double,
    ): Boolean {
        if (north <= south) return false
        val lat = fix.latDeg
        if (lat < south || lat > north) return false
        val lon = fix.lonDeg
        return if (west <= east) lon in west..east else (lon >= west || lon <= east)
    }

    companion object {
        const val STORE = "vela_satellites"

        /** The one CelesTrak GP endpoint; one request per group inside a cycle. */
        const val BASE_URL = "https://celestrak.org/NORAD/elements/gp.php"

        /** The groups G-3 asks for. Near-Earth element sets only; deep space is dropped. */
        val GROUPS: List<String> = listOf("stations", "weather", "science")

        /** Two hours, the CelesTrak usage policy and the sheet's freshness window. */
        const val CACHE_MS = 2L * 60L * 60L * 1_000L

        /** The pass search window. */
        const val PASS_SCAN_MS = 48L * 60L * 60L * 1_000L

        /** Visible satellites kept from one refresh. */
        const val MAX_SATELLITES = 120

        private const val KEY_CYCLE_AT = "tle_cycle_at"
        private const val DEG = kotlin.math.PI / 180.0
        private const val WGS84_A = 6378.137
        private const val WGS84_F = 1.0 / 298.257223563
        private const val WGS84_E2 = WGS84_F * (2.0 - WGS84_F)

        fun bodyKey(group: String): String = "tle_$group"

        fun timeKey(group: String): String = "tle_${group}_at"

        private fun twoDecimals(value: Double): String {
            val scaled = (value * 100.0).roundToInt()
            return "${scaled / 100}.${(abs(scaled) % 100).toString().padStart(2, '0')}"
        }
    }
}
