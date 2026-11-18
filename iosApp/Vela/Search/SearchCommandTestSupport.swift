import Foundation
import VelaCore

/// Debug-only state for the typed and spoken command scenarios. It uses the real SavedStore and
/// only runs when a launch line asks for it, so a normal launch never gains a shortcut or a route.
enum SearchCommandTestSupport {
    #if DEBUG
    private static var prepared = false
    #endif

    /// Seeds Home, Work and a fixed San Francisco route once per process. Called after the map's
    /// own test reset, so the shortcuts the test reads are exactly these.
    static func prepareIfNeeded() {
        #if DEBUG
        // QUALITY-REG: the route-order audit needs the router's answer to be deterministic, so the
        // fixture is armed from the same early call that seeds the command shortcuts. It is only a
        // router replacement; the chooser, its toggles and its actions stay the real UI.
        if flag("VelaRouteOrderFixture") { RouteOrderFixture.shared.enabled = true }
        guard !prepared else { return }
        prepared = true
        guard flag("VelaSearchCommandFixture") else { return }
        let store = AppGraph.session.saved
        // Overwrite both shortcuts instead of relying on a reset that may run in another order:
        // the scenario always starts from its own Home and Work.
        store.clearShortcutNamed(name: "HOME")
        store.clearShortcutNamed(name: "WORK")
        store.setShortcutNamed(name: "HOME", place: SearchCommandPlaces.shared.place(
            id: "command-fixture:home",
            name: "Ferry Building",
            address: "1 Ferry Building, San Francisco",
            lat: 37.7955,
            lng: -122.3937))
        store.setShortcutNamed(name: "WORK", place: SearchCommandPlaces.shared.place(
            id: "command-fixture:work",
            name: "Salesforce Tower",
            address: "415 Mission St, San Francisco",
            lat: 37.7897,
            lng: -122.3972))
        #endif
    }

    /// The route the along-route scenario searches beside, as flat lat,lng pairs. Ignored once a
    /// real route is planned: the command always reads the live route first.
    static func routeFixture() -> [Double]? {
        #if DEBUG
        let text = flag("VelaSearchCommandFixture")
            ? argument("VelaSearchCommandRoute") ?? "37.7749,-122.4194;37.7955,-122.3937"
            : argument("VelaSearchCommandRoute")
        guard let text, !text.isEmpty else { return nil }
        let values = text.split(whereSeparator: { $0 == ";" || $0 == " " })
            .flatMap { pair in pair.split(separator: ",").compactMap { Double($0) } }
        return values.count >= 4 && values.count % 2 == 0 ? values : nil
        #else
        return nil
        #endif
    }

    /// A command the Debug scenarios submit once a drive has travelled far enough. The drive
    /// chrome has no search field, so the along-route scenario hands this phrase to the same
    /// `submit` path the field uses. It rides the existing fixture flag, which no scenario turns
    /// on without a drive, and does nothing in Release.
    static func duringNavCommand() -> String? {
        #if DEBUG
        return flag("VelaSearchCommandFixture") ? "coffee along the route" : nil
        #else
        return nil
        #endif
    }

    /// How far the car must have travelled before [duringNavCommand] runs, 600 m.
    static let duringNavMeters = 600.0

    #if DEBUG
    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func flag(_ name: String) -> Bool {
        guard let value = argument(name)?.lowercased() else { return false }
        return value == "yes" || value == "true" || value == "1"
    }
    #endif
}
