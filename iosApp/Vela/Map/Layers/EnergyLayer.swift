import CoreLocation
import Foundation
import MapLibre
import UIKit
import VelaCore

/// One approximate NESO region loaded from `neso-regions.json`: an unofficial center for the
/// sheet row and simplified polygons for the map fill.
struct NesoRegionShape {
    let regionId: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let radiusKm: Double
    let polygons: [[[Double]]]
}

/// One region as the layer draws it, after the forecast has been matched with its shape.
private struct EnergyDisplayRegion {
    let regionId: Int
    let name: String
    let forecast: Int
    let index: String
    let latitude: Double
    let longitude: Double
    let polygons: [[[Double]]]
}

/// Socket for the energy layer (A-3). It draws keyless NESO carbon intensity for Great Britain and
/// carries the optional Electricity Maps and Cloudflare Radar feeds. A missing key is a visible
/// state, never an empty map: Electricity Maps says key required and Radar says token missing.
///
/// The host (`WorldLayers.swift` and `WorldLayerSection.swift`) is untouched. `installed` is true
/// because `refresh` and `apply` really produce data; the WLD-1 row is therefore enabled.
final class EnergyLayer: WorldLayer {
    static let installed = true
    static let sourceId = "vela-energy-src"
    static let fillLayerIds = [
        "vela-energy-verylow", "vela-energy-low", "vela-energy-moderate",
        "vela-energy-high", "vela-energy-veryhigh", "vela-energy-unknown",
    ]
    static let labelLayerId = "vela-energy-label"
    static let maxAgeMs: Int64 = 30 * 60 * 1_000

    let id = "energy"
    let title = VelaL10n.text("world_layer_energy")
    let source = "NESO Carbon Intensity, CC BY 4.0; Cloudflare Radar, CC BY-NC 4.0; Electricity Maps with a user key"
    var isInstalled: Bool { Self.installed }

    private(set) var rows: [WorldLayerRow] = []

    private var store: EnergyStore?
    private var radar: RadarLayer?
    private var regions: [NesoRegionShape] = []
    private var displayRegions: [EnergyDisplayRegion] = []
    private var lastUpdatedMs: Int64 = 0
    private var lastOffline = false
    private var loadedRegions = false

    init() {
        #if DEBUG
        WorldEnergyFixture.prepare()
        #endif
        loadRegions()
        #if DEBUG
        if WorldEnergyFixture.isActive {
            rows = fixtureRows(nowMs: Int64(Date().timeIntervalSince1970 * 1_000))
        }
        #endif
    }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? {
        guard !lastOffline else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        #if DEBUG
        if WorldEnergyFixture.isActive {
            return fixtureRefresh(nowMs: now)
        }
        #endif
        ensureStores()
        guard let store else { return nil }
        let mapsKey = WorldLayerSecrets.value(account: WorldLayerSecrets.electricityMapsAccount)
        let snapshot: EnergySnapshot?
        do {
            snapshot = try await store.refresh(
                zones: kotlinZones(), electricityMapsKey: mapsKey, nowMs: now)
        } catch {
            snapshot = nil
        }
        let radarOK = (await radar?.refresh(nowMs: now)) ?? false
        guard snapshot != nil || radarOK else { return nil }
        lastUpdatedMs = snapshot?.updatedAtMs ?? now
        displayRegions = displayRegionsFrom(snapshot)
        rows = makeRows(snapshot: snapshot, nowMs: now)
        let radarStatus = radar?.status ?? "unavailable"
        rows.insert(debugRow(radarStatus: radarStatus, snapshot: snapshot), at: 0)
        return WorldLayerRefresh(updatedAtMs: lastUpdatedMs, rows: rows)
    }

    func apply(style: MLNStyle, offline: Bool) {
        lastOffline = offline
        guard !offline else { return }
        #if DEBUG
        if !WorldEnergyFixture.isActive {
            WorldEnergyKeyPrompt.presentIfNeeded()
        }
        #else
        WorldEnergyKeyPrompt.presentIfNeeded()
        #endif
        let fresh = lastUpdatedMs > 0
            && Int64(Date().timeIntervalSince1970 * 1_000) - lastUpdatedMs <= Self.maxAgeMs
        drawCarbon(style, visible: fresh && !displayRegions.isEmpty)
        radar?.apply(style: style, offline: offline)
    }

    // MARK: - Sources

