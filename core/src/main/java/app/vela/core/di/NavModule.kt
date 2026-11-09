package app.vela.core.di

import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.data.MapDataSource
import app.vela.core.data.RouteEngine
import app.vela.core.data.google.AndroidGoogleSource
import app.vela.core.data.google.GoogleMapsDataSource
import app.vela.core.data.google.GoogleSession
import app.vela.core.diag.DiagLog
import app.vela.core.feedback.Haptics
import app.vela.core.nav.NavSession
import app.vela.core.platform.CoreGraph
import app.vela.core.voice.VoiceGuide
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import javax.inject.Singleton

/** The navigation and routing classes that moved to `:core-common` without their `@Inject`,
 *  built on the Android seams: the drive's voice is `VoiceGuide`, its haptics `Haptics`, its
 *  diagnostics `DiagLog`, its clock and log the platform ones; the hybrid router's clients are
 *  derived from the shared OkHttp client ([AndroidGoogleSource]). */
@Module
@InstallIn(SingletonComponent::class)
object NavModule {

    @Provides
    @Singleton
    fun navSession(
        dataSource: MapDataSource,
        voice: VoiceGuide,
        haptics: Haptics,
        diag: DiagLog,
        graph: CoreGraph,
    ): NavSession = NavSession(dataSource, voice, haptics, diag, graph.log, graph.clock)

    @Provides
    @Singleton
    fun googleMapsDataSource(
        http: OkHttpClient,
        graph: CoreGraph,
        session: GoogleSession,
        calibration: CalibrationStore,
        jsTransforms: JsTransforms,
        diag: DiagLog,
        routeEngine: RouteEngine,
    ): GoogleMapsDataSource = AndroidGoogleSource.create(http, graph, session, calibration, jsTransforms, diag, routeEngine)
}
