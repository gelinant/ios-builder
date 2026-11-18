#if DEBUG
import CoreLocation
import Foundation

/// Debug-only navigation render for NavRenderUITests. A live fixture route does not always carry
/// traffic spans or lanes, and its turns can be kilometers away from the car, so the scenario opts
/// in with `-VelaNavRenderFixture YES` and gets a known gray cut, one heavy stretch, two arrows
/// near the car and a lane row. The symbols and kinds come from the banner's own state, so the
/// screenshot still proves the map and the card agree.
enum NavRenderTestSupport {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var enabled: Bool {
        guard let index = arguments.firstIndex(of: "-VelaNavRenderFixture"),
              index + 1 < arguments.count else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }

    static func apply(
        to draw: NavRouteDraw,
        traveledM: Double,
        kind: String,
        nextKind: String,
        lanes: [NavBannerLane]
    ) -> NavRouteDraw {
        var route: [CLLocationCoordinate2D] = []
        for piece in draw.pieces {
            for coordinate in piece.coordinates {
                if let last = route.last, distance(last, coordinate) < 0.4 { continue }
                route.append(coordinate)
            }
        }
        guard route.count >= 2 else { return draw }
        let total = length(route)
        let done = min(max(traveledM, 0), max(total - 5, 0))
        let heavyEnd = min(total, done + 120)
        let cutEnd = min(total, done + 12)
        var result = NavRouteDraw.empty
        let rawPieces: [(level: Int, coordinates: [CLLocationCoordinate2D])] = [
            (level: -1, coordinates: slice(route, from: 0, to: cutEnd)),
            (level: 2, coordinates: slice(route, from: cutEnd, to: heavyEnd)),
            (level: 0, coordinates: slice(route, from: heavyEnd, to: total)),
        ]
        result.pieces = rawPieces
            .filter { $0.coordinates.count >= 2 }
            .map { NavRoutePiece(level: $0.level, coordinates: $0.coordinates) }

        let nextAt = min(total, done + 55)
        let thenAt = min(total, done + 140)
        let following = nextKind.isEmpty ? kind : nextKind
        result.arrows = [
            NavRouteArrow(
                role: "next", kind: kind,
                coordinate: point(route, at: nextAt),
                rotation: bearing(route, before: nextAt)),
            NavRouteArrow(
                role: "then", kind: following,
                coordinate: point(route, at: thenAt),
                rotation: bearing(route, before: thenAt)),
        ].filter { $0.coordinate.latitude != 0 || $0.coordinate.longitude != 0 }

        if !lanes.isEmpty {
            let laneAt = min(total, done + 32)
            let center = point(route, at: laneAt)
            let heading = bearing(route, before: laneAt)
            let middle = Double(lanes.count - 1) / 2
            result.lanes = lanes.enumerated().map { index, lane in
                let offset = (Double(index) - middle) * 3.2
                return NavRouteLane(
                    indications: lane.arrows, valid: lane.valid,
                    coordinate: move(center, bearing: heading + 90, meters: offset),
                    rotation: heading)
            }
        }
        return result
    }

    private static func length(_ route: [CLLocationCoordinate2D]) -> Double {
        var total = 0.0
        for index in 1..<route.count { total += distance(route[index - 1], route[index]) }
        return total
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private static func point(_ route: [CLLocationCoordinate2D], at meters: Double) -> CLLocationCoordinate2D {
        guard meters > 0, route.count >= 2 else { return route.first ?? CLLocationCoordinate2D() }
        var walked = 0.0
        for index in 1..<route.count {
            let step = distance(route[index - 1], route[index])
            if walked + step >= meters {
                let fraction = step <= 0 ? 0 : (meters - walked) / step
                return CLLocationCoordinate2D(
                    latitude: route[index - 1].latitude
                        + (route[index].latitude - route[index - 1].latitude) * fraction,
                    longitude: route[index - 1].longitude
                        + (route[index].longitude - route[index - 1].longitude) * fraction)
            }
            walked += step
        }
        return route.last!
    }

    private static func slice(_ route: [CLLocationCoordinate2D], from: Double, to: Double)
        -> [CLLocationCoordinate2D] {
        guard to - from > 1 else { return [] }
        var out = [point(route, at: from)]
        var walked = 0.0
        for index in 1..<route.count {
            walked += distance(route[index - 1], route[index])
            if walked > from + 0.5 && walked < to - 0.5 { out.append(route[index]) }
        }
        out.append(point(route, at: to))
        return out
    }

    private static func bearing(_ route: [CLLocationCoordinate2D], before meters: Double) -> Double {
        let start = point(route, at: max(0, meters - 20))
        let end = point(route, at: max(0, meters - 1))
        let dLat = end.latitude - start.latitude
        let dLng = (end.longitude - start.longitude)
            * cos(start.latitude * Double.pi / 180)
        return (atan2(dLng, dLat) * 180 / Double.pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func move(_ from: CLLocationCoordinate2D, bearing degrees: Double,
                             meters: Double) -> CLLocationCoordinate2D {
        if meters == 0 { return from }
        let radians = degrees * Double.pi / 180
        let dLat = meters * cos(radians) / 111_320
        let dLng = meters * sin(radians)
            / (111_320 * max(0.2, cos(from.latitude * Double.pi / 180)))
        return CLLocationCoordinate2D(latitude: from.latitude + dLat,
                                      longitude: from.longitude + dLng)
    }
}
#endif
