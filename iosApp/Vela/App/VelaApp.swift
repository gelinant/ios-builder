import SwiftUI
import UIKit

@main
struct VelaApp: App {
    @UIApplicationDelegateAdaptor(VelaAppDelegate.self) private var appDelegate

    init() {
        if LaunchOptions.current.deterministic {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
        }
    }
}
