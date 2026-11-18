import Foundation
import VelaCore

/// One line of a stop board the app has seen, kept after the board closed so its label stays
/// searchable. The next departures are a snapshot: the board itself is the live surface.
struct UnifiedBoardLine: Equatable {
    let label: String?
    let mode: String
    let headsign: String?
    let color: String?
    let nextMinutes: [Int]
}

/// The last stop board, with the stop it belongs to.
struct UnifiedBoardMemory: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let lines: [UnifiedBoardLine]

    /// A board with no line has nothing to offer the search; the stop still does.
    var hasLines: Bool { !lines.isEmpty }
}

/// The local half of the unified search: rows built from the stores the app already holds, with
/// no request. [SearchModel] pushes the result through `UnifiedSearchStore.setLocal` whenever
/// saved places, transit stops or the remembered board change.
enum UnifiedLocalSources {
    /// Recents first, then list places, then quick saves, as Android orders the user's own data
    /// (SRCH-CARDS). A place keeps its first, strongest row.
    static func items(saved: SavedState, stops: [TransitStopPin], board: UnifiedBoardMemory?) -> [UnifiedHit] {
        var out: [UnifiedHit] = []
        var seen = Set<String>()

        for recent in saved.recentPlaces {
            let place = recent.place
            guard seen.insert(place.id).inserted else { continue }
            out.append(UnifiedHits.shared.recent(
                id: place.id, title: place.name, subtitle: place.address ?? "Recent",
                lat: place.lat, lng: place.lng, placeId: place.id, featureId: nil))
        }

        let listNames = Dictionary(uniqueKeysWithValues: saved.lists.map { ($0.id, $0.name) })
        for list in saved.lists {
            for place in list.places {
                guard seen.insert("\(list.id):\(place.id)").inserted else { continue }
                let inList = listNames[list.id].map { "In \($0)" }
                out.append(UnifiedHits.shared.saved(
                    id: "\(list.id):\(place.id)", title: place.name,
                    subtitle: place.address ?? inList, lat: place.lat, lng: place.lng,
                    placeId: place.id, featureId: place.featureId, listId: list.id))
            }
        }

        for place in saved.saved {
            guard seen.insert(place.id).inserted else { continue }
            out.append(UnifiedHits.shared.saved(
                id: place.id, title: place.name, subtitle: place.address ?? "Saved",
                lat: place.lat, lng: place.lng, placeId: place.id, featureId: nil, listId: nil))
        }

        for list in saved.lists {
            out.append(UnifiedHits.shared.list(
                id: list.id, name: list.name, count: Int32(list.places.count)))
        }

        for stop in stops {
            out.append(UnifiedHits.shared.localStop(
                id: stop.stopId, name: stop.name, subtitle: stopSubtitle(stop.modes),
                lat: stop.latitude, lng: stop.longitude))
        }

        if let board {
            // The map's own stop pin already names this stop when it is in view.
            if !stops.contains(where: { $0.name == board.name }) {
                out.append(UnifiedHits.shared.localStop(
                    id: "board:\(board.name)", name: board.name, subtitle: "Transit stop, last board",
                    lat: board.latitude, lng: board.longitude))
            }
            for line in board.lines {
                guard let label = line.label, !label.isEmpty else { continue }
                out.append(UnifiedHits.shared.line(
                    id: "\(board.name)|\(label)|\(line.headsign ?? "")",
                    label: label, headsign: line.headsign, stopName: board.name,
                    lat: board.latitude, lng: board.longitude,
                    detail: lineDetail(line)))
            }
        }

        out += settingsItems()
        return out
    }

    /// Every Settings row the About hub indexes, plus the one form row it does not name yet.
    static func settingsItems() -> [UnifiedHit] {
        var out = SettingsIndex.entries.map { entry in
            UnifiedHits.shared.setting(
                anchor: entry.anchor, label: entry.label, section: entry.section,
                keywords: entry.keywords)
        }
        out.append(UnifiedHits.shared.setting(
            anchor: "settings-quick-chips", label: "Quick search buttons", section: "Search",
            keywords: "quick chips categories shortcuts row map"))
        return out
    }

    private static func stopSubtitle(_ modes: [String]) -> String {
        let labels = modes.map { mode -> String in
            let upper = mode.uppercased()
            if upper.contains("RAIL") || upper == "TRAIN" || upper == "LONG_DISTANCE" { return "Train" }
            if upper == "TRAM" || upper == "SUBWAY" || upper == "METRO" { return "Metro" }
            if upper == "FERRY" { return "Ferry" }
            return "Bus"
        }
        var unique: [String] = []
        for label in labels where !unique.contains(label) { unique.append(label) }
        return unique.isEmpty ? "Transit stop" : "\(unique.prefix(2).joined(separator: ", ")) · Transit stop"
    }

    private static func lineDetail(_ line: UnifiedBoardLine) -> String? {
        guard !line.nextMinutes.isEmpty else { return nil }
        let next = line.nextMinutes.prefix(2).map { $0 <= 0 ? "Now" : "\($0) min" }
        return "Next \(next.joined(separator: ", "))"
    }
}
