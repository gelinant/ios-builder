package app.vela.core.nav

import app.vela.core.model.Lane
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.TrafficSpan
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The navigation route's drawn pieces ([RouteRender]): the gray cut at the car, the congestion
 * levels on the road still ahead, the two arrows selected for the banner's maneuvers, and the
 * lane row's approach gate.
 */
class RouteRenderTest {

    // A northbound line about 1.1 km long, so distances along it are easy to read.
    private val line = listOf(
        LatLng(37.0, -122.0),
        LatLng(37.01, -122.0),
    )

    private fun maneuver(type: ManeuverType, lat: Double, lng: Double): Maneuver = Maneuver(
        type = type,
        instruction = type.name,
        location = LatLng(lat, lng),
        distanceMeters = 100.0,
        durationSeconds = 10.0,
    )

    @Test
    fun traveledPartIsGrayAndTheRestKeepsFreeFlow() {
        val pieces = RouteRender.segments(line, traveledM = 400.0, spans = emptyList())
        assertEquals(listOf(-1, 0), pieces.map { it.level })
        assertTrue(abs(pieces[0].points.last().lat - (37.0 + 400.0 / 111_320.0)) < 0.0001,
            "the gray did not end where the car is: ${pieces[0].points.last()}")
        assertEquals(pieces[0].points.last(), pieces[1].points.first(),
            "the two pieces do not share the cut point")
        assertEquals(line.last(), pieces.last().points.last())
    }

    @Test
    fun congestionColorsOnlyTheRemainingStretches() {
        val pieces = RouteRender.segments(
            line, traveledM = 0.0, spans = listOf(TrafficSpan(level = 2, startMeters = 300.0, lengthMeters = 300.0)))
        assertEquals(listOf(0, 2, 0), pieces.map { it.level })
        assertTrue(pieces[1].points.size >= 2)
    }

    @Test
    fun theDrivenPartStaysGrayInsideAListedJam() {
        val pieces = RouteRender.segments(
            line, traveledM = 400.0, spans = listOf(TrafficSpan(level = 3, startMeters = 200.0, lengthMeters = 400.0)))
        assertEquals(listOf(-1, 3, 0), pieces.map { it.level })
        assertTrue(abs(pieces[0].points.last().lat - (37.0 + 400.0 / 111_320.0)) < 0.0001,
            "the gray cut was clamped to the span boundary instead of the car")
    }

    @Test
    fun overlappingSpansKeepTheWorstLevel() {
        val pieces = RouteRender.segments(
            line, traveledM = 0.0,
            spans = listOf(
                TrafficSpan(level = 1, startMeters = 100.0, lengthMeters = 400.0),
                TrafficSpan(level = 2, startMeters = 300.0, lengthMeters = 300.0),
            ))
        assertEquals(listOf(0, 1, 2, 0), pieces.map { it.level })
    }

    @Test
    fun roadAheadStartsWithTheBannersManeuver() {
        val maneuvers = listOf(
            maneuver(ManeuverType.DEPART, 37.0, -122.0),
            maneuver(ManeuverType.TURN_LEFT, 37.003, -122.0),
            maneuver(ManeuverType.TURN_RIGHT, 37.007, -122.0),
            maneuver(ManeuverType.ARRIVE, 37.01, -122.0),
        )
        val arrows = RouteRender.aheadArrows(line, maneuvers, stepIndex = 1)
        assertEquals(2, arrows.size)
        assertEquals("TURN_LEFT", arrows[0].kind)
        assertEquals("next", arrows[0].role)
        assertEquals("TURN_RIGHT", arrows[1].kind)
        assertEquals("then", arrows[1].role)
        assertEquals(37.003, arrows[0].location.lat)
    }

    @Test
    fun roadAheadSkipsTheDepartureAndSkipsADuplicatePoint() {
        val maneuvers = listOf(
            maneuver(ManeuverType.DEPART, 37.0, -122.0),
            maneuver(ManeuverType.TURN_LEFT, 37.004, -122.0),
            maneuver(ManeuverType.TURN_RIGHT, 37.004, -122.0),
            maneuver(ManeuverType.MERGE, 37.008, -122.0),
        )
        val arrows = RouteRender.aheadArrows(line, maneuvers, stepIndex = 0)
        assertEquals(listOf("TURN_LEFT", "MERGE"), arrows.map { it.kind })
    }

    @Test
    fun roadAheadEndsAtTheLastManeuverAndHonoursTheLimit() {
        val maneuvers = listOf(
            maneuver(ManeuverType.TURN_LEFT, 37.004, -122.0),
            maneuver(ManeuverType.TURN_RIGHT, 37.008, -122.0),
        )
        assertEquals(1, RouteRender.aheadArrows(line, maneuvers, stepIndex = 1).size)
        assertEquals(1, RouteRender.aheadArrows(line, maneuvers, stepIndex = 0, limit = 1).size)
        assertTrue(RouteRender.aheadArrows(line, maneuvers, stepIndex = 9).isEmpty())
    }

    @Test
    fun lanesShowOnlyAtTheApproach() {
        val lanes = listOf(Lane(listOf("left"), true), Lane(listOf("straight"), false))
        assertTrue(RouteRender.lanesVisible(lanes, distanceM = 700.0, speedMps = 5.0))
        assertTrue(!RouteRender.lanesVisible(lanes, distanceM = 900.0, speedMps = 5.0))
        // Above the floor the window grows with speed: 40 m/s buys 1200 m.
        assertTrue(RouteRender.lanesVisible(lanes, distanceM = 1100.0, speedMps = 40.0))
        assertTrue(!RouteRender.lanesVisible(emptyList(), distanceM = 10.0, speedMps = 0.0))
    }

    @Test
    fun laneGlyphsRunFromTheLeftLaneToTheRightOne() {
        val lanes = listOf(
            Lane(listOf("left"), true),
            Lane(listOf("straight"), false),
            Lane(listOf("right"), false),
        )
        val glyphs = RouteRender.laneGlyphs(line, LatLng(37.01, -122.0), lanes)
        assertEquals(3, glyphs.size)
        assertEquals(lanes.map { it.indications }, glyphs.map { it.indications })
        assertEquals(true, glyphs[0].valid)
        // Northbound: lane 0 (left) sits west, lane 2 (right) east, the center stays on the point.
        assertTrue(glyphs[0].location.lng < glyphs[1].location.lng)
        assertTrue(glyphs[1].location.lng < glyphs[2].location.lng)
        assertTrue(abs(glyphs[1].location.lng - (-122.0)) < 1e-6)
        assertTrue(abs(glyphs[0].rotation) < 5.0, "the row does not point along the approach")
    }
}
