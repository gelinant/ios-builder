package app.vela.core.di

import app.vela.core.config.CalibrationStore
import app.vela.core.data.google.ChromeIdentity
import app.vela.core.data.google.GoogleSession
import app.vela.core.platform.CoreGraph
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/** The Google classes that moved to `:core-common` and so lost their `@Inject` constructors. */
@Module
@InstallIn(SingletonComponent::class)
object GoogleModule {

    /** The session warm-up over the shared client ([CoreGraph.http]), so its cookies are the ones
     *  the data requests send. */
    @Provides
    @Singleton
    fun googleSession(graph: CoreGraph, calibration: CalibrationStore): GoogleSession =
        GoogleSession(graph.http, calibration, ChromeIdentity { calibration.current() })
}
