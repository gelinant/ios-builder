package app.vela.core.di

import app.vela.core.data.transit.TransitLineCache
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.platform.Clock
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.TextNormalizer
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.joinPath
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/** The Transitous client's seams and the transit line cache, both in `:core-common`. */
@Module
@InstallIn(SingletonComponent::class)
object TransitModule {

    /** The shared client: [app.vela.core.data.transit.Transitous.linesInBox] sets its own 40 s
     *  call deadline on the request. */
    @Provides
    @Singleton
    fun transitousHttp(http: VelaHttp, locale: PlatformLocale, text: TextNormalizer): TransitousHttp =
        TransitousHttp(http, locale, text)

    @Provides
    @Singleton
    fun transitLineCache(files: PlatformFiles, clock: Clock): TransitLineCache =
        TransitLineCache(files, joinPath(files.filesDir, "transit_lines"), clock::nowMillis)
}
