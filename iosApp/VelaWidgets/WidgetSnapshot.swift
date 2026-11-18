import Foundation

/// The only payload shared with the Home Screen extension. The app writes it to the App Group;
/// the widget never asks Google, Transitous or Core Location for anything. This file is compiled
/// into both the app and the extension, so both sides share one Codable definition.
struct WidgetSnapshot: Codable, Equatable {
    var parking: WidgetParking?
    var board: WidgetBoard?
    /// The last position the app already held, never a fresh request made by the widget.
    var location: WidgetLocation?
    var writtenAt: Date = .distantPast

    static let empty = WidgetSnapshot()

    /// A filled sample for the widget gallery and the provider placeholder. It is never read from
    /// the App Group and never replaces real data.
    static var preview: WidgetSnapshot {
        let now = Date()
        let board = WidgetBoard(
            stopName: "Davis Downtown",
            latitude: 38.5449,
            longitude: -121.7405,
            fetchedAt: now.addingTimeInterval(-2 * 60),
            offline: false,
            refreshFailed: false,
            lines: [
                WidgetBoardLine(
                    label: "E",
                    mode: "BUS",
                    headsign: "Sacramento",
                    color: "#1F7A3D",
                    departures: [
                        WidgetDeparture(
                            epochSec: Int64(now.addingTimeInterval(4 * 60).timeIntervalSince1970),
                            realtime: true,
                            clockText: nil),
                    ]),
                WidgetBoardLine(
                    label: "Z",
                    mode: "BUS",
                    headsign: "UC Davis",
                    color: "#B34A1E",
                    departures: [
                        WidgetDeparture(
                            epochSec: Int64(now.addingTimeInterval(9 * 60).timeIntervalSince1970),
                            realtime: false,
                            clockText: nil),
                    ]),
            ])
        return WidgetSnapshot(
            parking: WidgetParking(
                latitude: 38.5449,
                longitude: -121.7405,
                savedAt: now.addingTimeInterval(-2 * 3600 - 5 * 60)),
            board: board,
            location: WidgetLocation(
                latitude: 38.5462,
                longitude: -121.7391,
                fixedAt: now.addingTimeInterval(-5 * 60)),
            writtenAt: now)
    }

    /// The last position the app received from Core Location. The fix time travels with the
    /// coordinates so the widget can refuse to draw a distance from an old position.
    struct WidgetLocation: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var fixedAt: Date

        /// Older than a quarter of an hour is not a position the widget is willing to turn into
        /// a distance, even though the app may still hold it.
        static let maxAge: TimeInterval = 15 * 60

        func isFresh(asOf now: Date) -> Bool {
            let age = now.timeIntervalSince(fixedAt)
            return age >= -60 && age <= Self.maxAge
        }

        /// Straight-line distance to a point, in metres. The widget labels it as a distance and
        /// never turns it into an ETA or a route.
        func distanceMeters(toLatitude: Double, longitude: Double) -> Double {
            let earthRadius = 6_371_000.0
            let lat1 = latitude * .pi / 180
            let lat2 = toLatitude * .pi / 180
            let deltaLat = (toLatitude - latitude) * .pi / 180
            let deltaLng = (longitude - self.longitude) * .pi / 180
            let a = sin(deltaLat / 2) * sin(deltaLat / 2)
                + cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2)
            return 2 * earthRadius * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        }
    }
}

/// The parked car. SavedStore keeps a point and a timestamp and nothing else, so the widget shows
/// that point's age instead of inventing a street name the app never stored.
struct WidgetParking: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var savedAt: Date

    var deepLink: URL {
        URL(string: "vela://parking")!
    }
}

/// One departure row. Epoch seconds let each timeline entry recompute the countdown instead of
/// trusting a minutes value captured when the app last refreshed.
struct WidgetDeparture: Codable, Equatable, Identifiable {
    var epochSec: Int64
    var realtime: Bool
    var clockText: String?

    var id: Int64 { epochSec }

