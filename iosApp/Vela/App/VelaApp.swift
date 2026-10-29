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
    #if DEBUG
    /// M-2 fixture: open the separate Relief screen once the map screen is up, for
    /// TerrainUITests only. The short delay lets the UI test wait for the launch screen first.
    @State private var showsTerrainFixture = false
    #endif

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
        #if DEBUG
        // The line sheet's recorded fixture (docs/ios/TRANSIT-DESIGN.md). It opens through the
        // same TransitLineLink entry point a board row uses; no production path reads this flag.
        Task { @MainActor in TransitLineLink.shared.startFixtureIfRequested() }
        #endif
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
                #if DEBUG
                .fullScreenCover(isPresented: $showsTerrainFixture) {
                    TerrainScreen()
                }
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("-VelaTerrainFixture") else { return }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    showsTerrainFixture = true
                }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { PrivacySettings.shared.rotateIfDue() }
            if phase == .background { PrivacyRequestCounter.saveNow() }
        }
    }
}
