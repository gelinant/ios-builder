package app.vela.core.offline

import app.vela.core.platform.HttpRequest
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.platform.joinPath
import app.vela.core.util.ioDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One downloadable region asset, from a manifest. [s]/[w]/[n]/[e] = covered bbox. Shared by the obf,
 *  place-pack, overlay and basemap catalogs (same row shape); the trailing fields are pack-only
 *  (update revision + row counts + optional row-level delta) and stay at their defaults elsewhere. */
data class RoutingRegion(
    val id: String,
    val name: String,
    val url: String,
    val sizeMb: Int,
    val s: Double,
    val w: Double,
    val n: Double,
    val e: Double,
    val installedMb: Int = 0,               // unpacked on-disk size; 0 in old manifests (estimate from the zip)
    val rev: Int = 0,                       // pack revision (bumped every rebuild)
    val counts: Map<String, Long> = emptyMap(), // expected per-table row counts, verifies a delta apply
    val deltaUrl: String? = null,           // row-level delta from [deltaFromRev] to [rev], if published
    val deltaFromRev: Int = 0,
    val deltaSizeMb: Int = 0,
) {
    /** Whether this region holds the point: its real boundary where [RegionPolys] has one, else
     *  the box. Every "which region is this point in" decision goes through here (issue #599). */
    fun covers(lat: Double, lng: Double): Boolean =
        RegionPolys.covers(id, lat, lng) ?: RegionPolys.boxCovers(s, w, n, e, lat, lng)

    /** The box's area in square degrees, the tie-break among covering regions: the smallest one is
     *  the specific region for a point where boxes overlap at a border. */
    fun boxArea(): Double = (n - s) * (e - w)
}

/**
 * The region catalog fetch: reads a `{regions:[...]}` manifest into [RoutingRegion] rows. The obf
 * routing catalog is the one caller today; the store that used to live here (the GraphHopper
 * graph download, its index and the road-name sidecar) was retired on 2026-09-15 once the obf
 * carried the speed limit and the romanized names itself.
 */
class RegionCatalog(
    private val http: VelaHttp,
    private val files: PlatformFiles,
) {
    /** The catalog as last fetched, kept on disk (2026-09-23): with no signal the fetch failed and
     *  the Offline maps page listed nothing, installed regions included, so a user who had just
     *  downloaded a state read it as "nothing is downloaded". */
    private fun cacheFile(url: String) = joinPath(files.filesDir, "catalog-${url.hashCode().toUInt()}.json")

    suspend fun manifest(manifestUrl: String): List<RoutingRegion> = withContext(ioDispatcher) {
        runCatching {
            val json = runCatching {
                http.call(HttpRequest(manifestUrl))
                    .let { r -> if (!r.isSuccessful) error("HTTP ${r.code}"); r.bodyText() }
                    .also { fresh -> runCatching { files.writeTextAtomic(cacheFile(manifestUrl), fresh) } }
            }.getOrElse { cacheFile(manifestUrl).takeIf { files.exists(it) }?.let(files::readText) ?: throw it }
            parseManifest(json)
        }.getOrDefault(emptyList())
    }

    companion object {
        /** The `{regions:[...]}` rows, with org.json's leniency: a missing or unreadable `sizeMb`,
         *  `installedMb` or `rev` is 0. */
        fun parseManifest(json: String): List<RoutingRegion> =
            Json.parseToJsonElement(json).jsonObject.getValue("regions").jsonArray.map { row ->
                val o = row.jsonObject
                val b = o.getValue("bbox").jsonArray // [S, W, N, E]
                // Pack rows carry the expected per-table row counts; places and basemap rows do
                // not. The optional delta object is the same shape in every catalog.
                val counts = (o["counts"] as? JsonObject)?.mapNotNull { (table, value) ->
                    (value as? JsonPrimitive)?.content?.toLongOrNull()?.let { table to it }
                }?.toMap().orEmpty()
                val delta = o["delta"] as? JsonObject
                RoutingRegion(
                    o.string("id"), o.string("name"), o.string("url"), o.optInt("sizeMb"),
                    b[0].jsonPrimitive.double, b[1].jsonPrimitive.double, b[2].jsonPrimitive.double, b[3].jsonPrimitive.double,
                    installedMb = o.optInt("installedMb"),
                    rev = o.optInt("rev"),
                    counts = counts,
                    deltaUrl = delta?.get("url")?.let {
                        (it as? JsonPrimitive)?.content?.takeIf { url -> url.isNotBlank() }
                    },
                    deltaFromRev = delta?.optInt("fromRev") ?: 0,
                    deltaSizeMb = delta?.optInt("sizeMb") ?: 0,
                )
            }
    }
}

/** org.json's `getString`: the value as text, a number or a boolean included; throws when missing
 *  or null. */
internal fun JsonObject.string(key: String): String {
    val p = getValue(key).jsonPrimitive
    if (p is kotlinx.serialization.json.JsonNull) throw IllegalArgumentException("$key is null")
    return p.content
}

/** org.json's `optInt`: a number (a fraction cut toward zero) or a numeric string, else [default]. */
internal fun JsonObject.optInt(key: String, default: Int = 0): Int = optLong(key)?.toInt() ?: default

/** org.json's `optLong`, null where it would answer its default. */
internal fun JsonObject.optLong(key: String): Long? {
    val p = this[key] as? kotlinx.serialization.json.JsonPrimitive ?: return null
    if (p is kotlinx.serialization.json.JsonNull) return null
    val c = p.content
    return c.toLongOrNull() ?: c.toDoubleOrNull()?.takeIf { !it.isNaN() }?.toLong()
}
