import CoreLocation
import Foundation

enum MapDefaults {
    /// A local style document generated from the bundled Liberty base. There is deliberately no
    /// remote fallback: a bundle without the generated styles shows the base document instead of
    /// fetching a style from a server.
    static var styleURL: URL {
        MapStyleBuilder.bundledStyleURL()
            ?? MapStyleBuilder.resource("liberty-roboto")
            ?? URL(fileURLWithPath: "/dev/null")
    }

    /// San Francisco, the big-city fixture.
    static let initialCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    static let initialZoom: Double = 12

    /// Credit the Liberty style requires. The map's info button lists the full source attribution.
    static let attribution = "© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors"
    static let attributionURL = URL(string: "https://www.openstreetmap.org/copyright")!
}
