package app.vela.ios.route

import app.vela.core.VelaConfig
import app.vela.core.data.naming.RoadNameTiles
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.call
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Where [RoadNameTiles] reads street names from on iOS: the live tile host the map draws from
 * (OpenFreeMap), its dated tile path read from its TileJSON every few hours. Android's
 * `RoadNameTileSource` without the downloaded basemaps (I-7).
 */
object IosRoadNameTiles {
    private const val TILEJSON = "https://tiles.openfreemap.org/planet"
    private const val TEMPLATE_TTL_MS = 6 * 60 * 60 * 1000L

    // Short: a tile is tens of kilobytes, and the route is waiting on this with a deadline of its own.
    private const val TILE_TIMEOUT_MS = 4_000L

    private var template: String? = null
    private var templateAt = 0L
    private var installed = false

    fun install(core: CoreGraph) {
        if (installed) return
        installed = true
        RoadNameTiles.fetch = { z, x, y ->
            template(core)?.let { tpl -> get(core, tpl.replace("{z}", "$z").replace("{x}", "$x").replace("{y}", "$y")) }
        }
    }

    private suspend fun get(core: CoreGraph, url: String): ByteArray? = runCatching {
        val r = core.http.call(HttpRequest(url, headers = listOf(HttpHeader("User-Agent", VelaConfig.VELA_UA)), timeoutMillis = TILE_TIMEOUT_MS))
        r.body.takeIf { r.isSuccessful }
    }.getOrNull()

    private suspend fun template(core: CoreGraph): String? {
        val now = core.clock.nowMillis()
        template?.let { if (now - templateAt < TEMPLATE_TTL_MS) return it }
        val t = get(core, TILEJSON)?.let { bytes ->
            runCatching { Json.parseToJsonElement(bytes.decodeToString()).jsonObject["tiles"]!!.jsonArray[0].jsonPrimitive.content }.getOrNull()
        }
        if (t != null) { template = t; templateAt = now }
        return t ?: template
    }
}
