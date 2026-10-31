import CoreLocation
import Foundation
import MapLibre
import Security
import UIKit
import VelaCore

/// The Keychain accounts the energy layer reads. Reads are deliberately local to this lot: the
/// shared `KeychainSecrets` still owns writes and presence, while a request needs the value in
/// memory long enough to build one header. No value is printed, stored in UserDefaults, put in a
/// row or included in a debug line.
enum WorldLayerSecrets {
    /// Must match `KeychainSecrets.service`; the account names match `WorldLayerSettings`.
    static let service = "app.vela.ios.world"
    static let radarAccount = "world_layer_energy_key"
    static let electricityMapsAccount = "world_layer_energy_maps_key"

    static func value(account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One Cloudflare Radar event as the sheet and the map use it. A country's approximate center is
/// only a place to anchor a country-level annotation; it is never presented as the outage site.
struct RadarEntry {
    let id: String
    let kind: String
    let title: String
    let detail: String
    let startedAtMs: Int64
    let locations: [String]
    let url: String
    let latitude: Double?
    let longitude: Double?
}

/// Cloudflare Radar outages and attacks for the energy layer. The token comes from the Keychain,
/// and a missing token produces the `key_required` state rather than an empty map that reads as a
/// quiet Internet.
final class RadarLayer {
    static let sourceId = "vela-radar-src"
    static let outageLayerId = "vela-radar-outage"
    static let attackLayerId = "vela-radar-attack"
    static let labelLayerId = "vela-radar-labels"

    private var store: RadarStore?
    private(set) var entries: [RadarEntry] = []
    private(set) var status = "unavailable"
    private(set) var eventCount = 0
    private(set) var fetchedAtMs: Int64 = 0
    private(set) var tokenPresent = false

    init(http: VelaHttp?) {
        if let http {
            store = RadarStore(http: http, baseUrl: "https://api.cloudflare.com/client/v4")
        }
    }

    /// One refresh: at most two Cloudflare calls (outages and attacks) and only with a token.
    @discardableResult
    func refresh(nowMs: Int64) async -> Bool {
        guard let store else {
            status = "unavailable"
            return false
        }
        let token = WorldLayerSecrets.value(account: WorldLayerSecrets.radarAccount)
        let snapshot: RadarSnapshot?
        do {
            snapshot = try await store.refresh(token: token, nowMs: nowMs)
        } catch {
            snapshot = nil
        }
        let state = store.state(nowMs: nowMs)
        tokenPresent = state.tokenPresent
        status = state.status
        eventCount = Int(state.eventCount)
        fetchedAtMs = state.fetchedAtMs
        entries = (snapshot?.events ?? []).compactMap { event in
            let code = Self.markerCode(event)
            let center = code.flatMap { Self.centers[$0] }
            return RadarEntry(
                id: event.id,
                kind: event.kind,
                title: event.title,
                detail: event.detail,
                startedAtMs: event.startedAtMs,
                locations: event.locations,
                url: event.url,
                latitude: center?.0,
                longitude: center?.1)
        }
        return snapshot != nil
    }

    /// Debug-only fixture entries, set by `EnergyLayer` before the next `apply`.
    func setFixture(_ fixture: [RadarEntry]) {
        entries = fixture
        status = "fresh"
        eventCount = fixture.count
        fetchedAtMs = Int64(Date().timeIntervalSince1970 * 1_000)
        tokenPresent = true
    }

    func clearFixture() {
        entries = []
        status = "key_required"
        eventCount = 0
        fetchedAtMs = 0
        tokenPresent = false
    }

    /// Rows for the sheet. The token-missing row is the explicit answer; no row ever carries the
    /// token itself.
    func rows(nowMs: Int64) -> [WorldLayerRow] {
        if status == "key_required" {
            return [
                WorldLayerRow(
                    id: "energy-radar-key",
                    title: "Cloudflare Radar: token missing",
                    detail: "Outages and attacks are unknown, not empty. Add a Radar token in the sheet; Radar sees only Cloudflare traffic, not all Internet."),
            ]
        }
        if status == "unavailable" {
            return [
                WorldLayerRow(
                    id: "energy-radar-unavailable",
                    title: "Cloudflare Radar: unavailable",
                    detail: "The token was rejected or no answer came back. No events are shown, and this is not an all-clear."),
            ]
        }
        var out: [WorldLayerRow] = []
        if entries.isEmpty {
            out.append(WorldLayerRow(
                id: "energy-radar-empty",
                title: "Cloudflare Radar: no events in the last 7 days",
                detail: "Cloudflare traffic only. A quiet Radar is not a global all-clear."))
        } else {
            for entry in entries {
                out.append(WorldLayerRow(
                    id: "energy-radar-\(entry.id)",
                    title: entry.title,
                    detail: Self.detail(entry, nowMs: nowMs),
                    lat: entry.latitude,
                    lng: entry.longitude))
            }
            out.append(WorldLayerRow(
                id: "energy-radar-scope",
                title: "Cloudflare Radar: Cloudflare traffic only",
                detail: "Outages and attacks describe traffic Cloudflare sees, not the whole Internet."))
        }
        return out
    }

    /// Adds one circle source for the events whose country has an approximate center. No marker is
    /// drawn for a country-only annotation without a center, so no coordinate is invented.
    func apply(style: MLNStyle, offline: Bool) {
        guard !offline else { return }
        if style.source(withIdentifier: Self.sourceId) == nil {
            style.addSource(MLNShapeSource(identifier: Self.sourceId, shape: nil, options: nil))
        }
        let points = entries.compactMap { entry -> MLNPointFeature? in
            guard let lat = entry.latitude, let lng = entry.longitude else { return nil }
            let pin = MLNPointFeature()
            pin.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            pin.attributes = ["kind": entry.kind, "text": Self.summary(entry, nowMs: now)]
            return pin
        }
        (style.source(withIdentifier: Self.sourceId) as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: points)
        guard let source = style.source(withIdentifier: Self.sourceId) else { return }
        if style.layers.first(where: { $0.identifier == Self.outageLayerId }) == nil {
            let outage = Self.circle(Self.outageLayerId, source: source, color: UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1))
            outage.predicate = NSPredicate(format: "kind == %@", "outage")
            style.addLayer(outage)
        }
        if style.layers.first(where: { $0.identifier == Self.attackLayerId }) == nil {
            let attack = Self.circle(Self.attackLayerId, source: source, color: UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1))
            attack.predicate = NSPredicate(format: "kind == %@", "attack")
            style.addLayer(attack)
        }
        if style.layers.first(where: { $0.identifier == Self.labelLayerId }) == nil {
            let label = MLNSymbolStyleLayer(identifier: Self.labelLayerId, source: source)
            label.text = NSExpression(forKeyPath: "text")
            label.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            label.textFontSize = NSExpression(forConstantValue: 9)
            label.textColor = NSExpression(forConstantValue: UIColor(
                red: 0.5, green: 0.1, blue: 0.1, alpha: 1))
            label.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            label.textHaloWidth = NSExpression(forConstantValue: 1.3)
            label.textOffset = NSExpression(forConstantValue: NSValue(
                cgVector: CGVector(dx: 0, dy: 1.1)))
            label.textAllowsOverlap = NSExpression(forConstantValue: true)
            label.textIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(label)
        }
        let visible = !entries.isEmpty
        style.layers.first { $0.identifier == Self.outageLayerId }?.isVisible = visible
        style.layers.first { $0.identifier == Self.attackLayerId }?.isVisible = visible
        style.layers.first { $0.identifier == Self.labelLayerId }?.isVisible = visible
    }

