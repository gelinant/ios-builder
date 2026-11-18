package app.vela.core.data

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import app.vela.core.di.StoresModule
import app.vela.core.model.LatLng
import app.vela.core.model.ListPlace
import app.vela.core.model.ParkedSpot
import app.vela.core.model.Place
import app.vela.core.model.PlaceList
import app.vela.core.model.Review
import app.vela.core.model.SavedPlace
import app.vela.core.model.SavedRoute
import app.vela.core.model.ShortcutKind
import app.vela.core.model.StreetViewPano
import app.vela.core.platform.AndroidClock
import app.vela.core.platform.AndroidPlatformFiles
import app.vela.core.platform.SharedPrefsKeyValueStores
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * An install updated from the build whose stores read `SharedPreferences` and `java.io.File`
 * directly: data written the old way (the same calls, file names, keys and JSON) is read by the
 * stores built as Hilt builds them, through `SharedPrefsKeyValueStores` and `AndroidPlatformFiles`.
 */
class StoresAndroidCompatTest {
    private val prefs = HashMap<String, MemPrefs>()
    private val modes = HashMap<String, Int>()
    private val context = object : ContextWrapper(null) {
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
            modes[name] = mode
            return prefs.getOrPut(name) { MemPrefs() }
        }
    }
    private val kv = SharedPrefsKeyValueStores(context)
    private val json = Json { ignoreUnknownKeys = true }
    private val root = Files.createTempDirectory("vela-c6").toFile()
    private val files = AndroidPlatformFiles(File(root, "files"), File(root, "cache"), File(root, "nobackup"))

    @After fun tearDown() { root.deleteRecursively() }

    private fun old(name: String) = context.getSharedPreferences(name, Context.MODE_PRIVATE)

    @Test fun placesListsShortcutsAndRoutesWrittenTheOldWayReadBack() {
        val star = SavedPlace("g:1", "Davis Food Co-op", 38.5449, -121.7405, address = "620 G St", pinned = true)
        old("vela_saved").edit().putString("places", json.encodeToString(listOf(star))).apply()
        val list = PlaceList("list:1", "Lunch", places = listOf(ListPlace("g:2", "Sam's", 38.5446, -121.7395, note = "Tuesday")))
        old("vela_lists").edit().putString("lists", json.encodeToString(listOf(list))).apply()
        old("vela_shortcuts").edit().putString(ShortcutKind.HOME.name, json.encodeToString(star)).apply()
        val route = SavedRoute("r1", "To work", "DRIVE", 38.54, -121.74, 38.58, -121.49, "Sacramento", "_p~iF~ps|U", 1L)
        old("vela_saved_routes").edit().putString("routes", json.encodeToString(listOf(route))).apply()

        assertEquals(listOf(star), StoresModule.savedPlaceStore(kv).saved())
        assertEquals(listOf(list), StoresModule.placeListStore(kv).lists())
        assertEquals(star, StoresModule.placeShortcutStore(kv).get(ShortcutKind.HOME))
        assertEquals(listOf(route), StoresModule.savedRouteStore(kv).all())
        assertTrue(modes.values.all { it == Context.MODE_PRIVATE })
    }

    @Test fun parkingAndRecentsWrittenTheOldWayReadBack() {
        val spot = ParkedSpot(38.5435, -121.74, 1_690_000_000_000L)
        old("vela_settings").edit()
            .putString("parking_lat", spot.lat.toString())
            .putString("parking_lng", spot.lng.toString())
            .putLong("parking_at", spot.savedAtMillis)
            .putString("parking_history", json.encodeToString(listOf(spot)))
            .apply()
        val parking = StoresModule.parkingStore(kv)
        assertEquals(ParkingStore.Current(spot.lat, spot.lng, spot.savedAtMillis), parking.current())
        assertEquals(listOf(spot), parking.history())

        val recent = RecentPlace(SavedPlace("g:3", "Mishka's", 38.5447, -121.7402), 1_690_000_000_000L)
        old("vela_recent_places").edit().putString("places2", json.encodeToString(listOf(recent))).apply()
        assertEquals(listOf(recent), StoresModule.recentPlaceStore(kv, AndroidClock).recent())
        old("vela_recents").edit().putString("queries", json.encodeToString(listOf("coffee"))).apply()
        assertEquals(listOf("coffee"), StoresModule.recentSearchStore(kv, AndroidClock).recent().map { it.query })
        assertTrue(old("vela_recents").getString("queries2", null)!!.startsWith("""[{"query":"coffee","at":"""))

        // The new code writes what the old one read: strings for the coordinates, a long for the time.
        parking.save(ParkedSpot(38.55, -121.7, 1_700_000_000_000L))
        assertEquals("38.55", old("vela_settings").getString("parking_lat", null))
        assertEquals(1_700_000_000_000L, old("vela_settings").getLong("parking_at", 0L))
    }

    @Test fun placeAndStreetViewFilesWrittenTheOldWayReadBack() {
        val place = Place(id = "g:1", name = "Nick The Greek", location = LatLng(38.5435, -121.74), featureId = "0x1:0x2", rating = 4.7)
        val placeDir = File(root, "files/placecache").apply { mkdirs() }
        val rec = CachedPlace(place, listOf(Review(author = "A", authorPhoto = null, rating = 5, relativeTime = null, text = "Good")), System.currentTimeMillis())
        File(placeDir, PlaceCache.keyOf(place) + ".json").writeText(json.encodeToString(CachedPlace.serializer(), rec))
        val cache = StoresModule.placeCache(files, AndroidClock)
        assertEquals(rec, cache.load(placeDir.path, place))
        assertEquals(placeDir.walkTopDown().filter { it.isFile }.sumOf { it.length() }, cache.dirSizeBytes(placeDir.path))

        val svDir = File(root, "files/svcache").apply { mkdirs() }
        val pano = StreetViewPano(panoId = "abc", lat = 38.5435, lng = -121.74)
        File(svDir, StreetViewCache.keyOf("abc") + ".json").writeText(json.encodeToString(StreetViewPano.serializer(), pano))
        File(svDir, StreetViewCache.keyOf("abc") + ".jpg").writeBytes(byteArrayOf(1, 2, 3))
        val sv = StoresModule.streetViewCache(files)
        assertEquals(pano, sv.loadMeta(svDir.path, "abc"))
        assertArrayEquals(byteArrayOf(1, 2, 3), sv.loadImage(svDir.path, "abc"))
        assertEquals("abc", sv.nearest(svDir.path, LatLng(38.54352, -121.74003))?.panoId)
        sv.clear(svDir.path)
        assertEquals(0, svDir.listFiles()!!.size)
    }

    /** `SharedPreferences` in memory, enough for the stores: apply and commit both land at once. */
    private class MemPrefs : SharedPreferences {
        val map = LinkedHashMap<String, Any?>()
        override fun getAll(): Map<String, *> = map.toMap()
        override fun getString(key: String, defValue: String?): String? = if (key in map) map[key] as String? else defValue
        override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? = throw UnsupportedOperationException()
        override fun getInt(key: String, defValue: Int): Int = if (key in map) map[key] as Int else defValue
        override fun getLong(key: String, defValue: Long): Long = if (key in map) map[key] as Long else defValue
        override fun getFloat(key: String, defValue: Float): Float = if (key in map) map[key] as Float else defValue
        override fun getBoolean(key: String, defValue: Boolean): Boolean = if (key in map) map[key] as Boolean else defValue
        override fun contains(key: String): Boolean = key in map
        override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
        override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
        override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
            val ops = ArrayList<() -> Unit>()
            var clear = false
            fun op(f: () -> Unit) = also { ops += f }
            override fun putString(key: String, value: String?) = op { if (value == null) map.remove(key) else map[key] = value }
            override fun putStringSet(key: String, values: Set<String>?) = throw UnsupportedOperationException()
            override fun putInt(key: String, value: Int) = op { map[key] = value }
            override fun putLong(key: String, value: Long) = op { map[key] = value }
            override fun putFloat(key: String, value: Float) = op { map[key] = value }
            override fun putBoolean(key: String, value: Boolean) = op { map[key] = value }
            override fun remove(key: String) = op { map.remove(key) }
            override fun clear() = also { clear = true }
            override fun commit(): Boolean { apply(); return true }
            override fun apply() { if (clear) map.clear(); ops.forEach { it() } }
        }
    }
}
