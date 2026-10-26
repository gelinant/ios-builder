import CoreLocation
import Foundation

enum MapDefaults {
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    /// San Francisco, the big-city fixture.
    static let initialCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    static let initialZoom: Double = 12

    /// Credit the Liberty style requires. The map's info button lists the full source attribution.
    static let attribution = "© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors"
    static let attributionURL = URL(string: "https://www.openstreetmap.org/copyright")!
}
