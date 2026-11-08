import Foundation
import VelaCore

enum TransitActivityTiming {
    static let updateInterval: TimeInterval = 5
    static let arrivalDismissalDelay: TimeInterval = 8
    static let staleAfter: TimeInterval = 60
}

/// Swift-owned input for reducer tests and for the compact in-app card. Production copies the
/// Kotlin TransitState once per emission; no itinerary or coordinate is held by ActivityKit.
struct TransitActivityInput {
    var active = false
    var arrived = false
    var destinationName = ""
    var sessionId: Int64 = 0
    var legIndex = -1
    var legCount = 0
    var legKind = "WALK"
    var lineName = ""
    var lineColorHex: String?
    var lineTextColorHex: String?
    var direction = ""
    var nextStop = ""
    var walkingTarget = ""
    var alightStop = ""
    var boarded = false
    var stopsRemaining = -1
    var scheduledDeparture: String?
    var estimatedDeparture: String?
    var scheduledArrival: String?
    var estimatedArrival: String?
    var overallArrivalText: String?
    var overallArrivalEpochSec: Int64?
    var overallArrivalIsEstimate = false
    var delayMinutes: Int?
    var progress = 0.0

    init() {}

    init(_ state: TransitState) {
        let current = state.current()
        let ride = state.displayRide()
        active = state.active
        arrived = state.arrived
        destinationName = state.destinationName
        sessionId = Int64(state.sessionId)
        legIndex = Int(state.legIndex)
        legCount = state.legs.count
        legKind = current?.kind ?? "WALK"
        lineName = ride?.line ?? ""
        lineColorHex = ride?.color
        lineTextColorHex = ride?.textColor
        direction = ride?.direction ?? ""
        walkingTarget = state.walkTarget ?? ""
        alightStop = current?.alightStop ?? ""
        boarded = state.boarded
        if legKind == "WALK" {
            nextStop = walkingTarget
        } else if !boarded, let board = current?.boardStop {
            nextStop = board
        } else {
            nextStop = state.nextStop ?? current?.alightStop ?? ""
        }
        stopsRemaining = Int(state.stopsRemaining)
        scheduledDeparture = ride?.scheduledDeparture
        estimatedDeparture = ride?.estimatedDeparture
        scheduledArrival = ride?.scheduledArrival
        estimatedArrival = ride?.estimatedArrival
        overallArrivalText = state.overallArrivalText
        overallArrivalEpochSec = state.overallArrivalEpochSec >= 0 ? Int64(state.overallArrivalEpochSec) : nil
        overallArrivalIsEstimate = state.overallArrivalIsEstimate
        delayMinutes = ride?.delayMinutes?.intValue
        progress = state.progress
    }
}

enum TransitActivityStateMapper {
    struct Sample: Equatable {
        var active: Bool
        var destinationName: String
        var sessionId: Int64
        var content: TransitActivityAttributes.ContentState
    }

    static func map(_ input: TransitActivityInput, now: Date = Date()) -> Sample {
        let instruction: String
        if input.arrived {
            instruction = "You have arrived"
        } else if input.legKind == "WALK" {
            instruction = input.walkingTarget.isEmpty ? "Walk" : "Walk to \(input.walkingTarget)"
        } else if !input.boarded {
            instruction = input.nextStop.isEmpty ? "Board \(input.lineName)" : "Board at \(input.nextStop)"
        } else if input.stopsRemaining == 1 || (!input.alightStop.isEmpty && input.nextStop == input.alightStop) {
            instruction = input.nextStop.isEmpty ? "Get off at the next stop" : "Get off at \(input.nextStop)"
        } else {
            instruction = input.nextStop.isEmpty ? "Ride to the next stop" : "Next stop: \(input.nextStop)"
        }
        let arrivalDate = input.overallArrivalEpochSec.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return Sample(
            active: input.active,
            destinationName: input.destinationName,
            sessionId: input.sessionId,
            content: TransitActivityAttributes.ContentState(
                sessionId: input.sessionId,
                legIndex: input.legIndex,
                legCount: input.legCount,
                legKind: input.legKind,
                lineName: input.lineName,
                lineColorHex: input.lineColorHex,
                lineTextColorHex: input.lineTextColorHex,
                direction: input.direction,
                instruction: instruction,
                nextStop: input.nextStop,
                boarded: input.boarded,
                stopsRemaining: input.stopsRemaining,
                scheduledDeparture: input.scheduledDeparture,
                estimatedDeparture: input.estimatedDeparture,
                scheduledArrival: input.scheduledArrival,
                estimatedArrival: input.estimatedArrival,
                overallArrivalText: input.overallArrivalText,
                overallArrivalDate: arrivalDate,
                overallArrivalIsEstimate: input.overallArrivalIsEstimate,
                delayMinutes: input.delayMinutes,
                arrived: input.arrived,
                progress: input.progress.isFinite ? min(1, max(0, input.progress)) : 0,
                updatedAt: now))
    }
}

