package app.vela.core.data

import app.vela.core.model.Place
import app.vela.core.model.Review
import app.vela.core.model.distanceTo
import app.vela.core.platform.Clock
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.joinPath
import app.vela.core.platform.treeSize
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Offline place cache: one JSON file per place (details + first review page),
 * written on every successful online load, read when the network is gone.
 * Photos ride Coil's own disk cache (prefetched alongside); text menus are NOT
 * parsed anywhere yet, so there is nothing of them to cache.
 *
 * Records live under `<dir>/<key>.json` where the key is the most stable id
 * available (placeId, then featureId, then the row id), sanitized. Stale past
 * [MAX_AGE_MS]. No migration story: a broken file reads as a miss.
 */
@Serializable
data class CachedPlace(
    val place: Place,
    val reviews: List<Review> = emptyList(),
    val savedAtMs: Long = 0L,
)

/**
 * Files go through [files]; [nameKey] folds a place name for the same-spot match (Android:
 * `PlaceNames.normalized`). Each call takes the folder, `<filesDir>/placecache` in the app.
 */
class PlaceCache(
    private val files: PlatformFiles,
    private val clock: Clock,
    private val nameKey: (String?) -> String,
) {
    fun save(dir: String, place: Place, reviews: List<Review>) {
        runCatching {
            if (!files.exists(dir)) files.mkdirs(dir)
            val rec = CachedPlace(place, reviews, clock.nowMillis())
            files.writeText(joinPath(dir, keyOf(place) + ".json"), json.encodeToString(CachedPlace.serializer(), rec))
        }
    }

    fun load(dir: String, place: Place, maxAgeMs: Long = MAX_AGE_MS): CachedPlace? = runCatching {
        val direct = joinPath(dir, keyOf(place) + ".json")
        if (files.exists(direct)) {
            val rec = json.decodeFromString(CachedPlace.serializer(), files.readText(direct))
            if (clock.nowMillis() - rec.savedAtMs <= maxAgeMs) return rec
        }
        // Key-scheme drift: a reopened saved/recent place carries only the row id
        // while the online record was keyed by placeId/featureId. Fall back to
        // scanning for the same place id.
        files.list(dir)?.filter { extension(it.name) == "json" }?.forEach { f ->
            val rec = runCatching { json.decodeFromString(CachedPlace.serializer(), files.readText(f.path)) }.getOrNull()
            if (rec != null && clock.nowMillis() - rec.savedAtMs <= maxAgeMs && (rec.place.id == place.id || sameSpot(rec.place, place))) return rec
        }
        null
    }.getOrNull()

    /** An offline search answers from the downloaded data, whose ids are not Google's: the same
     *  name within [SAME_SPOT_M] is the same place. */
    private fun sameSpot(a: Place, b: Place): Boolean =
        a.location.distanceTo(b.location) <= SAME_SPOT_M &&
            nameKey(a.name).let { it.isNotEmpty() && it == nameKey(b.name) }

    fun dirSizeBytes(dir: String): Long = runCatching { files.treeSize(dir) }.getOrDefault(0L)

    /** Keeps the store bounded: files older than [maxAgeMs] go, then the oldest past [maxFiles]. */
    fun trim(dir: String, maxFiles: Int = MAX_FILES, maxAgeMs: Long = MAX_AGE_MS) {
        runCatching {
            val now = clock.nowMillis()
            val list = files.list(dir)?.filter { extension(it.name) == "json" }?.sortedByDescending { it.lastModifiedMillis } ?: return
            list.forEachIndexed { i, f -> if (i >= maxFiles || now - f.lastModifiedMillis > maxAgeMs) files.delete(f.path) }
        }
    }

    fun clear(dir: String) {
        runCatching { files.list(dir)?.forEach { if (extension(it.name) == "json") files.delete(it.path) } }
    }

    companion object {
        const val MAX_AGE_MS = 30L * 24 * 60 * 60 * 1000
        const val MAX_FILES = 400
        const val SAME_SPOT_M = 60.0

        private val json = Json { ignoreUnknownKeys = true }

        fun keyOf(place: Place): String {
            val raw = place.placeId?.takeIf { it.isNotBlank() }
                ?: place.featureId?.takeIf { it.isNotBlank() }
                ?: place.id
            return raw.replace(Regex("[^A-Za-z0-9_-]"), "_").takeLast(80) +
                "_" + (raw.hashCode().toString().replace("-", "m"))
        }
    }
}

/** `File.extension`: the text after the last dot of [name], empty without one. */
internal fun extension(name: String): String = name.substringAfterLast('.', "")
