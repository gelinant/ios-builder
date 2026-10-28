import Foundation

/// One Transitous stop drawn on the map at high zoom. Swift holds the ids its board needs.
struct TransitStopMarker: Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let modes: [String]
    let parentId: String?
    let siblingIds: [String]

    /// A short glyph for the pin; the feed's first mode decides it, never a guessed vehicle.
    var symbol: String {
        let first = modes.first?.uppercased() ?? ""
        if first.contains("RAIL") || first == "SUBURBAN" || first == "LONG_DISTANCE" { return "tram.fill" }
        if first == "TRAM" || first == "SUBWAY" || first == "METRO" { return "tram.fill" }
        if first == "FERRY" { return "ferry.fill" }
        return "bus.fill"
    }
}
