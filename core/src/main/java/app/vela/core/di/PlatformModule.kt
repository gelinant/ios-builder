package app.vela.core.di

import android.content.Context
import app.vela.core.platform.AndroidClock
import app.vela.core.platform.AndroidLog
import app.vela.core.platform.AndroidPlatformFiles
import app.vela.core.platform.AndroidPlatformLocale
import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.JvmTextNormalizer
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.Log
import app.vela.core.platform.OkHttpVelaHttp
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.SharedPrefsKeyValueStores
import app.vela.core.platform.TextNormalizer
import app.vela.core.platform.VelaHttp
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import javax.inject.Singleton

/** The Android implementations of the platform seams in `:core-common` (SPEC "Platform seams"). */
@Module
@InstallIn(SingletonComponent::class)
object PlatformModule {

    @Provides
    @Singleton
    fun log(): Log = AndroidLog

    @Provides
    @Singleton
    fun clock(): Clock = AndroidClock

    @Provides
    @Singleton
    fun keyValueStores(@ApplicationContext context: Context): KeyValueStores = SharedPrefsKeyValueStores(context)

    @Provides
    @Singleton
    fun platformFiles(@ApplicationContext context: Context): PlatformFiles =
        AndroidPlatformFiles(context.filesDir, context.cacheDir, context.noBackupFilesDir)

    /** The shared client from [CoreModule.okHttpClient], so the request counter, Cronet and the
     *  cookie jar see every request. */
    @Provides
    @Singleton
    fun velaHttp(client: OkHttpClient): VelaHttp = OkHttpVelaHttp(client)

    @Provides
    @Singleton
    fun textNormalizer(): TextNormalizer = JvmTextNormalizer

    @Provides
    @Singleton
    fun platformLocale(): PlatformLocale = AndroidPlatformLocale

    @Provides
    @Singleton
    fun coreGraph(
        log: Log,
        clock: Clock,
        keyValues: KeyValueStores,
        files: PlatformFiles,
        http: VelaHttp,
        text: TextNormalizer,
        locale: PlatformLocale,
    ): CoreGraph = CoreGraph(log, clock, keyValues, files, http, text, locale)
}
