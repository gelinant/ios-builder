package app.vela.ios

import app.vela.core.config.Calibration
import app.vela.core.data.MapDataSource
import app.vela.core.data.PhotonGeocoder
import app.vela.core.data.google.DirectionsPb
import app.vela.core.data.google.GoogleMapsSource
import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.data.tiles.RasterTiles
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.TransitItinerary
import app.vela.core.model.StopDepartures
import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.JsEngine
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.Log
import app.vela.core.platform.NavHaptics
import app.vela.core.platform.NavVoice
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.SignatureVerifier
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.VelaHttp
import app.vela.core.util.ioDispatcher
import app.vela.ios.config.IosCalibration
import app.vela.ios.map.LayersStore
import app.vela.ios.net.BrowserIdentity
import app.vela.ios.net.SafariIdentity
import app.vela.ios.nav.InertLog
import app.vela.ios.nav.InertNavHaptics
import app.vela.ios.nav.InertNavVoice
import app.vela.ios.nav.NavAlertProvider
import app.vela.ios.nav.NavStore
import app.vela.ios.nav.OverpassNavAlertProvider
import app.vela.ios.offline.OfflineDownloadClient
import app.vela.ios.offline.OfflineStore
import app.vela.ios.place.PlaceStore
import app.vela.ios.route.RouteStore
import app.vela.ios.saved.SavedRouteDirections
import app.vela.ios.saved.SavedStore
import app.vela.ios.search.IosGoogle
import app.vela.ios.search.MapPoiStore
import app.vela.ios.search.SearchStore
import app.vela.ios.settings.SettingsStore
import app.vela.ios.streetview.StreetViewStore
import app.vela.ios.streetview.StreetViewTiles
import app.vela.ios.transit.TransitBoardStore
import app.vela.ios.transit.TransitBoardTarget
import app.vela.ios.transit.TransitPlanQuery
import app.vela.ios.transit.TransitSession
import app.vela.ios.transit.TransitStopPin
import app.vela.ios.transit.TransitStopStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The map screen's logic, one per process (docs/ios/PRESENTATION-MAP.md): the live calibration,
 * the search, place and directions facets. Building it does nothing; [start] applies settings,
 * then arms the calibration and builds the source over it (so the first request already reads the
 * cached bundle), sets the remaining process holders, then starts the facets.
 */
