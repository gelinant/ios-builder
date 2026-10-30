import MapLibre
import SwiftUI
import UIKit
import VelaCore

/// G-2: the native MapLibre globe projection.
///
/// The projection is a property of the style document (`"projection": {"type": "globe"}`), so a
/// switch reloads the same local style with that key and the camera is restored across the load.
/// The pre-release build is recognised by the `isCoordinateOccluded:` symbol the G-1 spike used;
/// a plain Mercator build keeps the app on Mercator and hides the control instead of failing.
enum MapProjection: String, CaseIterable {
    case mercator
    case globe

    var title: String {
        switch self {
        case .mercator: return "Mercator"
        case .globe: return "Globe"
        }
    }

    /// G-1 measured z0 at 45 % of the screen width; z1 keeps the planet readable.
    var minimumZoom: Double {
        self == .globe ? GlobeConstants.globeMinimumZoom : GlobeConstants.mercatorMinimumZoom
    }
}

enum GlobeConstants {
    /// The stable key also written by `GlobeSettingsStore` in :ios-shared.
    static let key = "map_projection"
    static let mercatorMinimumZoom = 0.0
    static let globeMinimumZoom = 1.0
    /// Dark navy behind the planet: the globe build has no atmosphere and MapLibre paints the
    /// area outside the disc with the map view's own background.
    static let surround = UIColor(red: 0.035, green: 0.051, blue: 0.078, alpha: 1)
}

/// Sheet copy for the G-2 control. The keys live in the shared Android catalog, so the globe
/// sheet follows the app language like every other surface.
enum GlobeCopy {
    static var title: String { VelaL10n.text("map_globe_title") }
    static var unavailable: String { VelaL10n.text("map_globe_unavailable") }
    static var footer: String { VelaL10n.text("map_globe_footer") }
}

/// True only for the globe build. `MLNMapView` exposes `isCoordinateOccluded:` in that build and
/// not in the Mercator release, so the sheet can stay honest when a plain framework is linked.
enum GlobeAvailability {
    static var isSupported: Bool {
        MLNMapView.instancesRespond(to: NSSelectorFromString("isCoordinateOccluded:"))
    }
}

/// Reads and writes the projection through the typed Kotlin store, so the value lives in the same
/// `vela_settings` suite as the other Android-compatible keys.
enum MapGlobeSettings {
    static let changedNotification = Notification.Name("VelaMapGlobeChanged")

    private static let store = GlobeSettingsStore(
        stores: UserDefaultsKeyValueStores(prefix: "app.vela.ios."))

    static var projection: MapProjection {
        guard GlobeAvailability.isSupported else { return .mercator }
        return MapProjection(rawValue: store.projection) ?? .mercator
    }

    static func set(_ projection: MapProjection) {
        guard GlobeAvailability.isSupported else { return }
        guard store.projection != projection.rawValue else { return }
        store.setProjection(value: projection.rawValue)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}

/// What the camera looked like before a projection reload, and the values the debug line reports.
struct GlobeCameraSnapshot {
    let center: CLLocationCoordinate2D
    let zoom: Double
    let bearing: Double
    let pitch: Double
}

/// The sheet's state and the `globe-debug` line the UI scenario reads.
final class GlobeState: ObservableObject {
    static let shared = GlobeState()

    @Published private(set) var projection = MapGlobeSettings.projection
    @Published private(set) var available = GlobeAvailability.isSupported
    @Published private(set) var cameraKept = false
    @Published private(set) var zoom = MapDefaults.initialZoom
    @Published private(set) var center = MapDefaults.initialCenter
    @Published private(set) var bearing = 0.0
    @Published private(set) var pitch = 0.0

    func update(projection: MapProjection? = nil, available: Bool? = nil,
                cameraKept: Bool? = nil, zoom: Double? = nil,
                center: CLLocationCoordinate2D? = nil, bearing: Double? = nil,
                pitch: Double? = nil) {
        if let projection, projection != self.projection { self.projection = projection }
        if let available, available != self.available { self.available = available }
        if let cameraKept, cameraKept != self.cameraKept { self.cameraKept = cameraKept }
        if let zoom, zoom != self.zoom { self.zoom = zoom }
        if let center, center.latitude != self.center.latitude
            || center.longitude != self.center.longitude {
            self.center = center
        }
        if let bearing, bearing != self.bearing { self.bearing = bearing }
        if let pitch, pitch != self.pitch { self.pitch = pitch }
    }

    /// The clamp value is a constant, reported next to the live zoom so the scenario can prove
    /// that repeated zoom-out requests stop at z1 rather than at MapLibre's advertised z0.
    var debugLine: String {
        "globe_projection=\(projection.rawValue)"
            + " globe_zoom_clamp=\(Int(projection.minimumZoom))"
            + " globe_camera_kept=\(cameraKept ? 1 : 0)"
            + " globe_available=\(available ? 1 : 0)"
            + " globe_zoom=\(String(format: "%.2f", zoom))"
            + " globe_center=\(String(format: "%.5f", center.latitude)),\(String(format: "%.5f", center.longitude))"
            + " globe_bearing=\(String(format: "%.1f", bearing))"
            + " globe_pitch=\(String(format: "%.1f", pitch))"
    }
}

/// Applies the dark surround to the map view. Mercator keeps the white surface it always had.
enum MapGlobeSurround {
    static func apply(to mapView: MLNMapView, projection: MapProjection) {
        let color = projection == .globe ? GlobeConstants.surround : .white
        mapView.backgroundColor = color
        mapView.layer.backgroundColor = color.cgColor
    }
}