    func minutes(from now: Date) -> Int {
        let seconds = TimeInterval(epochSec) - now.timeIntervalSince1970
        if seconds <= 0 { return 0 }
        return Int((seconds + 59) / 60)
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(epochSec))
    }
}

struct WidgetBoardLine: Codable, Equatable, Identifiable {
    var label: String?
    var mode: String
    var headsign: String?
    var color: String?
    var departures: [WidgetDeparture]

    var id: String {
        "\(label ?? "?")|\(mode)|\(headsign ?? "")|\(departures.first?.epochSec ?? 0)"
    }
}

/// The last stop whose departures the user opened in Vela. It is not a pin: the app has no pin
/// action, so the widget says "last stop" in its documentation and never claims otherwise.
struct WidgetBoard: Codable, Equatable {
    var stopName: String
    var latitude: Double
    var longitude: Double
    var fetchedAt: Date?
    /// True when the app is showing a cached board because the feed did not answer.
    var offline: Bool
    var refreshFailed: Bool
    var lines: [WidgetBoardLine]

    var deepLink: URL {
        URL(string: "vela://board")!
    }

    static let staleAfter: TimeInterval = 20 * 60

    /// A board without a fetch time is not fresh by definition. A failed refresh or a cached feed
    /// is stale immediately, even when the cache was written seconds ago.
    func isStale(asOf now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return refreshFailed || offline || now.timeIntervalSince(fetchedAt) > Self.staleAfter
    }

    func ageMinutes(asOf now: Date) -> Int {
        guard let fetchedAt else { return -1 }
        return max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
    }
}

/// Builders stay free of Kotlin and SwiftUI so the app publishes exactly the shape the widget
/// draws. The widget does no filtering of its own.
enum WidgetSnapshotBuilder {
    static func parking(latitude: Double, longitude: Double, savedAt: Date) -> WidgetParking? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return WidgetParking(latitude: latitude, longitude: longitude, savedAt: savedAt)
    }

    /// Keeps departures that have not left the stop yet, at most three per line, drops lines with
    /// nothing left and keeps at most three lines by soonest departure. The stop itself survives
    /// an empty answer so the widget can still open its board.
    static func board(
        stopName: String,
        latitude: Double,
        longitude: Double,
        fetchedAt: Date?,
        offline: Bool,
        refreshFailed: Bool,
        lines: [WidgetBoardLine],
        now: Date
    ) -> WidgetBoard? {
        let name = stopName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }
        let horizon = now.addingTimeInterval(-60).timeIntervalSince1970
        let kept = lines.compactMap { line -> WidgetBoardLine? in
            let departures = line.departures
                .filter { TimeInterval($0.epochSec) >= horizon }
                .sorted { $0.epochSec < $1.epochSec }
                .prefix(3)
            guard !departures.isEmpty else { return nil }
            var copy = line
            copy.departures = Array(departures)
            return copy
        }
        .sorted { ($0.departures.first?.epochSec ?? Int64.max) < ($1.departures.first?.epochSec ?? Int64.max) }
        .prefix(3)
        return WidgetBoard(
            stopName: name,
            latitude: latitude,
            longitude: longitude,
            fetchedAt: fetchedAt,
            offline: offline,
            refreshFailed: refreshFailed,
            lines: Array(kept))
    }
}

extension WidgetSnapshot {
    /// Content equality ignores the write timestamp: a restart that changes nothing must not
    /// reload every timeline.
    func sameContent(as other: WidgetSnapshot) -> Bool {
        parking == other.parking && board == other.board && location == other.location
    }
}

/// The App Group payload. UserDefaults stores one JSON value, written with one atomic `set`, and
/// the extension only ever reads it. A nil store means the App Group is not provisioned; the
/// widgets then show their setup state instead of the previous data.
struct WidgetSnapshotStore {
    static let appGroupID = "group.app.vela.ios"
    static let defaultsKey = "widget.snapshot.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static var shared: WidgetSnapshotStore? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        return WidgetSnapshotStore(defaults: defaults)
    }

    func load() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    func save(_ snapshot: WidgetSnapshot) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return false }
        defaults.set(data, forKey: Self.defaultsKey)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
