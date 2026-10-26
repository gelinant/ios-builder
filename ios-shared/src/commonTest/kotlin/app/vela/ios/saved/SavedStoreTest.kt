package app.vela.ios.saved

import app.vela.core.data.MapDataSource
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SavedRoute
import app.vela.core.model.SearchResult
import app.vela.core.model.ShortcutKind
import app.vela.core.model.TravelMode
import app.vela.core.platform.Clock
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.ios.MapSession
import app.vela.ios.route.RouteState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

private class SavedMemStores : KeyValueStores {
    val stores = mutableMapOf<String, SavedMemStore>()
    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { SavedMemStore() }
}

private class SavedMemStore : KeyValueStore {
    val values = mutableMapOf<String, Any?>()
    override fun contains(key: String) = key in values
    override fun getString(key: String, default: String?) = values[key] as String? ?: default
    override fun getLong(key: String, default: Long) = values[key] as Long? ?: default
    override fun getInt(key: String, default: Int) = values[key] as Int? ?: default
    override fun getBoolean(key: String, default: Boolean) = values[key] as Boolean? ?: default
    override fun getFloat(key: String, default: Float) = values[key] as Float? ?: default
    override fun keys() = values.keys.toSet()
    override fun edit(): KeyValueEditor = Editor()

    private inner class Editor : KeyValueEditor {
        val pending = mutableMapOf<String, Any?>()
        var clear = false
        private fun put(key: String, value: Any?): KeyValueEditor { pending[key] = value; return this }
        override fun putString(key: String, value: String?) = put(key, value)
        override fun putLong(key: String, value: Long) = put(key, value)
        override fun putInt(key: String, value: Int) = put(key, value)
        override fun putBoolean(key: String, value: Boolean) = put(key, value)
        override fun putFloat(key: String, value: Float) = put(key, value)
        override fun remove(key: String) = put(key, null)
        override fun clear(): KeyValueEditor = also { clear = true }
        override fun apply() {
            if (clear) values.clear()
            values.putAll(pending)
        }
        override fun commit(): Boolean { apply(); return true }
    }
}

private class SavedClock(var now: Long = 1_000L) : Clock {
    override fun nowMillis() = now
    override fun elapsedRealtimeMillis() = now
    override fun monotonicNanos() = now * 1_000_000
}

private val savedCoop = Place(
    id = "coop",
    name = "Davis Food Co-op",
    location = LatLng(38.5449, -121.7405),
    category = "Grocery store",
    address = "620 G St, Davis, CA 95616",
    rating = 4.6,
    featureId = "0x8085299fd6f41a23:0x10d37b4cae550f0",
)

