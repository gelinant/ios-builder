package app.vela.ios.streetview

import app.vela.core.model.StreetViewLink
import app.vela.core.model.StreetViewPano
import app.vela.core.model.StreetViewTime

/**
 * Metadata for the CI renderer fixture. Google's datacenter-facing runner may answer "no imagery"
 * for a Davis address (the same limit the place scenarios hit), so the UI scenario still exercises
 * drag, zoom, the compass and the walk arrows against a synthetic equirectangular image drawn by
 * the Swift side. It is not a real panorama and never appears unless the debug launch argument
 * `-VelaStreetViewFixture YES` asks for it.
 */
object StreetViewFixture {
    const val PANO_ID = "vela-fixture-pano-0001"
    const val HISTORY_2023 = "vela-fixture-pano-2023"
    const val HISTORY_2018 = "vela-fixture-pano-2018"

    /** Newest first, as Google lists a spot's captures. */
    val history: List<StreetViewTime> = listOf(
        StreetViewTime(PANO_ID, 2026, 10),
        StreetViewTime(HISTORY_2023, 2023, 6),
        StreetViewTime(HISTORY_2018, 2018, 4),
    )

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
        history = history,
    )

    /**
     * The fixture stand-in for an older capture. It keeps the synthetic texture (the fixture
     * renderer draws the same image for any pano id) but carries the picked date and the view
     * direction the user had, so the UI scenario can prove the history switch and the heading.
     */
    fun historical(time: StreetViewTime, faceBearingDeg: Double): StreetViewPano = pano().copy(
        panoId = time.panoId,
        captureYear = time.year,
        captureMonth = time.month,
        initialFacingDeg = faceBearingDeg,
    )
}
