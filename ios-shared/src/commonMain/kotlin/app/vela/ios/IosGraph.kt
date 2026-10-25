package app.vela.ios

import app.vela.core.platform.CoreGraph
import app.vela.core.platform.JsEngine
import app.vela.core.platform.SignatureVerifier
import app.vela.core.util.RoadNameShort
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The iOS app's entry into the Kotlin side, `IosGraph.shared` in Swift. The app builds the
 * [CoreGraph] and the [JsEngine] and [SignatureVerifier] seams in Swift at launch and hands them
 * to [start], which builds the one [MapSession] of the process.
 */
object IosGraph {
    /** The VelaCore framework's version. Not `version`: NSObject already answers that name. */
    val frameworkVersion: String = "0.1.0"

    /** The graph [start] was given, null before. */
    var core: CoreGraph? = null
        private set

    /** The map session [start] built, null before. */
    var session: MapSession? = null
        private set

    /** Builds and starts the map session over [core], [js] and [signatures] once; later calls
     *  return the same session. [use24h] is the device's clock, [region] its two-letter region
     *  (Google's `gl=`), null when unknown. */
    fun start(core: CoreGraph, js: JsEngine, signatures: SignatureVerifier, use24h: Boolean, region: String?): MapSession {
        session?.let { return it }
        this.core = core
        return MapSession.over(core, js, signatures, use24h, region).also {
            session = it
            it.start()
        }
    }

    /** A road name as the turn card shows it, through `:core-common`'s [RoadNameShort]. */
    fun shortRoadName(name: String): String = RoadNameShort.shorten(name)

    /**
     * One line that needs the Kotlin runtime, `:core-common` and a coroutine hop to come back.
     * A Swift `async throws` function through SKIE.
     */
    suspend fun selfCheck(): String = withContext(Dispatchers.Default) {
        "VelaCore $frameworkVersion: $SAMPLE_ROAD -> ${shortRoadName(SAMPLE_ROAD)}"
    }

    const val SAMPLE_ROAD = "West Covell Boulevard"
}
