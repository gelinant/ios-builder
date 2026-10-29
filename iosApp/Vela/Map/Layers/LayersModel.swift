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
    /// ARROW only: the symbol name (`arrow-through`, `arrow-left`, ...) and its map heading.
    var icon = ""
    var rotation = 0.0
}

struct LayerPin: Equatable {
    let coordinate: LayerCoordinate
    let kind: String
    let text: String
    /// Camera facing in degrees clockwise from north, nil for every non-camera pin and for a
    /// camera whose source carries no direction.
    let bearing: Double?

    init(coordinate: LayerCoordinate, kind: String, text: String, bearing: Double? = nil) {
        self.coordinate = coordinate
        self.kind = kind
        self.text = text
        self.bearing = bearing
    }
}

struct LayerBridge: Equatable {
    let coordinate: LayerCoordinate
    let openNow: Bool
    let endsAt: Int64
}

/// One isolated OSM tree. `crownM` is 0 when the source carries no crown or height; the renderer
/// then uses a neutral disc rather than inventing a size.
struct LayerTree: Equatable {
    let coordinate: LayerCoordinate
    let heightM: Double
    let crownM: Double
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
    var treesOn = false
    var trafficOn = false
    var satelliteOn = false
    var poiIconScale = 1.0
    var poiSource = "both"
    var showPlaces = true
    var showTransit = true
    var poiFiltered = false
    var visiblePoiClasses: [String] = []
    var visiblePoiGroups: [String] = []
    var poiDensity = "normal"
    /// The viewport zoom the store last reported. The map also tracks its own zoom; the larger
    /// of the two gates the overlays, so a style load after a data change cannot hide them at 0.
    var zoom = 0.0
    var paintedMarks: [PaintedMark] = []
    var speedPoints: [LayerPin] = []
    var alprPoints: [LayerPin] = []
    var controlPoints: [LayerPin] = []
    var fuelPoints: [LayerPin] = []
    var bridgePoints: [LayerBridge] = []
    var treePoints: [LayerTree] = []
    /// `auto`, `live` or `pack`: which family the renderer may draw.
    var cameraSource = "auto"
    /// Cameras read from the bundled or a region pack, already clipped to the viewport.
    var packSpeedPoints: [LayerPin] = []
    var packAlprPoints: [LayerPin] = []
    var packName = ""
    var packDate = ""
    var packCovers = false
    var packStale = false
    /// Bumped when the sheet closes. The map consumes this value through `onChange`, which does
    /// not fire for a change that happened while the sheet covered the map: without it a layer
    /// whose answer arrived behind the sheet stayed invisible until the camera moved.
    var revision = 0

    static let empty = MapLayerData()

