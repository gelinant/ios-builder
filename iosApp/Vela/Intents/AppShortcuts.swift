import AppIntents

/// English source phrases are translated in en.lproj and fr.lproj/AppShortcuts.strings. The query
/// is requested by Siri or supplied by Shortcuts because an open-ended String cannot be interpolated
/// into an App Shortcut phrase. Saved place entities can be spoken directly.
struct VelaAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NavigateHomeIntent(),
            phrases: [
                "Navigate home with \(.applicationName)",
                "Go home with \(.applicationName)",
            ],
            shortTitle: "Navigate Home",
            systemImageName: "house.fill")
        AppShortcut(
            intent: NavigateWorkIntent(),
            phrases: [
                "Navigate to work with \(.applicationName)",
                "Go to work with \(.applicationName)",
            ],
            shortTitle: "Navigate to Work",
            systemImageName: "briefcase.fill")
        AppShortcut(
            intent: WhereIsMyCarIntent(),
            phrases: [
                "Where is my car in \(.applicationName)",
                "Find my parked car with \(.applicationName)",
            ],
            shortTitle: "Find My Car",
            systemImageName: "car.fill")
        AppShortcut(
            intent: SearchVelaIntent(),
            phrases: [
                "Search with \(.applicationName)",
                "Find a place with \(.applicationName)",
            ],
            shortTitle: "Search Vela",
            systemImageName: "magnifyingglass")
        AppShortcut(
            intent: NavigateToPlaceIntent(),
            phrases: [
                "Navigate to \(\.$place) with \(.applicationName)",
                "Navigate to a saved place with \(.applicationName)",
            ],
            shortTitle: "Navigate to Saved Place",
            systemImageName: "mappin.circle.fill")
    }
}
