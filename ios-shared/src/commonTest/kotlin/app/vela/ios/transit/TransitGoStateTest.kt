package app.vela.ios.transit

import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitLine
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TransitGoStateTest {
    private val now = 1_700_000_000L

    private fun stop(name: String, scheduled: Long, estimated: Long = 0) =
        TransitGoStop(name, scheduled, estimated)

    private fun ride(
        scheduledDeparture: Long = now + 120,
        estimatedDeparture: Long = 0,
        scheduledArrival: Long = now + 300,
        estimatedArrival: Long = 0,
        stops: List<TransitGoStop> = listOf(
            stop("République", scheduledDeparture, estimatedDeparture),
            stop("Colonel Fabien", now + 120),
            stop("Belleville", scheduledArrival, estimatedArrival),
        ),
        timed: Boolean = true,
    ) = TransitGoLeg(
        kind = TransitGoMachine.KIND_RIDE,
        line = "M2",
        colorHex = "#1f6fb2",
        textColorHex = "#FFFFFF",
        direction = "Nation",
        fromName = "République",
        toName = "Belleville",
        durationMinutes = 6,
        scheduledDepartureEpochSec = scheduledDeparture,
        estimatedDepartureEpochSec = estimatedDeparture,
        scheduledArrivalEpochSec = scheduledArrival,
        estimatedArrivalEpochSec = estimatedArrival,
        stops = stops,
        stopCount = stops.size - 1,
        timed = timed,
    )

    private fun walk(to: String, minutes: Int = 4) = TransitGoLeg(
        kind = TransitGoMachine.KIND_WALK,
        toName = to,
        durationMinutes = minutes,
    )

    private fun plan(
        legs: List<TransitGoLeg>,
        live: Boolean = false,
        fetchedAt: Long = now,
    ) = TransitGoPlan(
        destinationName = "Belleville",
        legs = legs,
        liveData = live,
        fetchedAtEpochSec = fetchedAt,
        scheduledArrivalEpochSec = now + 900,
    )

    @Test
    fun walkThenRideThenDoneWalksTheFourReportedSteps() {
        val machine = TransitGoMachine(plan(listOf(walk("République"), ride(), walk("the destination", 2))))

        val walkState = machine.snapshot(now)
        assertEquals("walk", walkState.step)
        assertEquals("WALK", walkState.phase)
        assertEquals("Walk 4 min to République", walkState.action)

        machine.skipStep()
        val wait = machine.snapshot(now)
        assertEquals("walk", wait.step)
        assertEquals("WAIT", wait.phase)
        assertEquals("Take M2 towards Nation", wait.action)
        assertTrue(wait.canBoard)
        assertEquals("Scheduled", wait.timeLabel)
        assertEquals("departing in 2 min", wait.countdownText(now))

        machine.board()
        val board = machine.snapshot(now)
        assertEquals("ride", board.step)
        assertEquals("RIDE", board.phase)
        assertEquals("Get off at Belleville in 2 stops", board.action)
        assertEquals(2, board.stopsRemaining)
        assertEquals("arriving in 5 min", board.countdownText(now))

        machine.advanceStop()
        assertEquals(1, machine.snapshot(now).stopsRemaining)
        machine.advanceStop()
        val alight = machine.snapshot(now)
        assertEquals("Get off now at Belleville", alight.action)
        assertEquals(0, alight.stopsRemaining)
        assertEquals("stop", alight.cue)
        assertEquals("now", alight.countdownText(now))

        machine.advanceStop()
        val transfer = machine.snapshot(now)
        assertEquals("transfer", transfer.step)
        assertEquals("Transfer: walk 2 min to the destination", transfer.action)

        machine.skipStep()
        val done = machine.snapshot(now)
        assertEquals("done", done.step)
        assertEquals("You have arrived at Belleville", done.action)
        assertFalse(done.active)
    }

    @Test
    fun aRideAfterAnotherRideReportsTransferAndCanBeSkipped() {
        val machine = TransitGoMachine(plan(listOf(ride(), ride())))
        assertEquals("WAIT", machine.snapshot(now).phase)
        machine.board()
        repeat(2) { machine.advanceStop() }
        assertEquals("RIDE", machine.snapshot(now).phase)
        machine.advanceStop()
        val transfer = machine.snapshot(now)
        assertEquals("transfer", transfer.step)
        assertEquals("WAIT", transfer.phase)
        assertEquals("Take M2 towards Nation", transfer.action)
    }

    @Test
    fun getOffCueFiresAtTwoStopsThenAtTheStopAndNeverRepeats() {
        val machine = TransitGoMachine(plan(listOf(ride())))
        machine.board()

        val first = machine.snapshot(now)
        assertEquals("two_before", first.cue)
        assertEquals("Get off in two stops at Belleville", first.cueText)
        val serial = first.cueSerial
        assertEquals(serial, machine.snapshot(now).cueSerial, "a repeated snapshot repeated the cue")

        machine.advanceStop()
        val nextStop = machine.snapshot(now)
        assertEquals("two_before", nextStop.cue, "the cue left before the stop")
        assertEquals("Get off at the next stop at Belleville", nextStop.cueText)
        machine.advanceStop()
        val atStop = machine.snapshot(now)
        assertEquals("stop", atStop.cue)
        assertEquals("Get off now at Belleville", atStop.cueText)
        assertTrue(atStop.cueSerial > serial)
    }

    @Test
    fun aLegWithoutTimesStaysSilentAndSaysNoTime() {
        val ride = ride(
            scheduledDeparture = 0, scheduledArrival = 0,
            stops = listOf(stop("République", 0), stop("Belleville", 0)),
        )
        val machine = TransitGoMachine(plan(listOf(ride)))
        machine.board()
        val state = machine.snapshot(now)
        assertEquals("No time", state.countdownText(now))
        assertEquals("No time", state.timeLabel)
        assertEquals("", state.cue)
        assertEquals(-1.0, state.estimatedFraction)

        // The manual controls stay possible when the data is missing.
        machine.advanceStop()
        assertEquals(0, machine.snapshot(now).stopsRemaining)
        machine.advanceStop()
        assertEquals("done", machine.snapshot(now).step)
    }

    @Test
    fun offlineDropsTheCountdownToTheTimetable() {
        val liveRide = ride(
            scheduledDeparture = now + 120,
            estimatedDeparture = now + 60,
            scheduledArrival = now + 400,
            estimatedArrival = now + 330,
        )
        val machine = TransitGoMachine(plan(listOf(liveRide), live = true), networkAvailable = false)
        val state = machine.snapshot(now)
        assertEquals("Scheduled", state.timeLabel)
        assertTrue(state.scheduledOnly)
        assertTrue(state.offline)
        assertFalse(state.estimated)
        assertEquals("departing in 2 min", state.countdownText(now))
        assertEquals("", state.positionLabel)
    }

    @Test
    fun aStalePlanKeepsItsStepsButLosesEveryLiveClaim() {
        val liveRide = ride(estimatedArrival = now + 300, estimatedDeparture = now + 60)
        val machine = TransitGoMachine(
            plan(listOf(liveRide), live = true, fetchedAt = now - 3 * 60 * 60))
        machine.board()
        val state = machine.snapshot(now)
        assertTrue(state.stale)
        assertTrue(state.scheduledOnly)
        assertFalse(state.estimated)
        assertEquals("", state.cue, "a stale plan announced a get-off")
        assertEquals("Scheduled", state.timeLabel)
        assertEquals("ride", state.step, "staleness dropped the step machine")
    }

    @Test
    fun estimatedPositionComesOnlyFromTheAdjacentLiveTimes() {
        val liveRide = ride(
            scheduledDeparture = now - 300,
            estimatedDeparture = now - 300,
            scheduledArrival = now + 300,
            estimatedArrival = now + 300,
            stops = listOf(
                stop("République", now - 300, now - 300),
                stop("Colonel Fabien", now - 60, now - 60),
                stop("Belleville", now + 300, now + 300),
            ),
        )
        val machine = TransitGoMachine(plan(listOf(liveRide), live = true))
        machine.board()
        machine.advanceStop()
        val state = machine.snapshot(now)
        assertEquals("Colonel Fabien", state.estimatedFromStop)
        assertEquals("Belleville", state.estimatedToStop)
        assertTrue(state.estimatedFraction in 0.0..1.0)
        assertEquals("Estimated", state.positionLabel)

        val dry = TransitGoMachine(plan(listOf(ride()), live = false))
        dry.board()
        assertEquals(-1.0, dry.snapshot(now).estimatedFraction)
    }

    @Test
    fun countdownTicksFromTheClockWithoutAnotherPlan() {
        val machine = TransitGoMachine(
            plan(listOf(ride(scheduledDeparture = now + 300, scheduledArrival = now + 900))))
        val wait = machine.snapshot(now)
        assertEquals("departing in 5 min", wait.countdownText(now))
        assertEquals("departing in 4 min", wait.countdownText(now + 60))
        assertEquals("departing in 1 min", wait.countdownText(now + 240))
        assertEquals("now", wait.countdownText(now + 300))
        assertEquals("departure time passed", wait.countdownText(now + 360))
    }

    @Test
    fun leaveLaterAnchorsOnTheBoardsOwnDepartureAtTheStop() {
        val leg = ride(
            scheduledDeparture = now + 600,
            stops = listOf(stop("République", now + 600), stop("Belleville", now + 900)),
        ).copy(departureClockText = "10:15")
        val anchor = TransitGoAnchorSelector.select(
            leg = leg,
            boardStopName = "République",
            boardDepartures = listOf(
                TransitGoBoardDeparture("M2", "Nation", "10:05", now + 300),
                TransitGoBoardDeparture("M2", "Nation", "10:15", now + 600),
                TransitGoBoardDeparture("M1", "La Défense", "10:15", now + 660),
            ),
            nowEpochSec = now,
            deltaMinutes = 15,
        )
        assertEquals("board", anchor.source)
        assertEquals(now + 600 + 15 * 60, anchor.epochSec)
        assertEquals("République", anchor.stopName)
    }

    @Test
    fun leaveLaterFallsBackToNowWhenTheBoardHasNoTime() {
        val leg = ride(
            scheduledDeparture = now + 600,
            stops = listOf(stop("République", now + 600), stop("Belleville", now + 900)),
        ).copy(departureClockText = "10:15")

        val empty = TransitGoAnchorSelector.select(
            leg = leg,
            boardStopName = "République",
            boardDepartures = emptyList(),
            nowEpochSec = now,
            deltaMinutes = 15,
        )
        assertEquals("now", empty.source)
        assertEquals(now + 15 * 60, empty.epochSec)

        // Another line, another run or another stop is not this run's departure either.
        val otherLine = TransitGoAnchorSelector.select(
            leg = leg,
            boardStopName = "République",
            boardDepartures = listOf(
                TransitGoBoardDeparture("M1", "Nation", "10:15", now + 600),
                TransitGoBoardDeparture("M2", "Nation", "10:25", now + 700),
            ),
            nowEpochSec = now,
            deltaMinutes = 5,
        )
        assertEquals("now", otherLine.source)
        assertEquals(now + 5 * 60, otherLine.epochSec)

        val otherStop = TransitGoAnchorSelector.select(
            leg = leg,
            boardStopName = "Belleville",
            boardDepartures = listOf(
                TransitGoBoardDeparture("M2", "Nation", "10:15", now + 600),
            ),
            nowEpochSec = now,
            deltaMinutes = 30,
        )
        assertEquals("now", otherStop.source)
        assertEquals(now + 30 * 60, otherStop.epochSec)
    }

    @Test
    fun aSessionMayPushTheStopForwardButNeverBackward() {
        val machine = TransitGoMachine(plan(listOf(walk("République"), ride(), walk("the destination", 2))))
        machine.sync(legIndex = 1, passedStops = 2, boarded = true, arrived = false)
        val state = machine.snapshot(now)
        assertEquals("RIDE", state.phase)
        assertEquals(2, state.stopIndex)
        assertEquals(0, state.stopsRemaining)
        assertEquals("stop", state.cue)

        machine.sync(legIndex = 0, passedStops = 0, boarded = false, arrived = false)
        assertEquals("RIDE", machine.snapshot(now).phase, "the machine rewound to an earlier leg")

        machine.sync(legIndex = 2, passedStops = 0, boarded = false, arrived = false)
        assertEquals("WALK", machine.snapshot(now).phase)
        assertEquals("transfer", machine.snapshot(now).step)
    }

    @Test
    fun endingTheTripStopsTheMachine() {
        val machine = TransitGoMachine(plan(listOf(walk("République"), ride())))
        machine.board()
        machine.end()
        val state = machine.snapshot(now)
        assertFalse(state.active)
        assertEquals("done", state.step)
        assertEquals("", state.cue)
    }

    @Test
    fun fromItineraryKeepsStopsColoursAndLiveTimes() {
        val built = TransitGoPlanBuilder.fromItinerary(
            trip = TransitPreview.sf,
            destinationName = "Ferry Building",
            fetchedAtEpochSec = 1_792_945_700L,
            liveData = true,
        )
        assertEquals("Ferry Building", built.destinationName)
        assertEquals(3, built.legs.size)
        val ride = built.legs[1]
        assertEquals("K", ride.line)
        assertEquals("#437c93", ride.colorHex)
        assertEquals("Embarcadero Station", ride.direction)
        assertEquals(5, ride.stops.size)
        assertTrue(ride.timed)
        assertTrue(ride.estimatedDepartureEpochSec > 0)
        assertTrue(ride.scheduledDepartureEpochSec > 0)
        assertTrue(ride.stops.first().estimatedEpochSec > 0)
    }

    @Test
    fun fromItineraryDoesNotInventTimesForASilentLeg() {
        val silent = TransitItinerary(
            steps = listOf(
                TransitStep(mode = TransitMode.WALK, durationText = "3 min"),
                TransitStep(
                    mode = TransitMode.SUBWAY,
                    line = TransitLine("M2", TransitMode.SUBWAY),
                    headsign = "Nation",
                    boardStop = TransitStopTime("République"),
                    alightStop = TransitStopTime("Belleville"),
                    numStops = 2,
                ),
            ),
        )
        val built = TransitGoPlanBuilder.fromItinerary(silent, "Belleville", now, liveData = false)
        val ride = built.legs[1]
        assertFalse(ride.timed)
        assertEquals(0, ride.scheduledDepartureEpochSec)
        assertEquals(0, ride.scheduledArrivalEpochSec)
        assertEquals(0, ride.stops.first().scheduledEpochSec)
        assertEquals("#d93025", ride.colorHex, "a line without a feed colour takes the mode colour")
        val machine = TransitGoMachine(built)
        assertEquals("Walk 3 min to République", machine.snapshot(now).action)
        machine.skipStep()
        val state = machine.snapshot(now)
        assertEquals("Take M2 towards Nation", state.action)
        assertEquals("No time", state.countdownText(now))
    }

    @Test
    fun theFixtureWalksBoardsRidesAndGetsOff() {
        val fixture = TransitGoFixtures.paris(now)
        val machine = TransitGoMachine(fixture)
        assertEquals("walk", machine.snapshot(now).step)
        machine.skipStep()
        assertEquals("Take M2 towards Nation", machine.snapshot(now).action)
        machine.board()
        machine.advanceStop()
        val state = machine.snapshot(now)
        assertEquals("ride", state.step)
        assertEquals("Estimated", state.positionLabel)
        assertEquals("Belleville", state.targetName)
    }

    @Test
    fun previousAndNextWalkTheSameStepsBothWays() {
        val machine = TransitGoMachine(plan(listOf(walk("République"), ride(), walk("the destination", 2))))
        val start = machine.snapshot(now)
        assertFalse(start.canPrevious, "the first step has no previous step")
        assertTrue(start.canNext)
        assertEquals("Take M2 towards Nation", start.nextAction)

        machine.next()
        assertEquals("WAIT", machine.snapshot(now).phase)
        machine.next()
        val ride = machine.snapshot(now)
        assertEquals("RIDE", ride.phase)
        assertEquals("Take M2 towards Nation", ride.previousAction)
        assertEquals("Transfer: walk 2 min to the destination", ride.nextAction)
        machine.next()
        assertEquals("transfer", machine.snapshot(now).step)
        machine.next()
        val done = machine.snapshot(now)
        assertEquals("done", done.step)
        assertFalse(done.canNext, "done has no next step")
        assertTrue(done.canPrevious)
        assertEquals("Transfer: walk 2 min to the destination", done.previousAction)

        machine.previous()
        assertEquals("transfer", machine.snapshot(now).step)
        machine.previous()
        val back = machine.snapshot(now)
        assertEquals("RIDE", back.phase)
        assertEquals(0, back.stopIndex, "a ride entered backwards starts at its first stop")
        machine.previous()
        assertEquals("WAIT", machine.snapshot(now).phase)
        machine.previous()
        val first = machine.snapshot(now)
        assertEquals("WALK", first.phase)
        assertEquals(0, first.legIndex)
        machine.previous()
        assertEquals(first.legIndex, machine.snapshot(now).legIndex, "Previous went before the first step")
    }

    @Test
    fun previousFromASecondRideGoesBackToTheFirstRide() {
        val machine = TransitGoMachine(plan(listOf(ride(), ride())))
        repeat(2) { machine.next() }
        val transfer = machine.snapshot(now)
        assertEquals("transfer", transfer.step)
        assertEquals(1, transfer.legIndex)
        machine.previous()
        val first = machine.snapshot(now)
        assertEquals("ride", first.step)
        assertEquals(0, first.legIndex)
    }

    @Test
    fun aManualPreviousHoldsUntilTheSessionReportsProgressBeyondIt() {
        val machine = TransitGoMachine(plan(listOf(walk("République"), ride(), walk("the destination", 2))))
        machine.sync(legIndex = 1, passedStops = 1, boarded = true, arrived = false)
        assertEquals(1, machine.snapshot(now).stopIndex)

        machine.previous()
        val held = machine.snapshot(now)
        assertEquals("WAIT", held.phase)
        assertTrue(held.held)

        // The stale report, then the session's own Previous: neither moves the step forward.
        machine.sync(legIndex = 1, passedStops = 1, boarded = true, arrived = false)
        machine.sync(legIndex = 1, passedStops = 0, boarded = false, arrived = false)
        assertEquals("WAIT", machine.snapshot(now).phase, "a stale index undid the manual Previous")

        // Progress beyond the step the user left: the hold ends and the session leads again.
        machine.sync(legIndex = 1, passedStops = 2, boarded = true, arrived = false)
        val resumed = machine.snapshot(now)
        assertEquals("RIDE", resumed.phase)
        assertEquals(2, resumed.stopIndex)
        assertFalse(resumed.held)
    }

    @Test
    fun nextBackToTheHeldStepEndsTheHold() {
        val machine = TransitGoMachine(plan(listOf(walk("République"), ride(), walk("the destination", 2))))
        machine.sync(legIndex = 1, passedStops = 0, boarded = true, arrived = false)
        machine.previous()
        assertTrue(machine.snapshot(now).held)
        machine.next()
        val ride = machine.snapshot(now)
        assertEquals("RIDE", ride.phase)
        assertFalse(ride.held)
        machine.sync(legIndex = 1, passedStops = 1, boarded = true, arrived = false)
        assertEquals(1, machine.snapshot(now).stopIndex)
    }

    @Test
    fun goingBackAndForthOverACuedStopNeverReplaysTheCue() {
        val machine = TransitGoMachine(plan(listOf(ride(), walk("the destination", 2))))
        machine.board()
        val two = machine.snapshot(now)
        assertEquals("two_before", two.cue)
        repeat(2) { machine.advanceStop() }
        val stop = machine.snapshot(now)
        assertEquals("stop", stop.cue)
        val serial = stop.cueSerial

        machine.next()
        machine.previous()
        val again = machine.snapshot(now)
        assertEquals("RIDE", again.phase)
        assertEquals("", again.cue, "the two-stop cue replayed after Previous")
        repeat(2) { machine.advanceStop() }
        val alight = machine.snapshot(now)
        assertEquals("", alight.cue, "the stop cue replayed after Previous")
        assertEquals(serial, alight.cueSerial)
        machine.previous()
        machine.next()
        assertEquals(serial, machine.snapshot(now).cueSerial)
    }

    @Test
    fun endedGuidanceHasNoPreviousStep() {
        val machine = TransitGoMachine(plan(listOf(walk("République"), ride())))
        machine.next()
        machine.end()
        machine.previous()
        val ended = machine.snapshot(now)
        assertFalse(ended.active)
        assertFalse(ended.canPrevious)
        assertFalse(ended.canNext)
    }
}
