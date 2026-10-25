import Foundation
import VelaCore

/// Builds the Kotlin `CoreGraph` and the JavaScript and signature seams from Swift once per process
/// and hands them to `IosGraph`, which builds the map session (PORTAGE_IOS.md 3.1, SPEC "Platform
/// seams"). Building does no work; `MapSession.start()` (called by `IosGraph.start`) loads the
/// cached calibration and launches its refresh, then sets the process holders (the device clock
/// and region among them) before any Google request.
enum AppGraph {
    static let navVoice = AppleNavVoice()
    static let navHaptics = AppleNavHaptics()

    static let session: MapSession = {
        let core = CoreGraph(
            log: OSLogLog(),
            clock: SystemClock(),
            keyValues: UserDefaultsKeyValueStores(prefix: "app.vela.ios."),
            files: FileManagerPlatformFiles(),
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
            use24h: uses24HourClock(), region: Locale.current.region?.identifier)
        session.place.web = ReviewsWebFetcher.shared
        session.configureNavigation(voice: navVoice, haptics: navHaptics)
        return session
    }()

    static let location = CoreLocationPipeline()

    /// Whether the device shows times on a 24-hour clock (the "j" skeleton has no "a").
    static func uses24HourClock() -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
        return !format.contains("a")
    }
}
