package app.vela.core

import app.vela.core.data.PlaceCache
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.platform.MemFiles
import app.vela.core.platform.TestClock
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PlaceCacheTest {
    private val clock = TestClock()
    private val files = MemFiles(clock)
    private val cache = PlaceCache(files, clock) { it.orEmpty().lowercase() }
    private val dir = "/data/files/placecache"

    private val online = Place(id = "g:1", name = "Nick The Greek", location = LatLng(38.5435, -121.7400), featureId = "0x1:0x2", rating = 4.7)

    @Test
    fun `an offline result finds the copy saved online by name and position`() {
        cache.save(dir, online, emptyList())
        val offline = Place(id = "overture:abc", name = "Nick the Greek", location = LatLng(38.54352, -121.74003))
        assertEquals(4.7, cache.load(dir, offline)?.place?.rating)
    }

    @Test
    fun `the same name across town is another place`() {
        cache.save(dir, online, emptyList())
        assertNull(cache.load(dir, Place(id = "overture:zzz", name = "Nick The Greek", location = LatLng(38.56, -121.70))))
    }

    @Test
    fun `a copy past its age is a miss and trim drops it`() {
        cache.save(dir, online, emptyList())
        clock.now += PlaceCache.MAX_AGE_MS + 1
        assertNull(cache.load(dir, online))
        cache.trim(dir)
        assertEquals(emptyList(), files.list(dir))
    }
}
