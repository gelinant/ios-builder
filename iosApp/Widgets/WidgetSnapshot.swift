import Foundation

/// The only payload the Home Screen widgets read. The app writes it to the App Group; the
/// extension never queries Google or Transitous itself. It is compiled into the app, the widget
/// extension and the unit tests, so both sides share one Codable definition.
struct WidgetSnapshot: Codable, Equatable {
    var shortcuts: [WidgetShortcut] = []
    var parking: WidgetParking?
    var board: WidgetBoard?
    var writtenAt: Date = .distantPast

    static let empty = WidgetSnapshot()

    /// A filled sample for widget previews and for the unit tests. Coordinates are the Davis and
    /// Sacramento fixtures already used by the app's tests.
    static let preview: WidgetSnapshot = {
        let now = Date()
        let board = WidgetBoard(
            stopName: "Davis Downtown",
            latitude: 38.5449,
            longitude: -121.7405,
            fetchedAt: now.addingTimeInterval(-120),
            refreshFailed: false,
            lines: [
                WidgetBoardLine(
                    label: "E",
                    mode: "BUS",
                    headsign: "Sacramento",
                    color: "#1F7A3D",
                    departures: [
                        WidgetDeparture(epochSec: epoch(now, plus: 240), realtime: true, clockText: "09:45"),
                        WidgetDeparture(epochSec: epoch(now, plus: 900), realtime: false, clockText: "09:56"),
                    ]),
                WidgetBoardLine(
                    label: "Z",
                    mode: "BUS",
                    headsign: "UC Davis",
                    color: "#B34A1E",
                    departures: [
                        WidgetDeparture(epochSec: epoch(now, plus: 480), realtime: false, clockText: "09:49"),
                    ]),
            ])
        return WidgetSnapshot(
            shortcuts: [
                WidgetShortcut(kind: .home, name: "Home", address: "620 G St, Davis, CA 95616"),
                WidgetShortcut(kind: .work, name: "Work", address: "1 Capitol Mall, Sacramento, CA 95814"),
            ],
            parking: WidgetParking(
                latitude: 38.5449, longitude: -121.7405,
                savedAt: now.addingTimeInterval(-2 * 3600 - 5 * 60)),
            board: board,
            writtenAt: now)
    }()

    private static func epoch(_ date: Date, plus seconds: TimeInterval) -> Int64 {
        Int64(date.addingTimeInterval(seconds).timeIntervalSince1970)
    }
}

/// One Home or Work shortcut. The deep link is the app's existing `navigate` route, not a second
/// router: the app resolves the shortcut from its own SavedStore when the link arrives.
struct WidgetShortcut: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case home
        case work
    }

    var kind: Kind
    var name: String
    var address: String?

    var id: String { kind.rawValue }

    var deepLink: URL {
        URL(string: "vela://navigate/\(kind.rawValue)")!
    }
}

/// The parked car. SavedStore keeps only a point and a timestamp, so the widget shows the point
/// and the age instead of inventing a street name the app never stored.
struct WidgetParking: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var savedAt: Date

    var deepLink: URL { URL(string: "vela://parking")! }

    var coordinateText: String {
        String(format: "%.4f, %.4f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    /// Whole hours and minutes since the car was parked, for a stable widget label and tests.
    func ageComponents(from now: Date) -> (hours: Int, minutes: Int) {
        let seconds = max(0, now.timeIntervalSince(savedAt))
        return (Int(seconds) / 3600, (Int(seconds) % 3600) / 60)
    }

    func ageText(from now: Date) -> String {
        let (hours, minutes) = ageComponents(from: now)
        if hours > 0 && minutes > 0 { return "\(hours) h \(minutes) min" }
        if hours > 0 { return "\(hours) h" }
        return "\(minutes) min"
    }
}

/// One departure of a board row. Epoch seconds let the widget recompute the countdown at each
/// timeline entry instead of trusting a minutes value captured when the app last refreshed.
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

    func minutesText(from now: Date) -> String {
        let minutes = minutes(from: now)
        return minutes <= 0 ? "Now" : "\(minutes) min"
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

/// The stop the user opened last in Vela. Times come from the Transitous open feed fetched by the
/// app; the timestamp is what makes the widget honest about its age.
struct WidgetBoard: Codable, Equatable {
    var stopName: String
    var latitude: Double
    var longitude: Double
    var fetchedAt: Date?
    var refreshFailed: Bool
    var lines: [WidgetBoardLine]

    var deepLink: URL { URL(string: "vela://board")! }

    static let staleAfter: TimeInterval = 20 * 60

    func isStale(asOf now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return refreshFailed || now.timeIntervalSince(fetchedAt) > Self.staleAfter
    }

    /// "Updated 09:41" or "No update yet"; the caller adds the stale warning around it.
    func updatedText() -> String {
        guard let fetchedAt else { return "No update yet" }
        return "Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))"
    }
}

/// Builders kept free of Kotlin and SwiftUI so the unit tests cover exactly what the app publishes.
enum WidgetSnapshotBuilder {
    static func shortcuts(home: WidgetShortcut?, work: WidgetShortcut?) -> [WidgetShortcut] {
        [home, work].compactMap { $0 }
    }

    /// Keeps departures that have not left the stop yet, at most three per line, drops empty
    /// lines and shows at most three lines by soonest departure. The stop itself is kept even when
    /// the feed answered with no departures so the widget can still open the board.
    static func board(
        stopName: String,
        latitude: Double,
        longitude: Double,
        fetchedAt: Date?,
        refreshFailed: Bool,
        lines: [WidgetBoardLine],
        now: Date
    ) -> WidgetBoard? {
        guard !stopName.isEmpty else { return nil }
        let horizon = now.addingTimeInterval(-60)
        let kept = lines.compactMap { line -> WidgetBoardLine? in
            let departures = line.departures
                .filter { TimeInterval($0.epochSec) >= horizon.timeIntervalSince1970 }
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
            stopName: stopName,
            latitude: latitude,
            longitude: longitude,
            fetchedAt: fetchedAt,
            refreshFailed: refreshFailed,
            lines: Array(kept))
    }
}

/// The App Group payload. UserDefaults keeps one JSON value; writing it is one atomic
/// `set(_:forKey:)`, and the extension's provider only ever reads it.
struct WidgetSnapshotStore {
    static let appGroupID = "group.app.vela.ios"
    static let defaultsKey = "widget.snapshot.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// nil when the App Group is not provisioned (for example a sideloaded build whose profile
    /// lacks the group): the widgets then show their setup state instead of stale data.
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
