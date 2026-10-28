import CoreSpotlight
import SwiftUI
import UIKit

@main
struct VelaApp: App {
    @UIApplicationDelegateAdaptor(VelaAppDelegate.self) private var appDelegate
    @StateObject private var deepLinks: VelaDeepLinkCenter
    @Environment(\.scenePhase) private var scenePhase
    /// The first-run Google question stays in front until it is answered (SET-PRIVACY).
    @State private var needsConsent: Bool

    init() {
        if LaunchOptions.current.deterministic {
            UIView.setAnimationsEnabled(false)
        }
        // Reset before the privacy session reads its stamp or the request count its saved days,
        // then replace a session that is due, before the first Google request.
        SettingsPersistence.resetForLaunchIfNeeded()
        PrivacyRequestCounter.start()
        PrivacySettings.shared.startAtLaunch()
        _deepLinks = StateObject(wrappedValue: VelaDeepLinkCenter())
        _needsConsent = State(initialValue: !PrivacySettings.consentAnswered)
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(deepLinks)
                .onOpenURL { deepLinks.open($0) }
                .onContinueUserActivity(CSSearchableItemActionType) {
                    deepLinks.openSpotlightActivity($0)
                }
                .fullScreenCover(isPresented: $needsConsent) {
                    ConsentScreen { needsConsent = false }
                        .environmentObject(deepLinks)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { PrivacySettings.shared.rotateIfDue() }
            if phase == .background { PrivacyRequestCounter.saveNow() }
        }
    }
}
