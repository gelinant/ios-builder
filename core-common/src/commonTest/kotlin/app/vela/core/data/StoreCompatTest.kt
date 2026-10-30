package app.vela.core.data

import app.vela.core.model.ParkedSpot
import app.vela.core.model.SavedPlace
import app.vela.core.model.ShortcutKind
import app.vela.core.platform.MemKeyValueStores
import app.vela.core.platform.TestClock
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The stores read what the Android build wrote before they moved to the seam: the same store
 * names, keys and JSON. Each fixture is a value as the old `SharedPreferences` code stored it.
 * Fixture places: Davis.
 */
class StoreCompatTest {
    private val kv = MemKeyValueStores()
    private val clock = TestClock()

    private fun seed(store: String, vararg values: Pair<String, Any>) {
        kv.open(store)
        kv.stores.getValue(store).values.putAll(values)
    }

    private fun stored(store: String, key: String): Any? = kv.stores[store]?.values?.get(key)

    @Test
    fun `saved places come back from vela_saved places`() {
        seed(
            "vela_saved",
            "places" to """[{"id":"g:1","name":"Davis Food Co-op","lat":38.5449,"lng":-121.7405,"address":"620 G St","pinned":true},""" +
                """{"id":"pin:38.54,-121.74","name":"Spot","lat":38.54,"lng":-121.74,"futureField":7}]""",
        )
        val store = SavedPlaceStore(kv)
        val saved = store.saved()
        assertEquals(listOf("g:1", "pin:38.54,-121.74"), saved.map { it.id })
        assertEquals("620 G St", saved[0].address)
        assertTrue(saved[0].pinned)
        assertTrue(store.isSaved("g:1"))
        store.setPinned("g:1", false)
        assertEquals(
            """[{"id":"g:1","name":"Davis Food Co-op","lat":38.5449,"lng":-121.7405,"address":"620 G St"},""" +
                """{"id":"pin:38.54,-121.74","name":"Spot","lat":38.54,"lng":-121.74}]""",
            stored("vela_saved", "places"),
        )
        val e = kv.stores.getValue("vela_saved")
        assertEquals(0, e.commits, "the stores write with apply")
        assertEquals(1, e.applies)
    }

    @Test
    fun `lists come back from vela_lists lists`() {
        seed(
            "vela_lists",
            "lists" to """[{"id":"list:1","name":"Lunch","icon":"emoji:🍜","color":4280391411,"places":[""" +
                """{"id":"g:2","name":"Sam's","lat":38.5446,"lng":-121.7395,"note":"Tuesday","featureId":"0x1:0x2"}]}]""",
        )
        val store = PlaceListStore(kv)
        val lists = store.lists()
        assertEquals("Lunch", lists.single().name)
        assertEquals(4280391411, lists.single().color)
        assertEquals("Tuesday", lists.single().places.single().note)
        assertEquals(listOf("list:1"), store.listsContaining("other", "0x1:0x2").map { it.id })
    }

    @Test
    fun `home and work come back from vela_shortcuts`() {
        seed("vela_shortcuts", "HOME" to """{"id":"pin:h","name":"Home","lat":38.55,"lng":-121.75}""")
        val store = PlaceShortcutStore(kv)
        assertEquals("pin:h", store.get(ShortcutKind.HOME)?.id)
        assertNull(store.get(ShortcutKind.WORK))
        store.set(ShortcutKind.WORK, SavedPlace("pin:w", "Work", 38.53, -121.76))
        assertEquals("""{"id":"pin:w","name":"Work","lat":38.53,"lng":-121.76}""", stored("vela_shortcuts", "WORK"))
        store.set(ShortcutKind.HOME, null)
        assertTrue("HOME" !in kv.stores.getValue("vela_shortcuts").values)
    }