enum TransitActivityUpdatePolicy {
    static func shouldUpdate(
        previous: TransitActivityStateMapper.Sample,
        candidate: TransitActivityStateMapper.Sample,
        now: Date
    ) -> Bool {
        let old = previous.content
        let new = candidate.content
        if previous.sessionId != candidate.sessionId
            || old.legIndex != new.legIndex
            || old.legKind != new.legKind
            || old.lineName != new.lineName
            || old.lineColorHex != new.lineColorHex
            || old.direction != new.direction
            || old.instruction != new.instruction
            || old.nextStop != new.nextStop
            || old.boarded != new.boarded
            || old.stopsRemaining != new.stopsRemaining
            || old.scheduledDeparture != new.scheduledDeparture
            || old.estimatedDeparture != new.estimatedDeparture
            || old.scheduledArrival != new.scheduledArrival
            || old.estimatedArrival != new.estimatedArrival
            || old.delayMinutes != new.delayMinutes
            || old.arrived != new.arrived {
            return true
        }
        guard now.timeIntervalSince(old.updatedAt) >= TransitActivityTiming.updateInterval else {
            return false
        }
        return old.overallArrivalText != new.overallArrivalText
            || old.overallArrivalDate != new.overallArrivalDate
            || old.overallArrivalIsEstimate != new.overallArrivalIsEstimate
            || old.progress != new.progress
    }
}

struct TransitActivityReducer {
    enum Phase: Equatable {
        case idle
        case guiding
        case arrived
    }

    enum Action: Equatable {
        case start(TransitActivityStateMapper.Sample)
        case update(TransitActivityStateMapper.Sample)
        case arrive(TransitActivityStateMapper.Sample, dismissalDate: Date)
        case end
    }

    private(set) var phase: Phase = .idle
    private var lastPublished: TransitActivityStateMapper.Sample?

    mutating func publish(_ sample: TransitActivityStateMapper.Sample, now: Date) -> Action? {
        guard sample.active else {
            guard phase != .idle else {
                lastPublished = nil
                return nil
            }
            phase = .idle
            lastPublished = nil
            return .end
        }
        if sample.content.arrived {
            guard phase != .arrived else { return nil }
            phase = .arrived
            lastPublished = sample
            return .arrive(sample, dismissalDate: now.addingTimeInterval(TransitActivityTiming.arrivalDismissalDelay))
        }
        if phase == .guiding, let previous = lastPublished {
            if previous.sessionId != sample.sessionId {
                lastPublished = sample
                return .start(sample)
            }
            guard TransitActivityUpdatePolicy.shouldUpdate(previous: previous, candidate: sample, now: now) else {
                return nil
            }
            lastPublished = sample
            return .update(sample)
        }
        phase = .guiding
        lastPublished = sample
        return .start(sample)
    }
}

enum TransitActivityStalePolicy {
    static func shouldAdopt(_ state: TransitActivityAttributes.ContentState, now: Date) -> Bool {
        now.timeIntervalSince(state.updatedAt) < TransitActivityTiming.staleAfter
    }

    static func expiration(of state: TransitActivityAttributes.ContentState) -> Date {
        state.updatedAt.addingTimeInterval(TransitActivityTiming.staleAfter)
    }
}
