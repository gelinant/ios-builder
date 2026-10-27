import Foundation

/// Suite names shared with UserDefaultsKeyValueStores in iosMain.
enum SettingsPersistence {
    static let settingsSuite = "app.vela.ios.vela_settings"
    static let unitsSuite = "app.vela.ios.vela_units"

    /// Gives a UI scenario a clean settings store before PlatformLocale or Kotlin reads it.
    static func resetForLaunchIfNeeded() {
        #if DEBUG
        guard LaunchOptions.current.resetSettings else { return }
        for suite in [settingsSuite, unitsSuite] {
            let defaults = UserDefaults(suiteName: suite)
            defaults?.removePersistentDomain(forName: suite)
            defaults?.synchronize()
        }
        #endif
    }
}