    static func values(_ entry: RadarEntry, nowMs: Int64) -> [LayerInfoValue] {
        let contract = LayerInfoCatalog.contract(.radar)
        var values = [
            contract.value("kind", entry.kind.capitalized),
        ]
        if !entry.locations.isEmpty {
            values.append(contract.value("location", entry.locations.joined(separator: ", ")))
        }
        if entry.startedAtMs > 0 {
            let minutes = max(0, (nowMs - entry.startedAtMs) / 60_000)
            values.append(LayerInfoValue(id: "age", text: "\(minutes)", unit: "min"))
        }
        return values
    }

    static func summary(_ entry: RadarEntry, nowMs: Int64) -> String {
        LayerInfoCatalog.contract(.radar).mapLabel(values(entry, nowMs: nowMs))
    }

    private static func circle(_ id: String, source: MLNSource, color: UIColor) -> MLNCircleStyleLayer {
        let layer = MLNCircleStyleLayer(identifier: id, source: source)
        layer.circleRadius = NSExpression(forConstantValue: 6)
        layer.circleColor = NSExpression(forConstantValue: color)
        layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        layer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
        return layer
    }

    private static func markerCode(_ event: RadarEvent) -> String? {
        if event.kind == "attack" { return event.locations.first }
        return event.locations.count == 1 ? event.locations.first : nil
    }

    private static func detail(_ entry: RadarEntry, nowMs: Int64) -> String {
        let fields = summary(entry, nowMs: nowMs)
        return "\(fields). \(entry.detail). Cloudflare traffic only."
    }

