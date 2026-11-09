#if DEBUG
import Foundation
import VelaCore

/// Debug-only: `-VelaRouteCameraFixture YES` turns on the deterministic camera source of
/// `RouteCameraFixture` for the camera-avoidance scenario. The flag is read before the first
/// directions request of the session; nothing here exists in a release build.
enum RouteCameraTestSupport {
    private static var registered = false

    static func enableIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !registered,
              let index = arguments.firstIndex(of: "-VelaRouteCameraFixture"),
              index + 1 < arguments.count,
              ["yes", "true", "1"].contains(arguments[index + 1].lowercased()) else { return }
        registered = true
        RouteCameraFixture.shared.enabled = true
    }
}
#endif
