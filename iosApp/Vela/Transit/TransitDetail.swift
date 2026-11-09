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
    /// The planner's own mode name ("REGIONAL_RAIL", "COACH"...), nil when it gave only the coarse one.
    let modeName: String?
    /// The leg's operator when the planner named one per leg; the itinerary agency is the first only.
    let agency: String?
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
    /// The planner's own clock for this leg, for the waiting time between an arrival and a departure.
    let departEpochSec: Int64?
    let arriveEpochSec: Int64?

    var isWalk: Bool { kind == "WALK" }

    /// The leg's vehicle as the row names it: glyph, mode name and "Bus 38" / "M1" / "RER B".
    var mode: TransitLegMode { TransitLegMode.of(kind: modeName ?? kind) }

    /// The headline the detail sheet and the trip screen show for this leg.
    var title: String { mode.title(line: line, agency: agency) }
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
                modeName: step.modeName ?? step.line?.mode.name,
                agency: step.agencyName,
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
                },
                departEpochSec: step.departEpochSec?.int64Value,
                arriveEpochSec: step.arriveEpochSec?.int64Value)
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

    /// The whole trip as "Walk · M1 · RER A · Walk", for the sheet's header strip.
    var modeSequence: String {
        TransitLegMode.sequence(legs.map {
            (kind: $0.modeName ?? $0.kind, line: $0.line, agency: $0.agency)
        })
    }

    /// The ride legs, in travel order; the transfer rows sit between them.
    var rides: [TransitDetailLeg] { legs.filter { !$0.isWalk } }

    /// The number of transfers: one fewer than the number of rides.
    var transferCount: Int { max(0, rides.count - 1) }

    /// The planned minutes between the arrival of [leg] and the departure of the next ride, nil when
    /// the planner gave no clock for either.
    func waitMinutes(after leg: TransitDetailLeg) -> Int? {
        guard let arrival = leg.arriveEpochSec else { return nil }
        guard let next = legs.drop { $0.id <= leg.id }.first(where: { !$0.isWalk }),
              let departure = next.departEpochSec else { return nil }
        return max(0, Int((departure - arrival) / 60))
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
