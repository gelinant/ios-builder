import CoreLocation
import Foundation

/// START-LOCATION: the camera the map opens on, decided in this one place.
///
/// Precedence, highest first:
/// 1. An explicit target: `-VelaStartCamera`, an incoming link, a saved place, a route or a replay.
/// 2. The user's own position, when permission is already granted and a fix arrives inside
///    `deadline`. The camera opens at `positionZoom`, a city view rather than street level.
/// 3. The last camera the user left, persisted by `StartCameraStore`.
/// 4. `MapDefaults`: San Francisco at zoom 12.
///
/// A late fix moves the camera once. A pan before it arrives, or any explicit target, drops that
/// move for good. The map is never blocked: it shows the last or default camera at once, and a
/// missing or denied permission leaves it there without a spinner or an empty view.
final class StartCamera {
    enum Source: String {
        case explicit
        case position
        case last
        case fallback = "default"
    }

    struct Decision: Equatable {
        let camera: LaunchOptions.Camera
        let source: Source
    }

    /// A city view: the user's neighbourhood, not a street-level pin.
    static let positionZoom: Double = 14
    /// How long a granted launch waits for its first fix. A fix after this leaves the camera on the
    /// last or default view rather than making the user wait.
    static let deadline: TimeInterval = 2
    /// A pan this large is the user's, not rounding drift from a programmatic move.
    static let panToleranceM: Double = 40

    private let store: StartCameraStore
    private let now: () -> Date
    private(set) var decision: Decision
    private(set) var userMoved = false
    private var explicit: Bool
    private var pending = false
    private var armedAt: Date?
    private var didMove = false

    init(explicit: LaunchOptions.Camera?,
         store: StartCameraStore = StartCameraStore(),
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        self.explicit = explicit != nil
        decision = Self.initial(explicit: explicit, last: store.load())
    }

    /// The launch camera without any fix: explicit, then the last camera, then the default. The
    /// start-position setting narrows the chain without changing its order: `last` drops the
    /// position step, `city` also drops the last camera. An explicit target still wins.
    static func initial(explicit: LaunchOptions.Camera?, last: LaunchOptions.Camera?) -> Decision {
        if let explicit {
            return Decision(camera: explicit, source: .explicit)
        }
        switch MapGestureSettings.storedStartView() {
        case .city:
            return Decision(camera: defaultCamera, source: .fallback)
        case .last:
            if let last, isValid(last) {
                return Decision(camera: last, source: .last)
            }
            return Decision(camera: defaultCamera, source: .fallback)
        case .here:
            if let last, isValid(last) {
                return Decision(camera: last, source: .last)
            }
            return Decision(camera: defaultCamera, source: .fallback)
        }
    }

    static var defaultCamera: LaunchOptions.Camera {
        LaunchOptions.Camera(latitude: MapDefaults.initialCenter.latitude,
                             longitude: MapDefaults.initialCenter.longitude,
                             zoom: MapDefaults.initialZoom)
    }

    /// The user's fix at the launch city zoom, or nil outside the map's own bounds.
    static func position(latitude: Double, longitude: Double) -> LaunchOptions.Camera? {
        let camera = LaunchOptions.Camera(
            latitude: latitude, longitude: longitude, zoom: positionZoom)
        return isValid(camera) ? camera : nil
    }

    /// A camera that can be restored later: inside the world, and not the (0,0) null island a
    /// missing fix leaves behind.
    static func isValid(_ camera: LaunchOptions.Camera) -> Bool {
        guard (-90...90).contains(camera.latitude),
              (-180...180).contains(camera.longitude),
              (0...22).contains(camera.zoom) else { return false }
        return abs(camera.latitude) > 0.000_001 || abs(camera.longitude) > 0.000_001
    }

    /// Opens the wait for a fix. A granted permission starts the deadline now; an undetermined or
    /// denied permission leaves it closed until the user's answer arrives.
    func begin(granted: Bool) {
        guard !explicit, !didMove, !userMoved, followsPosition else { return }
        if granted {
            pending = true
            armedAt = now()
        } else {
            pending = false
            armedAt = nil
        }
    }

    /// `here` is the only start-position choice that moves onto the fix. `last` and `city` keep
    /// the camera they opened on.
    private var followsPosition: Bool {
        MapGestureSettings.storedStartView() == .here
    }

    /// The permission answer changed. A late grant opens a fresh deadline, so a user who allows
    /// location from the locate button still lands on their position. Returns true while waiting.
    @discardableResult
    func permissionAnswered(granted: Bool) -> Bool {
        guard !explicit, !didMove, !userMoved, followsPosition else { return false }
        if granted {
            pending = true
            armedAt = now()
            return true
        }
        pending = false
        armedAt = nil
        return false
    }

    /// A fix arrived. Returns the one camera move when it is still armed and inside the deadline.
    func fix(latitude: Double, longitude: Double) -> Decision? {
        guard pending, !explicit, !userMoved, !didMove, followsPosition, let armedAt,
              now().timeIntervalSince(armedAt) <= Self.deadline,
              let camera = Self.position(latitude: latitude, longitude: longitude) else {
            return nil
        }
        pending = false
        didMove = true
        decision = Decision(camera: camera, source: .position)
        return decision
    }

    /// The user moved the map: never steal the camera from them afterwards.
    func userPanned() {
        userMoved = true
        pending = false
    }

    /// An explicit target (link, saved place, route, replay, follow request) took the camera.
    func cancel() {
        explicit = true
        pending = false
    }

    // MARK: Last camera

    /// Remembers where the user left the map. Invalid cameras are ignored rather than stored.
    func remember(latitude: Double, longitude: Double, zoom: Double) {
        store.save(LaunchOptions.Camera(latitude: latitude, longitude: longitude, zoom: zoom))
    }
}

/// The last camera the user left, under a versioned key. The stored document also carries its
/// version, so a future layout can ignore an old one instead of misreading it.
final class StartCameraStore {
    static let key = "app.vela.ios.map.last_camera.v1"
    static let version = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LaunchOptions.Camera? {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == Self.version else { return nil }
        let camera = LaunchOptions.Camera(
            latitude: stored.latitude, longitude: stored.longitude, zoom: stored.zoom)
        return StartCamera.isValid(camera) ? camera : nil
    }

    func save(_ camera: LaunchOptions.Camera) {
        guard StartCamera.isValid(camera),
              let data = try? JSONEncoder().encode(Stored(
                version: Self.version, latitude: camera.latitude,
                longitude: camera.longitude, zoom: camera.zoom)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private struct Stored: Codable {
        let version: Int
        let latitude: Double
        let longitude: Double
        let zoom: Double
    }
}
