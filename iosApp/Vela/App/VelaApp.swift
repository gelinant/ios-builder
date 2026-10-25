import CoreSpotlight
import SwiftUI
import UIKit

@main
struct VelaApp: App {
    @StateObject private var deepLinks = VelaDeepLinkCenter()

    init() {
        if LaunchOptions.current.deterministic {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(deepLinks)
                .onOpenURL { deepLinks.open($0) }
                .onContinueUserActivity(CSSearchableItemActionType) {
                    deepLinks.openSpotlightActivity($0)
                }
        }
    }
}
