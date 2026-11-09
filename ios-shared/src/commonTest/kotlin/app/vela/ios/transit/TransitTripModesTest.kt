package app.vela.ios.transit

import app.vela.core.model.LatLng
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitLine
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * TRANSIT-MODES: the trip screen's cards read the planner's own mode and agency, and a wait card
 * carries the minutes between the previous arrival and the next departure. A two-ride trip keeps
 * every card, including the transfer walk after the first ride.
 */
class TransitTripModesTest {
    private fun ride(
        mode: TransitMode,
        modeName: String,
        line: String,
        agency: String,
        depart: Long,
        arrive: Long,
        board: String,
        alight: String,
    ) = TransitStep(
        mode = mode,
        line = TransitLine(name = line, mode = mode),
        modeName = modeName,
        agencyName = agency,
        departEpochSec = depart,
        arriveEpochSec = arrive,
        departText = "2:32 PM",
        arriveText = "2:43 PM",
        boardStop = TransitStopTime(name = board, location = LatLng(48.85, 2.35)),
        alightStop = TransitStopTime(name = alight, location = LatLng(48.87, 2.29)),
        numStops = 2,
    )

    private fun trip() = TransitItinerary(
        steps = listOf(
            TransitStep(mode = TransitMode.WALK, durationText = "3 min", modeName = "WALK"),
            ride(TransitMode.SUBWAY, "SUBWAY", "1", "RATP", 100_000, 100_600, "Hôtel de Ville", "Étoile"),
            TransitStep(
                mode = TransitMode.WALK, durationText = "2 min", modeName = "WALK",
                departEpochSec = 100_600, arriveEpochSec = 100_720),
            ride(TransitMode.TRAIN, "REGIONAL_RAIL", "A", "RER", 100_780, 101_000, "Étoile", "La Défense"),
            TransitStep(mode = TransitMode.WALK, durationText = "4 min", modeName = "WALK"),
        ),
    )

    @Test fun `every ride card keeps its planner mode and agency`() {
        val rides = TransitTrip.segmentsOf(trip()).filter { it.kind == TransitTrip.KIND_RIDE }
        assertEquals(2, rides.size)
        assertEquals(listOf("SUBWAY", "REGIONAL_RAIL"), rides.map { it.modeName })
        assertEquals(listOf("RATP", "RER"), rides.map { it.agencyName })
        assertEquals(listOf("1", "A"), rides.map { it.lineLabel })
    }

    @Test fun `the wait card carries the planned minutes`() {
        val segments = TransitTrip.segmentsOf(trip())
        val waits = segments.filter { it.kind == TransitTrip.KIND_WAIT }
        assertEquals(2, waits.size)
        assertEquals(null, waits[0].waitMinutes, "the walk has no clock in this fixture")
        assertEquals(1, waits[1].waitMinutes, "the transfer walk ends 100720, the RER leaves 100780")
    }

    @Test fun `the transfer walk keeps its own card`() {
        val segments = TransitTrip.segmentsOf(trip())
        assertEquals(
            listOf("WALK", "WAIT", "RIDE", "TRANSFER", "WAIT", "RIDE", "WALK"),
            segments.map { it.kind },
        )
    }
}
