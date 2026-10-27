import CoreLocation
import Foundation
import VelaCore

/// A point handed to MapLibre. `CLLocationCoordinate2D` is not `Equatable`, so the model keeps its
/// own value type until the renderer converts it.
struct LayerCoordinate: Equatable {
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct PaintedMark: Equatable {
    let kind: String
    let coordinates: [LayerCoordinate]
    let width: Double
}

struct LayerPin: Equatable {
    let coordinate: LayerCoordinate
    let kind: String
    let text: String
}

struct LayerBridge: Equatable {
    let coordinate: LayerCoordinate
    let openNow: Bool
    let endsAt: Int64
}

/// Everything the map draws for the layer sheet. Status and text live in `LayersModel`; this value
/// changes only when geometry or a switch does, so SwiftUI does not re-apply a style every tick.
struct MapLayerData: Equatable {
    var paintedRoads = false
    var speedCameras = false
    var alprCameras = false
    var trafficControls = false
    var fuelPrices = false
    var bridgeOpenings = false
    var trafficOn = false
    var satelliteOn = false
    var poiIconScale = 1.0
    var showPlaces = true
    var showTransit = true
    var poiFiltered = false
    var visiblePoiClasses: [String] = []
    var poiDensity = "normal"
    var paintedMarks: [PaintedMark] = []
    var speedPoints: [LayerPin] = []
    var alprPoints: [LayerPin] = []
    var controlPoints: [LayerPin] = []
    var fuelPoints: [LayerPin] = []
    var bridgePoints: [LayerBridge] = []

    static let empty = MapLayerData()

    var isEmpty: Bool {
        !paintedRoads && !speedCameras && !alprCameras && !trafficControls
            && !fuelPrices && !bridgeOpenings
    }
}

struct LayerSnapshot: Equatable {
    let phase: String
    let count: Int
    let minZoom: Double
    let detail: String
}

/// SwiftUI's mirror of `LayersStore`. A layer loads only after its switch is on; the map viewport
/// is forwarded from `MapController.regionDidChange`, never from a display link.
final class LayersModel: ObservableObject {
    @Published private(set) var data = MapLayerData.empty
    @Published private(set) var statuses: [String: LayerSnapshot] = [:]
    @Published private(set) var enabled: Set<String> = []
    @Published private(set) var showPlaces = true
    @Published private(set) var categories: Set<String> = ["food", "fuel", "transit", "parking", "other"]
    @Published private(set) var poiDensity = "normal"
    @Published private(set) var style = MapStyleSettings.current()
    @Published private(set) var poiIconScale = 1.0

    private let store: LayersStore?
    private var observing: Task<Void, Never>?

    init(session: MapSession?) {
        store = session?.layers
    }

