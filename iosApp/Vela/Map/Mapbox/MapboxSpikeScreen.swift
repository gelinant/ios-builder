#if DEBUG
import CoreLocation
import MapboxMaps
import QuartzCore
import SwiftUI
import UIKit

/// The Mapbox spike (docs/ios/MAPBOX-SPIKE.md): one Debug screen with Mapbox Maps SDK v11, the
/// Standard style, 3D terrain and three San Francisco cameras, opened instead of the map screen by
/// `-VelaMapboxSpike YES`. It never reads the user's location and touches no app state.
enum MapboxSpikeLaunch {
    static let isRequested: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaMapboxSpike"), index + 1 < arguments.count else {
            return false
        }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }()

    /// Whether the build carries a public token. Only this yes or no is ever shown or logged.
    static var hasToken: Bool {
        let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
        return token.hasPrefix("pk.") && token.count > 20
    }

    /// The version of the linked MapboxCoreMaps framework, or "0" when it is not loaded.
    static var sdkVersion: String {
        guard let bundle = Bundle.allFrameworks.first(where: {
            $0.bundlePath.hasSuffix("MapboxCoreMaps.framework")
        }) else { return "0" }
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String
        return version ?? "linked"
    }

    /// Mapbox telemetry starts off. The SDK reads this key when its first map view is built and
    /// registers `true` as the default; a value already stored, from this call or from the
    /// attribution menu, wins over that default.
    static func disableTelemetryByDefault() {
        let key = "MGLMapboxMetricsEnabled"
        let domain = Bundle.main.bundleIdentifier ?? "app.vela.ios"
        if UserDefaults.standard.persistentDomain(forName: domain)?[key] == nil {
            UserDefaults.standard.set(false, forKey: key)
        }
    }
}

/// The fixture cameras. Twin Peaks has the relief, downtown has the buildings.
enum MapboxSpikeCamera: String, CaseIterable {
    case twinPeaks15 = "twinpeaks-z15"
    case twinPeaks17 = "twinpeaks-z17"
    case downtown16 = "downtown-z16"

    static let twinPeaks = CLLocationCoordinate2D(latitude: 37.7544, longitude: -122.4477)
    static let downtown = CLLocationCoordinate2D(latitude: 37.7915, longitude: -122.3990)
    static let pitch: CGFloat = 60
    static let bearing: Double = 200

    var center: CLLocationCoordinate2D {
        self == .downtown16 ? Self.downtown : Self.twinPeaks
    }

    var zoom: Double {
        switch self {
        case .twinPeaks15: return 15
        case .twinPeaks17: return 17
        case .downtown16: return 16
        }
    }

    var options: CameraOptions {
        CameraOptions(center: center, zoom: zoom, bearing: Self.bearing, pitch: Self.pitch)
    }
}

/// The spike's state and the FPS motion. The status line is what MapboxSpikeUITests reads.
final class MapboxSpikeModel: NSObject, ObservableObject {
    /// The scripted motion shared with the WebMap probe (MapFpsProbe): bearing +360 over 10 s.
    static let motionSeconds: Double = 10
    static let motionDegrees: Double = 360
    /// Map3D.terrainExaggeration on the WebMap.
    static let terrainExaggeration: Double = 1.2

    @Published private(set) var line = ""

    let hasToken = MapboxSpikeLaunch.hasToken
    let sdk = MapboxSpikeLaunch.sdkVersion
    weak var mapView: MapboxMaps.MapView?
    var cancelables = Set<AnyCancelable>()

    private let createdAt = CACurrentMediaTime()
    private var styleMs = -1
    private var loadedMs = -1
    private var styleLoaded = false
    private var terrainSet = false
    private var elevation: Double?
    /// The highest ground seen under a camera center. Twin Peaks stands near 280 m; a flat map
    /// without terrain answers nil.
    private var peakElevation: Double = 0
    private var camera = MapboxSpikeCamera.twinPeaks15
    private var idle = false
    private var errors = 0
    private var lastError = "-"
    private var fpsText = "-"
    private var fpsPending = false
    private var fpsLink: CADisplayLink?
    private var fpsStart: CFTimeInterval?
    private var fpsFrames = 0
    private var fpsTicks = 0
    private var countingFrames = false

    override init() {
        super.init()
        refresh()
    }

    func styleDidLoad() {
        guard !styleLoaded else { return }
        styleLoaded = true
        styleMs = Int((CACurrentMediaTime() - createdAt) * 1000)
        refresh()
    }

    func mapDidLoad() {
        guard loadedMs < 0 else { return }
        loadedMs = Int((CACurrentMediaTime() - createdAt) * 1000)
        refresh()
    }

    func terrainDidSet() {
        terrainSet = true
        refresh()
    }

    func mapDidIdle() {
        idle = true
        if let map = mapView?.mapboxMap {
            elevation = map.elevation(at: camera.center)
            peakElevation = max(peakElevation, elevation ?? 0)
        }
        if fpsPending {
            fpsPending = false
            startMotion()
        }
        refresh()
    }

    func frameRendered() {
        if countingFrames { fpsFrames += 1 }
    }

    func loadingFailed(_ message: String) {
        errors += 1
        lastError = String(message.replacingOccurrences(of: " ", with: "_").prefix(60))
        refresh()
    }

    func show(_ target: MapboxSpikeCamera) {
        // The same camera again would never send a new idle event.
        guard let map = mapView?.mapboxMap, fpsLink == nil, target != camera else { return }
        camera = target
        idle = false
        fpsText = "-"
        map.setCamera(to: target.options)
        refresh()
    }

