package app.vela.core.di

import android.content.Context
import app.vela.core.data.OfflineAddressStore
import app.vela.core.data.OfflinePoiStore
import app.vela.core.offline.RegionCatalog
import app.vela.core.platform.AndroidSqlDbs
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.VelaHttp
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/** The offline stores and catalogs that live in `:core-common` (SPEC "Platform seams"). */
@Module
@InstallIn(SingletonComponent::class)
object OfflineModule {

    @Provides
    @Singleton
    fun sqlDbs(@ApplicationContext context: Context): SqlDbs = AndroidSqlDbs(context)

    @Provides
    @Singleton
    fun offlinePoiStore(sql: SqlDbs): OfflinePoiStore = OfflinePoiStore(sql)

    @Provides
    @Singleton
    fun offlineAddressStore(sql: SqlDbs): OfflineAddressStore = OfflineAddressStore(sql)

    /** The shared client, as the catalog fetch used before it moved. */
    @Provides
    @Singleton
    fun regionCatalog(http: VelaHttp, files: PlatformFiles): RegionCatalog = RegionCatalog(http, files)
}