    func start() {
        guard let store, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func setLayer(_ key: String, _ on: Bool) {
        store?.setSwitch(key: key, on: on)
    }

    func setShowPlaces(_ on: Bool) {
        store?.setShowPlaces(on: on)
    }

    func setCategory(_ category: String, _ on: Bool) {
        store?.setPoiCategory(category: category, on: on)
    }

    func setDensity(_ density: String) {
        store?.setPoiDensity(density: density)
    }

    func setLook(_ look: MapLook) {
        var next = style
        next.look = look
        applyStyle(next)
    }

    func setAppearance(_ appearance: MapAppearance) {
        var next = style
        next.appearance = appearance
        applyStyle(next)
    }

    func setNames(_ names: MapNamesMode) {
        var next = style
        next.names = names
        applyStyle(next)
    }

    func setHouseNumbers(_ level: HouseNumberLevel) {
        var next = style
        next.houseNumbers = level
        applyStyle(next)
    }

    private func applyStyle(_ options: MapStyleOptions) {
        style = options
        MapStyleSettings.save(options)
    }

    /// The three Android sizes: 0.7 small, 1.0 default, 1.25 large.
    func setIconScale(_ scale: Double) {
        store?.setPoiIconScale(scale: Float(scale))
    }

    func viewportChanged(_ viewport: MapViewport) {
        store?.onViewport(
            south: viewport.south, west: viewport.west,
            north: viewport.north, east: viewport.east, zoom: viewport.zoom)
    }

    func snapshot(_ key: String) -> LayerSnapshot {
        statuses[key] ?? LayerSnapshot(phase: "off", count: 0, minZoom: 0, detail: "")
    }

    var debugLine: String {
        let keys = ["painted", "speed", "alpr", "controls", "fuel", "bridges"]
        let layers = keys.map { key -> String in
            let s = snapshot(key)
            return "\(key)=\(s.phase):\(s.count)"
        }.joined(separator: " ")
        let cats = ["food", "fuel", "transit", "parking", "other"].filter(categories.contains)
        let zoom = lastZoom > 0 ? String(format: "%.1f", lastZoom) : "-"
        let rasters = " traffic=\(enabled.contains("traffic") ? "on" : "off")"
            + " satellite=\(enabled.contains("satellite") ? "on" : "off")"
            + " raster=\(MapRasterDebug.layers)"
        #if DEBUG
        let tiles = " tiles=\(MapTileNetwork.shared.rasterRequests)"
        #else
        let tiles = ""
        #endif
        return "layers \(layers) poi=\(cats.joined(separator: ",")) density=\(poiDensity)"
            + " icon=\(String(format: "%.2f", poiIconScale))"
            + " look=\(style.look.rawValue) appearance=\(style.appearance.rawValue)"
            + " names=\(style.names.rawValue) house=\(style.houseNumbers.rawValue)"
            + rasters + tiles
            + " zoom=\(zoom)"
    }

    private var lastZoom = 0.0

    private func apply(_ state: LayersState) {
        enabled = Set(Self.flags(state).filter { $0.value }.map(\.key))
        showPlaces = state.showPlaces
        categories = Set(Self.categories(state).filter { $0.value }.map(\.key))
        poiDensity = state.poiDensity
        poiIconScale = Double(state.poiIconScale)
        statuses = Dictionary(uniqueKeysWithValues: state.layerStatus.map {
            ($0.kind, LayerSnapshot(phase: $0.phase, count: Int($0.count),
                                     minZoom: $0.minZoom, detail: $0.detail))
        })
        lastZoom = state.zoom
        data = MapLayerData(
            paintedRoads: state.paintedRoads,
            speedCameras: state.speedCameras,
            alprCameras: state.alprCameras,
            trafficControls: state.trafficControls,
            fuelPrices: state.fuelPrices,
            bridgeOpenings: state.bridgeOpenings,
            trafficOn: state.trafficOn,
            satelliteOn: state.satelliteOn,
            poiIconScale: Double(state.poiIconScale),
            showPlaces: state.showPlaces,
            showTransit: state.showTransit,
            poiFiltered: state.poiFiltered,
            visiblePoiClasses: state.visiblePoiClasses,
            poiDensity: state.poiDensity,
            paintedMarks: state.paintedMarks.map { mark in
                PaintedMark(
                    kind: mark.kind,
                    coordinates: mark.points.map { LayerCoordinate(lat: $0.lat, lng: $0.lng) },
                    width: mark.widthM)
            },
            speedPoints: state.speedCameraPoints.map { pin(kind: "speed", point: $0) },
            alprPoints: state.alprCameraPoints.map { pin(kind: "alpr", point: $0) },
            controlPoints: state.controlPoints.map {
                LayerPin(
                    coordinate: LayerCoordinate(lat: $0.lat, lng: $0.lng),
                    kind: $0.kind, text: "")
            },
            fuelPoints: state.fuelPoints.map { fuel in
                LayerPin(
                    coordinate: LayerCoordinate(lat: fuel.lat, lng: fuel.lng),
                    kind: "fuel", text: Self.fuelText(fuel))
            },
            bridgePoints: state.bridgePoints.map {
                LayerBridge(
                    coordinate: LayerCoordinate(lat: $0.lat, lng: $0.lng),
                    openNow: $0.openNow, endsAt: $0.endMs)
            })
    }

    private func pin(kind: String, point: MapPoint) -> LayerPin {
        LayerPin(coordinate: LayerCoordinate(lat: point.lat, lng: point.lng), kind: kind, text: "")
    }

    private static func flags(_ state: LayersState) -> [String: Bool] {
        [
            "painted": state.paintedRoads,
            "speed": state.speedCameras,
            "alpr": state.alprCameras,
            "controls": state.trafficControls,
            "fuel": state.fuelPrices,
            "bridges": state.bridgeOpenings,
            "traffic": state.trafficOn,
            "satellite": state.satelliteOn,
        ]
    }

    private static func categories(_ state: LayersState) -> [String: Bool] {
        [
            "food": state.showFood,
            "fuel": state.showFuel,
            "transit": state.showTransit,
            "parking": state.showParking,
            "other": state.showOther,
        ]
    }

    #if DEBUG
    func fuelTextForTest(brand: String, e10: Double, e5: Double, b7p: Double) -> String {
        Self.fuelText(brand: brand, e10: e10, e5: e5, b7p: b7p)
    }
    #endif

    private static func fuelText(_ fuel: MapFuelPoint) -> String {
        fuelText(brand: fuel.brand, e10: fuel.e10Pence, e5: fuel.e5Pence, b7p: fuel.b7pPence)
    }

    private static func fuelText(brand rawBrand: String, e10: Double, e5: Double, b7p: Double) -> String {
        let brand = rawBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = e10 >= 0 ? e10 : (e5 >= 0 ? e5 : b7p)
        guard price >= 0 else { return brand }
        let text = String(format: "%.1fp", price)
        return brand.isEmpty ? text : "\(brand) \(text)"
    }
}
