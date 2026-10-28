package app.vela.ios.transit

import app.vela.core.model.TransitMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TransitSessionTest {
    @Test fun startKeepsOrderedLegsAndFindsCurrentAndNextRides() {
        val session = TransitSession()
        assertTrue(session.start(TransitPreview.sf, "Ferry Building"))
        val s = session.state.value
        assertTrue(s.active)
        assertFalse(s.arrived)
        assertEquals(listOf("WALK", "TRAM", "WALK"), s.legs.map { it.kind })
        assertEquals(0, s.legIndex)
        assertEquals("Metro Van Ness Station", s.walkTarget)
        assertEquals("K", s.displayRide()?.line)
        assertEquals("K", s.nextRide()?.line)
        assertEquals("9:39 AM", s.overallArrivalText)
        assertEquals(1_792_946_340L, s.overallArrivalEpochSec)
        assertTrue(s.overallArrivalIsEstimate)
        assertEquals(-1, s.stopsRemaining)
        assertTrue(session.line().isNotEmpty())
    }

    @Test fun previewAdvancesWalkRideWalkArrivalAndEnd() {
        val session = TransitSession().also { it.start(TransitPreview.sf, "Ferry Building") }
        session.advanceForPreview()
        var s = session.state.value
        assertEquals(1, s.legIndex)
        assertFalse(s.boarded)
        assertEquals(4, s.stopsRemaining)
        assertEquals("Metro Civic Center Station/Downtn", s.nextStop)
        assertEquals("Metro Van Ness Station", s.current()?.boardStop)
        assertNull(s.nextRide())

        session.advanceForPreview()
        s = session.state.value
        assertEquals(2, s.legIndex)
        assertEquals("Ferry Building", s.walkTarget)
        assertNull(s.displayRide())

        session.advanceForPreview()
        s = session.state.value
        assertTrue(s.arrived)
        assertTrue(s.active)
        assertEquals(1.0, s.progress)
        assertEquals(-1, s.stopsRemaining)
        assertNull(s.nextStop)
        session.advanceForPreview()
        assertEquals(s, session.state.value)

        session.end()
        assertEquals(TransitState(sessionId = 1), session.state.value)
        assertTrue(session.line().isEmpty())
    }

    @Test fun fixesAdvanceWalkingAndEachStopWithoutInventingPrecision() {
        val session = TransitSession().also { it.start(TransitPreview.sf, "Ferry Building") }
        session.onLocation(37.775127, -122.41925, 20.0)
        assertEquals(1, session.state.value.legIndex)

        session.onLocation(37.779713, -122.413345, 101.0)
        assertEquals(0, session.state.value.passedStops)
        session.onLocation(37.779713, -122.413345, 35.0)
        var s = session.state.value
        assertTrue(s.boarded)
        assertEquals(1, s.passedStops)
        assertEquals(3, s.stopsRemaining)
        assertEquals("Metro Powell Station/Downtown", s.nextStop)
        assertTrue(s.progress > 1.0 / 3.0 && s.progress < 2.0 / 3.0)

        session.onLocation(37.784653, -122.40709, 35.0)
        assertEquals(2, session.state.value.stopsRemaining)
        session.onLocation(37.78922, -122.40135, 35.0)
        val lastStop = session.state.value
        assertEquals(1, lastStop.stopsRemaining)
        assertEquals("Metro Embarcadero Station", lastStop.nextStop)

        session.onLocation(37.793133, -122.39643, 35.0)
        s = session.state.value
        assertEquals(2, s.legIndex)
        assertEquals(TransitMode.WALK.name, s.current()?.kind)
        session.onLocation(37.7942, -122.3946, 35.0)
        assertTrue(session.state.value.arrived)
    }

    @Test fun aRideWithoutIntermediateDetailsLeavesBoardingBeforeAlighting() {
        val trip = TransitPreview.sf
        val ride = trip.steps[1].copy(intermediateStops = emptyList(), numStops = 1)
        val session = TransitSession().also { it.start(trip.copy(steps = listOf(ride)), "Ferry Building") }
        session.onLocation(37.7780, -122.4150, 20.0)
        val s = session.state.value
        assertTrue(s.boarded)
        assertEquals(1, s.stopsRemaining)
        assertEquals("Metro Embarcadero Station", s.nextStop)
    }

    @Test fun scheduledTimesStaySeparateFromLiveEstimatesAndDelays() {
        val session = TransitSession().also { it.start(TransitPreview.sf, "Ferry Building") }
        val live = session.state.value.legs[1]
        assertEquals("9:24 AM", live.scheduledDeparture)
        assertEquals("9:28 AM", live.estimatedDeparture)
        assertEquals("9:29 AM", live.scheduledArrival)
        assertEquals("9:35 AM", live.estimatedArrival)
        assertEquals(4, live.delayMinutes)

        val trip = TransitPreview.sf
        val scheduledRide = trip.steps[1].copy(
            departText = "9:24 AM",
            arriveText = "9:29 AM",
            boardStop = trip.steps[1].boardStop?.copy(
                timeText = "9:24 AM", scheduledText = null, delayMin = null,
            ),
            alightStop = trip.steps[1].alightStop?.copy(
                timeText = "9:29 AM", scheduledText = null, delayMin = null,
            ),
            delayText = null,
        )
        val scheduled = TransitSession().also {
            it.start(trip.copy(steps = listOf(scheduledRide), arrivalText = "9:29 AM"), "Ferry Building")
        }.state.value
        val leg = scheduled.legs.single()
        assertEquals("9:24 AM", leg.scheduledDeparture)
        assertNull(leg.estimatedDeparture)
        assertEquals("9:29 AM", leg.scheduledArrival)
        assertNull(leg.estimatedArrival)
        assertNull(leg.delayMinutes)
        assertFalse(scheduled.overallArrivalIsEstimate)
    }

    @Test fun unknownStopCountStaysUnknownAndEndIgnoresLaterFixes() {
        val trip = TransitPreview.sf
        val ride = trip.steps[1].copy(
            boardStop = null, alightStop = null, intermediateStops = emptyList(), numStops = null,
        )
        val session = TransitSession().also { it.start(trip.copy(steps = listOf(ride)), "Ferry Building") }
        assertEquals(-1, session.state.value.stopsRemaining)
        assertNull(session.state.value.nextStop)
        session.end()
        session.onLocation(37.793133, -122.39643, 20.0)
        assertFalse(session.state.value.active)
        assertEquals(0, session.state.value.revision)
    }
}
