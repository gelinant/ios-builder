package app.vela.ios.transit

import app.vela.core.model.LatLng
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TransitGoMapTest {
    private val trip = TransitPreview.sf
    private val origin = LatLng(37.7749, -122.4194)
    private val vanNess = LatLng(37.775127, -122.41925)
    private val civicCenter = LatLng(37.779713, -122.413345)
    private val powell = LatLng(37.784653, -122.40709)
    private val embarcadero = LatLng(37.793133, -122.39643)
    private val destination = LatLng(37.7942, -122.3946)

    private fun TransitGoMapBox.holds(point: LatLng) = contains(point)

    @Test
    fun eachStepTargetsItsOwnEnd() {
        val walk = TransitGoMap.frame(trip, 0, TransitGoMachine.PHASE_WALK, origin)
        assertEquals(vanNess, walk.target)
        assertEquals(TransitGoMap.KIND_WALK, walk.targetKind)
        val wait = TransitGoMap.frame(trip, 1, TransitGoMachine.PHASE_WAIT, origin)
        assertEquals(vanNess, wait.target)
        assertEquals(TransitGoMap.KIND_BOARD, wait.targetKind)
        val ride = TransitGoMap.frame(trip, 1, TransitGoMachine.PHASE_RIDE, origin)
        assertEquals(embarcadero, ride.target)
        assertEquals(TransitGoMap.KIND_ALIGHT, ride.targetKind)
        val last = TransitGoMap.frame(trip, 2, TransitGoMachine.PHASE_WALK, embarcadero)
        assertEquals(destination, last.target)
        assertEquals(TransitGoMap.KIND_DESTINATION, last.targetKind)
        val done = TransitGoMap.frame(trip, 2, TransitGoMachine.PHASE_DONE, destination)
        assertEquals(destination, done.target)
        assertTrue(done.leg.isEmpty())
    }

    @Test
    fun theBoxHoldsTheUserTheTargetAndTheLegBetweenThem() {
        val user = LatLng(37.7800, -122.4128)
        val frame = TransitGoMap.frame(trip, 1, TransitGoMachine.PHASE_RIDE, user)
        val box = assertNotNull(frame.box)
        assertTrue(frame.usesUser)
        assertTrue(box.holds(user))
        assertTrue(box.holds(embarcadero))
        frame.leg.forEach { assertTrue(box.holds(it), "leg vertex $it outside the box") }
        // The ride's path is cut at the vertex nearest the user: Van Ness is already behind.
        assertEquals(civicCenter, frame.leg.first())
        assertEquals(embarcadero, frame.leg.last())
        assertTrue(box.south > vanNess.lat, "the stretch behind the user was framed")
    }

    @Test
    fun withoutAFixTheTargetAndTheWholeLegAreFramed() {
        val frame = TransitGoMap.frame(trip, 1, TransitGoMachine.PHASE_RIDE, null)
        val box = assertNotNull(frame.box)
        assertFalse(frame.usesUser)
        assertEquals(5, frame.leg.size)
        assertTrue(box.holds(vanNess))
        assertTrue(box.holds(embarcadero))
    }

    @Test
    fun aTargetNextToTheUserStillGetsAReadableBox() {
        val frame = TransitGoMap.frame(trip, 1, TransitGoMachine.PHASE_WAIT, vanNess)
        val box = assertNotNull(frame.box)
        assertTrue(box.north - box.south >= TransitGoMap.MIN_SPAN_DEGREES - 1e-9)
        assertTrue(box.east - box.west >= TransitGoMap.MIN_SPAN_DEGREES - 1e-9)
        assertTrue(box.holds(vanNess))
    }

    @Test
    fun aReversedPathIsWalkedFromTheUserToTheTarget() {
        val path = listOf(embarcadero, powell, civicCenter, vanNess)
        assertEquals(listOf(powell, civicCenter, vanNess), TransitGoMap.between(path, powell, vanNess))
        assertEquals(listOf(vanNess, civicCenter, powell), TransitGoMap.between(path, vanNess, powell))
    }

    @Test
    fun aRefitIsNeededOnlyWhenAPointLeavesTheSafeArea() {
        val visible = TransitGoMapBox(37.770, -122.425, 37.800, -122.390)
        assertFalse(TransitGoMap.needsRefit(visible, civicCenter, embarcadero))
        // Inside the view but within the edge band: refit before it is hidden by the edge.
        assertTrue(TransitGoMap.needsRefit(visible, LatLng(37.7705, -122.41), embarcadero))
        assertTrue(TransitGoMap.needsRefit(visible, civicCenter, LatLng(37.81, -122.39)))
        // Without a fix only the target counts.
        assertFalse(TransitGoMap.needsRefit(visible, null, embarcadero))
    }

    @Test
    fun theLineShowsWhileRidingOrWhenTheBoardingStopIsClose() {
        val riding = assertNotNull(TransitGoMap.nearLine(trip, 1, TransitGoMachine.PHASE_RIDE, null))
        assertEquals("K", riding.label)
        assertEquals("#437c93", riding.colorHex)
        assertEquals(5, riding.path.size)
        assertNotNull(TransitGoMap.nearLine(trip, 1, TransitGoMachine.PHASE_WAIT, null))
        // On foot 25 m from Van Ness: the next ride is near.
        assertEquals(1, TransitGoMap.nearLine(trip, 0, TransitGoMachine.PHASE_WALK, origin)?.legIndex)
        // On foot about 2 km away, or without a fix: no line and no request.
        assertNull(TransitGoMap.nearLine(trip, 0, TransitGoMachine.PHASE_WALK, LatLng(37.7600, -122.4400)))
        assertNull(TransitGoMap.nearLine(trip, 0, TransitGoMachine.PHASE_WALK, null))
        // The final walk has no next ride.
        assertNull(TransitGoMap.nearLine(trip, 2, TransitGoMachine.PHASE_WALK, embarcadero))
        assertNull(TransitGoMap.nearLine(trip, 2, TransitGoMachine.PHASE_DONE, destination))
    }

    @Test
    fun theFixtureStretchesInterpolateOnTheLineAndFeedTheHint() {
        val now = 1_792_945_800L
        val vehicles = TransitVehicles.markers(TransitGoMapFixtures.runs(trip, now), now)
        val onLine = TransitGoMap.vehiclesOn(vehicles + otherLine(), "k")
        assertEquals(2, onLine.size)
        assertTrue(onLine.all { it.estimated })
        val line = assertNotNull(TransitGoMap.nearLine(trip, 1, TransitGoMachine.PHASE_RIDE, null))
        val box = assertNotNull(TransitGoMap.requestBox(line, origin))
        onLine.forEach { assertTrue(box.contains(LatLng(it.lat, it.lng))) }
        assertTrue(box.contains(origin))
        val hint = assertNotNull(TransitGoMap.hintVehicle(onLine, civicCenter, null))
        assertEquals("go-fixture-k-out", hint.id)
        assertEquals(0.5, hint.fraction, 1e-9)
        val far = assertNotNull(TransitGoMap.hintVehicle(onLine, LatLng(37.789, -122.4013), null))
        assertEquals("go-fixture-k-in", far.id)
    }

    private fun otherLine() = listOf(
        TransitVehicles.mapped(
            id = "n", label = "N", mode = "TRAM", colorHex = "#005b95", feedColorHex = null,
            headsign = "Ocean Beach", fromStopName = "A", nextStopName = "B",
            lat = 37.78, lng = -122.41, bearing = 0.0, fraction = 0.5,
            delayMinutes = 0, hasDelay = false, destinationEpochSec = 0,
        ),
    )
}
