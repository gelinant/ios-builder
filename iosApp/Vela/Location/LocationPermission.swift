import CoreLocation
import Foundation

/// When-in-use location permission. The map draws the user puck itself once it is granted.
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus

    private let manager: CLLocationManager
    private var onGranted: (() -> Void)?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isGranted: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    /// Runs `granted` now if permission is already given, or after the user allows it.
    func requestWhenInUse(then granted: @escaping () -> Void) {
        if isGranted {
            granted()
            return
        }
        guard status == .notDetermined else { return }
        onGranted = granted
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if isGranted, let granted = onGranted {
            onGranted = nil
            granted()
        }
    }
}
