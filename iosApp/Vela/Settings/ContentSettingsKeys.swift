import Foundation

/// UserDefaults keys shared by the Kotlin SettingsStore and the Swift photo loader. The Kotlin
/// side writes them through the `app.vela.ios.vela_settings` suite; the Swift side reads them
/// before an image request, so a change applies to the next gallery without a relaunch.
enum ContentSettingsKeys {
    static let suite = SettingsPersistence.settingsSuite
    static let lowDataMode = "low_data_mode"
    static let lowRamMode = "low_ram_mode"
    static let placeContent = "place_content"
    static let showReviews = "show_reviews"
    static let loadPhotos = "load_photos"
    static let photosWifiOnly = "photos_wifi_only"
    static let photoQuality = "photo_quality"
    static let photoCacheMb = "photo_cache_mb"
    static let hideExternalLinks = "hide_external_links"
    static let redactPlacesInExports = "diag_redact"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suite) ?? .standard
    }

    /// Standard and low differ from the URL the Kotlin photo parser already upscaled to; high asks
    /// for one more step. `standard` keeps that URL untouched.
    static var photoQualityValue: String {
        defaults.string(forKey: photoQuality) ?? "standard"
    }

    static var redactPlacesInExportsValue: Bool {
        defaults.bool(forKey: redactPlacesInExports)
    }

    static var hideExternalLinksValue: Bool {
        defaults.bool(forKey: hideExternalLinks)
    }

    static var photosWifiOnlyValue: Bool {
        defaults.bool(forKey: photosWifiOnly)
    }

    static var lowDataModeValue: Bool {
        defaults.bool(forKey: lowDataMode)
    }

    static var loadPhotosValue: Bool {
        defaults.object(forKey: loadPhotos) as? Bool ?? true
    }

    static var photoCacheMbValue: Int {
        let value = defaults.integer(forKey: photoCacheMb)
        return value == 0 ? 200 : min(400, max(50, value))
    }
}
