package app.vela.ios.transit

import app.vela.core.i18n.NavStringsRegistry
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Walking legs: instructions derived from the leg's own bearings when the planner sends no
 *  street-level steps, named maneuvers when the walk router answers, and prompts said once. */
class TransitWalkGuideTest {
    private val strings = NavStringsRegistry.current()

    /** Davis: north 90 m, then east 85 m. Allowed fixture coordinates. */
    private val start = LatLng(38.5449, -121.7405)
    private val corner = LatLng(38.54571, -121.7405)
    private val end = LatLng(38.54571, -121.73951)

    private fun dense(a: LatLng, b: LatLng, count: Int = 6): List<LatLng> =
        (0..count).map { i ->
            val f = i.toDouble() / count
            LatLng(a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f)
        }

    @Test fun geometryProducesATurnWithoutInventingStreetNames() {
        val path = dense(start, corner) + dense(corner, end).drop(1)
        val plan = assertNotNull(
            WalkingDirections.fromGeometry(path, start, end, "Market Street", strings),
        )
        assertEquals("path", plan.source)
        assertFalse(plan.named)
        assertEquals(3, plan.instructions.size, "start, one turn, arrive")
        assertEquals(WalkManeuver.START, plan.instructions[0].maneuver)
        assertEquals(WalkManeuver.RIGHT, plan.instructions[1].maneuver)
        assertEquals(WalkManeuver.ARRIVE, plan.instructions[2].maneuver)
        assertNull(plan.instructions[1].road)
        assertTrue(abs(plan.instructions[1].atMeters - 90.0) < 15.0, "turn at ${plan.instructions[1].atMeters}")
        assertTrue(abs(plan.totalMeters - 175.0) < 20.0, "total ${plan.totalMeters}")
        assertEquals("Market Street", plan.targetName)
    }

    @Test fun aLeftTurnIsReadFromTheBearingChange() {
        val path = listOf(start, corner, LatLng(38.54571, -121.7415))
        val plan = assertNotNull(WalkingDirections.fromGeometry(path, start, path.last(), null, strings))
        assertEquals(WalkManeuver.LEFT, plan.instructions[1].maneuver)
    }

    @Test fun withoutAPathTheLegSaysItRestsOnTheEndpoints() {
        val plan = assertNotNull(WalkingDirections.fromGeometry(null, start, end, null, strings))
        assertEquals("straight", plan.source)
        assertEquals(2, plan.instructions.size)
        assertEquals(plan.totalMeters, plan.instructions[1].atMeters, 0.5)
        assertNull(WalkingDirections.fromGeometry(null, null, null, null, strings))
    }

    @Test fun routerManeuversKeepTheirStreets() {
        val maneuvers = listOf(
            Maneuver(
                type = ManeuverType.DEPART,
                instruction = "Head east on Market Street",
                location = start,
                distanceMeters = 90.0,
                durationSeconds = 65.0,
                road = "Market Street",
            ),
            Maneuver(
                type = ManeuverType.TURN_LEFT,
                instruction = "Turn left onto 4th Street",
                location = corner,
                distanceMeters = 85.0,
                durationSeconds = 60.0,
                road = "4th Street",
            ),
            Maneuver(
                type = ManeuverType.ARRIVE,
                instruction = "Arrive at your destination",
                location = end,
                distanceMeters = 0.0,
                durationSeconds = 0.0,
            ),
        )
        val plan = assertNotNull(WalkingDirections.fromManeuvers(maneuvers, listOf(start, corner, end), "4th Street"))
        assertEquals("steps", plan.source)
        assertTrue(plan.named)
        assertEquals(3, plan.instructions.size)
        assertTrue(plan.instructions[1].text.contains("4th Street"))
        assertEquals("4th Street", plan.instructions[1].road)
    }

    @Test fun promptsAreSaidOncePerBand() {
        val plan = assertNotNull(
            WalkingDirections.fromGeometry(listOf(start, corner, end), start, end, null, strings),
        )
        val guide = WalkGuide(plan, strings, imperial = true)
        assertEquals(plan.instructions[0].spoken, guide.takePrompt(0.0), "the walk starts with its first line")
        assertNull(guide.takePrompt(1.0), "the start is not repeated")

        val turnAt = plan.instructions[1].atMeters
        assertNull(guide.takePrompt(turnAt - 70.0), "nothing is said outside the far band")
        val far = assertNotNull(guide.takePrompt(turnAt - 30.0))
        assertTrue(far.contains(plan.instructions[1].spoken), "far prompt: $far")
        assertNull(guide.takePrompt(turnAt - 25.0), "the far band is said once")
        val near = guide.takePrompt(turnAt - 8.0)
        assertEquals(plan.instructions[1].spoken, near)
        assertNull(guide.takePrompt(turnAt - 5.0))
        assertEquals(strings.arrived(), guide.takePrompt(plan.totalMeters - 5.0))
        assertNull(guide.takePrompt(plan.totalMeters - 2.0))
    }

    @Test fun theBannerShowsTheUpcomingTurnThenTheArrival() {
        val plan = assertNotNull(
            WalkingDirections.fromGeometry(listOf(start, corner, end), start, end, null, strings),
        )
        val guide = WalkGuide(plan, strings, imperial = false)
        val first = guide.view(0.0)
        assertTrue(first.active)
        assertEquals(WalkManeuver.START, plan.instructions[first.instructionIndex].maneuver)
        assertEquals(plan.instructions.size, first.instructionCount)

        val approaching = guide.view(plan.instructions[1].atMeters - 25.0)
        assertEquals(WalkManeuver.RIGHT, plan.instructions[approaching.instructionIndex].maneuver)
        assertTrue(abs(approaching.distanceMeters - 25.0) < 1.0)

        val nearEnd = guide.view(plan.totalMeters - 10.0)
        assertEquals(WalkManeuver.ARRIVE, plan.instructions[nearEnd.instructionIndex].maneuver)
        assertTrue(nearEnd.remainingMeters <= 10.0)
    }

    @Test fun anOffRouteFixDoesNotProjectOnTheWalk() {
        val plan = assertNotNull(
            WalkingDirections.fromGeometry(listOf(start, corner, end), start, end, null, strings),
        )
        val guide = WalkGuide(plan, strings, imperial = false)
        assertNull(guide.alongOf(LatLng(start.lat + 0.01, start.lng)))
        assertNotNull(guide.alongOf(LatLng(start.lat + 0.0003, start.lng)))
    }
}