    private func ensureStores() {
        guard store == nil, let http = IosGraph.shared.core?.http else { return }
        store = EnergyStore(
            carbon: CarbonIntensitySource(
                http: http, baseUrl: "https://api.carbonintensity.org.uk"),
            electricityMaps: ElectricityMapsSource(
                http: http, baseUrl: "https://api.electricitymaps.com"))
        radar = RadarLayer(http: http)
    }

    private func loadRegions() {
        guard !loadedRegions else { return }
        loadedRegions = true
        let candidates: [String?] = [nil, "world", "Resources/world"]
        var url: URL?
        for directory in candidates {
            if let found = Bundle.main.url(
                forResource: "neso-regions", withExtension: "json", subdirectory: directory) {
                url = found
                break
            }
        }
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(NesoRegionFile.self, from: data) else { return }
        regions = file.regions.sorted { $0.regionId < $1.regionId }.map { region in
            NesoRegionShape(
                regionId: region.regionId,
                name: region.name,
                latitude: region.center.first ?? 0,
                longitude: region.center.count > 1 ? region.center[1] : 0,
                radiusKm: region.radiusKm ?? 50,
                polygons: region.polygons ?? [])
        }
    }

    private func kotlinZones() -> [NesoZone] {
        regions.map { region in
            NesoZone(
                regionId: Int32(region.regionId),
                name: region.name,
                latitude: region.latitude,
                longitude: region.longitude,
                radiusKm: region.radiusKm)
        }
    }

