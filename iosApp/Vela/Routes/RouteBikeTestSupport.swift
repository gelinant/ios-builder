#if DEBUG
import Foundation
import VelaCore

/// Debug-only: `-VelaBikeProfileFixture YES` turns on the deterministic bicycle routes of
/// `BikeProfileFixture`, so the safety-weighted and fastest profiles answer with two different
/// lines on the CI runner. The flag is read before the first directions request of the session;
/// nothing here exists in a release build.
enum RouteBikeTestSupport {
    private static var registered = false

    static func enableIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !registered,
              let index = arguments.firstIndex(of: "-VelaBikeProfileFixture"),
              index + 1 < arguments.count,
              ["yes", "true", "1"].contains(arguments[index + 1].lowercased()) else { return }
        registered = true
        BikeProfileFixture.shared.enabled = true
    }
}
#endif