    /// Approximate country centers, used only to place a country-level annotation. Missing codes
    /// stay as list rows and get no marker.
    private static let centers: [String: (Double, Double)] = [
        "AE": (24.0, 54.0), "AR": (-34.0, -64.0), "AT": (47.5, 14.5), "AU": (-25.0, 134.0),
        "BD": (24.0, 90.0), "BE": (50.8, 4.5), "BG": (42.7, 25.5), "BR": (-10.0, -52.0),
        "CA": (56.0, -106.0), "CH": (46.8, 8.2), "CL": (-33.0, -71.0), "CN": (35.0, 105.0),
        "CZ": (49.8, 15.5), "DE": (51.0, 10.0), "DK": (56.0, 10.0), "EG": (27.0, 30.0),
        "ES": (40.0, -4.0), "FI": (64.0, 26.0), "FR": (46.0, 2.0), "GB": (54.0, -2.0),
        "GR": (39.0, 22.0), "HU": (47.0, 19.5), "ID": (-2.0, 118.0), "IE": (53.0, -8.0),
        "IL": (31.5, 35.0), "IN": (22.0, 79.0), "IR": (32.0, 53.0), "IT": (42.5, 12.5),
        "JP": (36.0, 138.0), "KR": (36.5, 128.0), "MX": (23.0, -102.0), "MY": (4.0, 102.0),
        "NG": (10.0, 8.0), "NL": (52.5, 5.5), "NO": (64.0, 11.0), "NZ": (-42.0, 173.0),
        "PH": (13.0, 122.0), "PK": (30.0, 70.0), "PL": (52.0, 19.0), "PT": (39.5, -8.0),
        "RO": (46.0, 25.0), "RU": (60.0, 90.0), "SA": (24.0, 45.0), "SE": (62.0, 15.0),
        "SG": (1.3, 103.8), "TH": (15.0, 101.0), "TR": (39.0, 35.0), "TW": (23.7, 121.0),
        "UA": (49.0, 32.0), "US": (39.0, -98.0), "VN": (16.0, 106.0), "ZA": (-29.0, 24.0),
    ]
}

/// A one-time key prompt for the optional feeds. It appears only when the layer is drawing in a
/// real build, never during a UI test, and stores through `KeychainSecrets` so the value never
/// reaches UserDefaults. The prompt itself asks for a token, not for a password, and never echoes
/// either value after saving.
enum WorldEnergyKeyPrompt {
    private static var asked = false

    static func presentIfNeeded() {
        guard !asked, !isRunningTests else { return }
        #if DEBUG
        guard !WorldEnergyFixture.isActive else { return }
        #endif
        let hasRadar = WorldLayerSecrets.value(account: WorldLayerSecrets.radarAccount) != nil
        let hasMaps = WorldLayerSecrets.value(account: WorldLayerSecrets.electricityMapsAccount) != nil
        guard !hasRadar || !hasMaps else { return }
        guard let top = topViewController() else { return }
        asked = true
        let alert = UIAlertController(
            title: "Optional energy keys",
            message: "Cloudflare Radar needs your own token. Electricity Maps needs your own key. Both are optional and stored in the Keychain; the layer says key required without them. Radar only sees Cloudflare traffic.",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Cloudflare Radar token"
            field.isSecureTextEntry = true
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "Electricity Maps key"
            field.isSecureTextEntry = true
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Later", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let radar = alert.textFields?.first?.text ?? ""
            let maps = alert.textFields?.last?.text ?? ""
            if !radar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainSecrets.shared.put(secretId: WorldLayerSecrets.radarAccount, value: radar)
            }
            if !maps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainSecrets.shared.put(secretId: WorldLayerSecrets.electricityMapsAccount, value: maps)
            }
            WorldLayersHub.shared.reload()
        })
        top.present(alert, animated: true)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
            ?? scenes.flatMap(\.windows).first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

/// Debug-only deterministic answers for `EnergyRadarUITests`. No provider host is contacted and
/// no fixture key is a real credential.
#if DEBUG
enum WorldEnergyFixture {
    static var isActive: Bool { flag("VelaWorldEnergyFixture") }
    static var seedKeys: Bool { flag("VelaWorldEnergyKeys") }
    static var clearKeys: Bool { flag("VelaWorldEnergyNoKeys") }

    static let radarToken = "fixture-radar-token"
    static let electricityMapsKey = "fixture-electricity-maps-key"

    static func prepare() {
        if seedKeys {
            KeychainSecrets.shared.put(secretId: WorldLayerSecrets.radarAccount, value: radarToken)
            KeychainSecrets.shared.put(secretId: WorldLayerSecrets.electricityMapsAccount,
                                       value: electricityMapsKey)
        }
        if clearKeys {
            KeychainSecrets.shared.remove(secretId: WorldLayerSecrets.radarAccount)
            KeychainSecrets.shared.remove(secretId: WorldLayerSecrets.electricityMapsAccount)
        }
    }

    static var keysPresent: Bool { seedKeys && !clearKeys }

    private static func flag(_ name: String) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else {
            return false
        }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }
}
#endif
