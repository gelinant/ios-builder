import Foundation
import VelaCore

/// Builds the Kotlin `CoreGraph` and the JavaScript and signature seams from Swift once per process
/// and hands them to `IosGraph`, which builds the map session (PORTAGE_IOS.md 3.1, SPEC "Platform
/// seams"). Building does no work; `MapSession.start()` (called by `IosGraph.start`) loads the
/// cached calibration and launches its refresh.
enum AppGraph {
    static let session: MapSession = {
        let core = CoreGraph(
            log: OSLogLog(),
            clock: SystemClock(),
            keyValues: UserDefaultsKeyValueStores(prefix: "app.vela.ios."),
            files: FileManagerPlatformFiles(),
            http: URLSessionVelaHttp(),
            text: FoundationTextNormalizer(),
            locale: DevicePlatformLocale())
        return IosGraph.shared.start(
            core: core, js: JavaScriptCoreJsEngine(), signatures: SecKeySignatureVerifier())
    }()
}