    var isEmpty: Bool {
        !paintedRoads && !speedCameras && !alprCameras && !trafficControls
            && !fuelPrices && !bridgeOpenings && !treesOn
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
    @Published private(set) var poiSource = "both"
    @Published private(set) var cameraSource = "auto"
    @Published private(set) var packName = ""
    @Published private(set) var packDate = ""
    @Published private(set) var packCount = 0
    @Published private(set) var packCovers = false
    @Published private(set) var packStale = false

    private let store: LayersStore?
    private let offlineRoot: String?
    private let offlineStore: OfflineStore?
    private var observing: Task<Void, Never>?
    private var offlineObserving: Task<Void, Never>?
    private var lastState: LayersState?
    private var packSelection = CameraPacks.Selection()

    init(session: MapSession?) {
        store = session?.layers
        offlineRoot = session?.offline?.rootPath
        offlineStore = session?.offline
    }

    func start() {
        guard let store, observing == nil else { return }
        // The UI scenario pins the camera source for one launch; nothing is persisted for it.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-VelaCameraSource"), index + 1 < arguments.count {
            store.setCameraSource(source: arguments[index + 1])
        }
        if let index = arguments.firstIndex(of: "-VelaTreesFixture"), index + 1 < arguments.count {
            store.setTreeFixture(on: ["yes", "true", "1"].contains(arguments[index + 1].lowercased()))
        }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
        // A downloaded region owns the style: the tree polygons stay, the Overpass trees do not.
        if let offlineStore {
            offlineObserving = Task { @MainActor [weak self] in
                for await state in offlineStore.state {
                    self?.store?.setOffline(
                        on: state.currentRegionId != nil || !state.networkAvailable)
                }
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

    /// `vela`, `tiles` or `both`, Android's `map_places_source`.
    func setPoiSource(_ source: String) {
        store?.setPoiSource(source: source)
    }

    /// `auto`, `live` or `pack`: where the two camera families come from.
    func setCameraSource(_ source: String) {
        store?.setCameraSource(source: source)
    }

    var cameraSourceMode: CameraSource { CameraSource.normalize(cameraSource) }

    /// The sheet's one-line account of the pack under the current view. A stale pack says so and
    /// draws nothing; it is never presented as a usable source.
    var packText: String {
        if packStale && !packCovers {
            return "The last pack for this view is dated \(packDate) and is older than \(CameraPack.maxAgeDays) days. Nothing is drawn."
        }
        guard packCovers else { return "No offline camera pack covers this view." }
        return "\(packName): \(packCount) cameras in this view."
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
        refreshPack(viewport)
    }

    /// Reads the pack files for this viewport, then folds them into the value the map draws. The
    /// bundled pack is loaded once; region packs are cached by file date.
    private func refreshPack(_ viewport: MapViewport) {
        let selection = CameraPacks.selection(
            south: viewport.south, west: viewport.west,
            north: viewport.north, east: viewport.east, rootPath: offlineRoot)
        packSelection = selection
        let fresh = selection.fresh.first
        let stale = selection.stale.first
        packName = fresh?.name ?? ""
        packDate = fresh?.date ?? stale?.date ?? ""
        packCount = selection.speed.count + selection.alpr.count
        packCovers = !selection.fresh.isEmpty
        packStale = selection.fresh.isEmpty && !selection.stale.isEmpty
        rebuildData()
    }

    /// Re-emits the current data after the sheet closes so the map applies anything that landed
    /// while it was covered.
    func republish() {
        revision += 1
        rebuildData()
    }

    func snapshot(_ key: String) -> LayerSnapshot {
        statuses[key] ?? LayerSnapshot(phase: "off", count: 0, minZoom: 0, detail: "")
    }

    var debugLine: String {
        let keys = ["painted", "speed", "alpr", "controls", "fuel", "bridges", "trees"]
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
        return "layers \(layers) poi=\(poiSource) cats=\(cats.joined(separator: ","))"
            + " pack=\(VelaPoiPack.count) density=\(poiDensity)"
            + " icon=\(String(format: "%.2f", poiIconScale))"
            + " look=\(style.look.rawValue) appearance=\(style.appearance.rawValue)"
            + " names=\(style.names.rawValue) house=\(style.houseNumbers.rawValue)"
            + rasters + tiles + " " + CameraPackDebug.line + " " + CameraPackDebug.cones
            + " tree_source=\(treeSource)"
            + " marks_source=\(PaintedPack.source) marks_count=\(data.paintedMarks.count)"
            + " marks_zoom=\(zoom) zoom=\(zoom) " + PaintedDebug.line
            + " " + WorldLayersHub.shared.debugLine + " " + MapTapDebug.line
    }

    private var lastZoom = 0.0
    private var treeSource = "none"
    private var revision = 0

    private func apply(_ state: LayersState) {
        enabled = Set(Self.flags(state).filter { $0.value }.map(\.key))
        showPlaces = state.showPlaces
        categories = Set(Self.categories(state).filter { $0.value }.map(\.key))
        poiDensity = state.poiDensity
        poiIconScale = Double(state.poiIconScale)
        poiSource = state.poiSource
        cameraSource = state.cameraSource
        statuses = Dictionary(uniqueKeysWithValues: state.layerStatus.map {
            ($0.kind, LayerSnapshot(phase: $0.phase, count: Int($0.count),
                                     minZoom: $0.minZoom, detail: $0.detail))
        })
        lastZoom = state.zoom
        treeSource = state.treeSource
        lastState = state
        rebuildData()
    }

    /// Rebuilt from the last Kotlin state and the current pack selection. Called on every state
    /// change and whenever the viewport moves, so the pack points always match the visible box.
    private func rebuildData() {
        guard let state = lastState else { return }
        data = MapLayerData(
            paintedRoads: state.paintedRoads,
            speedCameras: state.speedCameras,
            alprCameras: state.alprCameras,
            trafficControls: state.trafficControls,
            fuelPrices: state.fuelPrices,
            bridgeOpenings: state.bridgeOpenings,
            treesOn: state.treesOn,
            trafficOn: state.trafficOn,
            satelliteOn: state.satelliteOn,
            poiIconScale: Double(state.poiIconScale),
            poiSource: state.poiSource,
            showPlaces: state.showPlaces,
            showTransit: state.showTransit,
            poiFiltered: state.poiFiltered,
            visiblePoiClasses: state.visiblePoiClasses,
            visiblePoiGroups: state.visiblePoiGroups,
            poiDensity: state.poiDensity,
            zoom: state.zoom,
            paintedMarks: state.paintedMarks.map { mark in
                PaintedMark(
                    kind: mark.kind,
                    coordinates: mark.points.map { LayerCoordinate(lat: $0.lat, lng: $0.lng) },
                    width: mark.widthM,
                    icon: mark.icon,
                    rotation: mark.rotDeg)
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
            },
            treePoints: state.treePoints.map {
                LayerTree(
                    coordinate: LayerCoordinate(lat: $0.lat, lng: $0.lng),
                    heightM: $0.heightM, crownM: $0.crownM)
            },
            cameraSource: state.cameraSource,
            packSpeedPoints: packSelection.speed.map { pin(kind: "speed", point: $0) },
            packAlprPoints: packSelection.alpr.map { pin(kind: "alpr", point: $0) },
            packName: packName,
            packDate: packDate,
            packCovers: packCovers,
            packStale: packStale,
            revision: revision)
    }

    private func pin(kind: String, point: MapPoint) -> LayerPin {
        LayerPin(coordinate: LayerCoordinate(lat: point.lat, lng: point.lng), kind: kind,
                 text: "", bearing: point.direction?.doubleValue)
    }

    private func pin(kind: String, point: CameraPoint) -> LayerPin {
        LayerPin(coordinate: LayerCoordinate(lat: point.lat, lng: point.lng), kind: kind,
                 text: "", bearing: point.bearing)
    }

    private static func flags(_ state: LayersState) -> [String: Bool] {
        [
            "painted": state.paintedRoads,
            "speed": state.speedCameras,
            "alpr": state.alprCameras,
            "controls": state.trafficControls,
            "fuel": state.fuelPrices,
            "bridges": state.bridgeOpenings,
            "trees": state.treesOn,
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
