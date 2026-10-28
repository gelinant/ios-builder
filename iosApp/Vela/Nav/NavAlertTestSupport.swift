#if DEBUG
import CoreLocation
import Foundation

/// Debug-only Overpass answers derived from the route query itself. No fixture coordinates or fake
/// production provider ship in the app. The UI scenario opts in with -VelaNavAlertsFixture YES.
enum NavAlertTestSupport {
    private static var registered = false

    static func enableIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !registered,
              let index = arguments.firstIndex(of: "-VelaNavAlertsFixture"), index + 1 < arguments.count,
              ["yes", "true", "1"].contains(arguments[index + 1].lowercased()) else { return }
        registered = true
        NavAlertFixtureURLProtocol.enabled = true
        _ = URLProtocol.registerClass(NavAlertFixtureURLProtocol.self)
    }

    /// A custom URLSession does not reliably pick up a protocol registered after its creation on
    /// iOS 26. Install the fixture in its protocolClasses as well, still Debug only.
    static func configure(session configuration: URLSessionConfiguration) {
        enableIfRequested()
        guard NavAlertFixtureURLProtocol.enabled else { return }
        configuration.protocolClasses = [NavAlertFixtureURLProtocol.self] + (configuration.protocolClasses ?? [])
    }
}

final class NavAlertFixtureURLProtocol: URLProtocol {
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
        let route = Self.routePoints(query)
        let body = Self.response(query: query, route: route)
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func response(query: String, route: [CLLocationCoordinate2D]) -> String {
        guard let camera = point(atLeast: 250, route: route) else {
            return #"{"elements":[]}"#
        }
        let lat = number(camera.latitude)
        let lng = number(camera.longitude)
        if query.contains("speed_camera") {
            return #"{"elements":[{"lat":\#(lat),"lon":\#(lng)}]}"#
        }
        if query.contains("surveillance") {
            return #"{"elements":[{"lat":\#(lat),"lon":\#(lng),"tags":{"surveillance:type":"ALPR"}}]}"#
        }
        if query.contains("maxspeed") {
            let geometry = route.map {
                #"{"lat":\#(number($0.latitude)),"lon":\#(number($0.longitude))}"#
            }.joined(separator: ",")
            return #"{"elements":[{"tags":{"maxspeed":"80"},"geometry":[\#(geometry)]}]}"#
        }
        return #"{"elements":[]}"#
    }

    private static func routePoints(_ query: String) -> [CLLocationCoordinate2D] {
        guard let begin = query.range(of: "(around:"),
              let end = query[begin.upperBound...].firstIndex(of: ")") else { return [] }
        let values = query[begin.upperBound..<end].split(separator: ",").dropFirst()
            .compactMap { Double($0) }
        guard values.count >= 4 else { return [] }
        var points: [CLLocationCoordinate2D] = []
        var index = 0
        while index + 1 < values.count {
            points.append(CLLocationCoordinate2D(latitude: values[index], longitude: values[index + 1]))
            index += 2
        }
        return points
    }

    private static func point(
        atLeast meters: Double,
        route: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        guard route.count >= 2 else { return nil }
        var traveled = 0.0
        for index in 1..<route.count {
            let previous = CLLocation(latitude: route[index - 1].latitude, longitude: route[index - 1].longitude)
            let current = CLLocation(latitude: route[index].latitude, longitude: route[index].longitude)
            traveled += previous.distance(from: current)
            if traveled >= meters { return route[index] }
        }
        return route.last
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
#endif
