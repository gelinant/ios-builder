import ActivityKit
import Foundation

/// Shared by the app and its widget extension. Distances are meters and durations are seconds.
/// No coordinates belong in an ActivityKit state: the extension only renders navigation guidance.
public struct NavActivityAttributes: ActivityAttributes {
    public enum Mode: String, Codable, Hashable {
        case drive
        case walk
    }

    public struct ContentState: Codable, Hashable {
        public var maneuverKind: String
        public var instruction: String
        public var streetName: String
        public var distanceToNextManeuverMeters: Double
        public var remainingDistanceMeters: Double
        public var remainingDurationSeconds: Double
        public var arrivalDate: Date
        public var offRoute: Bool
        public var mode: Mode
        public var progress: Double
        public var arrived: Bool
        public var updatedAt: Date

        public init(
            maneuverKind: String,
            instruction: String,
            streetName: String,
            distanceToNextManeuverMeters: Double,
            remainingDistanceMeters: Double,
            remainingDurationSeconds: Double,
            arrivalDate: Date,
            offRoute: Bool,
            mode: Mode,
            progress: Double,
            arrived: Bool,
            updatedAt: Date
        ) {
            self.maneuverKind = maneuverKind
            self.instruction = instruction
            self.streetName = streetName
            self.distanceToNextManeuverMeters = distanceToNextManeuverMeters
            self.remainingDistanceMeters = remainingDistanceMeters
            self.remainingDurationSeconds = remainingDurationSeconds
            self.arrivalDate = arrivalDate
            self.offRoute = offRoute
            self.mode = mode
            self.progress = progress
            self.arrived = arrived
            self.updatedAt = updatedAt
        }
    }

    public var destinationName: String

    public init(destinationName: String) {
        self.destinationName = destinationName
    }
}
