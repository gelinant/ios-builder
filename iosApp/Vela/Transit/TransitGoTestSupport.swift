#if DEBUG
import SwiftUI
import UIKit
import VelaCore

/// Debug-only host for `TransitGoUITests`. The map screen is owned by other lots, so this seam
/// presents the GO screen over the running app when `-VelaTransitGoTest` is present. It is inert
/// in production: the launch argument is the only entry point, and no map file calls it.
@objc(TransitGoTestSupport)
final class TransitGoTestSupport: NSObject {
    @objc static func present() {
        present(attempt: 0)
    }

    private static func present(attempt: Int) {
        guard let top = topViewController() else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { present(attempt: attempt + 1) }
            }
            return
        }
        let arguments = ProcessInfo.processInfo.arguments
        let scene = value(after: "-VelaTransitGoScene", in: arguments) ?? "ride"
        let degraded = arguments.contains("-VelaTransitGoDegraded")
        let now = Date()
        let nowSec = Int64(now.timeIntervalSince1970)
        let plan = TransitGoFixtures.shared.paris(
            nowEpochSec: nowSec,
            live: !degraded,
            fetchedAtEpochSec: nowSec)
        let model = TransitGoModel(plan: plan, networkAvailable: !degraded)
        model.usesHostNetwork = false
        // "prepare" leaves the model without a state, so the loading line is the visible surface.
        // The screen starts the model on appear, so the model itself must hold that start back.
        model.autoStart = scene != "prepare"
        if scene != "prepare" {
            // Start at the ride and one stop in, so the rail has a passed stop and the get-off cue
            // has not fired yet. The degraded scene keeps the same position.
            model.start()
            model.seek(legIndex: 1, stopIndex: 1, boarded: true)
        }
        let root = TransitGoScreen(model: model, onClose: {})
        let host = UIHostingController(rootView: root)
        host.modalPresentationStyle = .fullScreen
        top.present(host, animated: false)
        NSLog("TRANSIT_GO_TEST presented scene=%@ degraded=%d", scene, degraded ? 1 : 0)
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

    private static func value(after key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
#endif