    private func displayRegionsFrom(_ snapshot: EnergySnapshot?) -> [EnergyDisplayRegion] {
        guard let carbon = snapshot?.carbon else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: regions.map { ($0.regionId, $0) })
        return carbon.regions.compactMap { reading in
            guard let shape = byId[Int(reading.regionId)] else { return nil }
            return EnergyDisplayRegion(
                regionId: shape.regionId,
                name: reading.name,
                forecast: Int(reading.forecastGrams),
                index: reading.index,
                latitude: shape.latitude,
                longitude: shape.longitude,
                polygons: shape.polygons)
        }
    }

    // MARK: - Rows

    private func makeRows(snapshot: EnergySnapshot?, nowMs: Int64) -> [WorldLayerRow] {
        var out: [WorldLayerRow] = []
        if snapshot?.carbon != nil, !displayRegions.isEmpty {
            for region in displayRegions {
                out.append(WorldLayerRow(
                    id: "energy-carbon-\(region.regionId)",
                    title: "\(region.name): \(region.index) (\(region.forecast) gCO2/kWh)",
                    detail: "NESO half-hour forecast. Zone shape simplified from NESO DNO boundaries; center approximate.",
                    lat: region.latitude,
                    lng: region.longitude))
            }
        } else {
            out.append(WorldLayerRow(
                id: "energy-carbon-none",
                title: "NESO Carbon Intensity: no data",
                detail: "The last request failed. The layer keeps the previous forecast and shows its age rather than inventing values."))
        }

        let mapsState = snapshot?.electricityMapsState
        switch mapsState {
        case "ok":
            if let reading = snapshot?.electricityMaps.first {
                out.append(WorldLayerRow(
                    id: "energy-electricity-maps",
                    title: "Electricity Maps: GB \(Int(reading.carbonIntensity)) gCO2/kWh",
                    detail: "User key. Electricity Maps has no anonymous free tier; this value is shown only when a key is stored."))
            }
        case "no_data":
            out.append(WorldLayerRow(
                id: "energy-electricity-maps-none",
                title: "Electricity Maps: no data",
                detail: "A key is stored but the request failed. No value is invented."))
        default:
            let keyPresent = KeychainSecrets.shared.has(
                secretId: WorldLayerSecrets.electricityMapsAccount)
            out.append(WorldLayerRow(
                id: "energy-electricity-maps-key",
                title: keyPresent ? "Electricity Maps: no data" : "Electricity Maps: key required",
                detail: keyPresent
                    ? "The stored key returned no reading. No value is invented."
                    : "No key saved. Without a key this feed stays empty, not zero carbon. Add a key from the sheet."))
        }

        if let radar {
            out.append(contentsOf: radar.rows(nowMs: nowMs))
        } else {
            out.append(WorldLayerRow(
                id: "energy-radar-unavailable",
                title: "Cloudflare Radar: unavailable",
                detail: "The HTTP client did not start. Radar only sees Cloudflare traffic."))
        }
        return out
    }

    private func debugRow(radarStatus: String, snapshot: EnergySnapshot?) -> WorldLayerRow {
        let count = snapshot?.carbon?.regions.count ?? 0
        let maps = snapshot?.electricityMapsState ?? "no_data"
        return WorldLayerRow(
            id: "energy-debug",
            title: "energy_source=neso radar_state=\(radarStatus) energy_regions=\(count) electricity_maps=\(maps)")
    }

    // MARK: - Drawing

    private func drawCarbon(_ style: MLNStyle, visible: Bool) {
        if style.source(withIdentifier: Self.sourceId) == nil {
            style.addSource(MLNShapeSource(identifier: Self.sourceId, shape: nil, options: nil))
        }
        guard let source = style.source(withIdentifier: Self.sourceId) else { return }
        var shapes: [MLNPolygonFeature] = []
        if visible {
            for region in displayRegions {
                let band = Self.bandKey(region.index)
                for polygon in region.polygons {
                    guard polygon.count >= 3 else { continue }
                    var coordinates = polygon.map {
                        CLLocationCoordinate2D(latitude: $0.count > 1 ? $0[1] : 0,
                                               longitude: $0.first ?? 0)
                    }
                    let feature = MLNPolygonFeature(
                        coordinates: &coordinates, count: UInt(coordinates.count))
                    feature.attributes = ["band": band, "name": region.name]
                    shapes.append(feature)
                }
            }
        }
        (source as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: shapes)
        ensureEnergyLayers(style)
        for id in Self.fillLayerIds {
            style.layers.first { $0.identifier == id }?.isVisible = visible
        }
        style.layers.first { $0.identifier == Self.labelLayerId }?.isVisible = visible
    }

    private func ensureEnergyLayers(_ style: MLNStyle) {
        guard let source = style.source(withIdentifier: Self.sourceId) else { return }
        let anchor = MapLayers.labelAnchor(in: style)
        func add(_ layer: MLNStyleLayer) {
            if let anchor {
                style.insertLayer(layer, below: anchor)
            } else {
                style.addLayer(layer)
            }
        }
        let bands: [(String, UIColor)] = [
            ("verylow", UIColor(energyRGB: 0x1B7F3A)),
            ("low", UIColor(energyRGB: 0x7CB342)),
            ("moderate", UIColor(energyRGB: 0xF9A825)),
            ("high", UIColor(energyRGB: 0xEF6C00)),
            ("veryhigh", UIColor(energyRGB: 0xC62828)),
            ("unknown", UIColor(energyRGB: 0x757575)),
        ]
        for (index, (band, color)) in bands.enumerated() {
            let id = Self.fillLayerIds[index]
            guard style.layers.first(where: { $0.identifier == id }) == nil else { continue }
            let fill = MLNFillStyleLayer(identifier: id, source: source)
            fill.predicate = NSPredicate(format: "band == %@", band)
            fill.fillColor = NSExpression(forConstantValue: color)
            fill.fillOpacity = NSExpression(forConstantValue: 0.38)
            fill.fillOutlineColor = NSExpression(forConstantValue: color.withAlphaComponent(0.7))
            add(fill)
        }
        guard style.layers.first(where: { $0.identifier == Self.labelLayerId }) == nil else { return }
        let label = MLNSymbolStyleLayer(identifier: Self.labelLayerId, source: source)
        label.text = NSExpression(forKeyPath: "name")
        label.textFontNames = NSExpression(forConstantValue: ["Roboto Medium"])
        label.textFontSize = NSExpression(forConstantValue: 10)
        label.textColor = NSExpression(forConstantValue: UIColor(white: 0.1, alpha: 1))
        label.textHaloColor = NSExpression(forConstantValue: UIColor.white)
        label.textHaloWidth = NSExpression(forConstantValue: 1.4)
        label.textAllowsOverlap = NSExpression(forConstantValue: false)
        add(label)
    }

    private static func bandKey(_ index: String) -> String {
        switch index.lowercased() {
        case "very low": return "verylow"
        case "low": return "low"
        case "moderate": return "moderate"
        case "high": return "high"
        case "very high": return "veryhigh"
        default: return "unknown"
        }
    }

    // MARK: - Debug fixtures

    #if DEBUG
    private func fixtureRefresh(nowMs: Int64) -> WorldLayerRefresh? {
        let keys = WorldEnergyFixture.keysPresent
        lastUpdatedMs = nowMs
        displayRegions = regions.map { region in
            let forecast = Self.fixtureForecast(region.regionId)
            return EnergyDisplayRegion(
                regionId: region.regionId,
                name: region.name,
                forecast: forecast,
                index: Self.fixtureIndex(forecast),
                latitude: region.latitude,
                longitude: region.longitude,
                polygons: region.polygons)
        }
        if keys {
            radar?.setFixture(Self.fixtureRadarEntries(nowMs: nowMs))
        } else {
            radar?.clearFixture()
        }
        rows = fixtureRows(nowMs: nowMs)
        return WorldLayerRefresh(updatedAtMs: nowMs, rows: rows)
    }

    private func fixtureRows(nowMs: Int64) -> [WorldLayerRow] {
        var out: [WorldLayerRow] = []
        let keys = WorldEnergyFixture.keysPresent
        out.append(WorldLayerRow(
            id: "energy-debug",
            title: "energy_source=neso radar_state=\(keys ? "fresh" : "key_required") energy_regions=14 electricity_maps=\(keys ? "ok" : "key_required")"))
        for region in regions {
            let forecast = Self.fixtureForecast(region.regionId)
            let index = Self.fixtureIndex(forecast)
            out.append(WorldLayerRow(
                id: "energy-carbon-\(region.regionId)",
                title: "\(region.name): \(index) (\(forecast) gCO2/kWh)",
                detail: "Fixture. NESO half-hour forecast; zone shape approximate.",
                lat: region.latitude,
                lng: region.longitude))
        }
        if keys {
            out.append(WorldLayerRow(
                id: "energy-electricity-maps",
                title: "Electricity Maps: GB 88 gCO2/kWh",
                detail: "Fixture answer for a stored key."))
            for entry in Self.fixtureRadarEntries(nowMs: nowMs) {
                out.append(WorldLayerRow(
                    id: "energy-radar-\(entry.id)",
                    title: entry.title,
                    detail: "Fixture. \(entry.detail). Cloudflare traffic only.",
                    lat: entry.latitude,
                    lng: entry.longitude))
            }
            out.append(WorldLayerRow(
                id: "energy-radar-scope",
                title: "Cloudflare Radar: Cloudflare traffic only",
                detail: "Outages and attacks describe traffic Cloudflare sees, not the whole Internet."))
        } else {
            out.append(WorldLayerRow(
                id: "energy-electricity-maps-key",
                title: "Electricity Maps: key required",
                detail: "No key saved. Without a key this feed stays empty, not zero carbon."))
            out.append(WorldLayerRow(
                id: "energy-radar-key",
                title: "Cloudflare Radar: token missing",
                detail: "Outages and attacks are unknown, not empty. Radar sees only Cloudflare traffic."))
        }
        return out
    }

    private static func fixtureIndex(_ forecast: Int) -> String {
        switch forecast {
        case ...50: return "very low"
        case ...100: return "low"
        case ...150: return "moderate"
        case ...200: return "high"
        default: return "very high"
        }
    }

    private static func fixtureForecast(_ id: Int) -> Int {
        let values = [0, 25, 60, 90, 120, 150, 205, 23, 85, 61, 32, 95, 170, 250]
        return values[(id - 1).clamped(to: 0...(values.count - 1))]
    }

    private static func fixtureRadarEntries(nowMs: Int64) -> [RadarEntry] {
        [
            RadarEntry(
                id: "fixture-outage-gb",
                kind: "outage",
                title: "Cloudflare outage annotation, United Kingdom",
                detail: "Fixture outage annotation, cable cut",
                startedAtMs: nowMs - 3_600_000,
                locations: ["GB"],
                url: "",
                latitude: 54.0,
                longitude: -2.0),
            RadarEntry(
                id: "fixture-attack-fr",
                kind: "attack",
                title: "Attack from France to United Kingdom",
                detail: "Fixture share of layer 3 attack traffic",
                startedAtMs: nowMs - 7_200_000,
                locations: ["FR", "GB"],
                url: "",
                latitude: 46.0,
                longitude: 2.0),
        ]
    }
    #endif
}

/// The bundled file's shape. Only the fields this layer needs are decoded.
private struct NesoRegionFile: Decodable {
    let regions: [NesoRegion]
}

private struct NesoRegion: Decodable {
    let regionId: Int
    let name: String
    let center: [Double]
    let radiusKm: Double?
    let polygons: [[[Double]]]?
}

private extension UIColor {
    convenience init(energyRGB: UInt32) {
        self.init(
            red: CGFloat((energyRGB >> 16) & 0xFF) / 255,
            green: CGFloat((energyRGB >> 8) & 0xFF) / 255,
            blue: CGFloat(energyRGB & 0xFF) / 255,
            alpha: 1)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
