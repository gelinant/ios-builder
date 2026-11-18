package app.vela.ios.offline

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OfflineUpdatesTest {
    @Test fun aDeltaIsChosenOnlyForItsOwnFromRevision() {
        assertEquals(OfflineUpdates.Mode.DELTA, OfflineUpdates.decide(3, 4, 3, "https://x/p"))
        assertEquals(OfflineUpdates.Mode.FULL, OfflineUpdates.decide(2, 4, 3, "https://x/p"))
        assertEquals(OfflineUpdates.Mode.FULL, OfflineUpdates.decide(3, 4, 3, null))
        assertEquals(OfflineUpdates.Mode.NONE, OfflineUpdates.decide(4, 4, 3, "https://x/p"))
        assertEquals(OfflineUpdates.Mode.NONE, OfflineUpdates.decide(5, 4, 3, "https://x/p"))
    }

    @Test fun aRevisionGapFallsBackToTheWholeDownload() {
        assertNull(OfflineUpdates.deltaUrl(1, app.vela.core.offline.RoutingRegion(
            id = "monaco", name = "Monaco", url = "https://x/full", sizeMb = 5,
            s = 43.7, w = 7.4, n = 43.8, e = 7.5, rev = 4,
            deltaUrl = "https://x/delta", deltaFromRev = 3)))
        assertEquals("https://x/delta", OfflineUpdates.deltaUrl(3, app.vela.core.offline.RoutingRegion(
            id = "monaco", name = "Monaco", url = "https://x/full", sizeMb = 5,
            s = 43.7, w = 7.4, n = 43.8, e = 7.5, rev = 4,
            deltaUrl = "https://x/delta", deltaFromRev = 3)))
    }

    @Test fun freeSpaceNeedsThePiecesAndTheMargin() {
        val assets = listOf(
            OfflineAssetPlan("monaco", OfflineStore.KIND_PLACES, "https://x/p", "/p", sizeMb = 10),
            OfflineAssetPlan("monaco", OfflineStore.KIND_BASEMAP, "https://x/m", "/m", sizeMb = 20),
        )
        val needed = OfflineStorage.neededBytes(assets)
        assertEquals(30L * 1024 * 1024, needed)
        assertTrue(OfflineStorage.fits(needed + OfflineStorage.MARGIN_BYTES, needed))
        assertFalse(OfflineStorage.fits(needed + OfflineStorage.MARGIN_BYTES - 1, needed))
        assertTrue(OfflineStorage.fits(0, needed), "an unknown volume size never blocks a download")
    }

    @Test fun theWorldArchiveIsAFloorOnlyWhileOffline() {
        assertEquals("/data/world.pmtiles", OfflineStore.worldFallbackPath("/data/world.pmtiles", true))
        assertNull(OfflineStore.worldFallbackPath("/data/world.pmtiles", false))
        assertNull(OfflineStore.worldFallbackPath(null, true))
    }

    @Test fun revisionsRoundTripAndReportAMissingPieceAsZero() {
        val revisions = InstalledRevisions()
            .with(OfflineStore.KIND_PACK, "monaco", 7)
            .with(OfflineStore.KIND_PLACES, "monaco", 8)
        assertEquals(7, revisions.get(OfflineStore.KIND_PACK, "monaco"))
        assertEquals(0, revisions.get(OfflineStore.KIND_BASEMAP, "monaco"))
        assertEquals(0, revisions.without(OfflineStore.KIND_PACK, "monaco")
            .get(OfflineStore.KIND_PACK, "monaco"))
    }

    @Test fun categoryBytesComeFromTheRegionsOwnPieces() {
        val row = OfflineRegionBytes("monaco", packBytes = 10, placesBytes = 20, basemapBytes = 30)
        assertEquals(10, OfflineStorage.categoryBytes(row, OfflineStore.KIND_PACK))
        assertEquals(20, OfflineStorage.categoryBytes(row, OfflineStore.KIND_PLACES))
        assertEquals(30, OfflineStorage.categoryBytes(row, OfflineStore.KIND_BASEMAP))
        assertEquals(0, OfflineStorage.categoryBytes(row, OfflineStore.KIND_GLYPHS))
    }
}
