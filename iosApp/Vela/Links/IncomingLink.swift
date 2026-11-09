import Foundation
import VelaCore

/// What an external link asks Vela to do. The common `MapLinkParser` supplies the data; this enum
/// only says which screen the map should show (a place sheet, a result list or the route chooser).
enum VelaIncomingKind: String, Equatable, Sendable {
    case place
    case search
    case directions
}

/// One end of a link: a name from the link, a point from the link, or both.
struct VelaIncomingPoint: Equatable, Sendable {
    let name: String?
    let latitude: Double?
    let longitude: Double?

    var hasCoordinates: Bool { latitude != nil && longitude != nil }
    var hasName: Bool { !(name ?? "").isEmpty }
}

/// A Google Maps or `geo:` link, copied out of the Kotlin `MapLink` so Swift holds a value.
struct VelaIncomingLink: Equatable, Sendable {
    /// Vela's own stop cap (`RouteStore.MAX_WAYPOINTS`): a link with more keeps its first stops.
    static let maxStops = 10

    let kind: VelaIncomingKind
    /// The URL the link came from, for diagnostics and for `VelaDeepLink.url`.
    let source: URL
    let target: VelaIncomingPoint?
    let origin: VelaIncomingPoint?
    /// The link's intermediate stops in travel order, at most `maxStops`.
    let stops: [VelaIncomingPoint]
    /// How many stops the link carried beyond `maxStops`; the map tells the user when it is not 0.
    let droppedStops: Int
    let zoom: Double?
    let featureID: String?
    let cid: String?
    /// The travel mode the link named (`DRIVE`, `WALK`, ...), nil to keep the stored mode.
    let mode: String?

    /// Every stop the link named, including the ones Vela had to leave out.
    var stopCount: Int { stops.count + droppedStops }

    var hasTarget: Bool {
        guard let target else { return false }
        return target.hasName || target.hasCoordinates
    }
}

/// The parser's answer: an internal Vela route, a short link whose redirect must be read first, or
/// a link Vela refuses.
enum VelaIncomingParse: Equatable {
    case route(VelaDeepLink)
    case resolve(URL)
    case rejected(VelaDeepLinkError)
}

/// Accepts only the links a maps app should open. Every other scheme and every non-Google host is
/// refused here, before anything can be loaded: Vela never opens arbitrary web content.
enum VelaIncomingLinkParser {
    static func parse(_ url: URL) -> VelaIncomingParse {
        switch (url.scheme ?? "").lowercased() {
        case "vela":
            switch VelaDeepLinkRouter.parse(url) {
            case .success(let route): return .route(route)
            case .failure(let error): return .rejected(error)
            }
        case "geo", "google.navigation":
            return googleParse(url, forcedKind: url.scheme?.lowercased() == "google.navigation" ? .directions : nil)
        case "http", "https":
            guard isGoogleMapsHost(url) else { return .rejected(.unsupportedScheme) }
            if isMapShortener(url) { return .resolve(url) }
            return googleParse(url, forcedKind: nil)
        default:
            return .rejected(.unsupportedScheme)
        }
    }

    /// The `cid` a Google link carries without a name or a coordinate. Kept separate because a
    /// bare cid cannot be opened offline (see docs/ios/INCOMING-LINKS.md).
    static func cid(in url: URL) -> String? {
        let value = queryValue(url, "cid")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, value.allSatisfy({ $0.isNumber }) else { return nil }
        return value
    }

    /// The S2 cell a place link's feature id names, used to bias a search by name.
    static func featureCell(_ featureID: String?) -> (latitude: Double, longitude: Double)? {
        guard let cell = MapLinkParser.shared.featureCell(featureId: featureID) else { return nil }
        return (cell.lat, cell.lng)
    }

    private static func googleParse(_ url: URL, forcedKind: VelaIncomingKind?) -> VelaIncomingParse {
        let raw = url.absoluteString
        if ShortLinks.shared.isList(url: raw) { return .rejected(.unreadableLink) }
        let cid = cid(in: url)
        guard let parsed = MapLinkParser.shared.parse(raw: raw) else {
            // A bare cid has nothing else: no name, no point, no redirect. The map can still match
            // it to a saved place's feature id, so it is carried through as an incoming link.
            if let cid {
                return .route(.incoming(VelaIncomingLink(
                    kind: .place, source: url, target: nil, origin: nil, stops: [], droppedStops: 0,
                    zoom: nil, featureID: linkFeatureID(url), cid: cid, mode: nil)))
            }
            return .rejected(.unreadableLink)
        }
        // A stop the common parser could not read makes the whole link unreadable: opening a trip
        // without it would be a silent different route.
        if parsed.stopsMalformed { return .rejected(.malformedStop) }
        let target = point(parsed)
        let featureID = parsed.featureId ?? linkFeatureID(url)
        let kind = forcedKind ?? kind(for: url, link: parsed)
        // Points dragged onto the route shape it; they are not stops the user can edit.
        let carried = parsed.stops.filter { !$0.via }.compactMap { point($0) }
        let stops = Array(carried.prefix(VelaIncomingLink.maxStops))
        if target == nil, cid == nil { return .rejected(.unreadableLink) }
        let link = VelaIncomingLink(
            kind: kind,
            source: url,
            target: target,
            origin: point(parsed.origin),
            stops: kind == .directions ? stops : [],
            droppedStops: kind == .directions ? carried.count - stops.count : 0,
            zoom: parsed.zoom?.doubleValue,
            featureID: featureID,
            cid: cid,
            mode: travelMode(from: raw))
        return .route(.incoming(link))
    }

