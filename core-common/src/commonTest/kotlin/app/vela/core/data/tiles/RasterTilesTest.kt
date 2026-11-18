package app.vela.core.data.tiles

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The raster URLs Android and iOS both load, pinned byte for byte. */
class RasterTilesTest {
    @Test fun trafficTemplateMatchesTheAndroidString() {
        assertEquals(
            "https://www.google.com/maps/vt/pb=!1m4!1m3!1i{z}!2i{x}!3i{y}!2m9!1e2!2straffic!3i999999" +
                "!4m2!1sincidents!2s1!4m2!1sincidents_text!2s1!3m8!2sen!3sus!5e1105!12m4!1e68!2m2!1sset!2sRoadmap!4e0!5m1!1e0",
            RasterTiles.TRAFFIC_URL)
    }

    @Test fun satelliteTemplatesKeepTheirAxisOrder() {
        assertEquals(
            "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
            RasterTiles.SATELLITE_URL)
        assertEquals("https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}", RasterTiles.SATELLITE_DEEP_URL)
    }

    @Test fun trafficTileUsesZThenXThenY() {
        assertEquals(
            "https://www.google.com/maps/vt/pb=!1m4!1m3!1i12!2i656!3i1583!2m9!1e2!2straffic!3i999999" +
                "!4m2!1sincidents!2s1!4m2!1sincidents_text!2s1!3m8!2sen!3sus!5e1105!12m4!1e68!2m2!1sset!2sRoadmap!4e0!5m1!1e0",
            RasterTiles.trafficTile(x = 656, y = 1583, z = 12))
    }

    @Test fun satelliteTileUsesGoogleStylePathAndXYZParams() {
        assertEquals(
            "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/12/1583/656",
            RasterTiles.satelliteTile(x = 656, y = 1583, z = 12))
        assertEquals(
            "https://mt1.google.com/vt/lyrs=s&x=656&y=1583&z=20",
            RasterTiles.satelliteDeepTile(x = 656, y = 1583, z = 20))
    }

    @Test fun zoomLimitsMatchAndroid() {
        assertEquals(16, RasterTiles.TRAFFIC_MAX_ZOOM)
        assertEquals(19, RasterTiles.SATELLITE_MAX_ZOOM)
        assertEquals(21, RasterTiles.SATELLITE_DEEP_MAX_ZOOM)
        assertTrue(RasterTiles.SATELLITE_DEEP_MIN_ZOOM < RasterTiles.SATELLITE_MAX_ZOOM)
    }
}