    /// Waits for the current camera to settle, then turns the bearing through 360 degrees over
    /// 10 s, one camera step per display frame, and counts the rendered frames.
    func runFps() {
        guard mapView != nil, fpsLink == nil, !fpsPending else { return }
        fpsText = "running"
        refresh()
        if idle {
            startMotion()
            return
        }
        fpsPending = true
        // A map that never reports idle (tiles failing) still runs the motion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.fpsPending else { return }
            self.fpsPending = false
            self.startMotion()
        }
    }

    private func startMotion() {
        guard fpsLink == nil else { return }
        fpsStart = nil
        fpsFrames = 0
        fpsTicks = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        fpsLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let map = mapView?.mapboxMap else {
            stopMotion(elapsed: 0)
            return
        }
        if fpsStart == nil {
            fpsStart = link.timestamp
            fpsFrames = 0
            countingFrames = true
        }
        let elapsed = link.timestamp - (fpsStart ?? link.timestamp)
        fpsTicks += 1
        if elapsed >= Self.motionSeconds {
            stopMotion(elapsed: elapsed)
            return
        }
        let bearing = MapboxSpikeCamera.bearing + Self.motionDegrees * elapsed / Self.motionSeconds
        map.setCamera(to: CameraOptions(bearing: bearing))
    }

    private func stopMotion(elapsed: Double) {
        countingFrames = false
        fpsLink?.invalidate()
        fpsLink = nil
        let fps = elapsed > 0 ? Double(fpsFrames) / elapsed : 0
        fpsText = String(format: "%.1f frames=%d ticks=%d seconds=%.2f", fps, fpsFrames, fpsTicks, elapsed)
        refresh()
    }

    private func refresh() {
        let elevationText = elevation.map { String(format: "%.0f", $0) } ?? "-"
        let terrainOn = terrainSet && peakElevation > 50
        line = [
            "token=\(hasToken ? 1 : 0)",
            "sdk=\(sdk)",
            "style=\(styleLoaded ? 1 : 0)",
            "style_ms=\(styleMs)",
            "loaded_ms=\(loadedMs)",
            "terrain=\(terrainOn ? 1 : 0)",
            "elevation=\(elevationText)",
            "peak=\(Int(peakElevation))",
            "camera=\(camera.rawValue)",
            "idle=\(idle ? 1 : 0)",
            "errors=\(errors)",
            "error=\(lastError)",
            "fps=\(fpsText)",
        ].joined(separator: " ")
    }
}

struct MapboxSpikeScreen: View {
    @StateObject private var model = MapboxSpikeModel()

    var body: some View {
        ZStack(alignment: .top) {
            if model.hasToken {
                MapboxSpikeMapView(model: model)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 8) {
                    Text("No Mapbox token")
                        .font(.title2.bold())
                        .accessibilityIdentifier("mapbox-no-token")
                    Text("Set VELA_MAPBOX_TOKEN in iosApp/Config/Mapbox.xcconfig (docs/ios/MAPBOX-SPIKE.md).")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.line)
                    .font(.caption2.monospaced())
                    .padding(4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityIdentifier("mapbox-spike-debug")
                    .allowsHitTesting(false)
                HStack(spacing: 6) {
                    ForEach(MapboxSpikeCamera.allCases, id: \.rawValue) { camera in
                        Button(camera.rawValue) { model.show(camera) }
                            .accessibilityIdentifier("spike-camera-\(camera.rawValue)")
                    }
                    Button("FPS") { model.runFps() }
                        .accessibilityIdentifier("spike-fps-run")
                }
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }
}

/// The Mapbox map view, built once with the Standard style and the first fixture camera.
struct MapboxSpikeMapView: UIViewRepresentable {
    let model: MapboxSpikeModel

    func makeUIView(context: Context) -> MapboxMaps.MapView {
        MapboxSpikeLaunch.disableTelemetryByDefault()
        let options = MapInitOptions(cameraOptions: MapboxSpikeCamera.twinPeaks15.options, styleURI: .standard)
        let mapView = MapboxMaps.MapView(frame: .zero, mapInitOptions: options)
        model.mapView = mapView
        let map = mapView.mapboxMap!
        map.onStyleLoaded.observe { [weak model, weak mapView] _ in
            model?.styleDidLoad()
            guard let mapView else { return }
            if Self.addTerrain(to: mapView) { model?.terrainDidSet() }
        }.store(in: &model.cancelables)
        map.onMapLoaded.observe { [weak model] _ in model?.mapDidLoad() }.store(in: &model.cancelables)
        map.onMapIdle.observe { [weak model] _ in model?.mapDidIdle() }.store(in: &model.cancelables)
        map.onRenderFrameFinished.observe { [weak model] _ in model?.frameRendered() }.store(in: &model.cancelables)
        map.onMapLoadingError.observe { [weak model] error in
            model?.loadingFailed(error.message)
        }.store(in: &model.cancelables)
        return mapView
    }

    func updateUIView(_ mapView: MapboxMaps.MapView, context: Context) {}

    /// Mapbox's own DEM under the Standard style, at the WebMap's exaggeration. Standard brings
    /// its sky, lighting and 3D buildings; the spike changes none of them.
    private static func addTerrain(to mapView: MapboxMaps.MapView) -> Bool {
        let map = mapView.mapboxMap!
        let sourceId = "mapbox-dem"
        do {
            if !map.sourceExists(withId: sourceId) {
                var dem = RasterDemSource(id: sourceId)
                dem.url = "mapbox://mapbox.mapbox-terrain-dem-v1"
                dem.tileSize = 514
                dem.maxzoom = 14
                try map.addSource(dem)
            }
            var terrain = Terrain(sourceId: sourceId)
            terrain.exaggeration = .constant(MapboxSpikeModel.terrainExaggeration)
            try map.setTerrain(terrain)
            return true
        } catch {
            NSLog("[mapbox-spike] terrain failed: %@", String(describing: error))
            return false
        }
    }
}
#endif
