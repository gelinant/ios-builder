import Foundation
import VelaCore

/// Builds the Kotlin `CoreGraph` and the JavaScript and signature seams from Swift once per process
/// and hands them to `IosGraph`, which builds the map session (PORTAGE_IOS.md 3.1, SPEC "Platform
/// seams"). Building does no work; `MapSession.start()` (called by `IosGraph.start`) applies the
/// persisted language, Google and clock choices, then loads the cached calibration and launches
/// its refresh before any facet can make a Google request.
enum AppGraph {
    static let navVoice = VelaNavVoice.shared
    static let navHaptics = AppleNavHaptics()

    static let session: MapSession = {
        SettingsPersistence.resetForLaunchIfNeeded()
        // PERF-1: the offline catalog starts after the first map frame, from `LaunchSequencer`;
        // it is not first-screen content and its SQLite and manifest work competed with the
        // frame. `-VelaPerfLegacy YES` keeps the old all-at-once start for a before/after
        // measurement.
        IosGraph.shared.deferSecondaryStarts = !LaunchOptions.current.perfLegacy
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
            core: core, sql: sql, downloader: URLSessionRegionDownloader.shared)
        // PERF-1: the 350 KB region table is a country lookup, not first-frame content. Its file
        // read and JSON parse used to sit on the main thread before the first frame; now they run
        // after the frame, on the sequencer's background queue, so they cannot compete with
        // MapLibre's own style load. `loadRegionPolygons` recomputes the current region when the
        // table lands. The legacy flag keeps the old synchronous read for the measurement.
        if LaunchOptions.current.perfLegacy {
            loadRegionPolygons(into: offline)
        } else {
            LaunchSequencer.enqueue { loadRegionPolygons(into: offline) }
        }
        session.place.web = ReviewsWebFetcher.shared
        session.configureNavigation(voice: navVoice, haptics: navHaptics)
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        session.trips.versionCode = Int32(build ?? "") ?? 0
        WidgetStatePublisher.startPublishing(session: session)
        return session
    }()

    static let location = CoreLocationPipeline()
    static let spotlight = SpotlightIndexer(store: session.saved)

    /// The bundled region table, read and parsed once. Shared by the deferred and legacy paths.
    private static func loadRegionPolygons(into offline: OfflineStore) {
        guard let url = OfflineStyleFactory.resource("region_polys", "json"),
              let polygons = try? String(contentsOf: url, encoding: .utf8) else { return }
        offline.loadRegionPolygons(text: polygons)
    }

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
