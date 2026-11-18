import Foundation
import VelaCore

enum NavActivityTiming {
    static let updateInterval: TimeInterval = 5
    static let distanceThresholdMeters = 25.0
    static let arrivalDismissalDelay: TimeInterval = 8
    static let staleAfter: TimeInterval = 60
}

/// The small, Swift-owned input used by the reducer tests. Production fills it directly from the
/// Kotlin state, so no route or coordinate crosses into ActivityKit.
struct NavActivityInput {
    var active = false
    var arrived = false
    var travelMode = "DRIVE"
    var maneuverKind = "STRAIGHT"
    var instruction = ""
    var streetName = ""
    var distanceToNextMeters = 0.0
    var routeDistanceMeters = 0.0
    var remainingDistanceMeters = 0.0
    var remainingDurationSeconds = 0.0
    var offRoute = false
    var destinationName = ""
    var routeRevision: Int64 = 0

    init(_ state: NavUiState) {
        active = state.active
        arrived = state.arrived
        travelMode = state.travelMode
        maneuverKind = state.maneuver?.type ?? "STRAIGHT"
        instruction = state.maneuver?.instruction ?? ""
        streetName = state.maneuver?.streetName ?? ""
        distanceToNextMeters = state.maneuver?.distanceMeters ?? 0
        routeDistanceMeters = state.routeDistanceMeters
        remainingDistanceMeters = state.remainingDistanceMeters
        remainingDurationSeconds = state.remainingDurationSeconds
        offRoute = state.offRoute
        destinationName = state.destinationLabel
        routeRevision = state.routeRevision
    }

    init(
        active: Bool = false,
        arrived: Bool = false,
        travelMode: String = "DRIVE",
        maneuverKind: String = "STRAIGHT",
        instruction: String = "",
        streetName: String = "",
        distanceToNextMeters: Double = 0,
        routeDistanceMeters: Double = 0,
        remainingDistanceMeters: Double = 0,
        remainingDurationSeconds: Double = 0,
        offRoute: Bool = false,
        destinationName: String = "",
        routeRevision: Int64 = 0
    ) {
        self.active = active
        self.arrived = arrived
        self.travelMode = travelMode
        self.maneuverKind = maneuverKind
        self.instruction = instruction
        self.streetName = streetName
        self.distanceToNextMeters = distanceToNextMeters
        self.routeDistanceMeters = routeDistanceMeters
        self.remainingDistanceMeters = remainingDistanceMeters
        self.remainingDurationSeconds = remainingDurationSeconds
        self.offRoute = offRoute
        self.destinationName = destinationName
        self.routeRevision = routeRevision
    }
}

enum NavActivityStateMapper {
    struct Sample: Equatable {
        var active: Bool
        var destinationName: String
        var routeRevision: Int64
        var content: NavActivityAttributes.ContentState
    }

    static func map(_ state: NavUiState, now: Date = Date()) -> Sample? {
        map(NavActivityInput(state), now: now)
    }

    static func map(_ input: NavActivityInput, now: Date = Date()) -> Sample? {
        let mode: NavActivityAttributes.Mode
        switch input.travelMode {
        case "DRIVE": mode = .drive
        case "WALK": mode = .walk
        default: return nil
        }
        let routeDistance = finite(input.routeDistanceMeters)
        let remainingDistance = finite(input.remainingDistanceMeters)
        let remainingSeconds = finite(input.remainingDurationSeconds)
        let progress: Double
        if input.arrived {
            progress = 1
        } else if routeDistance > 0 {
            progress = min(1, max(0, (routeDistance - remainingDistance) / routeDistance))
        } else {
            progress = 0
        }
        let kind = input.arrived && input.maneuverKind.isEmpty ? "ARRIVE" : input.maneuverKind
        let instruction = input.arrived && input.instruction.isEmpty ? "You have arrived" : input.instruction
        return Sample(
            active: input.active,
            destinationName: input.destinationName,
            routeRevision: input.routeRevision,
            content: NavActivityAttributes.ContentState(
                maneuverKind: kind,
                instruction: instruction,
                streetName: input.streetName,
                distanceToNextManeuverMeters: finite(input.distanceToNextMeters),
                remainingDistanceMeters: remainingDistance,
                remainingDurationSeconds: remainingSeconds,
                arrivalDate: now.addingTimeInterval(remainingSeconds),
                offRoute: input.offRoute,
                mode: mode,
                progress: progress,
                arrived: input.arrived,
                updatedAt: now))
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}

enum NavActivityUpdatePolicy {
    static func shouldUpdate(
        previous: NavActivityStateMapper.Sample,
        candidate: NavActivityStateMapper.Sample,
        now: Date
    ) -> Bool {
        let old = previous.content
        let new = candidate.content
        if previous.routeRevision != candidate.routeRevision
            || old.maneuverKind != new.maneuverKind
            || old.instruction != new.instruction
            || old.streetName != new.streetName
            || old.offRoute != new.offRoute
            || old.mode != new.mode
            || old.arrived != new.arrived {
            return true
        }
        let nextDelta = abs(old.distanceToNextManeuverMeters - new.distanceToNextManeuverMeters)
        let leftDelta = abs(old.remainingDistanceMeters - new.remainingDistanceMeters)
        if max(nextDelta, leftDelta) >= NavActivityTiming.distanceThresholdMeters {
            return true
        }
        guard now.timeIntervalSince(old.updatedAt) >= NavActivityTiming.updateInterval else {
            return false
        }
        return old.distanceToNextManeuverMeters != new.distanceToNextManeuverMeters
            || old.remainingDistanceMeters != new.remainingDistanceMeters
            || old.remainingDurationSeconds != new.remainingDurationSeconds
            || old.progress != new.progress
    }
}

/// Activity lifecycle independent of ActivityKit. This keeps throttling, arrival and End behavior
/// testable even on a runner where ActivityAuthorizationInfo disables Live Activities.
struct NavActivityReducer {
    enum Phase: Equatable {
        case idle
        case navigating
        case arrived
    }

    enum Action: Equatable {
        case start(NavActivityStateMapper.Sample)
        case update(NavActivityStateMapper.Sample)
        case arrive(NavActivityStateMapper.Sample, dismissalDate: Date)
        case end
    }

    private(set) var phase: Phase = .idle
    private var lastPublished: NavActivityStateMapper.Sample?

    mutating func publish(_ sample: NavActivityStateMapper.Sample?, now: Date) -> Action? {
        guard let sample, sample.active else {
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
            return .arrive(sample, dismissalDate: now.addingTimeInterval(NavActivityTiming.arrivalDismissalDelay))
        }
        guard phase == .navigating, let previous = lastPublished else {
            phase = .navigating
            lastPublished = sample
            return .start(sample)
        }
        guard NavActivityUpdatePolicy.shouldUpdate(previous: previous, candidate: sample, now: now) else {
            return nil
        }
        lastPublished = sample
        return .update(sample)
    }
}

enum NavActivityStalePolicy {
    static func shouldAdopt(_ state: NavActivityAttributes.ContentState, now: Date) -> Bool {
        now.timeIntervalSince(state.updatedAt) < NavActivityTiming.staleAfter
    }

    static func expiration(of state: NavActivityAttributes.ContentState) -> Date {
        state.updatedAt.addingTimeInterval(NavActivityTiming.staleAfter)
    }
}
