package app.vela.ios.transit

import app.vela.core.model.StopDeparture
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitMode
import app.vela.core.platform.Log
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.i
import app.vela.core.platform.joinPath
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.round

/** The last successful board of one stop, with the instant it was fetched. */
data class CachedBoard(val board: StopDepartures, val fetchedAtMillis: Long)

/**
 * The last successful departure board of each stop, under the app's private files. It exists so an
 * unreachable feed can still show the board the user already saw, labeled with its fetch time.
 * Cached departures are never marked live: the feed's realtime flag is dropped on read, and a
 * departure older than one minute is removed. Entries expire after [MAX_AGE_MILLIS] and only the
 * newest [MAX_ENTRIES] are kept, so the folder cannot grow without bound.
 *
 * Writes are small and atomic, and happen on the board store's own coroutine.
 */
class TransitBoardCache(
    private val files: PlatformFiles?,
    private val log: Log? = null,
) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    /** The board saved for [target], or null when there is none, it expired, or it has no upcoming
     *  departure left. An expired file is deleted on the way. */
    fun load(target: TransitBoardTarget, nowMillis: Long): CachedBoard? {
        val store = files ?: return null
        val key = keyOf(target)
        val path = pathOf(key)
        if (!store.exists(path)) return null
        val snapshot = runCatching { json.decodeFromString<CachedSnapshot>(store.readText(path)) }
            .getOrElse {
                log?.i(TAG, "load: unreadable $key")
                runCatching { store.delete(path) }
                return null
            }
        if (snapshot.version != VERSION || snapshot.key != key) {
            runCatching { store.delete(path) }
            return null
        }
        val age = nowMillis - snapshot.fetchedAtMillis
        if (age > MAX_AGE_MILLIS || age < -FUTURE_SLACK_MILLIS) {
            runCatching { store.delete(path) }
            return null
        }
        val board = snapshot.toBoard(nowMillis)
        if (board.lines.all { it.upcoming.isEmpty() }) {
            runCatching { store.delete(path) }
            return null
        }
        return CachedBoard(board, snapshot.fetchedAtMillis)
    }

    /** Replaces the entry of [target] and prunes the folder. A board without a line is not saved. */
    fun save(target: TransitBoardTarget, board: StopDepartures, nowMillis: Long) {
        val store = files ?: return
        val lines = board.lines.take(MAX_LINES)
            .map { line ->
                line.copy(upcoming = line.upcoming.filter { it.epochSec != null }.take(MAX_DEPARTURES_PER_LINE))
            }
            .filter { it.upcoming.isNotEmpty() }
        if (lines.isEmpty()) return
        val key = keyOf(target)
        val snapshot = CachedSnapshot(
            version = VERSION,
            key = key,
            stationName = board.stationName ?: target.name,
            fetchedAtMillis = nowMillis,
            lines = lines.map { it.toSnapshot() },
        )
        runCatching {
            store.mkdirs(directory())
            store.writeTextAtomic(pathOf(key), json.encodeToString(CachedSnapshot.serializer(), snapshot))
        }.onFailure { log?.i(TAG, "save: failed for $key") }
        prune(nowMillis)
    }

    /** Deletes every cached board; used when the user clears offline data. */
    fun clear() {
        val store = files ?: return
        runCatching { store.deleteRecursively(directory()) }
    }

    /** Drops expired entries, then the oldest beyond [MAX_ENTRIES]. */
    private fun prune(nowMillis: Long) {
        val store = files ?: return
        val dir = directory()
        val entries = store.list(dir) ?: return
        val kept = ArrayList<Pair<String, Long>>()
        for (entry in entries) {
            if (entry.isDirectory || !entry.name.endsWith(".json")) continue
            val snapshot = runCatching { json.decodeFromString<CachedSnapshot>(store.readText(entry.path)) }
                .getOrNull()
            val age = if (snapshot != null) nowMillis - snapshot.fetchedAtMillis else Long.MAX_VALUE
            if (snapshot == null || age > MAX_AGE_MILLIS || age < -FUTURE_SLACK_MILLIS) {
                runCatching { store.delete(entry.path) }
            } else {
                kept += entry.path to snapshot.fetchedAtMillis
            }
        }
        if (kept.size <= MAX_ENTRIES) return
        kept.sortedBy { it.second }
            .take(kept.size - MAX_ENTRIES)
            .forEach { runCatching { store.delete(it.first) } }
    }

    private fun directory(): String = joinPath(files?.filesDir ?: "", DIR)

    private fun pathOf(key: String): String =
        joinPath(directory(), "board-${key.hashCode().toUInt().toString(16)}.json")

    /** A stable key per physical stop: the Transitous id when the tap had one, else its rounded
     *  coordinate. The coordinate is what proximity boards are resolved from. */
    private fun keyOf(target: TransitBoardTarget): String {
        val id = target.stopId?.takeIf { it.isNotBlank() }
        if (id != null) return "stop:$id"
        val lat = (round(target.lat * 100_000.0) / 100_000.0)
        val lng = (round(target.lng * 100_000.0) / 100_000.0)
        return "geo:$lat,$lng"
    }

    @Serializable
    private data class CachedSnapshot(
        val version: Int,
        val key: String,
        val stationName: String? = null,
        val fetchedAtMillis: Long,
        val lines: List<CachedLine> = emptyList(),
    ) {
        fun toBoard(nowMillis: Long): StopDepartures {
            val nowSec = nowMillis / 1000L
            return StopDepartures(
                stationName = stationName,
                lines = lines.map { line ->
                    val model = line.toModel()
                    model.copy(upcoming = model.upcoming.filter { (it.epochSec ?: 0L) >= nowSec - 60L })
                },
            )
        }
    }

    @Serializable
    private data class CachedLine(
        val label: String? = null,
        val mode: String = TransitMode.GENERIC.name,
        val headsign: String? = null,
        val colorHex: String? = null,
        val departures: List<CachedDeparture> = emptyList(),
    ) {
        fun toModel(): StopDepartureLine = StopDepartureLine(
            label = label,
            mode = TransitMode.entries.firstOrNull { it.name == mode } ?: TransitMode.GENERIC,
            headsign = headsign,
            colorHex = colorHex,
            upcoming = departures.map {
                StopDeparture(
                    clockText = it.clockText,
                    epochSec = it.epochSec,
                    // A cached board cannot know what is live now; the flag is never restored.
                    realtime = false,
                    tripId = it.tripId,
                )
            },
        )
    }

    @Serializable
    private data class CachedDeparture(
        val clockText: String? = null,
        val epochSec: Long,
        val tripId: String? = null,
    )

    private fun StopDepartureLine.toSnapshot(): CachedLine = CachedLine(
        label = label,
        mode = mode.name,
        headsign = headsign,
        colorHex = colorHex,
        departures = upcoming.mapNotNull { departure ->
            val epoch = departure.epochSec ?: return@mapNotNull null
            CachedDeparture(clockText = departure.clockText, epochSec = epoch, tripId = departure.tripId)
        },
    )

    companion object {
        const val DIR = "transit-boards"
        const val VERSION = 1
        const val MAX_ENTRIES = 24
        const val MAX_AGE_MILLIS = 6L * 60 * 60 * 1000
        const val MAX_LINES = 24
        const val MAX_DEPARTURES_PER_LINE = 40
        private const val FUTURE_SLACK_MILLIS = 60L * 60 * 1000
        private const val TAG = "TransitBoardCache"
    }
}
