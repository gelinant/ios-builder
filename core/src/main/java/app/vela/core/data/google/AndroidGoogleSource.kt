package app.vela.core.data.google

import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.data.RouteEngine
import app.vela.core.diag.DiagLog
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.OkHttpRouteHttp
import app.vela.core.platform.OkHttpVelaHttp
import okhttp3.OkHttpClient
import kotlin.time.Duration.Companion.seconds

/** [GoogleMapsDataSource] on the Android clients (SPEC 2.5): every client derived from the shared
 *  one, as before the source moved to `:core-common`. */
object AndroidGoogleSource {
    /** The whole call for a reply of megabytes (`GoogleMapsSource.largeReplyHttp`). */
    private const val LARGE_REPLY_TIMEOUT_S = 90L

    fun create(
        http: OkHttpClient,
        graph: CoreGraph,
        session: GoogleSession,
        calibration: CalibrationStore,
        jsTransforms: JsTransforms,
        diag: DiagLog,
        routeEngine: RouteEngine,
    ): GoogleMapsDataSource = GoogleMapsDataSource(
        graph = graph,
        largeReplyHttp = OkHttpVelaHttp(
            http.newBuilder()
                .callTimeout(LARGE_REPLY_TIMEOUT_S.seconds)
                .readTimeout(60.seconds)
                .build(),
        ),
        routeHttp = OkHttpRouteHttp(http),
        openHttp = OkHttpVelaHttp(http),
        session = session,
        calibration = calibration,
        jsTransforms = jsTransforms,
        diag = diag,
        routeEngine = routeEngine,
    )
}
