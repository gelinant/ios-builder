package app.vela.ios.streetview

import app.vela.core.model.StreetViewLink
import app.vela.core.model.StreetViewPano

/**
 * Metadata for the CI renderer fixture. Google's datacenter-facing runner may answer "no imagery"
 * for a Davis address (the same limit the place scenarios hit), so the UI scenario still exercises
 * drag, zoom, the compass and the walk arrows against a synthetic equirectangular image drawn by
 * the Swift side. It is not a real panorama and never appears unless the debug launch argument
 * `-VelaStreetViewFixture YES` asks for it.
 */
object StreetViewFixture {
    const val PANO_ID = "vela-fixture-pano-0001"

    fun pano(): StreetViewPano = StreetViewPano(
        panoId = PANO_ID,
        lat = 38.5449,
        lng = -121.7405,
        headingDeg = 0.0,
        initialFacingDeg = 0.0,
        tileSize = 512,
        maxZoom = 3,
        levelDims = listOf(512 to 256, 1024 to 512, 2048 to 1024),
        addressLabel = "Vela Street View fixture",
        copyright = "© Vela fixture",
        captureYear = 2026,
        captureMonth = 10,
        neighbors = listOf(
            StreetViewLink("vela-fixture-pano-0002", 38.5450, -121.7405, 0.0, 10.0),
        ),
    )
}
