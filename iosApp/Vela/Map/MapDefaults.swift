import CoreLocation
import Foundation
import SwiftUI

enum MapDefaults {
    /// A local style document generated from the bundled Liberty base. There is deliberately no
    /// remote fallback: a bundle without the generated styles shows the base document instead of
    /// fetching a style from a server.
    static var styleURL: URL {
        MapStyleBuilder.bundledStyleURL()
            ?? MapStyleBuilder.resource("liberty-roboto")
            ?? URL(fileURLWithPath: "/dev/null")
    }

    /// San Francisco, the big-city fixture. A city view, at the zoom a city opens on.
    static let initialCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    static let initialZoom: Double = 12

    /// Credit the Liberty style requires. The map's info button lists the full source attribution.
    static let attribution = "© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors"
    static let attributionURL = URL(string: "https://www.openstreetmap.org/copyright")!
}

/// Settings > Map gestures, "Where the map opens" (START-LOCATION's precedence is unchanged):
/// `here` keeps the whole chain, `last` drops the position step and opens on the last camera,
/// `city` drops both and opens on the city fixture. An explicit target still wins over all three.
enum MapStartView: String, CaseIterable {
    case here
    case last
    case city

    var title: String {
        switch self {
        case .here: return "Where I am"
        case .last: return "Where I left the map"
        case .city: return "A city view"
        }
    }
}

/// The locate, parking and new map controls' shape (issue #797 on Android, key
/// `map_button_shape`): round, the design system default, or square-cornered.
enum MapButtonShape: String, CaseIterable {
    case round
    case square

    var title: String {
        switch self {
        case .round: return "Round"
        case .square: return "Square"
        }
    }

    var cornerRadius: CGFloat {
        self == .square ? 16 : Design.Chrome.actionSize / 2
    }

    var shape: AnyShape {
        self == .square
            ? AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            : AnyShape(Circle())
    }
}

/// The gesture and map-chrome preferences, in the shared `vela_settings` suite so a relaunch
/// reads them back. Every setter posts one notification; MapController applies the change at
/// once instead of waiting for the next camera event.
final class MapGestureSettings: ObservableObject {
    static let shared = MapGestureSettings()
    static let changedNotification = Notification.Name("VelaMapGestureSettingsChanged")

    static let keepNorthUpKey = "keep_north_up"
    static let preferButtonsKey = "prefer_buttons"
    static let buttonShapeKey = "map_button_shape"
    static let startViewKey = "start_view"

    @Published private(set) var keepNorthUp: Bool
    @Published private(set) var preferButtons: Bool
    @Published private(set) var buttonShape: MapButtonShape
    @Published private(set) var startView: MapStartView

    private let defaults: UserDefaults

    init(defaults: UserDefaults = MapGestureSettings.settingsDefaults()) {
        self.defaults = defaults
        keepNorthUp = defaults.bool(forKey: Self.keepNorthUpKey)
        preferButtons = defaults.bool(forKey: Self.preferButtonsKey)
        buttonShape = MapButtonShape(rawValue: defaults.string(forKey: Self.buttonShapeKey) ?? "")
            ?? .round
        startView = MapStartView(rawValue: defaults.string(forKey: Self.startViewKey) ?? "")
            ?? .here
    }

    func setKeepNorthUp(_ on: Bool) {
        defaults.set(on, forKey: Self.keepNorthUpKey)
        keepNorthUp = on
        notify()
    }

    func setPreferButtons(_ on: Bool) {
        defaults.set(on, forKey: Self.preferButtonsKey)
        preferButtons = on
        notify()
    }

    func setButtonShape(_ shape: MapButtonShape) {
        defaults.set(shape.rawValue, forKey: Self.buttonShapeKey)
        buttonShape = shape
        notify()
    }

    func setStartView(_ view: MapStartView) {
        defaults.set(view.rawValue, forKey: Self.startViewKey)
        startView = view
        notify()
    }

    /// Read without an instance: LaunchOptions builds the launch camera before any view exists.
    static func storedStartView() -> MapStartView {
        let defaults = settingsDefaults()
        return MapStartView(rawValue: defaults.string(forKey: startViewKey) ?? "") ?? .here
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    static func settingsDefaults() -> UserDefaults {
        UserDefaults(suiteName: SettingsPersistence.settingsSuite) ?? .standard
    }
}

/// A Google-style scale bar step: the longest round distance whose bar fits `maxWidth` points.
struct MapScale: Equatable {
    let meters: Double
    let label: String
}

enum MapScaleBar {
    /// The widest the bar may be. Matches Android's `MAX_BAR_DP`.
    static let maxWidth: Double = 96

    private static let metric: [Double] = [
        1, 2, 5, 10, 20, 50, 100, 200, 500,
        1_000, 2_000, 5_000, 10_000, 20_000, 50_000,
        100_000, 200_000, 500_000, 1_000_000, 2_000_000, 5_000_000,
    ]
    private static let feet: [Double] = [10, 20, 50, 100, 200, 500, 1_000, 2_000]
    private static let miles: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000]

    /// The step for the current latitude, in maps' own metres per point.
    static func scale(metersPerPoint: Double, imperial: Bool) -> MapScale? {
        guard metersPerPoint > 0, metersPerPoint.isFinite else { return nil }
        let maxMeters = metersPerPoint * maxWidth
        if imperial {
            let maxFeet = maxMeters * 3.280_839_895
            if maxFeet < 5_280 {
                let pick = feet.last(where: { $0 <= maxFeet }) ?? feet[0]
                return MapScale(meters: pick / 3.280_839_895, label: "\(Int(pick)) ft")
            }
            let maxMiles = maxFeet / 5_280
            let pick = miles.last(where: { $0 <= maxMiles }) ?? miles[0]
            return MapScale(meters: pick * 1_609.344, label: "\(Int(pick)) mi")
        }
        let pick = metric.last(where: { $0 <= maxMeters }) ?? metric[0]
        let label = pick < 1_000 ? "\(Int(pick)) m" : "\(Int(pick / 1_000)) km"
        return MapScale(meters: pick, label: label)
    }
}
