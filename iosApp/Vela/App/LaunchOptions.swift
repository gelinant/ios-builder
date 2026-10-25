import CoreLocation
import Foundation

/// Launch arguments the UI tests and scripts/ios/ci-ipa.sh pass (docs/ios/TESTING-IOS.md), read
/// once from the process arguments as `-Name value` pairs:
///
/// - `-VelaStartCamera <fixture>|<lat>,<lng>[,<zoom>]`: the first camera. Fixtures: `sf`, `davis`,
///   `sacramento`. Default: San Francisco at zoom 12.
/// - `-VelaDeterministic YES`: no UIKit or camera animation, for stable screenshots.
/// - `-VelaFollowUser YES`: follow the user location at launch when permission is already given,
///   for location replays.
struct LaunchOptions {
    struct Camera: Equatable {
        let latitude: Double
        let longitude: Double
        let zoom: Double

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    static let fixtures: [String: Camera] = [
        "sf": Camera(latitude: 37.7749, longitude: -122.4194, zoom: 12),
        "davis": Camera(latitude: 38.5449, longitude: -121.7405, zoom: 13),
        "sacramento": Camera(latitude: 38.5816, longitude: -121.4944, zoom: 12),
    ]

    let camera: Camera
    let deterministic: Bool
    let followUser: Bool
    let offlineTest: Bool

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        func value(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: "-" + name), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        func flag(_ name: String) -> Bool {
            guard let v = value(name)?.lowercased() else { return false }
            return v == "yes" || v == "true" || v == "1"
        }
        camera = Self.parseCamera(value("VelaStartCamera"))
            ?? Camera(latitude: MapDefaults.initialCenter.latitude,
                      longitude: MapDefaults.initialCenter.longitude, zoom: MapDefaults.initialZoom)
        deterministic = flag("VelaDeterministic")
        followUser = flag("VelaFollowUser")
        offlineTest = flag("VelaOfflineTest")
    }

    /// A fixture name or `lat,lng[,zoom]`; nil when unreadable or out of range.
    static func parseCamera(_ text: String?) -> Camera? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return nil }
        if let fixture = fixtures[text] { return fixture }
        let parts = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 || parts.count == 3, let lat = parts[0], let lng = parts[1],
              (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
        let zoom: Double? = parts.count == 3 ? parts[2] : MapDefaults.initialZoom
        guard let zoom, (0...22).contains(zoom) else { return nil }
        return Camera(latitude: lat, longitude: lng, zoom: zoom)
    }

    /// Whether camera moves animate.
    var animates: Bool { !deterministic }
}
