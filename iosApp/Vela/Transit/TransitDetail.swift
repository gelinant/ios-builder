import Foundation
import VelaCore

/// One stop on a selected itinerary, with the timetable time and the feed's live time kept apart.
struct TransitDetailStop: Identifiable, Equatable {
    let id: Int
    let name: String
    let code: String?
    let timeText: String?
    let scheduledText: String?
    let delayMinutes: Int?
    let canceled: Bool
}

/// One walk or ride of the selected itinerary. Ride legs carry their board and alight stops and
/// the intermediate stops the planner returned; walk legs stay a simple walk (their turn-by-turn
/// steps are not fetched on iOS yet).
struct TransitDetailLeg: Identifiable, Equatable {
    let id: Int
    let kind: String
    let line: String?
    let color: String?
    let textColor: String?
    let durationText: String?
    let distanceText: String?
    let departText: String?
    let arriveText: String?
    let headsign: String?
    let delayText: String?
    let stopCount: Int
    let board: TransitDetailStop?
    let alight: TransitDetailStop?
    let intermediate: [TransitDetailStop]

    var isWalk: Bool { kind == "WALK" }
}

/// The selected transit itinerary as the detail sheet shows it. Alerts and fare appear only when
/// the planner supplied them; the sheet never fills them in.
struct TransitDetail: Equatable {
    let departureText: String?
    let arrivalText: String?
    let durationText: String?
    let agency: String?
    let fare: String?
    let alerts: [String]
    let legs: [TransitDetailLeg]

    init?(_ trip: TransitItinerary) {
        let mapped = trip.steps.enumerated().map { index, step in
            TransitDetailLeg(
                id: index,
                kind: step.mode.name,
                line: step.line?.name,
                color: step.line?.colorHex,
                textColor: step.line?.textColorHex,
                durationText: step.durationText,
                distanceText: step.distanceText,
                departText: step.departText,
                arriveText: step.arriveText,
                headsign: step.headsign,
                delayText: step.delayText,
                stopCount: step.numStops?.intValue ?? -1,
                board: step.boardStop.map { Self.stop($0, id: index * 1000) },
                alight: step.alightStop.map { Self.stop($0, id: index * 1000 + 1) },
                intermediate: step.intermediateStops.enumerated().map { i, stop in
                    Self.stop(stop, id: index * 1000 + 2 + i)
                })
        }
        guard mapped.contains(where: { !$0.isWalk }) else { return nil }
        departureText = trip.departureText
        arrivalText = trip.arrivalText
        durationText = trip.durationText
        agency = trip.agency
        fare = trip.fare
        alerts = trip.alerts
        legs = mapped
    }

    private static func stop(_ stop: TransitStopTime, id: Int) -> TransitDetailStop {
        TransitDetailStop(
            id: id,
            name: stop.name,
            code: stop.code,
            timeText: stop.timeText,
            scheduledText: stop.scheduledText,
            delayMinutes: stop.delayMin?.intValue,
            canceled: stop.canceled)
    }
}
