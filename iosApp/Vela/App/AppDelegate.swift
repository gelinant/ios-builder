import UIKit

/// Keeps SwiftUI's lifecycle while returning background URLSession events to their durable owner.
final class VelaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        URLSessionRegionDownloader.handleEvents(
            forBackgroundURLSession: identifier, completionHandler: completionHandler)
        // Rebuild the persisted region plan so the next piece can start after this one installs.
        _ = AppGraph.session
    }
}
