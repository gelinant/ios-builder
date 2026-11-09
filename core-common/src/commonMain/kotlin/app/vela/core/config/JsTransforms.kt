package app.vela.core.config

import app.vela.core.model.Place
import app.vela.core.platform.JsEngine

/**
 * Bridges the remotely-pushed (signature-verified) `transforms.js` to the scraper.
 * The script can hot-fix a Google response whose *shape* changed, not just a moved
 * field, without an app update. Two optional hooks on the search path:
 *  - `parseSearch(rawResponse)` → flat places JSON: a full re-parse, used in place of
 *    the compiled parser when present.
 *  - `transformPlaces(placesJson)` → flat places JSON: post-processes the result.
 *
 * **Compiled Kotlin is always the fallback**: no script, a missing function, or any
 * error means the call returns null/unchanged and the caller keeps its own result.
 * Execution is sandboxed (see [JsEngine]); the fetched code sees only the JSON string
 * it's handed, never the platform or the device.
 */
class JsTransforms(private val calibration: CalibrationStore, private val js: JsEngine) {

    private fun call(fn: String, arg: String): String? {
        val src = calibration.current().transformsJs?.takeIf { it.isNotBlank() } ?: return null
        return js.call(src, fn, arg, MAX_RUN_MS)?.takeIf { it.isNotBlank() }
    }

    companion object {
        /** The kill switch: a script running longer returns null and the compiled result stands. */
        const val MAX_RUN_MS = 2_000L
    }

    fun searchOverride(rawResponse: String): List<Place>? =
        call("parseSearch", rawResponse)
            ?.let { PlaceJson.decode(it) }
            ?.takeIf { it.isNotEmpty() }

    fun refineSearch(places: List<Place>): List<Place> {
        if (places.isEmpty()) return places
        return call("transformPlaces", PlaceJson.encode(places))
            ?.let { PlaceJson.decode(it) }
            ?: places
    }
}