    private static func point(_ link: MapLink?) -> VelaIncomingPoint? {
        guard let link else { return nil }
        let name = link.query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let latitude = link.lat?.doubleValue
        let longitude = link.lng?.doubleValue
        let hasCoordinates = latitude != nil && longitude != nil
        guard !(name ?? "").isEmpty || hasCoordinates else { return nil }
        return VelaIncomingPoint(
            name: (name ?? "").isEmpty ? nil : name,
            latitude: latitude,
            longitude: longitude)
    }

    private static func kind(for url: URL, link: MapLink) -> VelaIncomingKind {
        if link.directions { return .directions }
        let path = url.path.lowercased()
        if path.contains("/maps/search") { return .search }
        if path.contains("/maps/place") { return .place }
        if url.scheme?.lowercased() == "geo" {
            return link.query != nil && link.lat == nil && link.lng == nil ? .search : .place
        }
        // The classic `maps?...&q=` form is a search when it carries no point of its own.
        if (queryValue(url, "q") != nil || queryValue(url, "query") != nil),
           link.lat == nil, link.lng == nil {
            return .search
        }
        return .place
    }

    /// The travel mode the link names, as the enum names `RouteStore` takes. The common parser
    /// reads it too, but Swift keeps no Kotlin enum here.
    private static func travelMode(from raw: String) -> String? {
        if let value = rawValue(raw, "travelmode")?.lowercased() {
            switch value {
            case "walking": return "WALK"
            case "bicycling": return "BICYCLE"
            case "transit": return "TRANSIT"
            case "driving", "two-wheeler": return "DRIVE"
            default: break
            }
        }
        if let flag = rawValue(raw, "dirflg")?.lowercased().first {
            switch flag {
            case "w": return "WALK"
            case "b": return "BICYCLE"
            case "r": return "TRANSIT"
            case "d": return "DRIVE"
            default: break
            }
        }
        if raw.lowercased().hasPrefix("google.navigation:"),
           let flag = rawValue(raw, "mode")?.lowercased().first {
            switch flag {
            case "w": return "WALK"
            case "b": return "BICYCLE"
            case "d", "l": return "DRIVE"
            default: break
            }
        }
        if let range = raw.range(of: #"!3e([0-3])(?:!|$|\?)"#, options: .regularExpression) {
            switch String(raw[range].dropFirst(3).prefix(1)) {
            case "0": return "DRIVE"
            case "1": return "BICYCLE"
            case "2": return "WALK"
            case "3": return "TRANSIT"
            default: break
            }
        }
        return nil
    }

    /// A query or opaque-scheme parameter; `google.navigation:q=...&mode=w` has no `?`.
    private static func rawValue(_ raw: String, _ key: String) -> String? {
        let body: String
        if let mark = raw.firstIndex(of: "?") {
            body = String(raw[raw.index(after: mark)...])
        } else if let mark = raw.firstIndex(of: ":") {
            body = String(raw[raw.index(after: mark)...])
        } else {
            body = raw
        }
        for part in body.split(separator: "&") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2, String(pieces[0]).caseInsensitiveCompare(key) == .orderedSame else {
                continue
            }
            return String(pieces[1])
        }
        return nil
    }

    private static func linkFeatureID(_ url: URL) -> String? {
        guard let value = queryValue(url, "ftid") else { return nil }
        return value.contains(":") ? value : nil
    }

    private static func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?
            .value
    }

    private static func isMapShortener(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "maps.app.goo.gl" { return true }
        return host == "goo.gl" && url.path.lowercased().hasPrefix("/maps")
    }

    /// Google's map hosts only: a map path on a Google domain, or a Maps shortener. google.com
    /// search, mail and every other service are refused even though the domain matches.
    private static func isGoogleMapsHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "maps.app.goo.gl" { return true }
        if host == "goo.gl" { return url.path.lowercased().hasPrefix("/maps") }
        let mapsHost = host == "maps.google.com" || host.hasPrefix("maps.google.")
        if mapsHost { return true }
        let googleHost = host == "google.com" || host == "www.google.com"
            || host.range(
                of: #"^(www\.)?google\.[a-z]{2,3}(\.[a-z]{2})?$"#,
                options: .regularExpression) != nil
        return googleHost && url.path.lowercased().hasPrefix("/maps")
    }
}
