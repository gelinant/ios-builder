import SwiftUI
import UIKit

@main
struct VelaApp: App {
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
