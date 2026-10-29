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
    /// chrome has no search field, so the mid-drive scenario hands the phrase to the same
    /// `submit` path the field uses. Nil outside a launch that asks for it.
    static func duringNavCommand() -> String? {
        #if DEBUG
        guard let text = argument("VelaSearchCommandDuringNav")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
        #else
        return nil
        #endif
    }

    /// How far the car must have travelled before [duringNavCommand] runs, 600 m by default.
    static func duringNavMeters() -> Double {
        #if DEBUG
        return argument("VelaSearchCommandDuringNavMeters").flatMap(Double.init) ?? 600.0
        #else
        return 0
        #endif
    }

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
