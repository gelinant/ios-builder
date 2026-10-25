package app.vela.ios.search

import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.data.ClockFormat
import app.vela.core.data.LowDataMode
import app.vela.core.data.NoGoogle
import app.vela.core.data.RouteEngine
import app.vela.core.data.RouteHttp
import app.vela.core.data.RoutingPrefs
import app.vela.core.data.google.GoogleMapsDataSource
import app.vela.core.data.google.GoogleMapsSource
import app.vela.core.data.google.GoogleSession
import app.vela.core.diag.DiagSink
import app.vela.core.i18n.DelayText
import app.vela.core.model.LatLng
import app.vela.core.model.Route
import app.vela.core.model.TravelMode
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.PlatformLocale
import app.vela.ios.net.BrowserIdentity
import app.vela.ios.net.SafariIdentity
import app.vela.ios.route.IosGoogleSource
import kotlin.math.abs

/**
 * The iOS Google source: the common [GoogleMapsSource] (C-2) over the platform graph, claiming
 * Safari on macOS ([SafariIdentity], PORTAGE_IOS.md D11), reading the live calibration and its
 * JS transforms, with Google's walk ([IosGoogleSource]). [hybridSource] is the single construction
 * point for the common hybrid router used by `MapSession`. Every request, large replies included,
 * goes through [CoreGraph.http]: the Swift client honors each request's own deadline.
 */
object IosGoogle {
    fun identity(locale: PlatformLocale): SafariIdentity =
        SafariIdentity({ BrowserIdentity.acceptLanguageFor(locale.preferredTags()) })

    fun source(core: CoreGraph, calibration: CalibrationStore, transforms: JsTransforms, identity: SafariIdentity): GoogleMapsSource =
        IosGoogleSource(
            graph = core,
            session = GoogleSession(core.http, calibration, identity),
            calibration = calibration,
            transforms = transforms,
            identity = identity,
        )

    /** The common hybrid router on iOS. One function is the deduplication point for the route
     * chooser and navigation: OSRM and Valhalla share the platform HTTP client, and there is no
     * on-phone `.obf` engine on iOS. */
    fun hybridSource(
        core: CoreGraph,
        calibration: CalibrationStore,
        transforms: JsTransforms,
        identity: SafariIdentity,
    ): GoogleMapsDataSource = GoogleMapsDataSource(
        graph = core,
        largeReplyHttp = core.http,
        routeHttp = RouteHttp.of(core.http),
        openHttp = core.http,
        session = GoogleSession(core.http, calibration, identity),
        calibration = calibration,
        jsTransforms = transforms,
        diag = DiagSink.NONE,
        routeEngine = IosRouteEngine,
    )

    /**
     * The process holders `:core-common` reads, set before the first request (PRESENTATION-MAP.md
     * 5, trap 3), as Android's `VelaApp` and `MapViewModel` init push them. iOS has no "without
     * Google" or low-data setting yet, so both are off; routing keeps its defaults.
     */
    fun applyFlags(source: GoogleMapsSource?, use24h: Boolean, region: String?) {
        NoGoogle.enabled = false
        LowDataMode.enabled = false
        RoutingPrefs.bikeSafe = true
        RoutingPrefs.avoidTolls = false
        RoutingPrefs.avoidHighways = false
        RoutingPrefs.avoidFerries = false
        RoutingPrefs.googleTraffic = true
        ClockFormat.use24h = use24h
        // English until the String Catalog is wired (I-8): the `transit_min_late` and
        // `transit_min_early` keys.
        DelayText.formatter = { m -> if (m > 0) "$m min late" else "${abs(m)} min early" }
        source?.glRegion = region?.lowercase()?.takeIf { it.length == 2 && it.all { c -> c in 'a'..'z' } }
    }
}

/** No offline router is installed on iOS: readiness and coverage stay false and routing falls
 * through to the common online hybrid ladder. */
private object IosRouteEngine : RouteEngine {
    override fun isReady(mode: TravelMode) = false
    override fun route(
        origin: LatLng,
        destination: LatLng,
        mode: TravelMode,
        avoidTolls: Boolean,
        avoidHighways: Boolean,
        avoidFerries: Boolean,
        departBearingDeg: Double?,
        maxMs: Long?,
    ): List<Route> = emptyList()
}
