package app.vela.ios

import app.vela.core.data.MapDataSource
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.JsEngine
import app.vela.core.platform.SignatureVerifier
import app.vela.ios.config.IosCalibration
import app.vela.ios.search.IosGoogleSearch
import app.vela.ios.search.SearchStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * The map screen's logic, one per process (docs/ios/PRESENTATION-MAP.md): for now the live
 * calibration and the search facet. Building it does nothing; [start] arms the calibration first,
 * so the first search already reads the cached bundle, then the facets.
 */
class MapSession(
    val source: MapDataSource,
    scope: CoroutineScope,
    val calibration: IosCalibration? = null,
) {
    val search = SearchStore(source, scope)

    private var started = false

    fun start() {
        if (started) return
        started = true
        calibration?.start()
        search.start()
    }

    companion object {
        /** The session over the platform graph and the Swift [js] and [signatures] seams, its work
         *  on the main thread. Search reads the live calibration and its JS transforms. */
        fun over(core: CoreGraph, js: JsEngine, signatures: SignatureVerifier): MapSession {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val calibration = IosCalibration(core, signatures, js, scope)
            val source = IosGoogleSearch(
                core.http,
                core.locale,
                calibration = calibration::current,
                transforms = { calibration.transforms },
            )
            return MapSession(source, scope, calibration)
        }
    }
}
