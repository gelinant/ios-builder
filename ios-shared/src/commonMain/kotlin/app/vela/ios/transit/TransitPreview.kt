package app.vela.ios.transit

import app.vela.core.model.LatLng
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitLine
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime

/** A deterministic copy of the first recorded San Francisco Transitous reply. Only the debug UI
 *  preview uses it; production guidance always receives the chooser's selected itinerary. */
object TransitPreview {
    val sf: TransitItinerary
        get() {
            val origin = LatLng(37.7749, -122.4194)
            val vanNess = LatLng(37.775127, -122.41925)
            val civicCenter = LatLng(37.779713, -122.413345)
            val powell = LatLng(37.784653, -122.40709)
            val montgomery = LatLng(37.78922, -122.40135)
            val embarcadero = LatLng(37.793133, -122.39643)
            val destination = LatLng(37.7942, -122.3946)
            val line = TransitLine(
                name = "K",
                mode = TransitMode.TRAM,
                colorHex = "#437c93",
                textColorHex = "#FFFFFF",
            )
            val walkToMetro = TransitStep(
                mode = TransitMode.WALK,
                durationText = "1 min",
                walkFrom = origin,
                walkTo = vanNess,
                path = listOf(origin, vanNess),
            )
            val ride = TransitStep(
                mode = TransitMode.TRAM,
                durationText = "7 min",
                line = line,
                departText = "9:28 AM",
                arriveText = "9:35 AM",
                headsign = "Embarcadero Station",
                boardStop = TransitStopTime(
                    name = "Metro Van Ness Station",
                    code = "15419",
                    timeText = "9:28 AM",
                    scheduledText = "9:24 AM",
                    location = vanNess,
                    delayMin = 4,
                ),
                alightStop = TransitStopTime(
                    name = "Metro Embarcadero Station",
                    code = "16992",
                    timeText = "9:35 AM",
                    scheduledText = "9:29 AM",
                    location = embarcadero,
                    delayMin = 6,
                ),
                intermediateStops = listOf(
                    TransitStopTime("Metro Civic Center Station/Downtn", location = civicCenter),
                    TransitStopTime("Metro Powell Station/Downtown", location = powell),
                    TransitStopTime("Metro Montgomery Station/Downtown", location = montgomery),
                ),
                numStops = 4,
                delayText = "4 min late",
                path = listOf(vanNess, civicCenter, powell, montgomery, embarcadero),
            )
            val walkToDestination = TransitStep(
                mode = TransitMode.WALK,
                durationText = "4 min",
                walkFrom = embarcadero,
                walkTo = destination,
                path = listOf(embarcadero, destination),
            )
            return TransitItinerary(
                departureEpochSec = 1_792_945_620L,
                arrivalEpochSec = 1_792_946_340L,
                departureText = "9:27 AM",
                arrivalText = "9:39 AM",
                durationText = "12 min",
                agency = "San Francisco Municipal Transportation Agency",
                lines = listOf(line),
                steps = listOf(walkToMetro, ride, walkToDestination),
            )
        }
}
