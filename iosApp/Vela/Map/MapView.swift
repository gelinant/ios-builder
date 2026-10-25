import MapLibre
import SwiftUI
import UIKit

/// Full screen MapLibre map with the OpenFreeMap Liberty style.
struct MapView: UIViewRepresentable {
    let controller: MapController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapDefaults.styleURL)
        let camera = LaunchOptions.current.camera
        mapView.setCenter(camera.center, zoomLevel: camera.zoom, animated: false)
        mapView.accessibilityIdentifier = "map"
        // The credit line in MapScreen replaces the logo; the info button stays for full attribution.
        mapView.logoView.isHidden = true
        mapView.delegate = context.coordinator
        controller.attach(mapView)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        for case let other as UITapGestureRecognizer in mapView.gestureRecognizers ?? [] where other.numberOfTapsRequired == 2 {
            tap.require(toFail: other)
        }
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private let controller: MapController

        init(controller: MapController) {
            self.controller = controller
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            controller.handleTap(at: gesture.location(in: view))
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            controller.styleDidLoad(style)
        }

        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            controller.trackingModeDidChange(mode)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            controller.regionDidChange()
        }

        func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            if let coordinate = userLocation?.location?.coordinate {
                controller.userLocationDidUpdate(coordinate)
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            controller.annotationView(for: annotation)
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            controller.didSelectAnnotation(annotation)
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            controller.canShowCallout(annotation)
        }
    }
}
