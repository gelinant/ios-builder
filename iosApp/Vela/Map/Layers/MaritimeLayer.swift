import Foundation
import MapLibre
import Security
import VelaCore

/// Ships around the view (A-2). Digitraffic AIS covers Finnish waters without a key and under
/// CC BY 4.0; AISHub adds coverage beyond Finland only with the member key saved for this layer.
/// The same layer carries the UKMTO incident list: a link list with a title, a date and a link,
/// never a copied summary and never a zone on the map.
///
/// No AIS data here is for navigation. Every coverage row says so.
final class MaritimeLayer: WorldLayer {
    static let installed = true

    /// The style layer this class draws. MAP-TAP reads it for its audit.
    static let mapLayerIdentifiers = ["vela-maritime-ship-dots"]
    let id = "maritime"
    let title = VelaL10n.text("world_layer_ships")
    let source = "Digitraffic AIS, CC BY 4.0; AISHub with a member key"

    var isInstalled: Bool { Self.installed }
    private(set) var rows: [WorldLayerRow] = []

    /// The coordinates the map draws. Populated after a refresh, read by `apply` on the main
    /// thread.
    private var ships: [DrawnShip] = []
    private weak var lastStyle: MLNStyle?
    private var lastOffline = false
    private var shipStore: MaritimeStore?
    private var noticeStore: UkmtoStore?

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? {
        if Self.fixtureEnabled {
            let result = Self.fixtureRefresh()
            await MainActor.run {
                self.ships = result.ships
                self.rows = result.rows
                self.drawAgain()
            }
            return WorldLayerRefresh(updatedAtMs: result.updatedAtMs, rows: result.rows)
        }

        let stores = stores()
        let box = MaritimeBox(
            south: viewport.south, west: viewport.west,
            north: viewport.north, east: viewport.east)
        // A Kotlin suspend function crosses SKIE as `async throws`; both stores turn a source
        // failure into nil rather than an error, so a thrown call is only cancellation.
        let maritime = try? await stores.ship.refresh(box: box, aishubKey: Self.keychainKey())
        let notices = try? await stores.notice.refresh()
        guard maritime != nil || notices != nil else { return nil }

        var next: [WorldLayerRow] = []
        if let maritime {
            next += maritime.rows.map(Self.worldRow)
        }
        if let notices {
            next += notices.rows.map(Self.worldRow)
        } else {
            next.append(WorldLayerRow(
                id: "maritime-ukmto-error",
                title: "UKMTO: link list unavailable",
                detail: "The UKMTO site did not answer. No incident is invented, and this is "
                    + "not a live advisory feed."))
        }
        let drawn = maritime?.ships.compactMap { ship in
            DrawnShip(lat: ship.lat, lng: ship.lng, mmsi: ship.mmsi)
        } ?? []
        await MainActor.run {
            self.ships = drawn
            self.rows = next
            self.drawAgain()
        }
        let stamp = max(maritime?.updatedAtMs ?? 0, 1)
        return WorldLayerRefresh(updatedAtMs: stamp, rows: next)
    }

