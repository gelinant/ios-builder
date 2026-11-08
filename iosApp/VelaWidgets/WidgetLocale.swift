import Foundation

/// The widget's copy of the app's language choice, so `VelaL10n` can be compiled into the
/// extension without linking the app, VelaCore or its settings graph. The app writes `app_language`
/// in this suite; when it follows the system, the device language wins.
enum DevicePlatformLocale {
    static func effectiveTag() -> String {
        let suite = UserDefaults(suiteName: "app.vela.ios.vela_settings")
        if let stored = suite?.string(forKey: "app_language"),
           VelaL10n.supportedLanguageCodes.contains(stored) {
            return stored
        }
        return Locale.preferredLanguages.first ?? "en"
    }
}
