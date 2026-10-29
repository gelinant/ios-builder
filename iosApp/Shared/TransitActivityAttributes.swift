import ActivityKit
import Foundation

/// Shared by the app and the existing navigation widget extension. Stop names and line colors are
/// display data only. No coordinates, push token or backend channel is part of the activity.
public struct TransitActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var sessionId: Int64
        public var legIndex: Int
        public var legCount: Int
        public var legKind: String
        public var lineName: String
        public var lineColorHex: String?
        public var lineTextColorHex: String?
        public var direction: String
        public var instruction: String
        public var nextStop: String
        public var boarded: Bool
        public var stopsRemaining: Int
        public var scheduledDeparture: String?
        public var estimatedDeparture: String?
        public var scheduledArrival: String?
        public var estimatedArrival: String?
        public var overallArrivalText: String?
        public var overallArrivalDate: Date?
        public var overallArrivalIsEstimate: Bool
        public var delayMinutes: Int?
        public var arrived: Bool
        public var progress: Double
        public var updatedAt: Date

        public init(
            sessionId: Int64,
            legIndex: Int,
            legCount: Int,
            legKind: String,
            lineName: String,
            lineColorHex: String?,
            lineTextColorHex: String?,
            direction: String,
            instruction: String,
            nextStop: String,
            boarded: Bool,
            stopsRemaining: Int,
            scheduledDeparture: String?,
            estimatedDeparture: String?,
            scheduledArrival: String?,
            estimatedArrival: String?,
            overallArrivalText: String?,
            overallArrivalDate: Date?,
            overallArrivalIsEstimate: Bool,
            delayMinutes: Int?,
            arrived: Bool,
            progress: Double,
            updatedAt: Date
        ) {
            self.sessionId = sessionId
            self.legIndex = legIndex
            self.legCount = legCount
            self.legKind = legKind
            self.lineName = lineName
            self.lineColorHex = lineColorHex
            self.lineTextColorHex = lineTextColorHex
            self.direction = direction
            self.instruction = instruction
            self.nextStop = nextStop
            self.boarded = boarded
            self.stopsRemaining = stopsRemaining
            self.scheduledDeparture = scheduledDeparture
            self.estimatedDeparture = estimatedDeparture
            self.scheduledArrival = scheduledArrival
            self.estimatedArrival = estimatedArrival
            self.overallArrivalText = overallArrivalText
            self.overallArrivalDate = overallArrivalDate
            self.overallArrivalIsEstimate = overallArrivalIsEstimate
            self.delayMinutes = delayMinutes
            self.arrived = arrived
            self.progress = progress
            self.updatedAt = updatedAt
        }
    }

    public var destinationName: String

    public init(destinationName: String) {
        self.destinationName = destinationName
    }
}