    func apply(style: MLNStyle, offline: Bool) {
        lastStyle = style
        lastOffline = offline
        let sourceId = Self.sourceId
        if offline || ships.isEmpty {
            if let layer = style.layer(withIdentifier: Self.layerId) {
                style.removeLayer(layer)
            }
            if let source = style.source(withIdentifier: sourceId) {
                style.removeSource(source)
            }
            return
        }
        let features = ships.map { ship -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: ship.lat, longitude: ship.lng)
            feature.attributes = ["mmsi": ship.mmsi]
            return feature
        }
        let shape = MLNShapeCollectionFeature(shapes: features)
        if let source = style.source(withIdentifier: sourceId) as? MLNShapeSource {
            source.shape = shape
            return
        }
        let source = MLNShapeSource(identifier: sourceId, shape: shape, options: nil)
        style.addSource(source)
        let layer = MLNCircleStyleLayer(identifier: Self.layerId, source: source)
        layer.circleColor = NSExpression(forConstantValue: UIColor(
            red: 0.13, green: 0.42, blue: 0.72, alpha: 0.92))
        layer.circleRadius = NSExpression(forConstantValue: 5.0)
        layer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
        layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        if let anchor = MapLayers.labelAnchor(in: style) {
            style.insertLayer(layer, below: anchor)
        } else {
            style.addLayer(layer)
        }
    }

    /// The host applies the style before it starts the refresh, so the first answer would only
    /// reach the map on the next camera move. Reapplying here draws the first answer at once.
    @MainActor
    private func drawAgain() {
        guard let style = lastStyle else { return }
        let offline = lastOffline
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.apply(style: style, offline: offline)
        }
    }

    private func stores() -> (ship: MaritimeStore, notice: UkmtoStore) {
        if let shipStore, let noticeStore { return (shipStore, noticeStore) }
        let http = URLSessionVelaHttp()
        let ship = MaritimeStore(http: http)
        let notice = UkmtoStore(http: http)
        shipStore = ship
        noticeStore = notice
        return (ship, notice)
    }

    private static func worldRow(_ row: MaritimeRow) -> WorldLayerRow {
        WorldLayerRow(
            id: row.id, title: row.title, detail: row.detail,
            lat: row.lat?.doubleValue, lng: row.lng?.doubleValue)
    }

    /// The account `KeychainSecrets` and `WorldLayerSettings.secretId` use for this layer. The
    /// value is read only here, only when the layer is on and a refresh runs. It never enters a
    /// log, a row or a setting.
    private static func keychainKey() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.vela.ios.world",
            kSecAttrAccount as String: "world_layer_maritime_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct DrawnShip {
        let lat: Double
        let lng: Double
        let mmsi: String
    }

    private struct FixtureResult {
        let updatedAtMs: Int64
        let rows: [WorldLayerRow]
        let ships: [DrawnShip]
    }

    private static let sourceId = "vela-maritime-ships"
    private static let layerId = "vela-maritime-ship-dots"

    /// Debug only, `-VelaMaritimeFixture YES`: deterministic ships near Helsinki and a UKMTO
    /// link list, so the UI scenario needs no network and no AISHub key.
    private static let fixtureEnabled: Bool = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaMaritimeFixture"),
              index + 1 < arguments.count else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
        #else
        return false
        #endif
    }()

    private static func fixtureRefresh() -> FixtureResult {
        let ships = [
            DrawnShip(lat: 59.487802, lng: 23.607103, mmsi: "230713000"),
            DrawnShip(lat: 60.152000, lng: 24.902000, mmsi: "276835000"),
            DrawnShip(lat: 59.321000, lng: 23.100000, mmsi: "265549230"),
        ]
        let rows = [
            WorldLayerRow(
                id: "maritime-coverage",
                title: "AIS coverage: Finland only",
                detail: "Digitraffic covers Finnish waters only. Beyond Finland an AISHub "
                    + "member key is needed. Not for navigation."),
            WorldLayerRow(
                id: "maritime-aishub",
                title: "AISHub: key required",
                detail: "Ships stay Finland only until a member key is saved in this sheet. "
                    + "No AISHub request is sent without one."),
            WorldLayerRow(
                id: "maritime-ship-230713000",
                title: "AUGUSTA",
                detail: "Cargo · 7.9 kn · course 246° · MMSI 230713000",
                lat: 59.487802, lng: 23.607103),
            WorldLayerRow(
                id: "maritime-ship-276835000",
                title: "TANKER ONE",
                detail: "Tanker · 0.0 kn · course 20° · MMSI 276835000",
                lat: 60.152000, lng: 24.902000),
            WorldLayerRow(
                id: "maritime-ship-265549230",
                title: "SILJA",
                detail: "Passenger · 18.4 kn · course 275° · MMSI 265549230",
                lat: 59.321000, lng: 23.100000),
            WorldLayerRow(
                id: "maritime-ukmto-header",
                title: "UKMTO incidents: link list only",
                detail: "Newest first. Title, date and link only. Not a live advisory feed; "
                    + "no zone is drawn."),
            WorldLayerRow(
                id: "maritime-ukmto-0077459b",
                title: "UKMTO #154 Attack",
                detail: "12 Oct 2026 · Link only · "
                    + "https://www.ukmto.org/recent-incidents#0077459b"),
            WorldLayerRow(
                id: "maritime-ukmto-27bc5e88",
                title: "UKMTO #152 Advisory",
                detail: "10 Oct 2026 · Link only · "
                    + "https://www.ukmto.org/recent-incidents#27bc5e88"),
            WorldLayerRow(
                id: "maritime-ukmto-a5b33f9d",
                title: "UKMTO #143 Suspicious Activity",
                detail: "28 Sep 2026 · Link only · "
                    + "https://www.ukmto.org/recent-incidents#a5b33f9d"),
        ]
        // The coverage and AISHub lines are information rows. The UKMTO rows carry no coordinate
        // and the host keeps them read-only; no point or zone is drawn for them.
        return FixtureResult(
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1_000),
            rows: rows,
            ships: ships)
    }
}
