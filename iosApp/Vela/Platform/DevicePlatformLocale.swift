import Foundation
import VelaCore

/// The `PlatformLocale` seam over the system languages and Vela's in-app override. Every call reads
/// the preference again, so Accept-Language and review languages change without rebuilding the graph.
/// `defaultLanguage` keeps Android's legacy codes (`iw`, `in`, `ji`) for the shared tables.
final class DevicePlatformLocale: NSObject, PlatformLocale {
    func defaultTag() -> String {
        Self.effectiveTag()
    }

    func defaultLanguage() -> String {
        Self.legacyLanguage(of: defaultTag())
    }

    func preferredTags() -> [String] {
        Self.tags()
    }

    func systemTags() -> [String] {
        Self.deviceLanguageTags()
    }

    /// The override first, then the system languages, for Safari's Accept-Language.
    static func tags() -> [String] {
        let system = deviceLanguageTags()
        let selected = effectiveTag()
        return selected == system.first ? system : [selected] + system
    }

    /// The selected app language, or the first system language when following the system.
    static func effectiveTag() -> String {
        if let launch = preferenceTag(LaunchOptions.current.language), !launch.isEmpty {
            return launch
        }
        let stored = UserDefaults(suiteName: SettingsPersistence.settingsSuite)?.string(forKey: "app_language")
        if let selected = preferenceTag(stored), !selected.isEmpty {
            return selected
        }
        return deviceLanguageTags().first!
    }

    static func deviceLanguageTags() -> [String] {
        let tags = Locale.preferredLanguages
        return tags.isEmpty ? ["en-US"] : tags
    }

    /// Canonical preference codes shared with SettingsStore and the 24-row language picker.
    static func preferenceTag(_ tag: String?) -> String? {
        guard let tag else { return nil }
        let parts = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").map(String.init)
        if parts.isEmpty { return "" }
        let legacy = ["iw": "he", "in": "id", "ji": "yi"]
        let language = legacy[parts[0].lowercased()] ?? parts[0].lowercased()
        let rest = parts.dropFirst()
        let region = rest.first { $0.count == 2 || $0.count == 3 }?.uppercased() ?? ""
        let script = rest.first { $0.count == 4 }?.lowercased() ?? ""
        let canonical: String
        switch language {
        case "pt": canonical = region == "BR" ? "pt-BR" : "pt"
        case "zh": canonical = script == "hant" || ["TW", "HK", "MO"].contains(region) ? "zh-TW" : "zh"
        case "en": canonical = region == "GB" ? "en-GB" : "en"
        default: canonical = language
        }
        return VelaL10n.supportedLanguageCodes.contains(canonical) ? canonical : nil
    }

    /// The language subtag of `tag` as `java.util.Locale.getLanguage` gives it.
    static func legacyLanguage(of tag: String) -> String {
        let language = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() } ?? "en"
        switch language {
        case "he": return "iw"
        case "id": return "in"
        case "yi": return "ji"
        default: return language
        }
    }
}
