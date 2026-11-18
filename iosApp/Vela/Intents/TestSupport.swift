import Foundation
import VelaCore

/// Debug-only launch hooks for XCUITest. They call the existing SavedStore APIs and never add a
/// production route or a second persistence path.
enum VelaIntentTestSupport {
    #if DEBUG
    private static var prepared = false
    private static var openedFirstSaved = false
    #endif

    static func prepareIfNeeded() {
        #if DEBUG
        guard !prepared else { return }
        prepared = true
        let arguments = ProcessInfo.processInfo.arguments
        if flag("VelaIntentTestReset", arguments: arguments) {
            let store = AppGraph.session.saved
            store.clearShortcutNamed(name: "HOME")
            store.clearShortcutNamed(name: "WORK")
            store.clearParking()
        }
        if value("VelaIntentTestFixture", arguments: arguments) == "parking" {
            AppGraph.session.saved.saveParking(at: LatLng(lat: 37.7749, lng: -122.4194))
        }
        #endif
    }

    /// Opens the newest quick save or list entry through the real URL center after a UI test has
    /// created it. The identifier stays out of screenshots and test logs.
    static func consumeFirstSavedLink() -> URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard !openedFirstSaved, flag("VelaOpenSavedLink", arguments: arguments) else { return nil }
        openedFirstSaved = true
        return VelaSavedContent.current.savedPlaces.first?.deepLink.url
        #else
        return nil
        #endif
    }

    #if DEBUG
    private static func value(_ name: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func flag(_ name: String, arguments: [String]) -> Bool {
        guard let value = value(name, arguments: arguments)?.lowercased() else { return false }
        return value == "yes" || value == "true" || value == "1"
    }
    #endif
}
