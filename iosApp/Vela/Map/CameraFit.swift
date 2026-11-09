import CoreLocation
import UIKit

/// Where the camera goes when a route is planned or a search answers.
enum CameraFit {
    /// A route preview never zooms past this, so a short walk still shows its streets around it.
    static let routeMaxZoom = 17.0
    static let animationDuration: TimeInterval = 0.6

    /// The flat, north-up camera that shows every point inside [padding], given in points from
    /// the view's edges (the content inset is part of it, not added to it).
    static func flatCamera(showing points: [CLLocationCoordinate2D], size: CGSize,
                           contentInset: UIEdgeInsets, padding: UIEdgeInsets,
                           minZoom: Double = 0, maxZoom: Double = routeMaxZoom) -> MLNMapCamera? {
        let valid = points.filter(CLLocationCoordinate2DIsValid)
        guard !valid.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let xs = valid.map { WebMapProjection.mercatorX($0.longitude) }
        let ys = valid.map { WebMapProjection.mercatorY($0.latitude) }
        let (x0, x1, y0, y1) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let width = max(1, size.width - padding.left - padding.right)
        let height = max(1, size.height - padding.top - padding.bottom)
        let fit = log2(min(Double(width) / max((x1 - x0) * 512, 1e-9),
                           Double(height) / max((y1 - y0) * 512, 1e-9)))
        let zoom = max(minZoom, min(maxZoom, fit.isFinite ? fit : maxZoom))
        // GL JS puts the camera center on the principal point, the middle of the area left by
        // the content inset. The box's middle must land on the middle of the padded area.
        let world = 512 * pow(2, zoom)
        let principal = WebMapProjection(center: kCLLocationCoordinate2DInvalid, zoom: zoom,
                                         bearing: 0, pitch: 0, size: size, inset: contentInset).principal
        let target = CGPoint(x: padding.left + width / 2, y: padding.top + height / 2)
        let cx = (x0 + x1) / 2 - Double(target.x - principal.x) / world
        let cy = (y0 + y1) / 2 - Double(target.y - principal.y) / world
        let center = CLLocationCoordinate2D(latitude: WebMapProjection.latitude(mercatorY: cy),
                                            longitude: cx * 360 - 180)
        return MLNMapCamera(center: center, zoomLevel: zoom, heading: 0, pitch: 0,
                            viewHeight: Double(size.height))
    }

    /// Moves [mapView] to the flat fit of [points]. False when there was nothing to fit.
    @discardableResult
    static func fitFlat(_ points: [CLLocationCoordinate2D], on mapView: MLNMapView,
                        padding: UIEdgeInsets) -> Bool {
        guard let camera = flatCamera(
            showing: points, size: mapView.bounds.size, contentInset: mapView.contentInset,
            padding: padding, minZoom: mapView.minimumZoomLevel,
            maxZoom: min(routeMaxZoom, mapView.maximumZoomLevel)) else { return false }
        mapView.setCamera(camera, withDuration: LaunchOptions.current.animates ? animationDuration : 0,
                          animationTimingFunction: nil, completionHandler: nil)
        return true
    }

    /// The zoom that frames a place of this kind, nil for a business, an address or anything
    /// that is not an area. Photon's category is its OSM `place` value ("City", "State"); Google
    /// gives a language-independent type ("SearchResult.TYPE_LOCALITY") and sometimes a category
    /// such as "City in California". "State park" or "Town hall" is not an area.
    static func areaZoom(category: String?, placeType: String?) -> Double? {
        if let type = placeType?.uppercased(), type.hasPrefix("SEARCHRESULT.TYPE_") {
            let name = type.dropFirst("SEARCHRESULT.TYPE_".count).lowercased()
            if let zoom = areaZooms[name] { return zoom }
            if name.hasPrefix("administrative_area_level_1") { return 7 }
            if name.hasPrefix("administrative_area") { return 9 }
        }
        guard let words = category?.lowercased().split(separator: " ").map(String.init),
              let first = words.first, let zoom = areaZooms[first] else { return nil }
        return words.count == 1 || words.dropFirst().first == "in" ? zoom : nil
    }

    /// The zoom that frames a search row as an area. Google answers a place name ("Sacramento,
    /// CA") with a row that has no category, no rating, no phone and an address without a digit
    /// ("California"): a geocoded place, framed as a city.
    static func areaZoom(_ row: SearchRow) -> Double? {
        if let zoom = areaZoom(category: row.category, placeType: row.placeType) { return zoom }
        let bare = (row.category ?? "").isEmpty && row.rating == nil && row.reviewCount == nil
            && row.phone == nil && row.placeType == nil
        let address = row.address ?? ""
        return bare && !address.isEmpty && !address.contains(where: \.isNumber) ? 12 : nil
    }

    private static let areaZooms: [String: Double] = [
        "continent": 3, "country": 5, "state": 7, "province": 7, "region": 7, "county": 9,
        "district": 10, "city": 11.5, "municipality": 11.5, "locality": 12, "town": 12.5,
        "postal_code": 13, "postcode": 13, "borough": 13, "sublocality": 13.5, "suburb": 14,
        "village": 14, "neighbourhood": 15, "neighborhood": 15, "quarter": 15, "hamlet": 15,
        "colloquial_area": 12,
    ]

    /// The indices of the densest group of [points]: the point with the most others within
    /// [radius] meters (ties go to the better-ranked one) and those neighbors. A far outlier, such
    /// as a namesake in another state, does not widen the frame to a continent.
    static func mainCluster(_ points: [CLLocationCoordinate2D], radius: CLLocationDistance = 50_000) -> [Int] {
        let locations = points.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var best: [Int] = []
        for anchor in locations {
            let near = locations.indices.filter { locations[$0].distance(from: anchor) <= radius }
            if near.count > best.count { best = near }
        }
        return best
    }

    /// One `key=value` line for the UI scenarios: how many of [points] the camera now shows
    /// inside [padding], and the camera itself.
    static func report(_ kind: String, points: [CLLocationCoordinate2D], on mapView: MLNMapView,
                       padding: UIEdgeInsets) -> String {
        let frame = mapView.bounds.inset(by: padding).insetBy(dx: -2, dy: -2)
        let inside = points.filter { frame.contains(mapView.convert($0, toPointTo: mapView)) }.count
        let center = mapView.centerCoordinate
        func f(_ value: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", value) }
        return "fit=\(kind) fit_points=\(points.count) fit_inside=\(inside)"
            + " fit_zoom=\(f(mapView.zoomLevel, 2)) fit_pitch=\(f(Double(mapView.camera.pitch), 0))"
            + " fit_bearing=\(f(mapView.direction, 0))"
            + " fit_center=\(f(center.latitude, 4)),\(f(center.longitude, 4))"
    }
}
