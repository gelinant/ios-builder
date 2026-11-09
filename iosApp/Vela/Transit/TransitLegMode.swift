import Foundation

/// The readable identity of one transit leg's vehicle, built from the planner's own mode name and,
/// when it helps, the leg's agency: "Bus 38", "M2", "RER B", "Cable car". A mode the planner leaves
/// generic reads "Transit" and never a guessed vehicle.
struct TransitLegMode: Equatable {
    /// The planner's raw mode name in upper case, "GENERIC" when it gave none.
    let kind: String
    /// The readable mode name: Walk, Bus, Tram, Metro, Rail, Ferry, Cable car, Funicular, Coach,
    /// Bike or Transit.
    let name: String
    /// The SF Symbol drawn beside the name.
    let symbol: String

    var isWalk: Bool { kind == "WALK" }

    /// Maps a planner mode name (or a coarse `TransitMode` name) to its readable identity.
    static func of(kind: String?) -> TransitLegMode {
        let raw = (kind ?? "").uppercased()
        switch raw {
        case "WALK":
            return TransitLegMode(kind: raw, name: "Walk", symbol: "figure.walk")
        case "BIKE":
            return TransitLegMode(kind: raw, name: "Bike", symbol: "bicycle")
        case "BUS", "TROLLEYBUS":
            return TransitLegMode(kind: raw, name: "Bus", symbol: "bus.fill")
        case "COACH":
            return TransitLegMode(kind: raw, name: "Coach", symbol: "bus.doubledecker.fill")
        case "TRAM":
            return TransitLegMode(kind: raw, name: "Tram", symbol: "tram.fill")
        case "SUBWAY", "METRO":
            return TransitLegMode(kind: raw, name: "Metro", symbol: "tram.fill.tunnel")
        case "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "HIGHSPEED_RAIL", "LONG_DISTANCE",
             "NIGHT_RAIL":
            return TransitLegMode(kind: raw, name: "Rail", symbol: "train.side.front.car")
        case "FERRY":
            return TransitLegMode(kind: raw, name: "Ferry", symbol: "ferry.fill")
        case "CABLE_CAR", "AERIAL_LIFT", "GONDOLA":
            return TransitLegMode(kind: raw, name: "Cable car", symbol: "cablecar")
        case "FUNICULAR":
            return TransitLegMode(kind: raw, name: "Funicular", symbol: "tram.fill")
        default:
            return TransitLegMode(kind: raw.isEmpty ? "GENERIC" : raw, name: "Transit", symbol: "tram.fill")
        }
    }

    /// The leg's headline: the mode and its line, "Bus 38", "M2", "RER B", "Tram K", "Walk". A
    /// generic mode keeps the word "Transit" and only adds the line the planner itself sent.
    func title(line: String?) -> String {
        let line = (line ?? "").trimmingCharacters(in: .whitespaces)
        switch kind {
        case "WALK":
            return "Walk"
        case "BIKE":
            return "Bike"
        case "BUS", "TROLLEYBUS":
            return line.isEmpty ? "Bus" : "Bus \(line)"
        case "COACH":
            return line.isEmpty ? "Coach" : "Coach \(line)"
        case "TRAM":
            return line.isEmpty ? "Tram" : "Tram \(line)"
        case "SUBWAY", "METRO":
            guard !line.isEmpty else { return "Metro" }
            return line.uppercased().hasPrefix("M") && line.dropFirst().first?.isNumber == true
                ? line : "M\(line)"
        case "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "HIGHSPEED_RAIL", "LONG_DISTANCE",
             "NIGHT_RAIL":
            return line.isEmpty ? "Rail" : "Rail \(line)"
        case "FERRY":
            return line.isEmpty ? "Ferry" : "Ferry \(line)"
        case "CABLE_CAR", "AERIAL_LIFT", "GONDOLA":
            return line.isEmpty ? "Cable car" : "Cable car \(line)"
        case "FUNICULAR":
            return line.isEmpty ? "Funicular" : "Funicular \(line)"
        default:
            return line.isEmpty ? "Transit" : "Transit \(line)"
        }
    }

    /// The leg's headline when the agency names the network: "RER B", "Transilien L", "TER 12".
    /// Anything else keeps [title]; an agency alone never turns a generic leg into a vehicle.
    func title(line: String?, agency: String?) -> String {
        let line = (line ?? "").trimmingCharacters(in: .whitespaces)
        let agency = (agency ?? "").trimmingCharacters(in: .whitespaces)
        guard !agency.isEmpty else { return title(line: line) }
        let network = agency.uppercased()
        if kind == "RAIL" || kind.hasSuffix("RAIL") || kind == "LONG_DISTANCE" || kind == "NIGHT_RAIL" {
            for prefix in ["RER", "TRANSILIEN", "TER"] where network.contains(prefix) {
                return line.isEmpty ? prefix : "\(prefix) \(line)"
            }
        }
        return title(line: line)
    }

    /// The mode name and, when it is not already in the headline, the agency: "Metro · RATP".
    func subtitle(line: String?, agency: String?) -> String {
        let agency = (agency ?? "").trimmingCharacters(in: .whitespaces)
        guard !agency.isEmpty, !title(line: line, agency: agency).uppercased().contains(agency.uppercased())
        else { return name }
        return "\(name) · \(agency)"
    }

    /// The compact sequence of a whole trip, "Walk · M1 · RER A · Walk".
    static func sequence(_ legs: [(kind: String, line: String?, agency: String?)]) -> String {
        legs.map { of(kind: $0.kind).title(line: $0.line, agency: $0.agency) }.joined(separator: " · ")
    }
}
