package app.vela.ios.layers

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * TREES-LAYER: the Overpass tree parser, the crown rule, the z17 gate, the per-screen cap and the
 * 30 minute tile cache. No network and no map are needed.
 */
class TreesTest {
    private val south = 37.7690
    private val west = -122.4870
    private val north = 37.7710
    private val east = -122.4840

    private val captured = """
        {"elements":[
          {"type":"node","lat":37.7701,"lon":-122.4855,"tags":{"natural":"tree","height":"12 m"}},
          {"type":"node","lat":37.7702,"lon":-122.4856,"tags":{"natural":"tree","diameter_crown":"14"}},
          {"type":"node","lat":37.7703,"lon":-122.4857,"tags":{"natural":"tree","diameter_crown":"6,5","height":"20"}},
          {"type":"node","lat":37.7704,"lon":-122.4858,"tags":{"natural":"tree"}},
          {"type":"node","lon":-122.4859,"tags":{"natural":"tree"}},
          {"type":"node","lat":91.0,"lon":-122.4860,"tags":{"natural":"tree"}}
        ]}
    """.trimIndent().encodeToByteArray()

    @Test
    fun parserReadsCoordinatesTagsAndCrowns() {
        val trees = Trees.parse(captured)
        assertEquals(4, trees.size)

        val fromHeight = trees[0]
        assertEquals(37.7701, fromHeight.lat)
        assertEquals(12.0, fromHeight.heightM)
        // Height alone gives the documented half-height estimate, not a fabricated crown tag.
        assertEquals(6.0, fromHeight.crownM)

        assertEquals(14.0, trees[1].crownM)
        // A tagged crown wins over height, and a decimal comma is accepted.
        assertEquals(6.5, trees[2].crownM)
        // No tag means no invented size; the renderer keeps its neutral disc.
        assertEquals(0.0, trees[3].crownM)
        assertEquals(0.0, trees[3].heightM)
    }

    @Test
    fun badBodyIsAnEmptyAnswerNotACrash() {
        assertEquals(0, Trees.parse("{not json".encodeToByteArray()).size)
        assertEquals(0, Trees.parse("{\"elements\":[]}".encodeToByteArray()).size)
    }

    @Test
    fun zoomGateHidesEveryTreeBelow17() {
        assertFalse(Trees.visible(16.9))
        assertFalse(Trees.visible(0.0))
        assertTrue(Trees.visible(17.0))
        assertTrue(Trees.visible(19.5))

        val many = List(300) { TreePoint(37.7700, -122.4850) }
        assertEquals(
            0,
            Trees.limit(many, south, west, north, east, 16.99).size,
            "no individual tree below the gate, whatever the caller passes",
        )
        assertTrue(Trees.limit(many, south, west, north, east, 17.0).isNotEmpty())
    }

    @Test
    fun capKeepsTheNearestTreesOnly() {
        // A wide box at z18 has room for the absolute ceiling, so 700 candidates become 500.
        val wideSouth = 37.70
        val wideNorth = 37.80
        val wideWest = -122.55
        val wideEast = -122.40
        val centerLat = (wideSouth + wideNorth) / 2
        val centerLng = (wideWest + wideEast) / 2
        val points = List(700) { index ->
            // Half the trees sit far away, half around the center: the cap must prefer the center.
            val offset = if (index < 350) 0.045 + index * 0.000001
            else 0.001 * (index - 350) / 349.0
            TreePoint(centerLat + offset, centerLng + offset)
        }
        val kept = Trees.limit(points, wideSouth, wideWest, wideNorth, wideEast, 18.0)
        assertEquals(Trees.CAP, kept.size)
        assertEquals(350, kept.count { it.lat < centerLat + 0.01 })
    }

    @Test
    fun aSmallViewGetsTheDensityFloorNotTheAbsoluteCap() {
        val points = List(300) { index ->
            TreePoint(37.7700 + index * 0.000001, -122.4850)
        }
        val kept = Trees.limit(points, south, west, north, east, 17.0)
        assertEquals(Trees.MIN_PER_SCREEN, kept.size)
    }

    @Test
    fun cacheIsFreshForThirtyMinutesInTheSameTileBox() {
        val box = Trees.boxFor(37.7700, -122.4850)
        val cache = TreeCache()
        val trees = listOf(TreePoint(box.centerLat, box.centerLng, 12.0, 6.0))
        val now = 1_700_000_000_000L

        cache.put(box, trees, now)
        assertNotNull(cache.get(box.south, box.west, box.north, box.east, now + 29 * 60 * 1000))
        assertNull(
            cache.get(box.south, box.west, box.north, box.east, now + 31 * 60 * 1000),
            "a 30 minute answer must not draw after half an hour",
        )
        assertEquals(0, cache.size, "the expired entry is dropped")
    }

    @Test
    fun cacheDoesNotAnswerOutsideItsBox() {
        val box = Trees.boxFor(37.7700, -122.4850)
        val cache = TreeCache()
        cache.put(box, listOf(TreePoint(box.centerLat, box.centerLng)), 1000L)
        assertNull(
            cache.get(box.south - 0.01, box.west, box.north, box.east, 2000L),
            "a view that left the cached box must request again",
        )
    }

    @Test
    fun cacheIsKeyedByTileSizedBox() {
        val here = Trees.boxFor(37.7700, -122.4850)
        val next = Trees.boxFor(37.7700, -122.4000)
        assertFalse(here.contains(next.south, next.west, next.north, next.east))
        assertEquals(Trees.TILE_ZOOM, Trees.tileKey(37.7700, -122.4850).split("/")[0].toInt())
        assertTrue(here.contains(37.7699, -122.4851, 37.7701, -122.4849))
    }

    @Test
    fun tileBoxAtHighLatitudeStaysInsideTheWorld() {
        val box = Trees.boxFor(84.0, 179.9)
        assertTrue(box.north <= 85.05112878)
        assertTrue(box.east <= 180.0)
        assertTrue(box.south < box.north)
        assertTrue(box.west < box.east)
    }

    @Test
    fun fixtureIsDeterministicAndCarriesTaggedCrowns() {
        val box = Trees.boxFor(37.7700, -122.4850)
        val first = Trees.fixture(box)
        val second = Trees.fixture(box)
        assertEquals(8, first.size)
        assertEquals(first, second)
        assertTrue(first.any { it.crownM > 10.0 })
        assertTrue(first.any { it.crownM == 0.0 }, "one untagged tree proves the neutral disc")
    }

    @Test
    fun emptyAnswerIsAValidCacheableResult() {
        val box = Trees.boxFor(37.7700, -122.4850)
        val cache = TreeCache()
        cache.put(box, emptyList(), 0L)
        assertEquals(emptyList(), cache.get(box.south, box.west, box.north, box.east, 1000L))
    }
}
