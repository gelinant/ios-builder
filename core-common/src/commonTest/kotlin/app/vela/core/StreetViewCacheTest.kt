package app.vela.core

import app.vela.core.data.StreetViewCache
import app.vela.core.model.LatLng
import app.vela.core.model.StreetViewPano
import app.vela.core.platform.MemFiles
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class StreetViewCacheTest {
    private val cache = StreetViewCache(MemFiles())
    private val dir = "/data/files/svcache"

    private fun pano(id: String, lat: Double, lng: Double) = StreetViewPano(panoId = id, lat = lat, lng = lng)

    @Test
    fun `a stored pano comes back by id and by position and clear removes it`() {
        cache.saveMeta(dir, pano("abc", 38.5435, -121.7400))
        cache.saveImage(dir, "abc", byteArrayOf(1, 2, 3))
        assertEquals("abc", cache.loadMeta(dir, "abc")?.panoId)
        assertEquals("abc", cache.nearest(dir, LatLng(38.54355, -121.74005))?.panoId)
        assertNull(cache.nearest(dir, LatLng(38.56, -121.70)))
        cache.clear(dir)
        assertNull(cache.loadMeta(dir, "abc"))
    }

    @Test
    fun `a tile is saved and loaded under its own key and cleared with the cache`() {
        val key = "panoAAA-3-1-2"
        cache.saveTile(dir, key, byteArrayOf(7, 8, 9))
        assertEquals(byteArrayOf(7, 8, 9).toList(), cache.loadTile(dir, key)?.toList())
        assertEquals("$dir/panoAAA-3-1-2.jpg", cache.tileFile(dir, key))
        assertNull(cache.loadTile(dir, "other-0-0-0"))
        cache.saveImage(dir, "abc", byteArrayOf(1))
        cache.saveMeta(dir, pano("abc", 38.5435, -121.7400))
        cache.clear(dir)
        assertNull(cache.loadTile(dir, key))
    }

    @Test
    fun `metadata with no image is not offered`() {
        cache.saveMeta(dir, pano("noimg", 38.5435, -121.7400))
        assertNull(cache.nearest(dir, LatLng(38.5435, -121.7400)))
    }
}
