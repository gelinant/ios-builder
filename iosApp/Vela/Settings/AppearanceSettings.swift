import SwiftUI
import UIKit

/// The app-wide light or dark choice. Android stores the same enum under `theme_mode` with
/// uppercase names, so a settings suite shared between the two applications stays readable.
enum AppearanceTheme: String, CaseIterable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"

    /// Accepts Android's uppercase value and a lowercase value written by an older iOS build.
    static func stored(_ raw: String?) -> AppearanceTheme {
        guard let raw else { return .system }
        return AppearanceTheme(rawValue: raw.uppercased()) ?? .system
    }

    var title: String {
        switch self {
        case .system: return "Follow system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// A11Y-SPLIT: `-VelaTheme dark` picks the appearance for one UI scenario. The value is kept
    /// in memory and never written to the settings suite, so a scenario can run dark without
    /// changing the choice the user made. A missing or unknown value keeps the stored one.
    static func launched(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> AppearanceTheme? {
        guard let index = arguments.firstIndex(of: "-VelaTheme"),
              index + 1 < arguments.count else { return nil }
        return AppearanceTheme(rawValue: arguments[index + 1].uppercased())
    }
}

/// Navigation puck size, under Android's `puck_size` key. The scale applies to the chrome icon
/// and to the maneuver glyph, never to the map itself.
enum NavIconSize: String, CaseIterable {
    case normal
    case large
    case xl

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .large: return "Large"
        case .xl: return "Extra large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .normal: return 1
        case .large: return 1.25
        case .xl: return 1.5
        }
    }
}

/// The app's own navigation-label step. It multiplies the Dynamic Type size instead of replacing
/// it, so the system setting keeps working and the two steps add up.
enum NavLabelSize: String, CaseIterable {
    case system
    case large
    case xl

    var title: String {
        switch self {
        case .system: return "Follow system"
        case .large: return "Larger labels"
        case .xl: return "Largest labels"
        }
    }

    var scale: CGFloat {
        switch self {
        case .system: return 1
        case .large: return 1.15
        case .xl: return 1.3
        }
    }
}

/// Which unit the drive's speed badge uses. `auto` follows the app's distance units, as Android
/// does; the two explicit values let a driver read mph in a km/h country or the reverse.
enum SpeedUnitChoice: String, CaseIterable {
    case auto
    case metric
    case imperial

    var title: String {
        switch self {
        case .auto: return "Follow units"
        case .metric: return "km/h"
        case .imperial: return "mph"
        }
    }

    func isImperial(modelImperial: Bool) -> Bool {
        switch self {
        case .auto: return modelImperial
        case .metric: return false
        case .imperial: return true
        }
    }
}

/// The navigation chrome's vehicle marker. The map's own location puck stays MapLibre's; this
/// choice draws the matching badge beside the speed, so the driver sees the same symbol as
/// Android's navigation icon without a second map layer.
enum NavVehicle: String, CaseIterable {
    case arrow
    case car
    case ufo
    case ship
    case duck

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .car: return "Car"
        case .ufo: return "UFO"
        case .ship: return "Pirate ship"
        case .duck: return "Rubber duck"
        }
    }

    var symbol: String {
        switch self {
        case .arrow: return "location.north.fill"
        case .car: return "car.fill"
        case .ufo: return "airplane"
        case .ship: return "sailboat.fill"
        case .duck: return "bird.fill"
        }
    }
}

/// How much secondary navigation chrome a drive shows. Safety alerts and the maneuver card are
/// never reduced; only the road label and the following-step line are.
enum NavDetailLevel: String, CaseIterable {
    case full
    case compact
    case minimal

    var title: String {
        switch self {
        case .full: return "Full"
        case .compact: return "Compact"
        case .minimal: return "Minimal"
        }
    }
}

