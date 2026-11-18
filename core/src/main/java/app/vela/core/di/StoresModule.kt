package app.vela.core.di

import app.vela.core.data.ParkingStore
import app.vela.core.data.PlaceCache
import app.vela.core.data.PlaceListStore
import app.vela.core.data.PlaceShortcutStore
import app.vela.core.data.RecentPlaceStore
import app.vela.core.data.RecentSearchStore
import app.vela.core.data.SavedPlaceStore
import app.vela.core.data.SavedRouteStore
import app.vela.core.data.StreetViewCache
import app.vela.core.platform.Clock
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.PlatformFiles
import app.vela.core.util.PlaceNames
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/** The place stores and caches that live in `:core-common`, built on the platform seams. */
@Module
@InstallIn(SingletonComponent::class)
object StoresModule {

    @Provides
    @Singleton
    fun parkingStore(keyValues: KeyValueStores): ParkingStore = ParkingStore(keyValues)

    @Provides
    @Singleton
    fun placeListStore(keyValues: KeyValueStores): PlaceListStore = PlaceListStore(keyValues)

    @Provides
    @Singleton
    fun placeShortcutStore(keyValues: KeyValueStores): PlaceShortcutStore = PlaceShortcutStore(keyValues)

    @Provides
    @Singleton
    fun recentPlaceStore(keyValues: KeyValueStores, clock: Clock): RecentPlaceStore = RecentPlaceStore(keyValues, clock)

    @Provides
    @Singleton
    fun recentSearchStore(keyValues: KeyValueStores, clock: Clock): RecentSearchStore = RecentSearchStore(keyValues, clock)

    @Provides
    @Singleton
    fun savedPlaceStore(keyValues: KeyValueStores): SavedPlaceStore = SavedPlaceStore(keyValues)

    @Provides
    @Singleton
    fun savedRouteStore(keyValues: KeyValueStores): SavedRouteStore = SavedRouteStore(keyValues)

    @Provides
    @Singleton
    fun placeCache(files: PlatformFiles, clock: Clock): PlaceCache = PlaceCache(files, clock, PlaceNames::normalized)

    @Provides
    @Singleton
    fun streetViewCache(files: PlatformFiles): StreetViewCache = StreetViewCache(files)
}
