import CoreSpotlight
import SwiftUI
import UIKit

@main
struct VelaApp: App {
    @UIApplicationDelegateAdaptor(VelaAppDelegate.self) private var appDelegate
    @StateObject private var deepLinks = VelaDeepLinkCenter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if LaunchOptions.current.deterministic {
            UIView.setAnimationsEnabled(false)
        }
        // Reset before the privacy session reads its stamp, then replace a session that is due,
        // before the first Google request.
        SettingsPersistence.resetForLaunchIfNeeded()
        PrivacySettings.shared.startAtLaunch()
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { PrivacySettings.shared.rotateIfDue() }
        }
    }
}
