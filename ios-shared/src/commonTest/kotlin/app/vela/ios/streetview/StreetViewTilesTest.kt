package app.vela.ios.streetview

import app.vela.core.model.StreetViewPano
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The tile grid, URL, cache key and visible selection, against the same shapes Android uses. */
class StreetViewTilesTest {
    private fun pano(
        tileSize: Int = 512,
        dims: List<Pair<Int, Int>> = emptyList(),
        heading: Double = 0.0,
    ) = StreetViewPano(
        panoId = "panoAAAAAAAAAAAAAAAAAA", lat = 38.5449, lng = -121.7405,
        headingDeg = heading, tileSize = tileSize, maxZoom = 6, levelDims = dims,
    )

    @Test
    fun `the tile URL is the keyless consumer template`() {
        assertEquals(
            "https://streetviewpixels-pa.googleapis.com/v1/tile" +
                "?cb_client=maps_sv.tactile&panoid=panoAAAAAAAAAAAAAAAAAA&x=3&y=2&zoom=4&nbt=1&fover=2",
            StreetViewTiles.url("panoAAAAAAAAAAAAAAAAAA", 3, 2, 4),
        )
    }

    @Test
    fun `a cache key keeps the pano id readable and path safe`() {
        assertEquals("panoAAA-3-1-2", StreetViewTiles.cacheKey("panoAAA", 3, 1, 2))
        assertEquals("pano_key-0-0-0", StreetViewTiles.cacheKey("pano/key", 0, 0, 0))
    }

    @Test
    fun `the modern default pyramid is 512 times two to the zoom`() {
        val base = StreetViewTiles.baseLevel(pano())
        val detail = StreetViewTiles.detailLevel(pano())
        assertEquals(1, base.zoom)
        assertEquals(1024, base.width)
        assertEquals(2, base.columns)
        assertEquals(1, base.rows)
        // The detail level stays at or below 4096 wide: 32 tiles for a full sphere.
        assertEquals(3, detail.zoom)
        assertEquals(4096, detail.width)
        assertEquals(2048, detail.height)
        assertEquals(8, detail.columns)
        assertEquals(4, detail.rows)
    }

    @Test
    fun `an old 416 pyramid sizes the grid from its own levels`() {
        val old = pano(
            tileSize = 416,
            dims = listOf(416 to 208, 832 to 416, 1664 to 832, 3328 to 1664),
        )
        val base = StreetViewTiles.baseLevel(old)
        val detail = StreetViewTiles.detailLevel(old)
        assertEquals(1, base.zoom)
        assertEquals(832, base.width)
        assertEquals(2, base.columns)
        assertEquals(1, base.rows)
        assertEquals(3, detail.zoom)
        assertEquals(3328, detail.width)
        assertEquals(8, detail.columns)
        assertEquals(4, detail.rows)
    }

    @Test
    fun `compass bearings and renderer yaw follow Google's texture frame`() {
        assertEquals(0.0, StreetViewTiles.yawForCompass(120.0, 30.0), 0.0001)
        assertEquals(120.0, StreetViewTiles.compassForYaw(0.0, 30.0), 0.0001)
        assertEquals(270.0, StreetViewTiles.yawForCompass(0.0, 0.0), 0.0001)
        assertEquals(0.0, StreetViewTiles.yawForCompass(90.0, 0.0), 0.0001)
    }

    @Test
    fun `visible tiles cover the view and wrap at the seam`() {
        val level = StreetViewTiles.detailLevel(pano())
        val front = StreetViewTiles.visibleTiles(level, yawDeg = 0.0, fovXDeg = 75.0,
            pitchDeg = 0.0, aspect = 1.0, margin = 0)
        assertEquals(listOf(5 to 1, 5 to 2, 6 to 1, 6 to 2), front.map { it.x to it.y })

        val west = StreetViewTiles.visibleTiles(level, yawDeg = 350.0, fovXDeg = 75.0,
            pitchDeg = 0.0, aspect = 1.0, margin = 0)
        assertTrue(west.all { it.x in 0 until level.columns && it.y in 0 until level.rows })
        assertEquals(west.size, west.distinct().size)

        val wider = StreetViewTiles.visibleTiles(level, yawDeg = 0.0, fovXDeg = 75.0,
            pitchDeg = 0.0, aspect = 1.0, margin = 1)
        assertTrue(wider.size > front.size)
    }

    @Test
    fun `the vertical limit clamps rows at the poles`() {
        val level = StreetViewTiles.detailLevel(pano())
        val up = StreetViewTiles.visibleTiles(level, yawDeg = 0.0, fovXDeg = 110.0,
            pitchDeg = 85.0, aspect = 0.5, margin = 0)
        assertTrue(up.all { it.y in 0 until level.rows })
        assertTrue(up.any { it.y == 0 })
    }
}