/// One observable holder for every appearance and navigation-chrome choice. The setters write
/// the same keys Android uses where they exist and post one notification, so the map style and
/// the drive chrome refresh without a relaunch.
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()
    static let changedNotification = Notification.Name("VelaAppearanceChanged")

    @Published private(set) var theme: AppearanceTheme
    @Published private(set) var mapLook: MapLook
    @Published private(set) var mapAppearance: MapAppearance
    @Published private(set) var iconSize: NavIconSize
    @Published private(set) var labelSize: NavLabelSize
    @Published private(set) var speedDisplay: Bool
    @Published private(set) var speedUnit: SpeedUnitChoice
    @Published private(set) var vehicle: NavVehicle
    @Published private(set) var detail: NavDetailLevel

    private let defaults: UserDefaults
    private var sceneObserver: NSObjectProtocol?

    private init() {
        defaults = UserDefaults(suiteName: SettingsPersistence.settingsSuite) ?? .standard
        theme = AppearanceTheme.launched()
            ?? AppearanceTheme.stored(defaults.string(forKey: "theme_mode"))
        let style = MapStyleSettings.current()
        mapLook = style.look
        mapAppearance = style.appearance
        iconSize = NavIconSize(rawValue: defaults.string(forKey: "puck_size") ?? "") ?? .normal
        labelSize = NavLabelSize(rawValue: defaults.string(forKey: "nav_label_size") ?? "") ?? .system
        speedDisplay = defaults.object(forKey: "speed_display") as? Bool ?? true
        speedUnit = SpeedUnitChoice(rawValue: defaults.string(forKey: "speed_unit") ?? "") ?? .auto
        vehicle = NavVehicle(rawValue: defaults.string(forKey: "puck_shape") ?? "") ?? .arrow
        detail = NavDetailLevel(rawValue: defaults.string(forKey: "nav_detail") ?? "") ?? .full

        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyTheme()
        }
        applyTheme()
    }

    // MARK: - Theme

    func setTheme(_ value: AppearanceTheme) {
        theme = value
        defaults.set(value.rawValue, forKey: "theme_mode")
        defaults.synchronize()
        applyTheme()
        publish()
    }

    /// Every window in every active scene carries the choice. `overrideUserInterfaceStyle` is the
    /// only app-wide switch SwiftUI does not own, and it needs re-applying to a window that the
    /// system creates after a scene activates.
    func applyTheme() {
        let style = theme.interfaceStyle
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }

    // MARK: - Map

    func setMapLook(_ look: MapLook) {
        mapLook = look
        saveMap(look: look, appearance: mapAppearance)
    }

    func setMapAppearance(_ appearance: MapAppearance) {
        mapAppearance = appearance
        saveMap(look: mapLook, appearance: appearance)
    }

    private func saveMap(look: MapLook, appearance: MapAppearance) {
        var options = MapStyleSettings.current()
        options.look = look
        options.appearance = appearance
        MapStyleSettings.save(options)
        publish()
    }

    // MARK: - Navigation chrome

    func setIconSize(_ value: NavIconSize) {
        iconSize = value
        defaults.set(value.rawValue, forKey: "puck_size")
        publish()
    }

    func setLabelSize(_ value: NavLabelSize) {
        labelSize = value
        defaults.set(value.rawValue, forKey: "nav_label_size")
        publish()
    }

    func setSpeedDisplay(_ on: Bool) {
        speedDisplay = on
        defaults.set(on, forKey: "speed_display")
        publish()
    }

    func setSpeedUnit(_ value: SpeedUnitChoice) {
        speedUnit = value
        defaults.set(value.rawValue, forKey: "speed_unit")
        publish()
    }

    func setVehicle(_ value: NavVehicle) {
        vehicle = value
        defaults.set(value.rawValue, forKey: "puck_shape")
        publish()
    }

    func setDetail(_ value: NavDetailLevel) {
        detail = value
        defaults.set(value.rawValue, forKey: "nav_detail")
        publish()
    }

    private func publish() {
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    /// One line for Debug UI scenarios, short enough to fit the appearance page.
    var debugLine: String {
        "theme=\(theme.rawValue.lowercased()) look=\(mapLook.rawValue)"
            + " map=\(mapAppearance.rawValue) icon=\(iconSize.rawValue)"
            + " label=\(labelSize.rawValue) speed=\(speedDisplay ? 1 : 0)"
            + " unit=\(speedUnit.rawValue) vehicle=\(vehicle.rawValue) detail=\(detail.rawValue)"
    }
}