private class ImportSource(private val hit: Place) : MapDataSource {
    val queries = mutableListOf<String>()
    var blocking = false
    var returnsHit = true
    var routes: List<Route> = emptyList()
    var directionError: Exception? = null

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult {
        queries += query
        if (blocking) delay(Long.MAX_VALUE)
        return SearchResult(query, if (returnsHit) listOf(hit) else emptyList())
    }
    override suspend fun placeDetails(id: String): Place = error("unused")
    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> {
        directionError?.let { throw it }
        return routes
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class SavedStoreTest {
    private fun TestScope.fixture(source: MapDataSource? = null): Triple<SavedStore, SavedMemStores, SavedClock> {
        val stores = SavedMemStores()
        val clock = SavedClock(1_000L)
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        return Triple(SavedStore(stores, clock, scope, { source }), stores, clock)
    }

    @Test fun savedListsRecentsAndShortcutsPersistAcrossStores() = runTest {
        val (store, stores, clock) = fixture()
        assertTrue(store.state.value.saved.isEmpty())
        store.start()
        assertTrue(store.toggleSave(savedCoop))
        store.recordSearch(" coffee ")
        store.recordPlace(savedCoop)
        val listId = store.createList(" Weekend ")
        store.addToList(listId, savedCoop)
        store.setShortcut(ShortcutKind.HOME, savedCoop)
        clock.now = 2_000L

        val restored = SavedStore(stores, clock, this.backgroundScope).also { it.start() }
        assertEquals(listOf("coop"), restored.state.value.saved.map { it.id })
        assertEquals(listOf("coop"), restored.state.value.listPlaces(listId).map { it.placeId })
        assertEquals("Weekend", restored.state.value.lists.single().name)
        assertEquals("coop", restored.state.value.home?.id)
        assertEquals("coffee", restored.state.value.recentSearches.single().query)
        assertEquals("coop", restored.state.value.recentPlaces.single().place.id)
        assertTrue(restored.contains("coop", savedCoop.featureId))
        assertEquals(2, restored.state.value.recentRows().size)

        restored.renamePlace("coop", "My co-op", savedCoop.featureId)
        restored.renameList(listId, "Local")
        assertEquals("My co-op", restored.state.value.saved.single().name)
        assertEquals("My co-op", restored.state.value.listPlaces(listId).single().name)
        assertEquals("Local", restored.state.value.listRows().single().name)
        restored.moveSavedPlace("coop", listId)
        assertTrue(restored.state.value.saved.isEmpty())
        restored.removeFromList(listId, "coop", savedCoop.featureId)
        assertTrue(restored.state.value.listPlaces(listId).isEmpty())
        restored.deleteList(listId)
        restored.clearShortcut(ShortcutKind.HOME)
        restored.clearRecents()
        assertTrue(restored.state.value.lists.isEmpty())
        assertNull(restored.state.value.home)
        assertTrue(restored.state.value.recentRows().isEmpty())
    }

    @Test fun shortcutsRemainIndependentOfQuickSavesListsAndRecents() = runTest {
        val (store, stores, clock) = fixture()
        store.start()
        store.setShortcut(ShortcutKind.HOME, savedCoop)
        store.setShortcut(ShortcutKind.WORK, savedCoop)
        store.toggleSave(savedCoop)
        store.recordPlace(savedCoop)
        store.removeSaved(savedCoop.id)
        store.clearRecents()

        assertTrue(store.state.value.saved.isEmpty())
        assertTrue(store.state.value.recentRows().isEmpty())
        assertEquals(savedCoop.location, store.state.value.home?.toPlace()?.location)
        assertEquals(savedCoop.location, store.state.value.work?.toPlace()?.location)
        val restored = SavedStore(stores, clock, backgroundScope).also { it.start() }
        assertEquals(savedCoop.id, restored.state.value.home?.id)
        assertEquals(savedCoop.id, restored.state.value.work?.id)
    }

    @Test fun parkingKeepsHistoryAndRestoresASpot() = runTest {
        val (store, _, clock) = fixture()
        store.start()
        assertFalse(store.saveParkingAtMyLocation())
        store.onLocation(38.55, -121.74)
        assertTrue(store.saveParkingAtMyLocation())
        assertEquals(1_000L, store.state.value.parking?.savedAtMillis)
        clock.now = 5_000L
        store.saveParking(Place(id = "p", name = "Garage", location = LatLng(38.56, -121.75)))
        assertEquals(2, store.state.value.parkingHistory.size)
        assertEquals(5.0, store.state.value.parkingRow()?.savedAtSeconds)
        assertEquals("Test parking", store.parkingPlace("Test parking")?.name)
        store.clearParking()
        assertNull(store.state.value.parking)
        assertNull(store.parkingPlace("Test parking"))
        assertEquals(2, store.state.value.parkingHistory.size)
        store.restoreParking(store.state.value.parkingRows().last())
        assertEquals(1.0, store.state.value.parkingRow()?.savedAtSeconds)
        store.clearParkingHistory()
        assertTrue(store.state.value.parkingHistory.isEmpty())
    }

    @Test fun activeRouteIsSavedWithItsLineAndCanBeRenamed() = runTest {
        val (store, _, _) = fixture()
        store.start()
        val points = listOf(LatLng(37.7749, -122.4194), LatLng(37.78, -122.41), LatLng(37.7942, -122.3946))
        val active = Route(points, emptyList(), 2600.0, 600.0, null)
        val route = RouteState(
            open = true,
            origin = savedCoop,
            destination = savedCoop.copy(id = "ferry", name = "Ferry Building"),
            mode = TravelMode.WALK,
            routes = listOf(active),
            active = active,
        )
        assertTrue(store.saveActiveRoute(route, "Morning walk"))
        assertFalse(store.saveActiveRoute(route, " "))
        val saved = store.state.value.savedRoutes.single()
        assertEquals("Morning walk", saved.name)
        assertEquals("WALK", saved.mode)
        assertEquals("Davis Food Co-op", saved.originLabel)
        assertEquals("Ferry Building", saved.destLabel)
        assertEquals(points, app.vela.core.data.google.PolylineCodec.decode(saved.polyline))
        assertNotNull(store.savedRoute(saved.id))
        store.renameRoute(saved.id, "Weekend walk")
        assertEquals("Weekend walk", store.state.value.routeRows().single().name)
        store.deleteRoute(saved.id)
        assertTrue(store.state.value.savedRoutes.isEmpty())
    }

    @Test fun importsKmlAndVelaListJsonWithoutConfusingTheirShapes() = runTest {
        val (store, _, _) = fixture()
        store.start()
        store.importFile("<kml><Placemark><name>Co-op</name><Point><coordinates>-121.7405,38.5449</coordinates></Point></Placemark></kml>", "pins.kml")
        advanceUntilIdle()
        assertEquals(SavedImportKind.ADDED, store.state.value.lastImport?.kind)
        assertEquals("imp:38.54490,-121.74050", store.state.value.saved.single().id)

        val listJson = """[{"id":"list:one","name":"One","places":[{"id":"coop","name":"Co-op","lat":38.5449,"lng":-121.7405}]}]"""
        store.importFile(listJson, "one.json")
        advanceUntilIdle()
        assertEquals("list:one", store.state.value.lists.single().id)
        assertEquals("coop", store.state.value.listPlaces("list:one").single().placeId)
    }

    @Test fun takeoutCsvKeepsPinsAndLooksUpListingsByFeatureId() = runTest {
        val source = ImportSource(savedCoop)
        val (store, _, _) = fixture(source)
        store.start()
        val fid = savedCoop.featureId!!
        val csv = "Title,Note,URL,Comment\n" +
            "Co-op,Good,$fid,Must try\n" +
            "A pin,,\"https://www.google.com/maps/search/38.5449,-121.7405\",\n"
        // A listing link carries the feature id in its data blob, as Takeout writes it.
        val withLink = csv.replace(fid, "https://www.google.com/maps/place/Co-op/data=!1s$fid")
        store.importFile(withLink, "Favorites.csv")
        advanceUntilIdle()
        val result = store.state.value.lastImport
        assertEquals(SavedImportKind.LIST_ADDED, result?.kind)
        assertEquals(2, result?.count)
        assertEquals(0, result?.missed)
        assertEquals(listOf("Co-op"), source.queries)
        val rows = store.state.value.listPlaces(store.state.value.lists.single().id)
        assertEquals("Good\nMust try", store.state.value.lists.single().places.first().note)
        assertEquals("imp:38.54490,-121.74050", rows[1].placeId)
    }

    @Test fun takeoutCancellationKeepsCompletedRowsAndResetsState() = runTest {
        val source = ImportSource(savedCoop).apply { blocking = true }
        val (store, stores, clock) = fixture(source)
        store.start()
        val csv = "Title,Note,URL,Comment\n" +
            "A pin,,\"https://www.google.com/maps/search/38.5449,-121.7405\",\n" +
            "Missing,,\"https://www.google.com/maps/place/Missing/data=!1s${savedCoop.featureId}\",\n"
        store.importFile(csv, "Favorites.csv")
        runCurrent()
        assertTrue(store.state.value.importing)
        store.cancelImport()
        advanceUntilIdle()

        assertFalse(store.state.value.importing)
        assertEquals(SavedImportKind.CANCELLED, store.state.value.lastImport?.kind)
        val list = store.state.value.lists.single()
        assertEquals(listOf("A pin"), list.places.map { it.name })
        val restored = SavedStore(stores, clock, backgroundScope).also { it.start() }
        assertEquals(listOf("A pin"), restored.state.value.lists.single().places.map { it.name })
    }

    @Test fun completedTakeoutLookupFailureRemovesStaleListRows() = runTest {
        val source = ImportSource(savedCoop)
        val (store, _, _) = fixture(source)
        store.start()
        val original = "Title,Note,URL,Comment\n" +
            "Co-op,,\"https://www.google.com/maps/place/Co-op/data=!1s${savedCoop.featureId}\",\n"
        store.importFile(original, "Favorites.csv")
        advanceUntilIdle()
        val listId = store.state.value.lists.single().id
        assertEquals(1, store.state.value.lists.single().places.size)

        source.returnsHit = false
        source.queries.clear()
        val otherFeature = "0x8085299fd6f41a23:0x10d37b4cae550f1"
        val csv = "Title,Note,URL,Comment\n" +
            "Missing,,\"https://www.google.com/maps/place/Missing/data=!1s$otherFeature\",\n"
        store.importFile(csv, "Favorites.csv")
        advanceUntilIdle()

        assertEquals(SavedImportKind.LIST_ADDED, store.state.value.lastImport?.kind)
        assertEquals(0, store.state.value.lastImport?.count)
        assertEquals(1, store.state.value.lastImport?.missed)
        assertEquals(listId, store.state.value.lists.single().id)
        assertTrue(store.state.value.lists.single().places.isEmpty())
        assertEquals(listOf("Missing", "Missing"), source.queries)
    }

    @Test fun savedLineOfferReusesIdentityWithoutInventingStepsOrTraffic() = runTest {
        val points = listOf(LatLng(37.7749, -122.4194), LatLng(37.78, -122.41), LatLng(37.7942, -122.3946))
        val computed = Route(points.reversed(), emptyList(), 2400.0, 500.0, 550.0)
        val source = ImportSource(savedCoop).apply { routes = listOf(computed) }
        val saved = SavedRoute(
            id = "route:saved",
            name = "Morning walk",
            mode = "WALK",
            originLat = points.first().lat,
            originLng = points.first().lng,
            destLat = points.last().lat,
            destLng = points.last().lng,
            destLabel = "Ferry Building",
            polyline = app.vela.core.data.google.PolylineCodec.encode(points),
            createdAt = 1_000L,
        )
        val offering = SavedRouteDirections(source) { listOf(saved) }
        val first = offering.directions(saved.origin, saved.dest, TravelMode.WALK)
        assertEquals(2, first.size)
        assertSame(computed, first[1])
        val line = first[0]
        assertEquals("Morning walk", line.savedName)
        assertEquals(points, line.polyline)
        assertEquals(-1.0, line.durationSeconds)
        assertNull(line.durationInTrafficSeconds)
        assertTrue(line.maneuvers.isEmpty())
        assertSame(line, offering.directions(saved.origin, saved.dest, TravelMode.WALK)[0])
        assertEquals(1, offering.directions(saved.origin, saved.dest, TravelMode.DRIVE).size)
        val newStart = LatLng(38.5449, -121.7405)
        assertEquals(1, offering.directions(newStart, saved.dest, TravelMode.WALK).size)
        offering.request(saved.id)
        assertSame(line, offering.directions(newStart, saved.dest, TravelMode.WALK)[0])
        offering.clearRequest()
        assertEquals(1, offering.directions(newStart, saved.dest, TravelMode.WALK).size)
        source.directionError = IllegalStateException("offline")
        val offline = offering.directions(saved.origin, saved.dest, TravelMode.WALK)
        assertEquals(1, offline.size)
        assertSame(line, offline[0])
    }

    @Test fun mapSessionReopeningPutsTheSavedLineInTheRealRouteState() = runTest {
        val points = listOf(LatLng(37.7749, -122.4194), LatLng(37.78, -122.41), LatLng(37.7942, -122.3946))
        val computed = Route(points, emptyList(), 2400.0, 500.0, 550.0)
        val source = ImportSource(savedCoop).apply { routes = listOf(computed) }
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val session = MapSession(
            sourceFactory = { source },
            scope = scope,
            keyValues = SavedMemStores(),
            clock = SavedClock(),
            routeSourceFactory = { source },
        )
        session.start()
        val destination = savedCoop.copy(id = "ferry", name = "Ferry Building")
        val initial = RouteState(
            open = true,
            destination = destination,
            mode = TravelMode.DRIVE,
            routes = listOf(computed),
            active = computed,
        )
        assertTrue(session.saved.saveActiveRoute(initial, "UI Saved Line"))
        val id = session.saved.state.value.savedRoutes.single().id
        session.route.onLocation(points.first().lat, points.first().lng)
        session.openSavedRoute(id)
        runCurrent()
        scope.cancel()

        val routes = session.route.state.value.routes
        assertEquals(2, routes.size)
        assertEquals("UI Saved Line", routes[0].savedName)
        assertEquals(-1.0, routes[0].durationSeconds)
        assertSame(computed, routes[1])
    }

    @Test fun listExportIsThePortableSingleListJson() = runTest {
        val (store, _, _) = fixture()
        store.start()
        val listId = store.createList("Weekend")
        store.addToList(listId, savedCoop)
        val json = store.exportListJson(listId)
        assertNotNull(json)
        assertTrue(json.contains("\"name\":\"Weekend\""))
        assertTrue(json.contains("\"id\":\"coop\""))
        assertNull(store.exportListJson("missing"))
    }

    @Test fun shareLinksUseTheExactListingOrANameAndPoint() {
        assertEquals(
            "https://www.google.com/maps?cid=18446744073709551615",
            SavedStore.sharePlaceUrl(savedCoop.copy(featureId = "0x0:0xffffffffffffffff")),
        )
        assertEquals(
            "https://www.google.com/maps/search/?api=1&query=Davis%20Food%20Co-op%2038.5449%2C-121.7405",
            SavedStore.sharePlaceUrl(savedCoop.copy(featureId = null)),
        )
    }
}
