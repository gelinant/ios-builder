import CoreLocation
import MapLibre
import SwiftUI
import UIKit
import VelaCore

/// The recorded line on a static MapLibre map: blue trace, green start and red end. It never asks
/// for the user's location and loads the same public style as the main map.
struct TripDetailMap: UIViewRepresentable {
    let points: [TripPoint]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapDefaults.styleURL)
        mapView.delegate = context.coordinator
        mapView.logoView.isHidden = true
        mapView.isUserInteractionEnabled = true
        mapView.showsUserLocation = false
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.show(points, on: mapView)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private var shownCount = -1
        private var start: MLNPointAnnotation?
        private var end: MLNPointAnnotation?

        func show(_ points: [TripPoint], on mapView: MLNMapView) {
            guard points.count != shownCount else { return }
            shownCount = points.count
            if let start { mapView.removeAnnotation(start) }
            if let end { mapView.removeAnnotation(end) }
            let existing = (mapView.annotations ?? []).compactMap { $0 as? MLNPolyline }
            mapView.removeAnnotations(existing)
            guard !points.isEmpty else { return }
            var coordinates = points.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
            }
            let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
            mapView.addAnnotation(line)
            let first = MLNPointAnnotation()
            first.coordinate = coordinates.first!
            first.title = "Start"
            start = first
            let last = MLNPointAnnotation()
            last.coordinate = coordinates.last!
            last.title = "End"
            end = last
            mapView.addAnnotations([first, last])
            var sw = coordinates.first!
            var ne = coordinates.first!
            for c in coordinates {
                sw.latitude = min(sw.latitude, c.latitude)
                sw.longitude = min(sw.longitude, c.longitude)
                ne.latitude = max(ne.latitude, c.latitude)
                ne.longitude = max(ne.longitude, c.longitude)
            }
            if coordinates.count > 1 {
                mapView.setVisibleCoordinateBounds(
                    MLNCoordinateBounds(sw: sw, ne: ne),
                    edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                    animated: false, completionHandler: nil)
            } else {
                mapView.setCenter(coordinates[0], zoomLevel: 15, animated: false)
            }
        }

        func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat { 1 }
        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { 5 }
        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            UIColor.systemBlue
        }
        func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            UIColor.systemBlue.withAlphaComponent(0.2)
        }
        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { true }
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard annotation is MLNPointAnnotation else { return nil }
            let view = MLNAnnotationView(annotation: annotation, reuseIdentifier: "trip-end")
            view.frame = CGRect(x: 0, y: 0, width: 14, height: 14)
            view.backgroundColor = (annotation as? MLNPointAnnotation)?.title == "Start" ? .systemGreen : .systemRed
            view.layer.cornerRadius = 7
            view.layer.borderWidth = 2
            view.layer.borderColor = UIColor.white.cgColor
            return view
        }
    }
}