    @Test
    fun `parking comes back from vela_settings with its string coordinates and long time`() {
        seed(
            "vela_settings",
            "parking_lat" to "38.5435",
            "parking_lng" to "-121.74",
            "parking_at" to 1_690_000_000_000L,
            "parking_history" to """[{"lat":38.5435,"lng":-121.74,"savedAtMillis":1690000000000}]""",
            "map_layer" to "other settings in the same file are left alone",
        )
        val store = ParkingStore(kv)
        assertEquals(ParkingStore.Current(38.5435, -121.74, 1_690_000_000_000L), store.current())
        assertEquals(listOf(ParkedSpot(38.5435, -121.74, 1_690_000_000_000L)), store.history())
        store.save(ParkedSpot(38.55, -121.7, 1_700_000_000_000L))
        assertEquals("38.55", stored("vela_settings", "parking_lat"))
        assertEquals("-121.7", stored("vela_settings", "parking_lng"))
        assertEquals(1_700_000_000_000L, stored("vela_settings", "parking_at"))
        assertEquals(2, store.history().size)
        store.clearCurrent()
        assertNull(store.current())
        assertEquals("other settings in the same file are left alone", stored("vela_settings", "map_layer"))
    }

    @Test
    fun `saved routes come back from vela_saved_routes routes`() {
        seed(
            "vela_saved_routes",
            "routes" to """[{"id":"r1","name":"To work","mode":"DRIVE","originLat":38.54,"originLng":-121.74,""" +
                """"destLat":38.58,"destLng":-121.49,"destLabel":"Sacramento","polyline":"_p~iF~ps|U","createdAt":1690000000000,""" +
                """"stops":[{"name":"Coffee","lat":38.55,"lng":-121.7}]}]""",
        )
        val store = SavedRouteStore(kv)
        val r = store.all().single()
        assertEquals("Sacramento", r.destLabel)
        assertEquals("Coffee", r.stops.single().name)
        assertEquals("", r.originLabel)
        assertEquals("Home run", store.rename("r1", " Home run ").single().name)
    }

    @Test
    fun `recent places read the timestamped key and the legacy one`() {
        seed(
            "vela_recent_places",
            "places2" to """[{"place":{"id":"g:3","name":"Mishka's","lat":38.5447,"lng":-121.7402},"at":1690000000000}]""",
        )
        val store = RecentPlaceStore(kv, clock)
        assertEquals(1_690_000_000_000L, store.recent().single().at)

        val legacy = MemKeyValueStores()
        legacy.open("vela_recent_places")
        legacy.stores.getValue("vela_recent_places").values["places"] =
            """[{"id":"g:3","name":"Mishka's","lat":38.5447,"lng":-121.7402},{"id":"g:4","name":"Tea","lat":38.545,"lng":-121.74}]"""
        val migrated = RecentPlaceStore(legacy, clock).recent()
        assertEquals(listOf(clock.now, clock.now - 60_000L), migrated.map { it.at })
        val values = legacy.stores.getValue("vela_recent_places").values
        assertTrue("places" in values, "the legacy key stays for a downgrade")
        assertTrue((values["places2"] as String).startsWith("""[{"place":{"id":"g:3""""))
    }

    @Test
    fun `recent searches read the timestamped key and the legacy one`() {
        seed("vela_recents", "queries" to """["coffee","Tacos"]""")
        val store = RecentSearchStore(kv, clock)
        assertEquals(listOf("coffee", "Tacos"), store.recent().map { it.query })
        clock.now += 1000
        store.add("tacos")
        assertEquals(listOf("tacos", "coffee"), store.recent().map { it.query })
        assertEquals(
            """[{"query":"tacos","at":${clock.now}},{"query":"coffee","at":${clock.now - 1000}}]""",
            stored("vela_recents", "queries2"),
        )
        store.clear()
        assertTrue(kv.stores.getValue("vela_recents").values.isEmpty())
    }

    @Test
    fun `the ambient cache file of an older build decodes`() {
        val raw = """[{"lat":38.54,"lng":-121.74,"atWallMs":1690000000000,"places":[""" +
            """{"id":"g:5","name":"Bakery","lat":38.541,"lng":-121.741,"category":"Bakery","closed":true}]}]"""
        val area = AmbientDiskCache.decode(raw)!!.single()
        assertEquals(9000.0, area.spanM)
        assertTrue(area.places.single().toPlace().permanentlyClosed)
        assertNull(AmbientDiskCache.decode("not json"))
    }
}
