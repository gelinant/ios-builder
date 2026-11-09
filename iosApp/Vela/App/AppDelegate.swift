import UIKit

/// Keeps SwiftUI's lifecycle while returning background URLSession events to their durable owner.
final class VelaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // TRIP-DIAG: the launch measurement starts from the kernel's process record, and the
        // exception handler must exist before SwiftUI builds the first view. Neither uploads.
        DiagnosticsMeasurements.shared.mark(.launch)
        CrashLog.install()
        return true
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        URLSessionRegionDownloader.handleEvents(
            forBackgroundURLSession: identifier, completionHandler: completionHandler)
        // Rebuild the persisted region plan so the next piece can start after this one installs.
        _ = AppGraph.session
    }
}
