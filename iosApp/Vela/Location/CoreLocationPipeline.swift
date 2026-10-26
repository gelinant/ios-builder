import CoreLocation
import Foundation
import OSLog

/// The process's location source. Configuration is navigation-grade from the start, updates do
/// not pause. A drive owns device heading; driving or an explicit transit session owns background
/// delivery, never an idle Live Activity. `CLLocation` has no GPS-provider name on iOS.
final class CoreLocationPipeline: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let log = Logger(subsystem: OSLogLog.subsystem, category: "Location")
    private var started = false
    private var navigating = false
    private var transitActive = false

    var onFix: ((CLLocation, Int64) -> Void)?
    var onTransitFix: ((CLLocation) -> Void)?
    var onHeading: ((CLLocationDirection) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.headingFilter = 2
        manager.headingOrientation = .portrait
    }

    /// Does not ask for permission at app launch. An existing grant starts updates; the map's
    /// locate button asks, and the authorization callback starts this source too.
    func start() {
        guard !started else { return }
        started = true
        startIfAuthorized()
    }

    func setNavigating(_ on: Bool) {
        guard navigating != on else { return }
        navigating = on
        updateBackgroundConfiguration()
        if on {
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        } else {
            manager.stopUpdatingHeading()
        }
    }

    /// Explicit transit guidance may keep receiving fixes in the background. End and arrival clear
    /// this flag; an inactive Live Activity has no way to set it.
    func setTransitActive(_ on: Bool) {
        guard transitActive != on else { return }
        transitActive = on
        updateBackgroundConfiguration()
    }

    var backgroundUpdatesEnabled: Bool { manager.allowsBackgroundLocationUpdates }

    private func updateBackgroundConfiguration() {
        manager.allowsBackgroundLocationUpdates = navigating || transitActive
        manager.activityType = navigating ? .automotiveNavigation : (transitActive ? .otherNavigation : .automotiveNavigation)
    }

    private func startIfAuthorized() {
        guard started else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.startUpdatingLocation()
        if navigating, CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            // Delivery time, not the location's wall-clock timestamp: this preserves monotonic dt
            // across GNSS UTC, network fixes and system clock changes.
            let stamp = Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
            onFix?(location, stamp)
            onTransitFix?(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.trueHeading >= 0 {
            onHeading?(newHeading.trueHeading)
        } else if newHeading.magneticHeading >= 0 {
            onHeading?(newHeading.magneticHeading)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.info("location update failed: \(error.localizedDescription, privacy: .public)")
    }
}
