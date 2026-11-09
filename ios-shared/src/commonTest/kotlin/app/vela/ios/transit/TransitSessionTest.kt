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

    @Test fun guidedIsTheStartedTripUntilTheEnd() {
        val session = TransitSession()
        assertNull(session.guided)
        val trip = TransitPreview.sf // a getter: every read builds a new itinerary
        session.start(trip, "Ferry Building")
        assertTrue(session.guided === trip)
        session.end()
        assertNull(session.guided)
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

    @Test fun manualStepsWalkForwardAndBackWithTheirTitles() {
        val session = TransitSession().also { it.start(TransitPreview.sf, "Ferry Building") }
        var s = session.state.value
        assertNull(s.previousStepTitle)
        assertEquals("Board K at Metro Van Ness Station", s.nextStepTitle)
        assertFalse(session.previousStep())

        assertTrue(session.nextStep())
        s = session.state.value
        assertEquals(1, s.legIndex)
        assertFalse(s.boarded)
        assertEquals("Walk to Metro Van Ness Station", s.previousStepTitle)
        assertEquals("Ride K to Metro Embarcadero Station", s.nextStepTitle)

        assertTrue(session.nextStep())
        assertTrue(session.state.value.boarded)
        assertTrue(session.nextStep())
        assertEquals(2, session.state.value.legIndex)
        assertTrue(session.nextStep())
        s = session.state.value
        assertTrue(s.arrived)
        assertNull(s.nextStepTitle)
        assertEquals("Walk to Ferry Building", s.previousStepTitle)
        assertFalse(session.nextStep())

        assertTrue(session.previousStep())
        s = session.state.value
        assertFalse(s.arrived)
        assertEquals(2, s.legIndex)
        assertTrue(session.previousStep())
        s = session.state.value
        assertEquals(1, s.legIndex)
        assertTrue(s.boarded)
        assertEquals(0, s.passedStops)
        assertTrue(session.previousStep())
        assertFalse(session.state.value.boarded)
        assertTrue(session.previousStep())
        assertEquals(0, session.state.value.legIndex)
    }

    @Test fun aManualPreviousHoldsAgainstFixesUntilTheyGoBeyondIt() {
        val session = TransitSession().also { it.start(TransitPreview.sf, "Ferry Building") }
        session.onLocation(37.775127, -122.41925, 20.0)
        session.nextStep()
        assertTrue(session.state.value.boarded)

        // Back to the wait: a fix past the boarding stop no longer boards again by itself.
        assertTrue(session.previousStep())
        assertTrue(session.state.value.held)
        session.onLocation(37.7780, -122.4150, 20.0)
        assertFalse(session.state.value.boarded, "a fix undid the manual Previous")

        // The next stop is beyond the step the user left: the hold ends and the fix applies.
        session.onLocation(37.779713, -122.413345, 35.0)
        val s = session.state.value
        assertTrue(s.boarded)
        assertEquals(1, s.passedStops)
        assertFalse(s.held)
    }

    @Test fun aManualPreviousToTheWalkWaitsForNextAtTheStop() {
        val session = TransitSession().also { it.start(TransitPreview.sf, "Ferry Building") }
        session.onLocation(37.775127, -122.41925, 20.0)
        assertEquals(1, session.state.value.legIndex)
        assertTrue(session.previousStep())
        session.onLocation(37.775127, -122.41925, 20.0)
        assertEquals(0, session.state.value.legIndex, "the fix at the stop jumped forward again")
        assertTrue(session.nextStep())
        assertFalse(session.state.value.held)
        session.onLocation(37.779713, -122.413345, 35.0)
        assertEquals(1, session.state.value.passedStops)
    }

    @Test fun walkingBackDoesNotRepeatTheFirstWalkInstruction() {
        val session = TransitSession().also { it.start(TransitPreview.sf, "Ferry Building") }
        val firstSeq = session.state.value.walk.promptSeq
        assertTrue(firstSeq > 0)
        session.nextStep()
        session.previousStep()
        val back = session.state.value.walk
        assertTrue(back.active)
        assertEquals(firstSeq, back.promptSeq, "the walk instruction was spoken again")
        assertNull(back.prompt)
    }

    @Test fun stepCommandsNeedAnActiveSession() {
        val session = TransitSession()
        assertFalse(session.nextStep())
        assertFalse(session.previousStep())
        session.start(TransitPreview.sf, "Ferry Building")
        session.end()
        assertFalse(session.nextStep())
    }
}
