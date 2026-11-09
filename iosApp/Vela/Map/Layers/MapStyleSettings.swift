import Foundation
import UIKit

/// The map looks the layers sheet offers. Android's five looks are kept: the Vela look is painted
/// light or dark, the other four keep OpenFreeMap's own palettes. Every one is a local style
/// document generated from the bundled Liberty base, never a style fetched from a server.
enum MapLook: String, CaseIterable {
    case vela
    case bright
    case positron
    case fiord
    case black

    var title: String {
        switch self {
        case .vela: return "Vela"
        case .bright: return "Bright"
        case .positron: return "Positron"
        case .fiord: return "Fiord"
        case .black: return "Black"
        }
    }

    func resourceName(dark: Bool) -> String {
        self == .vela ? (dark ? "style-vela-dark" : "style-vela-light") : "style-\(rawValue)"
    }
}

/// The Vela look follows the system by default, or can be pinned independent of the app theme.
enum MapAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "Use system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var isDark: Bool {
        switch self {
        case .light: return false
        case .dark: return true
        case .system: return UITraitCollection.current.userInterfaceStyle == .dark
        }
    }
}

/// Settings > Map > Names on the map, with the same four values and the same `name:en` /
/// `name:latin` / `name` precedence as Android. A reader of a non-Latin script keeps the local
/// name whatever the choice, as on Android.
enum MapNamesMode: String, CaseIterable {
    case englishLatin = "english_latin"
    case englishLocal = "english_local"
    case local
    case localEnglish = "local_english"

    static let preferenceValues = [
        englishLatin, englishLocal, local, localEnglish,
    ]

    var title: String {
        switch self {
        case .englishLatin: return "English or romanized"
        case .englishLocal: return "English, local where missing"
        case .local: return "Local names only"
        case .localEnglish: return "Local and English"
        }
    }
}

/// How far out house numbers appear, using Android's three zoom gates.
enum HouseNumberLevel: String, CaseIterable {
    case near
    case normal
    case far

    var title: String {
        switch self {
        case .near: return "Close"
        case .normal: return "Normal"
        case .far: return "Far"
        }
    }

    var minZoom: Double {
        switch self {
        case .near: return 18.3
        case .normal: return 17.8
        case .far: return 17.3
        }
    }
}

/// Everything a generated style needs beyond its look. The offline factory applies the same value,
/// so a downloaded region follows the name mode and house-number setting too.
struct MapStyleOptions: Equatable {
    var look: MapLook = .vela
    var appearance: MapAppearance = .system
    var names: MapNamesMode = .englishLatin
    var houseNumbers: HouseNumberLevel = .normal
    var language: String = Locale.current.languageCode ?? "en"

    var isDark: Bool { appearance.isDark }

    var styleResource: String { look.resourceName(dark: isDark) }

    /// The narrow, stable part of the cache key: a style reloads only when one of these changes.
    var cacheToken: String {
        [look.rawValue, appearance.rawValue, names.rawValue,
         houseNumbers.rawValue, language].joined(separator: "-")
    }
}

/// Reads and writes the same preference keys Android uses (`map_look`, `map_names`,
/// `housenumber_zoom`), plus `map_appearance` for the light/dark choice of the Vela look.
enum MapStyleSettings {
    static let changedNotification = Notification.Name("VelaMapStyleChanged")

    static var defaults: UserDefaults {
        UserDefaults(suiteName: SettingsPersistence.settingsSuite) ?? .standard
    }

    static func current() -> MapStyleOptions {
        var options = MapStyleOptions()
        let stored = defaults
        if let look = MapLook(rawValue: stored.string(forKey: "map_look") ?? "") {
            options.look = look
        }
        if let appearance = MapAppearance(rawValue: stored.string(forKey: "map_appearance") ?? "") {
            options.appearance = appearance
        }
        if let names = MapNamesMode(rawValue: stored.string(forKey: "map_names") ?? "") {
            options.names = names
        }
        if let house = HouseNumberLevel(rawValue: stored.string(forKey: "housenumber_zoom") ?? "") {
            options.houseNumbers = house
        }
        // UI tests and the screenshot run pin a look for one launch without touching the store.
        if let look = launchValue("VelaMapLook").flatMap(MapLook.init(rawValue:)) {
            options.look = look
        }
        if let appearance = launchValue("VelaMapAppearance").flatMap(MapAppearance.init(rawValue:)) {
            options.appearance = appearance
        }
        if let names = launchValue("VelaMapNames").flatMap(MapNamesMode.init(rawValue:)) {
            options.names = names
        }
        if let house = launchValue("VelaMapHouseNumbers").flatMap(HouseNumberLevel.init(rawValue:)) {
            options.houseNumbers = house
        }
        if let language = stored.string(forKey: "app_language"), !language.isEmpty {
            options.language = language
        } else if let language = LaunchOptions.current.language, !language.isEmpty {
            options.language = language
        }
        return options
    }

    static func save(_ options: MapStyleOptions) {
        let stored = defaults
        stored.set(options.look.rawValue, forKey: "map_look")
        stored.set(options.appearance.rawValue, forKey: "map_appearance")
        stored.set(options.names.rawValue, forKey: "map_names")
        stored.set(options.houseNumbers.rawValue, forKey: "housenumber_zoom")
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    private static func launchValue(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}
