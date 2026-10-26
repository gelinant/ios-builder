#if DEBUG
import Foundation

/// Debug-only Overpass answers derived from the requested box. The UI scenario opts in with
/// `-VelaMapLayersFixture YES`; no fixture coordinate or fake production provider ships.
enum MapLayersTestSupport {
    private static var registered = false

    static func enableIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !registered,
              let index = arguments.firstIndex(of: "-VelaMapLayersFixture"), index + 1 < arguments.count,
              ["yes", "true", "1"].contains(arguments[index + 1].lowercased()) else { return }
        registered = true
        MapLayersFixtureURLProtocol.enabled = true
        _ = URLProtocol.registerClass(MapLayersFixtureURLProtocol.self)
    }

    /// A custom URLSession does not reliably pick up a protocol registered after its creation on
    /// iOS 26. Install the fixture in its protocolClasses as well, still Debug only.
    static func configure(session configuration: URLSessionConfiguration) {
        enableIfRequested()
        guard MapLayersFixtureURLProtocol.enabled else { return }
        configuration.protocolClasses = [MapLayersFixtureURLProtocol.self] + (configuration.protocolClasses ?? [])
    }
}

final class MapLayersFixtureURLProtocol: URLProtocol {
    fileprivate(set) static var enabled = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard enabled, let url = request.url, let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.absoluteString.contains("overpass")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "data" })?.value ?? ""
        let box = Self.box(query) ?? (37.77, -122.43, 37.78, -122.41)
        let body = Self.response(query: query, box: box)
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func response(
        query: String, box: (south: Double, west: Double, north: Double, east: Double)
    ) -> String {
        let lat = (box.south + box.north) / 2
        let lng = (box.west + box.east) / 2
        if query.contains("speed_camera") {
            return elements((0..<3).map { i in
                "{\"lat\":\(number(lat + Double(i) * 0.001)),\"lon\":\(number(lng))}"
            })
        }
        if query.contains("surveillance") {
            return elements((0..<2).map { i in
                "{\"lat\":\(number(lat - Double(i) * 0.001)),\"lon\":\(number(lng + 0.001)),\"tags\":{\"surveillance:type\":\"ALPR\"}}"
            })
        }
        if query.contains("traffic_signals") && !query.contains("way[") {
            let controls = [
                "{\"lat\":\(number(lat)),\"lon\":\(number(lng)),\"tags\":{\"highway\":\"traffic_signals\"}}",
                "{\"lat\":\(number(lat + 0.00002)),\"lon\":\(number(lng + 0.00002)),\"tags\":{\"highway\":\"traffic_signals\"}}",
                "{\"lat\":\(number(lat + 0.00004)),\"lon\":\(number(lng + 0.00004)),\"tags\":{\"highway\":\"traffic_signals\"}}",
                "{\"lat\":\(number(lat + 0.002)),\"lon\":\(number(lng + 0.002)),\"tags\":{\"highway\":\"stop\"}}",
            ]
            return elements(controls)
        }
        if query.contains("way[\"highway\"") {
            return responsePainted(lat: lat, lng: lng)
        }
        return elements([])
    }

    private static func responsePainted(lat: Double, lng: Double) -> String {
        let a = "{\"lat\":\(number(lat - 0.0004)),\"lon\":\(number(lng - 0.003))}"
        let b = "{\"lat\":\(number(lat - 0.0004)),\"lon\":\(number(lng + 0.003))}"
        let c = "{\"lat\":\(number(lat - 0.0004)),\"lon\":\(number(lng))}"
        let d = "{\"lat\":\(number(lat + 0.002)),\"lon\":\(number(lng))}"
        let street = "{\"type\":\"way\",\"tags\":{\"highway\":\"secondary\",\"lanes\":\"4\",\"oneway\":\"no\",\"surface\":\"asphalt\"},\"geometry\":[\(a),\(b)]}"
        let crossing = "{\"type\":\"way\",\"tags\":{\"footway\":\"crossing\",\"crossing\":\"marked\"},\"geometry\":[\(c),\(d)]}"
        let stop = "{\"type\":\"node\",\"lat\":\(number(lat)),\"lon\":\(number(lng)),\"tags\":{\"highway\":\"traffic_signals\"}}"
        return elements([street, crossing, stop])
    }

    private static func elements(_ items: [String]) -> String {
        "{\"elements\":[\(items.joined(separator: ","))]}"
    }

    private static func box(
        _ query: String
    ) -> (south: Double, west: Double, north: Double, east: Double)? {
        guard let open = query.firstIndex(of: "("),
              let close = query[open...].firstIndex(of: ")") else { return nil }
        let values = query[query.index(after: open)..<close].split(separator: ",").compactMap { Double($0) }
        guard values.count >= 4 else { return nil }
        return (values[0], values[1], values[2], values[3])
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
#endif
