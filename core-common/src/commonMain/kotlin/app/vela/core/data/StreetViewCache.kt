package app.vela.core.data

import app.vela.core.model.LatLng
import app.vela.core.model.StreetViewPano
import app.vela.core.model.distanceTo
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.joinPath
import app.vela.core.platform.treeSize
import kotlinx.serialization.json.Json

/**
 * Offline Street View cache: one metadata JSON + one stitched-equirect JPEG per
 * viewed panorama, under `<dir>/<panoId>.json` / `<panoId>.jpg`. Written after
 * every successful online tile load, served when Street View opens with no
 * network (nearest cached pano to the requested spot). The VM handles the
 * Bitmap↔JPEG step (android.graphics); this store only moves JSON and bytes.
 *
 * No migration story: a broken file reads as a miss. Pruned to [MAX_BYTES]
 * oldest-first on every save. Files go through [files]; each call takes the folder,
 * `<filesDir>/svcache` in the app.
 */
class StreetViewCache(private val files: PlatformFiles) {
    fun metaFile(dir: String, panoId: String): String = joinPath(dir, keyOf(panoId) + ".json")

    fun imageFile(dir: String, panoId: String): String = joinPath(dir, keyOf(panoId) + ".jpg")

    fun saveMeta(dir: String, pano: StreetViewPano) {
        runCatching {
            if (!files.exists(dir)) files.mkdirs(dir)
            files.writeText(metaFile(dir, pano.panoId), json.encodeToString(StreetViewPano.serializer(), pano))
        }
    }

    fun saveImage(dir: String, panoId: String, jpeg: ByteArray) {
        runCatching {
            if (!files.exists(dir)) files.mkdirs(dir)
            files.writeBytes(imageFile(dir, panoId), jpeg)
            prune(dir)
        }
    }

    fun loadMeta(dir: String, panoId: String): StreetViewPano? = runCatching {
        val f = metaFile(dir, panoId)
        if (!files.exists(f)) return null
        json.decodeFromString(StreetViewPano.serializer(), files.readText(f))
    }.getOrNull()

    fun loadImage(dir: String, panoId: String): ByteArray? = runCatching {
        val f = imageFile(dir, panoId)
        if (!files.exists(f)) return null
        files.readBytes(f)
    }.getOrNull()

    fun has(dir: String, panoId: String): Boolean =
        files.exists(metaFile(dir, panoId)) && files.exists(imageFile(dir, panoId))

    /** Nearest cached pano to [at] within [maxM] meters (location opens offline). */
    fun nearest(dir: String, at: LatLng, maxM: Double = 100.0): StreetViewPano? = runCatching {
        val list = files.list(dir)?.filter { extension(it.name) == "json" } ?: return null
        var best: StreetViewPano? = null
        var bestD = maxM
        for (f in list) {
            val pano = runCatching { json.decodeFromString(StreetViewPano.serializer(), files.readText(f.path)) }.getOrNull()
                ?: continue
            if (!files.exists(imageFile(dir, pano.panoId))) continue
            val d = LatLng(pano.lat, pano.lng).distanceTo(at)
            if (d < bestD) {
                bestD = d
                best = pano
            }
        }
        best
    }.getOrNull()

    fun dirSizeBytes(dir: String): Long = runCatching { files.treeSize(dir) }.getOrDefault(0L)

    fun clear(dir: String) {
        runCatching { files.list(dir)?.forEach { val ext = extension(it.name); if (ext == "json" || ext == "jpg") files.delete(it.path) } }
    }

    private fun prune(dir: String, maxBytes: Long = MAX_BYTES) {
        runCatching {
            val list = files.list(dir)?.filter { !it.isDirectory } ?: return
            var total = list.sumOf { it.size }
            if (total <= maxBytes) return
            for (f in list.sortedBy { it.lastModifiedMillis }) {
                if (total <= maxBytes) break
                total -= f.size
                files.delete(f.path)
            }
        }
    }

    companion object {
        const val MAX_BYTES = 150L * 1024 * 1024

        private val json = Json { ignoreUnknownKeys = true }

        fun keyOf(panoId: String): String =
            panoId.replace(Regex("[^A-Za-z0-9_-]"), "_").takeLast(80) +
                "_" + (panoId.hashCode().toString().replace("-", "m"))
    }
}
