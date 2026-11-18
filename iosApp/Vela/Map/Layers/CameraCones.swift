import CoreLocation
import Foundation

/// The direction wedge drawn under a plate camera. The pack records a bearing, not a field of
/// view or a range, so the wedge is deliberately an indicator: 36 degrees wide and 30 m long at
/// street zooms. At high zoom its screen size is capped, which shortens it on the ground to a few
/// meters instead of letting a fixed-pixel bitmap claim hundreds of meters. That keeps it honest
/// next to the pack's five-decimal (1.1 m) coordinates and its whole-degree bearings.
///
/// The wedge is built in world coordinates from the bearing. It therefore turns with the map
/// without a second rotation step; `screenBearing` is the equivalent screen angle the tests pin.
enum CameraCones {
    /// Same gate as the camera dots. A cone is never drawn where the dot is hidden.
    static let minZoom = 13.5
    /// Nominal ground length at street zoom, about eight car lengths.
    static let lengthM = 30.0
    /// Half the wedge width. OSM carries no camera field of view, so 18 degrees is an indicator.
    static let halfAngleDeg = 18.0
    /// A low-zoom floor and a high-zoom ceiling, both in screen points.
    static let minScreenLengthPx = 18.0
    static let maxScreenLengthPx = 120.0

    private static let earthRadiusM = 6_371_000.0
    private static let metersPerPointAtEquator = 156_543.03392

    /// A finite bearing folded into 0..<360, or nil when the source has no usable direction.
    static func normalizeBearing(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        let value = raw.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Screen angle of a world bearing once the map is turned. A north-up map draws 90 as east;
    /// a map turned 30 degrees clockwise draws the same camera at 60 degrees on screen.
    static func screenBearing(directionDeg: Double, mapBearingDeg: Double) -> Double {
        guard let direction = normalizeBearing(directionDeg),
              let mapBearing = normalizeBearing(mapBearingDeg) else { return 0 }
        return normalizeBearing(direction - mapBearing) ?? 0
    }

    /// The dots and their cones share one switch and one zoom threshold.
    static func visible(zoom: Double, layerOn: Bool) -> Bool {
        layerOn && zoom >= minZoom
    }

    /// Ground length of the wedge at [zoom]. Between roughly z17 and z19 it is the nominal 30 m;
    /// farther out a screen minimum keeps it visible; above that a screen maximum makes it shrink
    /// to 14 m at z20 and under 4 m at z22.
    static func groundLengthM(zoom: Double, latitudeDeg: Double) -> Double {
        let clampedZoom = max(0.0, min(zoom, 24.0))
        let metersPerPoint = metersPerPointAtEquator
            * cos(latitudeDeg * .pi / 180) / pow(2, clampedZoom)
        guard metersPerPoint.isFinite, metersPerPoint > 0 else { return lengthM }
        let points = min(maxScreenLengthPx,
                         max(minScreenLengthPx, lengthM / metersPerPoint))
        return points * metersPerPoint
    }

    /// Apex at the camera, then an arc across the facing. Empty when the bearing is unusable, so
    /// a malformed direction can never draw a north-facing cone by accident.
    static func wedge(lat: Double, lng: Double, bearingDeg: Double,
                      lengthM: Double) -> [LayerCoordinate] {
        guard let bearing = normalizeBearing(bearingDeg), lengthM > 0,
              (-90.0 ... 90.0).contains(lat), (-180.0 ... 180.0).contains(lng) else {
            return []
        }
        let angularDistance = lengthM / earthRadiusM
        let steps = 8
        var points = [LayerCoordinate(lat: lat, lng: lng)]
        for step in 0 ... steps {
            let offset = -halfAngleDeg + 2 * halfAngleDeg * Double(step) / Double(steps)
            points.append(destination(lat: lat, lng: lng,
                                      bearingDeg: bearing + offset,
                                      angularDistance: angularDistance))
        }
        return points
    }

    private static func destination(lat: Double, lng: Double, bearingDeg: Double,
                                    angularDistance: Double) -> LayerCoordinate {
        let latitude = lat * .pi / 180
        let longitude = lng * .pi / 180
        let bearing = bearingDeg * .pi / 180
        let sinLatitude = sin(latitude)
        let cosLatitude = cos(latitude)
        let sinDistance = sin(angularDistance)
        let cosDistance = cos(angularDistance)
        let targetLatitude = asin(sinLatitude * cosDistance
                                  + cosLatitude * sinDistance * cos(bearing))
        let targetLongitude = longitude + atan2(sin(bearing) * sinDistance * cosLatitude,
                                                cosDistance - sinLatitude * sin(targetLatitude))
        let degrees = targetLongitude * 180 / .pi
        let wrapped = (degrees + 540).truncatingRemainder(dividingBy: 360) - 180
        return LayerCoordinate(lat: targetLatitude * 180 / .pi, lng: wrapped)
    }
}