class MapSession(
    sourceFactory: () -> MapDataSource,
    private val scope: CoroutineScope,
    keyValues: KeyValueStores,
    clock: Clock,
    http: VelaHttp,
    files: PlatformFiles,
    val calibration: IosCalibration? = null,
    /** Run once at [start], after the calibration and before any facet: the process holders. */
    private val beforeFacets: (MapDataSource) -> Unit = {},
    private val identity: SafariIdentity? = null,
    now: () -> Long = { 0L },
    reviewsHl: () -> String = { "en" },
    detailsLanguage: () -> String = { reviewsHl().substringBefore('-') },
    log: Log? = null,
    routeSettings: () -> KeyValueStore? = { null },
    /** The directions' source (the hybrid router); null routes on [sourceFactory]'s. */
    routeSourceFactory: (() -> MapDataSource)? = null,
    transitPlanner: (suspend (LatLng, LatLng, Int, Long?) -> List<TransitItinerary>)? = null,
    /** Transitous with the chooser's time, vehicles and preference; preferred over [transitPlanner]. */
    transitOptionsPlanner: (suspend (LatLng, LatLng, TransitPlanQuery) -> List<TransitItinerary>)? = null,
    /** The stop board's feed; the default answers nothing (no board). */
    transitBoardSource: suspend (TransitBoardTarget) -> StopDepartures? = { null },
    /** Transitous stop pins around a viewport, already merged into one pin per physical stop. */
    transitStopsSource: suspend (south: Double, west: Double, north: Double, east: Double) -> List<TransitStopPin> =
        { _, _, _, _ -> emptyList() },
    val settings: SettingsStore? = null,
    navAlertProvider: NavAlertProvider = NavAlertProvider.EMPTY,
    private var navVoice: () -> NavVoice = { InertNavVoice },
    private var navHaptics: () -> NavHaptics = { InertNavHaptics },
) {
    private val source by lazy(sourceFactory)
    private val routeSource by lazy { routeSourceFactory?.invoke() ?: source }

    val search = SearchStore({ source }, scope)
    val place = PlaceStore(
        source = { source },
        scope = scope,
        calibration = { calibration?.current() ?: Calibration.DEFAULT },
        now = now,
        reviewsHl = reviewsHl,
        detailsLanguage = detailsLanguage,
        log = log,
    )

    val mapPoi = MapPoiStore(source = { source }, scope = scope, onOpen = { place.select(it) })

    /** The interactive Street View viewer's session (SV-1): pano metadata, neighbors and tiles. */
    val streetView = StreetViewStore(
        source = { source },
        scope = scope,
        http = http,
        tileHeaders = {
            identity?.image(StreetViewTiles.REFERER, StreetViewTiles.ACCEPT) ?: emptyList()
        },
        files = files,
        log = log,
    )

    val route = RouteStore(
        source = { planningRouteSource },
        scope = scope,
        settings = routeSettings,
        avoidSupported = { DirectionsPb.avoidSupported((calibration?.current() ?: Calibration.DEFAULT).directionsPb) },
        now = now,
        transitPlanner = transitPlanner,
        transitOptionsPlanner = transitOptionsPlanner,
    )

    val board = TransitBoardStore(scope, transitBoardSource, nowMillis = { now() })
    val stops = TransitStopStore(scope, transitStopsSource)

    val saved = SavedStore(keyValues, clock, scope, source = { source })
    /** Optional map overlays: painted roads, cameras, controls, UK fuel and Dutch bridges. */
    val layers = LayersStore(
        stores = keyValues,
        http = http,
        scope = scope,
        files = files,
        now = now,
    )

    private val planningRouteSource by lazy {
        SavedRouteDirections(routeSource) { saved.state.value.savedRoutes }
    }
    val transit = TransitSession()
    val nav = NavStore(
        routeStore = route,
        source = { routeSource },
        scope = scope,
        clock = clock,
        alertProvider = navAlertProvider,
        voiceProvider = { navVoice() },
        sessionFactory = {
            NavStore.session(
                source = routeSource,
                voice = navVoice(),
                haptics = navHaptics(),
                log = log ?: InertLog,
                clock = clock,
            )
        },
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
        settings?.start()
        calibration?.start()
        beforeFacets(source)
        layers.start()
        search.start()
        place.start()
        mapPoi.start()
        route.start()
        offlineFacet?.start()
        saved.start()
        recordRecents()
        nav.start()
    }

    /** The same recents stores and write points as Android's runSearch and selectPlace. */
    private fun recordRecents() {
        scope.launch {
            var recordedSubmission = 0
            search.state.collect { state ->
                if (state.submissions == 0) recordedSubmission = 0
                else if (state.submissions != recordedSubmission) {
                    recordedSubmission = state.submissions
                    saved.recordSearch(state.query)
                }
            }
        }
        scope.launch {
            var openedId: String? = null
            place.state.collect { state ->
                val selected = state.selected
                if (selected == null) openedId = null
                else if (openedId != selected.id) {
                    openedId = selected.id
                    saved.recordPlace(selected)
                }
            }
        }
    }

    /** Supplies the Apple drive seams after graph startup and before the first Start tap. */
    fun configureNavigation(voice: NavVoice, haptics: NavHaptics) {
        navVoice = { voice }
        navHaptics = { haptics }
    }

    /** Starts guidance on the transit itinerary selected in the chooser, then closes only the
     *  chooser. The TransitSession retains the itinerary and its map line until End. */
    fun startTransit(): Boolean {
        val s = route.state.value
        val trip = s.transit.getOrNull(s.activeTransit) ?: return false
        if (!transit.start(trip, s.destination?.name.orEmpty())) return false
        route.close()
        return true
    }

    /** The place sheet's Directions: the chooser to the open place. */
    fun openDirections() {
        val p = place.state.value.selected ?: return
        planningRouteSource.clearRequest()
        route.directionsTo(p)
    }

    /** Opens the sheet of the search result at [index] (a list row or its pin). */
    fun openResult(index: Int) {
        val p = search.state.value.results.getOrNull(index) ?: return
        search.dismissSuggestions()
        place.select(p)
    }

    /** Opens a place suggestion and freezes autocomplete until the next edit. */
    fun openSearchSuggestion(index: Int) {
        val p = search.suggestion(index) ?: return
        search.dismissSuggestions()
        place.select(p)
    }

    /** Directions to a dropped pin or to an unmatched OSM label. */
    fun openMapPoiDirections() {
        val p = mapPoi.state.value.selected ?: return
        mapPoi.close()
        planningRouteSource.clearRequest()
        route.directionsTo(p)
    }

    /** Opens a quick-saved place, a list entry, or a recent place by its stable row ids. */
    fun openSavedPlace(listId: String?, placeId: String) {
        val listed = listId?.let { saved.listPlace(it, placeId) }
        val p = listed?.toPlace()
            ?: saved.savedPlace(placeId)?.toPlace()
            ?: saved.recentPlace(placeId)?.toPlace()
            ?: return
        place.select(p)
    }

    /** Save the route currently picked in the chooser under [name]. */
    fun saveActiveRoute(name: String): Boolean = saved.saveActiveRoute(route.state.value, name)

    /** Reopen a saved route in its own mode. The planning source offers its line beside fresh routes. */
    fun openSavedRoute(id: String) {
        val savedRoute = saved.savedRoute(id) ?: return
        val destination = Place(
            id = "saved-route:${savedRoute.id}",
            name = savedRoute.destLabel.ifBlank { savedRoute.name },
            location = savedRoute.dest,
        )
        place.select(destination)
        if (route.state.value.mode.name != savedRoute.mode) route.setModeNamed(savedRoute.mode)
        planningRouteSource.request(id)
        route.directionsTo(destination)
    }

    /** The selected place's canonical Google link for UIActivityViewController. */
    fun shareSelectedPlaceUrl(): String? = place.state.value.selected?.let(SavedStore::sharePlaceUrl)

    /** The headers a place photo is loaded with, as the Maps page would ask for it. */
    fun photoHeaders(): List<HttpHeader> = identity?.photo() ?: emptyList()

    /**
     * The headers MapLibre's Google raster tile requests carry. MapLibre iOS uses its own
     * `NSURLSession`, not the app client, so `MLNNetworkConfiguration`'s delegate is the only way
     * to give those tiles the Safari identity the rest of the Google traffic uses. Empty when the
     * session has no identity, in which case the tiles go out with the URL alone.
     */
    fun rasterTileHeaders(): List<HttpHeader> =
        identity?.image(BrowserIdentity.MAPS_REFERER, BrowserIdentity.ACCEPT_IMAGE) ?: emptyList()

    /** The raster templates and Android's limits, read by Swift's MapLibre layer builder. */
    fun rasterTrafficUrl(): String = RasterTiles.TRAFFIC_URL
    fun rasterSatelliteUrl(): String = RasterTiles.SATELLITE_URL
    fun rasterSatelliteDeepUrl(): String = RasterTiles.SATELLITE_DEEP_URL
    fun rasterTrafficMaxZoom(): Int = RasterTiles.TRAFFIC_MAX_ZOOM
    fun rasterSatelliteMaxZoom(): Int = RasterTiles.SATELLITE_MAX_ZOOM
    fun rasterSatelliteDeepMaxZoom(): Int = RasterTiles.SATELLITE_DEEP_MAX_ZOOM
    fun rasterSatelliteDeepMinZoom(): Double = RasterTiles.SATELLITE_DEEP_MIN_ZOOM.toDouble()
    fun rasterTrafficOpacity(): Double = RasterTiles.TRAFFIC_OPACITY
    fun rasterSatelliteBrightnessMax(): Double = RasterTiles.SATELLITE_BRIGHTNESS_MAX.toDouble()
    fun rasterSatelliteSaturation(): Double = RasterTiles.SATELLITE_SATURATION.toDouble()

    /** The user agent of the hidden Google pages: the same Safari as the HTTP requests (D11). */
    fun webUserAgent(): String = BrowserIdentity.SAFARI_MAC.userAgent

    companion object {
        /** The session over the platform graph and the Swift [js] and [signatures] seams, its work
         *  on the main thread. [use24h] is the device clock, [region] its two-letter region.
         *  [languageOverride] is the non-persistent UI-test launch argument. */
        fun over(
            core: CoreGraph,
            js: JsEngine,
            signatures: SignatureVerifier,
            use24h: Boolean,
            region: String?,
            languageOverride: String?,
        ): MapSession {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            val calibration = IosCalibration(core, signatures, js, scope)
            val identity = IosGoogle.identity(core.locale)
            val transitHttp = TransitousHttp(core.http, core.locale, core.text)
            val settings = SettingsStore(
                stores = core.keyValues,
                deviceUse24h = use24h,
                deviceImperial = (region?.uppercase() ?: "") in setOf("US", "GB", "LR", "MM"),
                systemTag = { core.locale.systemTags().firstOrNull() ?: "en" },
                languageOverride = languageOverride,
            )
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
                keyValues = core.keyValues,
                clock = core.clock,
                http = core.http,
                files = core.files,
                calibration = calibration,
                beforeFacets = { source ->
                    IosGoogle.applyFlags(source as? GoogleMapsSource, settings.use24h, region)
                },
                identity = identity,
                now = { core.clock.nowMillis() },
                reviewsHl = { PlaceStore.reviewsHl(core.locale.defaultLanguage(), core.locale.defaultTag()) },
                detailsLanguage = { core.locale.defaultLanguage() },
                log = core.log,
                routeSettings = { core.keyValues.open("vela_settings") },
                routeSourceFactory = {
                    IosGoogle.hybridSource(
                        core,
                        checkNotNull(calibration.calibrationStore) { "calibration not started" },
                        checkNotNull(calibration.transforms),
                        identity,
                    ).also { IosGoogle.applyRegion(it, region) }
                },
                transitPlanner = { o, d, timeMode, epoch ->
                    Transitous.plan(transitHttp, o, d, timeMode, epoch)
                },
                transitOptionsPlanner = { o, d, q ->
                    val query = q.normalized()
                    val trips = Transitous.plan(
                        transitHttp, o, d, query.timeMode, query.timeEpochSec, query.prefer,
                    )
                    app.vela.core.data.transit.TransitOrder.byPreference(trips, query.routePref)
                },
                transitBoardSource = { target ->
                    if (target.stopId != null) {
                        Transitous.boardFor(
                            transitHttp,
                            Transitous.MapStop(
                                name = target.name, stopId = target.stopId, parentId = target.parentId,
                                lat = target.lat, lon = target.lng, modes = target.modes,
                                siblingIds = target.siblingIds,
                            ),
                        )
                    } else {
                        Transitous.board(transitHttp, target.lat, target.lng)
                    }
                },
                transitStopsSource = { south, west, north, east ->
                    val found = Transitous.stopsInBox(transitHttp, south, west, north, east) ?: emptyList()
                    Transitous.mergeDirectionalPairs(found, core.text).map { stop ->
                        TransitStopPin(
                            stopId = stop.stopId, name = stop.name, latitude = stop.lat,
                            longitude = stop.lon, modes = stop.modes, parentId = stop.parentId,
                            siblingIds = stop.siblingIds,
                        )
                    }
                },
                settings = settings,
                navAlertProvider = OverpassNavAlertProvider(core.http, nowMillis = { core.clock.nowMillis() }),
            ).also { session ->
                session.search.photon = { query, near, limit, hardBox ->
                    withContext(ioDispatcher) {
                        PhotonGeocoder.suggest(
                            core.http, query, near, core.locale.defaultLanguage(), limit, hardBox,
                        )
                    }
                }
            }
        }
    }
}
