import Foundation
import VelaCore

/// Builds the Kotlin `CoreGraph` and the JavaScript and signature seams from Swift once per process
/// and hands them to `IosGraph`, which builds the map session (PORTAGE_IOS.md 3.1, SPEC "Platform
/// seams"). Building does no work; `MapSession.start()` (called by `IosGraph.start`) applies the
/// persisted language, Google and clock choices, then loads the cached calibration and launches
/// its refresh before any facet can make a Google request.
enum AppGraph {
    static let navVoice = AppleNavVoice()
    static let navHaptics = AppleNavHaptics()

    static let session: MapSession = {
        SettingsPersistence.resetForLaunchIfNeeded()
        let files = FileManagerPlatformFiles()
        let core = CoreGraph(
            log: OSLogLog(),
            clock: SystemClock(),
            keyValues: UserDefaultsKeyValueStores(prefix: "app.vela.ios."),
            files: files,
            http: URLSessionVelaHttp(),
            text: FoundationTextNormalizer(),
            locale: DevicePlatformLocale())
        let language = Locale.current.language
        NavStringsRegistry.shared.setLanguage(
            language: language.languageCode?.identifier ?? "en",
            region: Locale.current.region?.identifier ?? "",
            script: language.script?.identifier ?? "")
        let session = IosGraph.shared.start(
            core: core, js: JavaScriptCoreJsEngine(), signatures: SecKeySignatureVerifier(),
            use24h: deviceUses24HourClock(), region: Locale.current.region?.identifier,
            languageOverride: LaunchOptions.current.language)
        let sql = BundledSqlDbs(databaseDir: files.noBackupDir + "/offline-sql") { path in
            _ = files.mkdirs(path: path)
        }
        let offline = session.attachOffline(
            core: core, sql: sql, downloader: URLSessionRegionDownloader())
        if let url = OfflineStyleFactory.resource("region_polys", "json"),
           let polygons = try? String(contentsOf: url, encoding: .utf8) {
            offline.loadRegionPolygons(text: polygons)
        }
        session.place.web = ReviewsWebFetcher.shared
        session.configureNavigation(voice: navVoice, haptics: navHaptics)
        return session
    }()

    static let location = CoreLocationPipeline()

    /// The app's 12/24-hour choice, or the device setting while the graph is still starting.
    static func uses24HourClock() -> Bool {
        IosGraph.shared.session?.settings?.use24h ?? deviceUses24HourClock()
    }

    /// Whether the device shows times on a 24-hour clock (the "j" skeleton has no "a").
    static func deviceUses24HourClock() -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
        return !format.contains("a")
    }
}
