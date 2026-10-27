package app.vela.ios.replay

import app.vela.core.model.LatLng
import app.vela.core.model.Route
import app.vela.core.model.distanceTo
import app.vela.core.platform.Clock
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.joinPath
import app.vela.core.replay.TripLog
import app.vela.core.replay.TripScrub
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

/** One row of the saved-trip list. [partial] marks a file left by a force quit or a crash. */
data class TripSummary(
    val id: String,
    val label: String,
    val startedAt: Long,
    val distanceM: Double,
    val durationMs: Long,
    val fixes: Int,
    val partial: Boolean,
)

/** One recorded fix as the trip detail draws it. [tMs] is relative to the first fix. */
data class TripPoint(
    val lat: Double,
    val lng: Double,
    val tMs: Long,
    val speedMps: Double,
    /** Meters from the first point, along the trace. */
    val distanceM: Double,
)

/** A place where the trace stayed still for [TripStops.MIN_STOP_MS] at least. */
data class TripStop(
    val lat: Double,
    val lng: Double,
    val startMs: Long,
    val endMs: Long,
)

/** Everything the detail screen needs, read in one pass over the CSV. */
data class TripDetail(
    val summary: TripSummary,
    val points: List<TripPoint>,
    val stops: List<TripStop>,
    val maxSpeedMps: Double,
    val averageSpeedMps: Double,
    val maneuvers: Int,
    val routeSegments: Int,
)

/** The fixes [radiusM] would keep, shown before anything leaves the phone. */
data class TripTrim(
    val radiusM: Double,
    val fixesBefore: Int,
    val fixesAfter: Int,
    val trimmable: Boolean,
)

/**
 * Records and reads Vela trips on iOS, in the same CSV format as Android's `:app` TripStore: the
 * writer and every reader share [TripLog], so a trip recorded on either platform replays the same.
 *
 * Files live in `Application Support/trips`. A drive being recorded is written as
 * `trip_<startedAt>.csv.recording`, replaced atomically every few fixes: a force quit leaves a
 * parseable file that the list marks partial, and the user may keep or delete it. [finishTrip]
 * renames it to `.csv`; a drive with fewer than five fixes is deleted rather than listed.
 *
 * Nothing here uploads, logs or names a coordinate: the label and destination in `META` are local
 * only, and [exportScrubbedCsv] is the one path out of the phone.
 */
