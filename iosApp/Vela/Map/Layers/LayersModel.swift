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
        return "layers \(layers) poi=\(cats.joined(separator: ",")) density=\(poiDensity) zoom=\(zoom)"
    }

    private var lastZoom = 0.0

    private func apply(_ state: LayersState) {
        enabled = Set(Self.flags(state).filter { $0.value }.map(\.key))
        showPlaces = state.showPlaces
        categories = Set(Self.categories(state).filter { $0.value }.map(\.key))
        poiDensity = state.poiDensity
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
            showPlaces: state.showPlaces,
            showTransit: state.showTransit,
            poiFiltered: state.poiFiltered,
            visiblePoiClasses: state.visiblePoiClasses,
            poiDensity: state.poiDensity,
            paintedMarks: state.paintedMarks.map { mark in
                PaintedMark(
                    kind: mark.kind, width: mark.widthM,
                    coordinates: mark.points.map { LayerCoordinate(lat: $0.lat, lng: $0.lng) })
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
    func fuelTextForTest(_ fuel: MapFuelPoint) -> String { Self.fuelText(fuel) }
    #endif

    private static func fuelText(_ fuel: MapFuelPoint) -> String {
        let brand = fuel.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = fuel.e10Pence >= 0 ? fuel.e10Pence : (fuel.e5Pence >= 0 ? fuel.e5Pence : fuel.b7pPence)
        guard price >= 0 else { return brand }
        let text = String(format: "%.1fp", price)
        return brand.isEmpty ? text : "\(brand) \(text)"
    }
}
