import Foundation

private final class VelaL10nBundleMarker {}

struct VelaLanguage: Identifiable, Hashable {
    let code: String
    let endonym: String
    var id: String { code }
}

/// Android resource keys in Localizable.xcstrings, with an explicit in-app locale and English
/// fallback. Data such as place names, addresses and reviews never goes through this helper.
enum VelaL10n {
    static let languages: [VelaLanguage] = [
        VelaLanguage(code: "en", endonym: "English"),
        VelaLanguage(code: "en-GB", endonym: "English (UK)"),
        VelaLanguage(code: "ar", endonym: "العربية"),
        VelaLanguage(code: "de", endonym: "Deutsch"),
        VelaLanguage(code: "es", endonym: "Español"),
        VelaLanguage(code: "et", endonym: "Eesti"),
        VelaLanguage(code: "fr", endonym: "Français"),
        VelaLanguage(code: "he", endonym: "עברית"),
        VelaLanguage(code: "hu", endonym: "Magyar"),
        VelaLanguage(code: "it", endonym: "Italiano"),
        VelaLanguage(code: "ja", endonym: "日本語"),
        VelaLanguage(code: "kmr", endonym: "Kurmancî"),
        VelaLanguage(code: "nl", endonym: "Nederlands"),
        VelaLanguage(code: "pl", endonym: "Polski"),
        VelaLanguage(code: "pt", endonym: "Português (Portugal)"),
        VelaLanguage(code: "pt-BR", endonym: "Português (Brasil)"),
        VelaLanguage(code: "ro", endonym: "Română"),
        VelaLanguage(code: "ru", endonym: "Русский"),
        VelaLanguage(code: "sl", endonym: "Slovenščina"),
        VelaLanguage(code: "sv", endonym: "Svenska"),
        VelaLanguage(code: "tr", endonym: "Türkçe"),
        VelaLanguage(code: "uk", endonym: "Українська"),
        VelaLanguage(code: "zh", endonym: "简体中文"),
        VelaLanguage(code: "zh-TW", endonym: "繁體中文（台灣）"),
    ]

    static let supportedLanguageCodes = Set(languages.map(\.code))

    /// Formats a real catalog key. Integer specifiers are %ld, matching Swift's 64-bit Int.
    static func text(_ key: String, _ args: CVarArg...) -> String {
        text(key, language: DevicePlatformLocale.effectiveTag(), args: args)
    }

    /// The explicit-language entry point also makes catalog behavior testable without changing
    /// the simulator language or process-wide UserDefaults.
    static func text(_ key: String, language: String, _ args: CVarArg...) -> String {
        text(key, language: language, args: args)
    }

    private static func text(_ key: String, language: String, args: [CVarArg]) -> String {
        let catalogLanguage = catalogLanguage(for: language)
        let format = localizedFormat(key, catalogLanguage: catalogLanguage)
        if args.isEmpty { return format }
        return String(format: format, locale: Locale(identifier: catalogLanguage), arguments: args)
    }

    static var isRightToLeft: Bool {
        let language = catalogLanguage(for: DevicePlatformLocale.effectiveTag()).split(separator: "-").first
        return language == "he" || language == "ar"
    }

    /// Maps system tags and Android preference codes to catalog locale folder names.
    static func catalogLanguage(for tag: String) -> String {
        let parts = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let first = parts.first?.lowercased() else { return "en" }
        let legacy = ["iw": "he", "in": "id", "ji": "yi"]
        let language = legacy[first] ?? first
        let rest = parts.dropFirst()
        let region = rest.first { $0.count == 2 || $0.count == 3 }?.uppercased() ?? ""
        let script = rest.first { $0.count == 4 }?.lowercased() ?? ""
        let resolved: String
        switch language {
        case "en": resolved = region == "GB" ? "en-GB" : "en"
        case "pt": resolved = region == "BR" ? "pt-BR" : "pt-PT"
        case "zh": resolved = script == "hant" || ["TW", "HK", "MO"].contains(region) ? "zh-Hant" : "zh-Hans"
        default: resolved = language
        }
        let available = supportedLanguageCodes.union(["pt-PT", "zh-Hans", "zh-Hant"])
        return available.contains(resolved) ? resolved : "en"
    }

    private static func localizedFormat(_ key: String, catalogLanguage: String) -> String {
        let missing = "\u{0}vela-missing-localization\u{0}"
        let appBundle = Bundle(for: VelaL10nBundleMarker.self)
        // Xcode compiles Kurmanji (kmr) into the generic Kurdish (ku) localization folder.
        let selected = catalogLanguage == "kmr" ? ["kmr", "ku"] : [catalogLanguage]
        for language in selected + (catalogLanguage == "en" ? [] : ["en"]) {
            guard let path = appBundle.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            let value = bundle.localizedString(forKey: key, value: missing, table: "Localizable")
            if value != missing { return value }
        }
        return key
    }
}

/// Short alias for call sites with several labels.
typealias L = VelaL10n
