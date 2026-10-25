import Foundation
import VelaCore

/// Builds the Kotlin `CoreGraph` and the JavaScript and signature seams from Swift once per process
/// and hands them to `IosGraph`, which builds the map session (PORTAGE_IOS.md 3.1, SPEC "Platform
/// seams"). Building does no work; `MapSession.start()` (called by `IosGraph.start`) loads the
/// cached calibration and launches its refresh, then sets the process holders (the device clock
/// and region among them) before any Google request.
enum AppGraph {
    static let session: MapSession = {
        let files = FileManagerPlatformFiles()
        let core = CoreGraph(
            log: OSLogLog(),
            clock: SystemClock(),
            keyValues: UserDefaultsKeyValueStores(prefix: "app.vela.ios."),
            files: files,
            http: URLSessionVelaHttp(),
            text: FoundationTextNormalizer(),
            locale: DevicePlatformLocale())
        let session = IosGraph.shared.start(
            core: core, js: JavaScriptCoreJsEngine(), signatures: SecKeySignatureVerifier(),
            use24h: uses24HourClock(), region: Locale.current.region?.identifier)
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
        return session
    }()

    /// Whether the device shows times on a 24-hour clock (the "j" skeleton has no "a").
    static func uses24HourClock() -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
        return !format.contains("a")
    }
}
