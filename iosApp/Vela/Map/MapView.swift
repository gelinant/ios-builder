import MapLibre
import SwiftUI

/// Full screen MapLibre map with the OpenFreeMap Liberty style.
struct MapView: UIViewRepresentable {
    let controller: MapController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapDefaults.styleURL)
        mapView.setCenter(MapDefaults.initialCenter, zoomLevel: MapDefaults.initialZoom, animated: false)
        // The credit line in MapScreen replaces the logo; the info button stays for full attribution.
        mapView.logoView.isHidden = true
        mapView.delegate = context.coordinator
        controller.attach(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private let controller: MapController

        init(controller: MapController) {
            self.controller = controller
        }

        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            controller.trackingModeDidChange(mode)
        }
    }
}
