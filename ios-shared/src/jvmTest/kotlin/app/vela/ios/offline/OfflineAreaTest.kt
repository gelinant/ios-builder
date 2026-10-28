package app.vela.ios.offline

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OfflineAreaTest {
    @Test fun theFrameSitsInsideTheViewportAtTheAndroidFractions() {
        val bounds = OfflineArea.framedBounds(south = 40.0, west = -10.0, north = 50.0, east = 10.0)
        assertTrue(bounds.south > 40.0 && bounds.south < 50.0)
        assertTrue(bounds.north > bounds.south && bounds.north < 50.0)
        assertEquals(-10.0 + 20.0 * OfflineArea.FRAME_LEFT, bounds.west, 1e-9)
        assertEquals(10.0 - 20.0 * OfflineArea.FRAME_RIGHT, bounds.east, 1e-9)
        // The frame is not centered: the card below takes more of the viewport than the hint above.
        assertTrue(50.0 - bounds.north < bounds.south - 40.0)
    }

    @Test fun theFrameIsVerticalAndNarrowerThanTheViewport() {
        val bounds = OfflineArea.framedBounds(south = -1.0, west = -1.0, north = 1.0, east = 1.0)
        assertTrue(bounds.north > bounds.south)
        assertEquals(-bounds.west, bounds.east, 1e-9)
        assertTrue(bounds.east - bounds.west < 2.0)
    }

    @Test fun oneTileAtZoomZeroAndAMonotoneTileEstimate() {
        val small = OfflineAreaBounds(43.72, 7.40, 43.73, 7.41)
        assertEquals(1, OfflineArea.tileCount(small, 0))
        val detail = OfflineArea.tiles(small, minZoom = 14.0)
        assertTrue(detail >= 1)
        val city = OfflineAreaBounds(43.70, 7.38, 43.78, 7.46)
        assertTrue(OfflineArea.tiles(city, minZoom = 12.0) > detail)
        assertTrue(OfflineArea.tileEstimateMb(600) >= 1)
        assertEquals(1, OfflineArea.tileEstimateMb(0))
    }

    @Test fun placesOffDropsThePackAndThePlaceArchives() {
        val assets = listOf(
            asset("monaco", OfflineStore.KIND_PACK),
            asset("monaco", OfflineStore.KIND_PLACES),
            asset("monaco", OfflineStore.KIND_BASEMAP),
            asset("map-fonts", OfflineStore.KIND_GLYPHS),
            asset("world", OfflineStore.KIND_BASEMAP),
        )
        val kept = OfflineArea.applyPreferences(
            assets, OfflineAreaPreferences(places = false, cameras = true, addresses = true))
        assertEquals(
            listOf(OfflineStore.KIND_BASEMAP, OfflineStore.KIND_GLYPHS, OfflineStore.KIND_BASEMAP),
            kept.map { it.kind })
        assertEquals(assets, OfflineArea.applyPreferences(assets, OfflineAreaPreferences()))
    }

    @Test fun cameraAndAddressExtrasFollowThePreferences() {
        assertEquals(
            listOf(OfflineStore.KIND_CAMERAS, OfflineStore.KIND_ADDRESSES),
            OfflineArea.extras(OfflineAreaPreferences()))
        assertEquals(
            listOf(OfflineStore.KIND_ADDRESSES),
            OfflineArea.extras(OfflineAreaPreferences(cameras = false)))
        assertEquals(emptyList(), OfflineArea.extras(OfflineAreaPreferences(false, false, false)))
    }

    @Test fun aFullVolumeRefusesTheDownloadBeforeAnyFileIsWritten() {
        val needed = 40L * 1024 * 1024
        assertEquals(
            OfflineAreaGate.NO_SPACE,
            OfflineAreaGate.reason(freeBytes = needed, neededBytes = needed, installed = false, extrasRequested = true))
        assertEquals(
            OfflineAreaGate.READY,
            OfflineAreaGate.reason(
                freeBytes = needed + OfflineStorage.MARGIN_BYTES, neededBytes = needed,
                installed = false, extrasRequested = true))
    }

    @Test fun anInstalledRegionIsOnlyOfferedAgainForItsExtras() {
        assertEquals(
            OfflineAreaGate.INSTALLED,
            OfflineAreaGate.reason(1_000_000_000, 0, installed = true, extrasRequested = false))
        assertEquals(
            OfflineAreaGate.READY,
            OfflineAreaGate.reason(1_000_000_000, 0, installed = true, extrasRequested = true))
        assertEquals(
            OfflineAreaGate.READY,
            OfflineAreaGate.reason(1_000_000_000, 0, installed = false, extrasRequested = false))
    }

    @Test fun theAddressBoxIsPaddedToAboutTenKilometersAndRefusedWhenHuge() {
        val frame = OfflineAreaBounds(43.73, 7.42, 43.74, 7.43)
        val padded = assertNotNull(OfflineArea.addressBounds(frame))
        assertTrue(padded.south < frame.south && padded.north > frame.north)
        assertTrue(padded.east - padded.west >= OfflineArea.GEOCODE_PAD_DEG - 1e-9)
        assertNull(OfflineArea.addressBounds(OfflineAreaBounds(30.0, -120.0, 40.0, -110.0)))
    }

    @Test fun theEstimateUsesTheArchiveDensityButStaysInItsBand() {
        assertEquals(110.0, OfflineArea.kbPerTile(null, 0), 1e-9)
        assertEquals(10.0, OfflineArea.kbPerTile(1, 1_000_000), 1e-9)
        assertEquals(170.0, OfflineArea.kbPerTile(1_000_000, 1), 1e-9)
        assertTrue(OfflineArea.kbPerTile(50, 1000) > 10.0)
    }

    @Test fun areaPreferencesDefaultToEverythingAndKeepTheAndroidPlacesKey() {
        assertEquals(true, OfflineAreaPreferences().places)
        assertEquals(true, OfflineAreaPreferences().cameras)
        assertEquals(true, OfflineAreaPreferences().addresses)
        assertEquals("offline_places_with_downloads", OfflineAreaPreferences.KEY_PLACES)
        assertFalse(OfflineAreaPreferences(places = false).places)
    }

    private fun asset(id: String, kind: String) = OfflineAssetPlan(
        id = id, kind = kind, url = "https://example.invalid/$id", targetPath = "/data/$id",
        sizeMb = 1,
    )
}
