package app.vela.ios

import app.vela.core.util.RoadNameShort
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The iOS app's entry into the Kotlin side, `IosGraph.shared` in Swift. It will build the common
 * graph over the Swift seam implementations (PORTAGE_IOS.md 3.1); for now it proves the
 * framework links and runs: the app calls [selfCheck] once at launch and logs the answer.
 */
object IosGraph {
    /** The VelaCore framework's version. Not `version`: NSObject already answers that name. */
    val frameworkVersion: String = "0.1.0"

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
