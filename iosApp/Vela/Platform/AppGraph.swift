import Foundation
import VelaCore

/// Builds the Kotlin `CoreGraph` from the Swift seams once per process and hands it to
/// `IosGraph`, which builds the map session (PORTAGE_IOS.md 3.1, SPEC "Platform seams").
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
        return IosGraph.shared.start(core: core)
    }()
}
