package app.vela.ios.transit

import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The session's walking guidance: geometry first, named steps when the router answers, poor
 *  fixes ignored, End final. */
@OptIn(ExperimentalCoroutinesApi::class)
class TransitWalkSessionTest {
    private val origin = LatLng(37.7749, -122.4194)
    private val vanNess = LatLng(37.775127, -122.41925)

    @Test fun startPublishesWalkInstructionsAndEndClearsThem() {
        val session = TransitSession().also { it.start(TransitPreview.sfTurns, "Ferry Building") }
        val walk = session.state.value.walk
        assertTrue(walk.active)
        assertTrue(walk.instructionCount >= 3, "instructions ${walk.instructionCount}")
        assertEquals("path", walk.source)
        assertFalse(walk.named, "the leg's own geometry has no street names")
        assertEquals("Metro Van Ness Station", walk.targetName)
        assertNotNull(walk.prompt, "the walk starts with a spoken line")
        assertEquals(1, walk.promptSeq)
        assertTrue(walk.instruction.isNotBlank())

        session.end()
        assertEquals(TransitWalkState(), session.state.value.walk)
    }

    @Test fun aStraightFixtureWalkStillHasStartAndArrival() {
        val session = TransitSession().also { it.start(TransitPreview.sf, "Ferry Building") }
        val walk = session.state.value.walk
        assertTrue(walk.active)
        assertEquals(2, walk.instructionCount)
        assertEquals(0, walk.instructionIndex)
    }

    @Test fun aPoorFixIsIgnoredAndAWalkedFixMovesTheBanner() {
        val session = TransitSession().also { it.start(TransitPreview.sfTurns, "Ferry Building") }
        val before = session.state.value
        session.onLocation(origin.lat, origin.lng, accuracyM = 240.0)
        assertEquals(before, session.state.value, "a 240 m fix must not move walking guidance")

        session.onLocation(37.7749, -122.4190, accuracyM = 8.0)
        val moved = session.state.value
        assertTrue(moved.walk.promptSeq > before.walk.promptSeq || moved.walk.remainingMeters < before.walk.remainingMeters)

        session.onLocation(vanNess.lat, vanNess.lng, accuracyM = 8.0)
        assertEquals(1, session.state.value.legIndex, "reaching the stop starts the ride leg")
        assertFalse(session.state.value.walk.active)
    }

    @Test fun namedRouterStepsReplaceTheBearingPlan() = runTest {
        val maneuvers = listOf(
            Maneuver(
                type = ManeuverType.DEPART, instruction = "Head east on Market Street",
                location = origin, distanceMeters = 70.0, durationSeconds = 55.0, road = "Market Street",
            ),
            Maneuver(
                type = ManeuverType.TURN_LEFT, instruction = "Turn left onto Van Ness Avenue",
                location = LatLng(37.7749, -122.4186), distanceMeters = 55.0, durationSeconds = 45.0,
                road = "Van Ness Avenue",
            ),
            Maneuver(
                type = ManeuverType.ARRIVE, instruction = "Arrive at your destination",
                location = vanNess, distanceMeters = 0.0, durationSeconds = 0.0,
            ),
        )
        var asked = 0
        val session = TransitSession(
            scope = backgroundScope,
            walkDirections = { _, _ -> asked += 1; maneuvers },
        )
        session.start(TransitPreview.sfTurns, "Ferry Building")
        runCurrent()
        val walk = session.state.value.walk
        assertEquals(1, asked)
        assertEquals("steps", walk.source)
        assertTrue(walk.named)
        assertTrue(walk.instructionCount >= 3)
        assertNull(walk.prompt, "the start line was already said from the geometry plan")

        // Ending while the router request is still pending must not resurrect the walk.
        session.end()
        assertEquals(TransitWalkState(), session.state.value.walk)
    }
}
