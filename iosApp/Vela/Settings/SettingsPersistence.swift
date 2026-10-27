import Foundation

/// Suite names shared with UserDefaultsKeyValueStores in iosMain.
enum SettingsPersistence {
    static let settingsSuite = "app.vela.ios.vela_settings"
    static let unitsSuite = "app.vela.ios.vela_units"

    /// One clean store per process: AppGraph also calls this, and a second wipe after the privacy
    /// session stamped its start would silently lose that stamp in a Debug reset launch.
    private static var didReset = false

    /// Gives a UI scenario a clean settings store before PlatformLocale or Kotlin reads it.
    static func resetForLaunchIfNeeded() {
        #if DEBUG
        guard LaunchOptions.current.resetSettings, !didReset else { return }
        didReset = true
        for suite in [settingsSuite, unitsSuite] {
            let defaults = UserDefaults(suiteName: suite)
            defaults?.removePersistentDomain(forName: suite)
            defaults?.synchronize()
        }
        #endif
    }
}
