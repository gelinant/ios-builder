import Foundation
import MapLibre

/// Owns the imperative side of the map so SwiftUI views can drive it.
final class MapController: ObservableObject {
    @Published private(set) var isFollowingUser = false

    private weak var mapView: MLNMapView?

    func attach(_ mapView: MLNMapView) {
        self.mapView = mapView
    }

    func showUser() {
        guard let mapView else { return }
        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(.follow, animated: true, completionHandler: nil)
    }

    func trackingModeDidChange(_ mode: MLNUserTrackingMode) {
        isFollowingUser = mode != .none
    }
}
