package app.vela.ios

import app.vela.core.config.Calibration
import app.vela.core.data.MapDataSource
import app.vela.core.data.google.DirectionsPb
import app.vela.core.data.google.GoogleMapsSource
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.JsEngine
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.Log
import app.vela.core.platform.SignatureVerifier
import app.vela.core.platform.SqlDbs
import app.vela.ios.config.IosCalibration
import app.vela.ios.net.BrowserIdentity
import app.vela.ios.net.SafariIdentity
import app.vela.ios.offline.OfflineDownloadClient
import app.vela.ios.offline.OfflineStore
import app.vela.ios.place.PlaceStore
import app.vela.ios.route.RouteStore
import app.vela.ios.search.IosGoogle
import app.vela.ios.search.SearchStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * The map screen's logic, one per process (docs/ios/PRESENTATION-MAP.md): the live calibration,
 * the search, place and directions facets. Building it does nothing; [start] arms the calibration
 * first, then builds the source over it (so the first request already reads the cached bundle)
 * and sets the process holders, then the facets.
 */
class MapSession(
    sourceFactory: () -> MapDataSource,
    private val scope: CoroutineScope,
    val calibration: IosCalibration? = null,
    /** Run once at [start], after the calibration and before any facet: the process holders. */
    private val beforeFacets: (MapDataSource) -> Unit = {},
    private val identity: SafariIdentity? = null,
    now: () -> Long = { 0L },
    reviewsHl: () -> String = { "en" },
    log: Log? = null,
    settings: () -> KeyValueStore? = { null },
) {
    private val source by lazy(sourceFactory)

    val search = SearchStore({ source }, scope)
    val place = PlaceStore(
        source = { source },
        scope = scope,
        calibration = { calibration?.current() ?: Calibration.DEFAULT },
        now = now,
        reviewsHl = reviewsHl,
        log = log,
    )

    val route = RouteStore(
        source = { source },
        scope = scope,
        settings = settings,
        avoidSupported = { DirectionsPb.avoidSupported((calibration?.current() ?: Calibration.DEFAULT).directionsPb) },
        now = now,
    )

    private var started = false
    private var offlineFacet: OfflineStore? = null
    val offline: OfflineStore? get() = offlineFacet

    /** Adds the iOS-only SQLite/download facet without widening IosGraph's startup signature. */
    fun attachOffline(core: CoreGraph, sql: SqlDbs, downloader: OfflineDownloadClient): OfflineStore {
        offlineFacet?.let { return it }
        return OfflineStore(core, sql, scope, downloader).also {
            offlineFacet = it
            search.offline = it
            if (started) it.start()
        }
    }

    fun start() {
        if (started) return
        started = true
        calibration?.start()
        beforeFacets(source)
        search.start()
        place.start()
        route.start()
        offlineFacet?.start()
    }

    /** The place sheet's Directions: the chooser to the open place. */
    fun openDirections() {
        val p = place.state.value.selected ?: return
        route.directionsTo(p)
    }

    /** Opens the sheet of the search result at [index] (a list row or its pin). */
    fun openResult(index: Int) {
        val p = search.state.value.results.getOrNull(index) ?: return
        place.select(p)
    }

    /** The headers a place photo is loaded with, as the Maps page would ask for it. */
    fun photoHeaders(): List<HttpHeader> = identity?.photo() ?: emptyList()

    /** The user agent of the hidden Google pages: the same Safari as the HTTP requests (D11). */
    fun webUserAgent(): String = BrowserIdentity.SAFARI_MAC.userAgent

    companion object {
        /** The session over the platform graph and the Swift [js] and [signatures] seams, its work
         *  on the main thread. [use24h] is the device clock, [region] its two-letter region. */
        fun over(core: CoreGraph, js: JsEngine, signatures: SignatureVerifier, use24h: Boolean, region: String?): MapSession {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val calibration = IosCalibration(core, signatures, js, scope)
            val identity = IosGoogle.identity(core.locale)
            return MapSession(
                sourceFactory = {
                    IosGoogle.source(
                        core,
                        checkNotNull(calibration.calibrationStore) { "calibration not started" },
                        checkNotNull(calibration.transforms),
                        identity,
                    )
                },
                scope = scope,
                calibration = calibration,
                beforeFacets = { source -> IosGoogle.applyFlags(source as? GoogleMapsSource, use24h, region) },
                identity = identity,
                now = { core.clock.nowMillis() },
                reviewsHl = { PlaceStore.reviewsHl(core.locale.defaultLanguage(), core.locale.defaultTag()) },
                log = core.log,
                settings = { core.keyValues.open("vela_settings") },
            )
        }
    }
}
