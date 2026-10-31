import Combine
import Foundation
import MapLibre
import VelaCore

/// One row a world layer can expose in the sheets, usually a named aircraft, ship or notice.
/// A row that carries a coordinate recenters the map when tapped.
struct WorldLayerRow: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let lat: Double?
    let lng: Double?

    init(id: String, title: String, detail: String = "", lat: Double? = nil, lng: Double? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.lat = lat
        self.lng = lng
    }
}

/// What a layer returns after a fetch: when the data was produced and the rows it carries.
struct WorldLayerRefresh {
    let updatedAtMs: Int64
    let rows: [WorldLayerRow]
}

/// The socket every world layer plugs into. A layer owns its file, its source, its drawing and
/// its own freshness window (read from `WorldLayerSettings`). It never edits the host files.
///
/// `isInstalled` stays false in the WLD-1 skeletons. A business lot sets it to true only once
/// `refresh` and `apply` really produce data, so the sheet can never offer an empty layer.
protocol WorldLayer: AnyObject {
    var id: String { get }
    var title: String { get }
    /// Human source line shown under the title, without a URL.
    var source: String { get }
    var isInstalled: Bool { get }
    /// Rows from the last accepted refresh; empty until the layer fetches.
    var rows: [WorldLayerRow] { get }
    /// Fetches once for this viewport. Return nil on failure; the stored data is kept and ages.
    func refresh(viewport: MapViewport) async -> WorldLayerRefresh?
    /// Draws the layer into the loaded style. Called only while the layer is installed and on.
    func apply(style: MLNStyle, offline: Bool)
}

/// The one host for the six world layers. It holds their switches and timestamps (through the
/// shared `WorldLayerSettings`), calls `refresh` only for an installed layer that is on and only
/// when the camera moved, and never runs a timer. With the WLD-1 skeletons every call is a no-op.
final class WorldLayersHub: ObservableObject {
    static let shared = WorldLayersHub()

    /// The six layers in sheet order. A layer lot replaces only its own implementation.
    let layers: [WorldLayer] = [
        AviationLayer(),
        MaritimeLayer(),
        EnergyLayer(),
        NotamLayer(),
        SatelliteLayer(),
        WikiLayer(),
    ]

    @Published private(set) var states: [String: WorldLayerState] = [:]
    @Published private(set) var rows: [String: [WorldLayerRow]] = [:]
    @Published private(set) var requestCount = 0

    private let settings: WorldLayerSettings
    private var inFlight: Set<String> = []
    private var hasViewport = false

    init(settings: WorldLayerSettings? = nil) {
        self.settings = settings ?? WorldLayerSettings(
            stores: UserDefaultsKeyValueStores(prefix: "app.vela.ios."),
            secrets: KeychainSecrets.shared)
        reload()
    }

    /// Recomputes the six states. Called when the sheet appears, when a switch or key changes and
    /// after a refresh; nothing schedules it, so a closed sheet costs nothing.
    func reload() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1_000)
        var next: [String: WorldLayerState] = [:]
        for layer in layers {
            next[layer.id] = settings.state(id: layer.id, installed: layer.isInstalled,
                                            nowMs: nowMs)
        }
        states = next
        for layer in layers {
            if rows[layer.id] == nil { rows[layer.id] = layer.rows }
        }
    }

    func state(_ id: String) -> WorldLayerState? { states[id] }

    func isOn(_ id: String) -> Bool { settings.isEnabled(id: id) }

    /// Off by default, and refused while the layer is not installed.
    func setEnabled(_ id: String, _ on: Bool) {
        guard let layer = layers.first(where: { $0.id == id }), layer.isInstalled else { return }
        settings.setEnabled(id: id, on: on)
        reload()
    }

    /// Saves a key through the Keychain-backed secret store; the value never enters the state.
    func setKey(_ id: String, _ value: String) {
        settings.setKey(id: id, value: value)
        reload()
    }

    func clearKey(_ id: String) {
        settings.clearKey(id: id)
        reload()
    }

    /// The single map socket. MapController calls it once per camera move with the current style.
    /// It returns immediately when no layer is installed and on, which is always the case in
    /// WLD-1: no request, no style pass and no work while the sheet is closed.
    func viewportChanged(_ viewport: MapViewport, style: MLNStyle?, offline: Bool) {
        let active = layers.filter { $0.isInstalled && settings.isEnabled(id: $0.id) }
        guard !active.isEmpty else { return }
        hasViewport = true
        if let style {
            for layer in active { layer.apply(style: style, offline: offline) }
        }
        for layer in active where !inFlight.contains(layer.id) {
            inFlight.insert(layer.id)
            Task { [weak self] in
                let result = await layer.refresh(viewport: viewport)
                await MainActor.run { self?.finish(layer, result) }
            }
        }
    }

    private func finish(_ layer: WorldLayer, _ result: WorldLayerRefresh?) {
        inFlight.remove(layer.id)
        requestCount += 1
        if let result {
            settings.markUpdated(id: layer.id, atMs: result.updatedAtMs)
            rows[layer.id] = result.rows
        }
        reload()
    }

    /// `world_layers` is the number of installed layers, `world_requests` the refresh attempts.
    var debugLine: String {
        let installed = layers.filter { $0.isInstalled }.count
        let on = layers.filter { $0.isInstalled && settings.isEnabled(id: $0.id) }.count
        return "world_layers=\(installed) world_requests=\(requestCount) world_on=\(on)"
            + " world_viewport=\(hasViewport ? 1 : 0)"
    }
}

/// Camera focus for a tapped world-layer row. The host posts a notification so the sheet needs no
/// reference to MapController and MapController keeps one call site.
enum WorldLayers {
    static let focusNotification = Notification.Name("app.vela.ios.worldLayerFocus")
    static let latitudeKey = "lat"
    static let longitudeKey = "lng"

    static func focus(latitude: Double, longitude: Double) {
        NotificationCenter.default.post(
            name: focusNotification, object: nil,
            userInfo: [latitudeKey: latitude, longitudeKey: longitude])
    }

    /// The installed ids, used by the report line and by the sheet.
    static var installedCount: Int { WorldLayersHub.shared.layers.filter { $0.isInstalled }.count }
}
