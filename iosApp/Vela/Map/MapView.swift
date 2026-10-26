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
        let mapView = MLNMapView(frame: .zero, styleURL: controller.initialStyleURL())
        let camera = LaunchOptions.current.camera
        mapView.setCenter(camera.center, zoomLevel: camera.zoom, animated: false)
        mapView.accessibilityIdentifier = "map"
        mapView.accessibilityLabel = "Map"
        mapView.accessibilityHint = "Use the rotor actions to select a feature or drop a pin at the map center."
        context.coordinator.mapView = mapView
        mapView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Select feature at map center",
                target: context.coordinator,
                selector: #selector(Coordinator.selectFeatureAtCenter(_:))),
            UIAccessibilityCustomAction(
                name: "Drop pin at map center",
                target: context.coordinator,
                selector: #selector(Coordinator.dropPinAtCenter(_:))),
        ]
        // The credit line in MapScreen replaces the logo; the info button stays for full attribution.
        mapView.logoView.isHidden = true
        mapView.delegate = context.coordinator
        controller.attach(mapView)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        for case let other as UITapGestureRecognizer in mapView.gestureRecognizers ?? [] where other.numberOfTapsRequired == 2 {
            tap.require(toFail: other)
        }
        mapView.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.delegate = context.coordinator
        mapView.addGestureRecognizer(pan)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        private let controller: MapController
        weak var mapView: MLNMapView?

        init(controller: MapController) {
            self.controller = controller
        }

        @objc func selectFeatureAtCenter(_ action: UIAccessibilityCustomAction) -> Bool {
            guard let mapView else { return false }
            controller.handleTap(at: CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY))
            return true
        }

        @objc func dropPinAtCenter(_ action: UIAccessibilityCustomAction) -> Bool {
            guard let mapView else { return false }
            controller.handleLongPress(at: CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY))
            return true
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            controller.handleTap(at: gesture.location(in: view))
        }

        @objc func longPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = gesture.view else { return }
            controller.handleLongPress(at: gesture.location(in: view))
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                controller.userPanned()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
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
