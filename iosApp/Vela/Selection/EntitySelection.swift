import CoreLocation
import Foundation

/// The kind of entity one selection can name. The map and every list share this vocabulary, so a
/// row and a symbol cannot disagree about what is selected.
enum EntitySelectionKind: String, CaseIterable {
    case vehicle
    case stop
    case line
    case place
    case saved
    case camera
    case ship
    case aircraft
    case satellite
}

/// Which surface produced the current selection. A map selection is already under the finger and
/// is not recentred; a list selection asks the map to reveal the entity when it is off screen.
enum EntitySelectionSource: String {
    case map
    case list
}

/// One selected entity, with its identity, its anchor and the surface that chose it. A feed id is
/// kept verbatim when one exists; a surface with no id passes the stable key it does have.
struct EntitySelectionValue: Equatable {
    let kind: EntitySelectionKind
    let id: String
    let label: String
    let latitude: Double
    let longitude: Double
    let source: EntitySelectionSource

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The key a list row can compare against without rebuilding the value.
    var key: String { "\(kind.rawValue):\(id)" }
}

/// THE one selection of the app. The map writes it when a symbol is tapped; the transit panels
/// write it when a row is tapped; both read it. Selecting another entity replaces the previous one,
/// and clearing it clears every surface, because there is nothing else to clear. The state lives
/// outside every view, so a sheet detent change and the globe/Mercator style reload cannot lose it.
///
/// Main thread only: map gestures, list taps and SwiftUI bodies all run there.
final class EntitySelection: ObservableObject {
    static let shared = EntitySelection()
    /// Posted after every replacement and every clear. The map listens because its halo is a style
    /// layer, not a SwiftUI view.
    static let changed = Notification.Name("vela.selection.changed")

    @Published private(set) var value: EntitySelectionValue?
    /// A cheap observation token for SwiftUI `onChange` and for the map's halo pass.
    @Published private(set) var revision = 0

    private init() {}

    /// Replaces the selection. Returns the stored value so a caller can read the normalised key.
    @discardableResult
    func select(
        kind: EntitySelectionKind, id: String, label: String,
        latitude: Double, longitude: Double, source: EntitySelectionSource
    ) -> EntitySelectionValue {
        let next = EntitySelectionValue(
            kind: kind, id: id, label: label,
            latitude: latitude, longitude: longitude, source: source)
        value = next
        revision &+= 1
        NotificationCenter.default.post(name: Self.changed, object: self)
        return next
    }

    /// Clears both sides. A no-op when nothing is selected, so an empty-map tap does not publish a
    /// pointless revision.
    func clear() {
        guard value != nil else { return }
        value = nil
        revision &+= 1
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    func isSelected(_ kind: EntitySelectionKind, id: String) -> Bool {
        guard let value, value.kind == kind else { return false }
        return value.id == id
    }

    /// A stop can reach a surface without its feed id (a tap on a reachability dot), so a row also
    /// accepts a selection whose anchor sits on the same stop. The radius is deliberately small:
    /// the nearest stop wins, never a stop from another street.
    func matches(
        kind: EntitySelectionKind, id: String? = nil,
        latitude: Double, longitude: Double, toleranceMeters: Double = 50
    ) -> Bool {
        guard let value, value.kind == kind else { return false }
        if let id, !id.isEmpty, value.id == id { return true }
        let meters = Self.distanceMeters(
            from: value.coordinate,
            to: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        return meters <= toleranceMeters
    }

    /// The line evidence the UI scenarios and the tap chain read. `selection_halo` says whether the
    /// map is drawing the ring for this value, which is the same as having a selection.
    var debugLine: String {
        guard let value else {
            return "selection_source=none selection_kind=none selection_halo=0 selection_id=-"
        }
        let id = value.id.isEmpty ? "-" : value.id.replacingOccurrences(of: " ", with: "_")
        return "selection_source=\(value.source.rawValue)"
            + " selection_kind=\(value.kind.rawValue)"
            + " selection_halo=1 selection_id=\(id)"
    }

    private static func distanceMeters(
        from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D
    ) -> Double {
        let earth = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earth * asin(min(1, sqrt(h)))
    }
}
