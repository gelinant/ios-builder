// Measures how well the mesh transform agrees with MapLibre's own ground projection. Both sides use
// the matrix MapLibre hands to the custom layer, so this checks the world-size convention and the
// Y flip rather than an independent camera model.
import MapLibre
import UIKit

enum CameraProbe {
    static func run(
        context: MLNStyleLayerDrawingContext,
        mapView: MLNMapView,
        block: DEMBlock
    ) -> [String: Any] {
        let size = context.size
        let matrix = context.projectionMatrix
        let zoom = context.zoomLevel
        let worldSize = 512.0 * pow(2.0, zoom)
        let latitude = context.centerCoordinate.latitude * Double.pi / 180
        let metersPerUnit = 40_075_016.686 * max(cos(latitude), 0.01) / worldSize
        let center = context.centerCoordinate

        let degreePerUnit = 360.0 / worldSize
        let fractions: [Double] = [-0.6, -0.3, 0, 0.3, 0.6]
        var best: (flip: Bool, maxError: Double, meanError: Double, count: Int, horizonLift: Double) =
            (true, .infinity, .infinity, 0, 0)

        for flip in [false, true] {
            var maxError = 0.0
            var sumError = 0.0
            var count = 0
            var horizonLift = 0.0
            for fy in fractions {
                for fx in fractions {
                    let lon = center.longitude + fx * Double(size.width) / 2 * degreePerUnit
                    let lat = center.latitude + fy * Double(size.height) / 2 * degreePerUnit * cos(latitude)
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let expected = mapView.convert(coordinate, toPointTo: mapView)
                    guard expected.x.isFinite, expected.y.isFinite,
                          expected.x > -20, expected.x < size.width + 20,
                          expected.y > -20, expected.y < size.height + 20 else { continue }
                    let mercator = project(coordinate)
                    let ground = apply(matrix, SIMD4<Double>(
                        mercator.x * worldSize,
                        mercator.y * worldSize,
                        0,
                        1
                    ))
                    guard ground.w > 1e-6 else { continue }
                    let ndcX = ground.x / ground.w
                    let ndcY = ground.y / ground.w
                    guard abs(ndcX) <= 1.2, abs(ndcY) <= 1.2 else { continue }
                    var pixel = CGPoint(
                        x: (ndcX * 0.5 + 0.5) * Double(size.width),
                        y: (0.5 - ndcY * 0.5) * Double(size.height)
                    )
                    if flip {
                        pixel.y = Double(size.height) - pixel.y
                    }
                    let error = hypot(pixel.x - Double(expected.x), pixel.y - Double(expected.y))
                    maxError = max(maxError, error)
                    sumError += error
                    count += 1

                    // How far the real surface rises above the flat map point at the horizon. This
                    // is not a sync error, it is the reason the mesh exists; it is reported apart.
                    let height = Double(block.heightAt(latitude: lat, longitude: lon))
                    let raised = apply(matrix, SIMD4<Double>(
                        mercator.x * worldSize,
                        mercator.y * worldSize,
                        height,
                        1
                    ))
                    if raised.w > 1e-6 {
                        let raisedNdcY = raised.y / raised.w
                        var raisedPixelY = (0.5 - raisedNdcY * 0.5) * Double(size.height)
                        if flip { raisedPixelY = Double(size.height) - raisedPixelY }
                        horizonLift = max(horizonLift, abs(raisedPixelY - pixel.y))
                    }
                }
            }
            if count > 0, sumError / Double(count) < best.meanError {
                best = (flip, maxError, sumError / Double(count), count, horizonLift)
            }
        }

        return [
            "zoom": zoom,
            "pitch": Double(context.pitch),
            "heading": Double(context.direction),
            "points": best.count,
            "flipY": best.flip,
            "maxErrorPx": best.maxError,
            "meanErrorPx": best.meanError,
            "horizonLiftPx": best.horizonLift,
        ]
    }

    private static func project(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let x = (180.0 + coordinate.longitude) / 360.0
        let latitude = coordinate.latitude * Double.pi / 180
        let y = (180.0 - log(tan(latitude) + 1 / cos(latitude)) * (180.0 / Double.pi)) / 360.0
        return (x, y)
    }

    /// Matrix fields are in column-major memory order, exactly like the float4x4 the shader sees.
    private static func apply(_ m: MLNMatrix4, _ v: SIMD4<Double>) -> SIMD4<Double> {
        SIMD4<Double>(
            m.m00 * v.x + m.m10 * v.y + m.m20 * v.z + m.m30 * v.w,
            m.m01 * v.x + m.m11 * v.y + m.m21 * v.z + m.m31 * v.w,
            m.m02 * v.x + m.m12 * v.y + m.m22 * v.z + m.m32 * v.w,
            m.m03 * v.x + m.m13 * v.y + m.m23 * v.z + m.m33 * v.w
        )
    }
}