class TripsStore(
    private val files: PlatformFiles,
    private val prefs: KeyValueStore?,
    private val clock: Clock,
) {
    /** The build that recorded a trip, in the `META` version slot. Set once by the app. */
    var versionCode: Int = 0

    private val dir: String get() = joinPath(files.filesDir, "trips")
    private val lock = SynchronizedObject()

    private var activeId: String? = null
    private var activePath: String? = null
    private var activeLines: MutableList<String> = mutableListOf()
    private var activeFixes = 0
    private var unflushedFixes = 0

    /** The opt-in switch, off by default. Stored under the trips' own key. */
    var recordingEnabled: Boolean
        get() = prefs?.getBoolean(RECORDING_KEY, false) ?: false
        set(value) {
            prefs?.edit()?.putBoolean(RECORDING_KEY, value)?.apply()
        }

    val isRecording: Boolean get() = synchronized(lock) { activeId != null }

    /**
     * Begins a drive. Returns the new id, or null when one is already recording or the folder
     * cannot be created. [dest] is kept only in the local header; a share removes it.
     */
    fun startTrip(label: String, dest: LatLng?, startedAt: Long): String? = synchronized(lock) {
        if (activeId != null) return null
        if (!files.mkdirs(dir)) return null
        val id = "trip_$startedAt"
        val safe = label.replace(',', ' ').replace('\n', ' ').trim().take(80).ifBlank { "Trip" }
        val meta = "META,$safe,$startedAt,${dest?.lat ?: ""},${dest?.lng ?: ""},$versionCode"
        activeId = id
        activePath = joinPath(dir, "$id$RECORDING_SUFFIX")
        activeLines = mutableListOf(meta)
        activeFixes = 0
        unflushedFixes = 0
        if (!flushLocked()) {
            activeId = null
            activePath = null
            return null
        }
        id
    }

    /** Appends one fix. A NaN measurement is written as an empty field, as Android's writer does. */
    fun recordFix(
        latitude: Double,
        longitude: Double,
        t: Long,
        bearingDeg: Double,
        speedMps: Double,
        offRoute: Boolean,
        accuracyM: Double,
        provider: String,
        offRouteHits: Int,
    ) = synchronized(lock) {
        if (activeId == null) return
        val accuracy = if (accuracyM.isFinite()) accuracyM.toString() else ""
        activeLines += "$latitude,$longitude,$t,${bearingDeg.toFloat()},${speedMps.toFloat()}," +
            "${if (offRoute) 1 else 0},$accuracy,${provider.replace(',', ' ')},$offRouteHits"
        activeFixes++
        unflushedFixes++
        if (unflushedFixes >= FLUSH_EVERY_FIXES) flushLocked()
        Unit
    }

    /** Appends a route block: the blue line and its maneuvers. A mid-drive swap starts a new one. */
    fun saveRoute(route: Route, reason: String = "") = synchronized(lock) {
        if (activeId == null || route.polyline.size < 2) return
        activeLines += TripLog.encodeRoute(route, reason).split('\n').filter { it.isNotBlank() }
        flushLocked()
        Unit
    }

    /** Appends a nav decision note. [text] must hold no coordinate, typed text or place name. */
    fun note(tag: String, text: String) = synchronized(lock) {
        if (activeId == null) return
        activeLines += "$tag,${clock.nowMillis()},${text.replace("\n", " ").replace("\r", "")}"
        flushLocked()
        Unit
    }

    /**
     * Closes the active drive. Returns the saved trip, or null when nothing was recording or the
     * drive was too short to keep. Idempotent: a second call is a no-op.
     */
    fun finishTrip(): TripSummary? = synchronized(lock) {
        val id = activeId ?: return null
        val path = activePath ?: return null
        flushLocked()
        activeId = null
        activePath = null
        activeLines = mutableListOf()
        if (activeFixes < MIN_FIXES) {
            files.delete(path)
            return null
        }
        val finalPath = joinPath(dir, "$id.csv")
        if (!files.rename(path, finalPath)) {
            val kept = runCatching {
                files.writeTextAtomic(finalPath, readRecordingLocked(path))
                files.delete(path)
            }.isSuccess
            if (!kept) return null
        }
        summaryOf(id, partial = false)
    }

    /** Throws away the active drive without listing it. Used when the user discards on purpose. */
    fun discard() = synchronized(lock) {
        val path = activePath ?: return
        files.delete(path)
        activeId = null
        activePath = null
        activeLines = mutableListOf()
        Unit
    }

    /** Every saved trip, newest first, partial (force-quit) recordings included. */
    fun list(): List<TripSummary> = synchronized(lock) {
        val entries = files.list(dir).orEmpty()
        entries.mapNotNull { entry ->
            val partial = entry.name.endsWith(RECORDING_SUFFIX)
            val csv = entry.name.endsWith(".csv")
            if (!csv && !partial) return@mapNotNull null
            val id = entry.name.removeSuffix(RECORDING_SUFFIX).removeSuffix(".csv")
            summaryOf(id, partial)
        }.sortedByDescending { it.startedAt }
    }

    fun summary(id: String): TripSummary? = synchronized(lock) {
        val path = pathOf(id) ?: return null
        summaryOf(id, partial = path.endsWith(RECORDING_SUFFIX))
    }

    /** The raw CSV, or null when the trip is missing. Callers share only scrubbed copies. */
    fun rawCsv(id: String): String? = synchronized(lock) {
        val path = pathOf(id) ?: return null
        runCatching { files.readText(path) }.getOrNull()
    }

    /** Renames a trip. The header surgery is [TripLog.renameHeader]; the write is atomic. */
    fun rename(id: String, label: String): Boolean = synchronized(lock) {
        val path = pathOf(id) ?: return false
        val out = runCatching {
            val lines = files.readText(path).split('\n').filter { it.isNotBlank() }
            TripLog.renameHeader(lines, label) ?: return false
        }.getOrNull() ?: return false
        runCatching { files.writeTextAtomic(path, out.joinToString("\n") + "\n") }.isSuccess
    }

    /** Keeps a partial recording: it stops being marked partial and is listed as a normal trip. */
    fun keepPartial(id: String): Boolean = synchronized(lock) {
        val from = joinPath(dir, "$id$RECORDING_SUFFIX")
        if (!files.exists(from)) return false
        files.rename(from, joinPath(dir, "$id.csv"))
    }

    fun delete(id: String) = synchronized(lock) {
        files.delete(joinPath(dir, "$id.csv"))
        files.delete(joinPath(dir, "$id$RECORDING_SUFFIX"))
        Unit
    }

    /** Parses the trace once for the detail screen. Null when the file is missing or empty. */
    fun detail(id: String): TripDetail? {
        val summary = summary(id) ?: return null
        val csv = rawCsv(id) ?: return null
        val parsed = runCatching { TripLog.parse(csv) }.getOrNull() ?: return null
        if (parsed.points.isEmpty()) return null
        val t0 = parsed.points.first().t
        var distance = 0.0
        var maxSpeed = 0.0
        var speedSum = 0.0
        var speedCount = 0
        val points = ArrayList<TripPoint>(parsed.points.size)
        for ((index, p) in parsed.points.withIndex()) {
            if (index > 0) {
                val prev = parsed.points[index - 1]
                distance += LatLng(prev.lat, prev.lng).distanceTo(LatLng(p.lat, p.lng))
            }
            val speed = p.speed.toDouble().coerceAtLeast(0.0)
            if (speed.isFinite()) {
                maxSpeed = maxOf(maxSpeed, speed)
                speedSum += speed
                speedCount++
            }
            points += TripPoint(p.lat, p.lng, (p.t - t0).coerceAtLeast(0L), speed, distance)
        }
        val maneuvers = parsed.segments.sumOf { it.route.maneuvers.size }
        return TripDetail(
            summary = summary,
            points = points,
            stops = stopsOf(points),
            maxSpeedMps = maxSpeed,
            averageSpeedMps = if (speedCount > 0) speedSum / speedCount else 0.0,
            maneuvers = maneuvers,
            routeSegments = parsed.segments.size,
        )
    }

    /** How many fixes [radiusM] keeps, before a share. */
    fun previewTrim(id: String, radiusM: Double = TripScrub.DEFAULT_RADIUS_M): TripTrim? {
        val csv = rawCsv(id) ?: return null
        val before = TripLog.parsePoints(csv.split('\n')).size
        val report = runCatching {
            TripScrub.scrub(csv, radiusM, label = SHARED_LABEL)
        }.getOrNull()
        return TripTrim(radiusM, before, report?.fixesAfter ?: 0, report != null)
    }

    /** The scrubbed CSV, with both ends, the destination and the label removed. */
    fun exportScrubbedCsv(id: String, radiusM: Double = TripScrub.DEFAULT_RADIUS_M): String? {
        val csv = rawCsv(id) ?: return null
        return runCatching { TripScrub.scrub(csv, radiusM, label = SHARED_LABEL) }.getOrNull()?.csv
    }

    /** The scrubbed trace as GPX. Null when the trim leaves nothing shareable. */
    fun exportGpx(id: String, radiusM: Double = TripScrub.DEFAULT_RADIUS_M): String? =
        exportScrubbedCsv(id, radiusM)?.let { TripExport.gpx(it) }

    private fun pathOf(id: String): String? {
        val finalPath = joinPath(dir, "$id.csv")
        if (files.exists(finalPath)) return finalPath
        val partial = joinPath(dir, "$id$RECORDING_SUFFIX")
        if (files.exists(partial)) return partial
        return null
    }

    private fun summaryOf(id: String, partial: Boolean): TripSummary? = runCatching {
        val path = pathOf(id) ?: return null
        val text = files.readText(path)
        val lines = text.split('\n').filter { it.isNotBlank() }
        val header = lines.firstOrNull { it.startsWith("META,") } ?: return null
        val f = header.removePrefix("META,").split(',')
        val stats = TripLog.stats(lines.asSequence())
        TripSummary(
            id = id,
            label = f.getOrNull(0)?.ifBlank { "Trip" } ?: "Trip",
            startedAt = f.getOrNull(1)?.toLongOrNull() ?: 0L,
            distanceM = stats.distanceM,
            durationMs = stats.durationMs,
            fixes = stats.fixes,
            partial = partial && files.exists(joinPath(dir, "$id$RECORDING_SUFFIX")),
        )
    }.getOrNull()

    private fun stopsOf(points: List<TripPoint>): List<TripStop> {
        val out = ArrayList<TripStop>()
        var start: TripPoint? = null
        var previous = points.firstOrNull() ?: return out
        for (p in points) {
            if (p.speedMps <= STOP_SPEED_MPS) {
                if (start == null) start = p
            } else {
                start?.let { s -> if (p.tMs - s.tMs >= MIN_STOP_MS) out += TripStop(s.lat, s.lng, s.tMs, p.tMs) }
                start = null
            }
            previous = p
        }
        start?.let { s -> if (previous.tMs - s.tMs >= MIN_STOP_MS) out += TripStop(s.lat, s.lng, s.tMs, previous.tMs) }
        return out
    }

    private fun flushLocked(): Boolean {
        val path = activePath ?: return false
        return runCatching { files.writeTextAtomic(path, activeLines.joinToString("\n") + "\n") }.isSuccess
    }

    private fun readRecordingLocked(path: String): String = files.readText(path)

    companion object {
        const val RECORDING_KEY = "trip_recording_on"
        private const val RECORDING_SUFFIX = ".recording"
        private const val MIN_FIXES = 5
        private const val FLUSH_EVERY_FIXES = 5
        private const val SHARED_LABEL = "Shared trip"
        private const val STOP_SPEED_MPS = 0.6
        private const val MIN_STOP_MS = 20_000L
    }
}
