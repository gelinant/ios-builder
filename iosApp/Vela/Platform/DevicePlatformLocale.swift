import Foundation
import VelaCore

/// The `PlatformLocale` seam over the device's language list. The app has no in-app language yet,
/// so the default is the first preferred language. `defaultLanguage` keeps Android's legacy codes
/// (`iw`, `in`, `ji`), which the shared tables are keyed on.
final class DevicePlatformLocale: NSObject, PlatformLocale {
    func defaultTag() -> String {
        Self.tags().first!
    }

    func defaultLanguage() -> String {
        Self.legacyLanguage(of: defaultTag())
    }

    func preferredTags() -> [String] {
        Self.tags()
    }

    func systemTags() -> [String] {
        Self.tags()
    }

    static func tags() -> [String] {
        let tags = Locale.preferredLanguages
        return tags.isEmpty ? ["en-US"] : tags
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
