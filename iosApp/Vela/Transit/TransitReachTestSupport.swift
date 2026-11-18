#if DEBUG
import Foundation
import UIKit
import VelaCore

/// Debug-only host for `TransitReachUITests`. The map screen is owned by other lots, so this seam
/// presents the screen over the running app when `-VelaTransitReachTest` is present. The recorded
/// reply comes from `-VelaTransitReachFixture`; without it the screen would ask Transitous, which
/// a UI test must never do. Inert in production: the launch arguments are the only entry point.
@objc(TransitReachTestSupport)
final class TransitReachTestSupport: NSObject {
    @objc @MainActor static func present() {
        present(attempt: 0)
    }

    @MainActor private static func present(attempt: Int) {
        guard let top = topViewController() else {
            retry(attempt)
            return
        }
        if top.presentedViewController != nil {
            retry(attempt)
            return
        }
        let service = TransitLiveService(
            http: TransitousHttp(
                http: URLSessionVelaHttp(),
                locale: DevicePlatformLocale(),
                text: FoundationTextNormalizer()),
            clock: SystemClock())
        TransitReachLink.shared.open(
            originLat: 37.7955,
            originLng: -122.3937,
            originName: "Ferry Building",
            service: service)
        NSLog("TRANSIT_REACH_TEST presented")
    }

    @MainActor private static func retry(_ attempt: Int) {
        guard attempt < 20 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in present(attempt: attempt + 1) }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        var controller = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
#endif
