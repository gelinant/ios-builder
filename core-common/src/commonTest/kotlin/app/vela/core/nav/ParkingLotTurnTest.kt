package app.vela.core.nav

import app.vela.core.data.naming.RoadNameTiles
import app.vela.core.i18n.NavStringsRegistry
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.Route
import app.vela.core.model.RouteLeg
import app.vela.core.util.toRadians
import kotlinx.coroutines.test.runTest
import kotlin.math.cos
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The last turn into a destination's parking lot: the map's own `service=parking_aisle` is the only
 * source, so the check runs on synthetic road lines instead of invented lot data.
 */
class ParkingLotTurnTest {
    private val lat = 38.5449
    private val lng0 = -121.7405
    private val mPerDegLng = 111_320.0 * cos(lat.toRadians())
    private var previousRoads: List<RoadNameTiles.RoadLine>? = null
    private var previousFetch: (suspend (Int, Int, Int) -> ByteArray?)? = null

    private fun pt(e: Double, n: Double) = LatLng(lat + n / 111_320.0, lng0 + e / mPerDegLng)

    @AfterTest fun reset() {
        RoadNameTiles.testRoads = previousRoads
        RoadNameTiles.fetch = previousFetch
        NavStringsRegistry.setLanguage("en", "US")
    }

    private fun install(roads: List<RoadNameTiles.RoadLine>?) {
        previousRoads = RoadNameTiles.testRoads
        previousFetch = RoadNameTiles.fetch
        RoadNameTiles.testRoads = roads
    }

    /** East 1500 m, a left turn onto [road] (null: no name), then north 500 m to an arrival. */
    private fun route(road: String? = null): Route {
        val poly = (0..150).map { pt(it * 10.0, 0.0) } + (1..30).map { pt(1500.0, it * 10.0) }
        val text = if (road != null) "Turn left onto $road" else "Turn left"
        val ms = listOf(
            Maneuver(ManeuverType.DEPART, "Head east", poly.first(), 1500.0, 150.0),
            Maneuver(ManeuverType.TURN_LEFT, text, pt(1500.0, 0.0), 300.0, 30.0, road = road, instructionNoRoad = "Turn left"),
            Maneuver(ManeuverType.ARRIVE, "Arrive", poly.last(), 0.0, 0.0),
        )
        return Route(poly, listOf(RouteLeg(1800.0, 180.0, null, ms)), 1800.0, 180.0, null)
    }

    /** The road the drive takes north after the turn, as the tiles would tag it. */
    private fun aisles(cls: String = "service", service: String? = "parking_aisle"): List<RoadNameTiles.RoadLine> =
        listOf(RoadNameTiles.RoadLine(cls, service, (0..30).map { pt(1500.0, it * 10.0) }))

    @Test fun `the turn off the street into the destination lot is worded as one`() = runTest {
        install(aisles())
        val r = route()
        val turnM = RouteProjection.cumulative(r.polyline)[150]
        assertTrue(ParkingLotTurn.entersLot(r, turnM, 1800.0), "the aisle was not read as a lot")
        val worded = ParkingLotTurn.wordDestination(r) { left ->
            NavStringsRegistry.current().intoLot(left)
        }
        val turn = worded.maneuvers[1]
        assertEquals("Turn left into the parking lot", turn.instruction)
        assertEquals("Turn left into the parking lot", turn.instructionNoRoad)
        assertEquals("Head east", worded.maneuvers[0].instruction, "another step was reworded")
        assertEquals("Arrive", worded.maneuvers[2].instruction)
        assertTrue(worded.made.contains("lotTurn"), "the route did not record the lot turn: ${worded.made}")
    }

    @Test fun `a street or an alley is never a parking lot`() = runTest {
        val r = route()
        val turnM = RouteProjection.cumulative(r.polyline)[150]
        install(aisles(cls = "street", service = null))
        assertFalse(ParkingLotTurn.entersLot(r, turnM, 1800.0), "a street was read as a lot")
        install(aisles(cls = "service", service = "alley"))
        assertFalse(ParkingLotTurn.entersLot(r, turnM, 1800.0), "an alley was read as a lot")
        install(aisles(cls = "service", service = "driveway"))
        assertFalse(ParkingLotTurn.entersLot(r, turnM, 1800.0), "a driveway alone was read as a lot")
        install(null)
        assertFalse(ParkingLotTurn.entersLot(r, turnM, 1800.0), "unreadable tiles claimed a lot")
    }

    @Test fun `a named turn keeps its plain words even beside an aisle`() = runTest {
        install(aisles())
        val named = route(road = "F Street")
        assertEquals(named, ParkingLotTurn.wordDestination(named) { "Turn left into the parking lot" })
    }

    @Test fun `a route with no turn before the end is left alone`() = runTest {
        install(aisles())
        val straight = Route(
            polyline = (0..100).map { pt(it * 10.0, 0.0) },
            legs = listOf(RouteLeg(
                1000.0, 100.0, null,
                listOf(
                    Maneuver(ManeuverType.DEPART, "Head east", pt(0.0, 0.0), 1000.0, 100.0),
                    Maneuver(ManeuverType.ARRIVE, "Arrive", pt(1000.0, 0.0), 0.0, 0.0),
                ),
            )),
            distanceMeters = 1000.0,
            durationSeconds = 100.0,
            durationInTrafficSeconds = null,
        )
        assertEquals(straight, ParkingLotTurn.wordDestination(straight) { "Turn left into the parking lot" })
    }
}
