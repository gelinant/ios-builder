package app.vela.ios

import app.vela.core.data.MapDataSource
import app.vela.core.platform.CoreGraph
import app.vela.ios.search.IosGoogleSearch
import app.vela.ios.search.SearchStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * The map screen's logic, one per process (docs/ios/PRESENTATION-MAP.md): for now the search
 * facet only. Building it does nothing; [start] arms the facets.
 */
class MapSession(
    val source: MapDataSource,
    scope: CoroutineScope,
) {
    val search = SearchStore(source, scope)

    private var started = false

    fun start() {
        if (started) return
        started = true
        search.start()
    }

    companion object {
        /** The session over the platform graph, its work on the main thread. */
        fun over(core: CoreGraph): MapSession =
            MapSession(IosGoogleSearch(core.http, core.locale), CoroutineScope(SupervisorJob() + Dispatchers.Main))
    }
}
