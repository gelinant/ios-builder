import CoreLocation
import Foundation
import MapLibre
import SwiftUI
import UIKit
import VelaCore

/// G-3: satellites on the world layer from CelesTrak GP (Dr T.S. Kelso), propagated locally with
/// SGP4. The layer draws the satellites above the horizon of the view as labelled dots, the ground
/// track of the selected satellite, and a card with its altitude, its velocity and its next pass
/// over the observer.
///
/// The layer owns this file only: `WorldLayers.swift` and `WorldLayerSection.swift` keep calling
/// `refresh` and `apply`. The same drawing works in Mercator and on the G-2 globe because the
/// geometry is a latitude and a longitude, never a screen position.
final class SatelliteLayer: NSObject, WorldLayer, UIGestureRecognizerDelegate {
    static let installed = true

    /// The style layer this class draws, and the one its own tap recognizer queries.
    static let mapLayerIdentifiers = ["vela-satellite-dots"]

    /// The fixed instant of the debug fixture: 2026-10-29T00:33:00Z. At that instant sixteen of the
    /// fixture element sets are above the horizon of (0, 0), ten of them GPS, and HST's next pass
    /// starts 97 minutes later with a 48-degree maximum. Never used outside a DEBUG launch argument.
    static let fixtureAtMs: Int64 = 1_793_233_980_000

    let id = "satellite"
    let title = VelaL10n.text("world_layer_satellites")
    let source = "CelesTrak GP, Dr T.S. Kelso"
    var isInstalled: Bool { Self.installed }
    private(set) var rows: [WorldLayerRow] = []

    /// Built on first use: the HTTP client is the app's URLSession seam, and the TLE cache lives
    /// in the same `app.vela.ios.` key-value suite as the other layer switches, which iOS persists
    /// on disk.
    private lazy var store = SatelliteStore(
        http: URLSessionVelaHttp(),
        stores: UserDefaultsKeyValueStores(prefix: "app.vela.ios."))
    private var snapshot: SatelliteSnapshot?
    private weak var style: MLNStyle?
    private weak var mapView: MLNMapView?
    private var tap: UITapGestureRecognizer?
    private var focusObserver: NSObjectProtocol?
    private var offline = false
    private var cardOpen = false
    private var selectedCatalog: Int32?
    private let fixture: Bool

    override init() {
        #if DEBUG
        fixture = SatelliteTestSupport.enabled
        #else
        fixture = false
        #endif
        super.init()
        focusObserver = NotificationCenter.default.addObserver(
            forName: WorldLayers.focusNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.rowFocused(note)
        }
    }

    deinit {
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
        }
        if let tap, let mapView {
            mapView.removeGestureRecognizer(tap)
        }
    }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? {
        guard !offline else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let liveObserver = Self.observerCoordinate() ?? CLLocationCoordinate2D(
            latitude: (viewport.south + viewport.north) / 2,
            longitude: (viewport.west + viewport.east) / 2)
        // The fixture keeps its observer at (0, 0): the visible sky and the next pass then do not
        // depend on where the scenario dragged the camera. Production always uses the user's fix
        // or the view center.
        let observer = fixture
            ? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            : liveObserver
        let answer: SatelliteSnapshot?
        if fixture {
            #if DEBUG
            answer = store.parseFixture(
                text: SatelliteTestSupport.fixtureText,
                atMs: Self.fixtureAtMs,
                stampMs: now,
                observerLatDeg: observer.latitude,
                observerLonDeg: observer.longitude,
                south: viewport.south,
                west: viewport.west,
                north: viewport.north,
                east: viewport.east,
                zoom: viewport.zoom)
            #else
            answer = nil
            #endif
        } else {
            answer = try? await store.refresh(
                nowMs: now,
                observerLatDeg: observer.latitude,
                observerLonDeg: observer.longitude,
                south: viewport.south,
                west: viewport.west,
                north: viewport.north,
                east: viewport.east,
                zoom: viewport.zoom)
        }
        guard let answer else { return nil }
        snapshot = answer
        rows = answer.rows.map { row in
            WorldLayerRow(
                id: row.id, title: row.title, detail: row.detail,
                lat: row.lat?.doubleValue, lng: row.lng?.doubleValue)
        }
        await MainActor.run { self.drawAgain() }
        return WorldLayerRefresh(updatedAtMs: answer.updatedAtMs, rows: rows)
    }

    func apply(style: MLNStyle, offline: Bool) {
        self.style = style
        self.offline = offline
        attachTapIfNeeded()
        if offline {
            clear(style)
            return
        }
        Self.installImage(in: style)
        draw()
    }

    /// The instant the visible positions belong to: the fixture's fixed instant, or now.
    private var propagationMs: Int64 {
        if let fixed = snapshot?.fixedAtMs, fixed > 0 { return fixed }
        return Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private var observerLat: Double { snapshot?.observerLatDeg ?? 0 }
    private var observerLng: Double { snapshot?.observerLonDeg ?? 0 }

    private func drawAgain() {
        guard let style else { return }
        let offline = self.offline
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.apply(style: style, offline: offline)
        }
    }

    private func draw() {
        guard let style else { return }
        let satellites = snapshot?.satellites ?? []
        let sourceId = Self.sourceId
        let features = satellites.map { satellite -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(
                latitude: satellite.latDeg, longitude: satellite.lonDeg)
            feature.attributes = [
                "catalog": NSNumber(value: satellite.catalogNumber),
                "name": satellite.name,
                "label": Self.label(satellite),
            ]
            return feature
        }
        if let source = style.source(withIdentifier: sourceId) as? MLNShapeSource {
            source.shape = features.isEmpty ? nil : MLNShapeCollectionFeature(shapes: features)
        } else {
            style.addSource(MLNShapeSource(
                identifier: sourceId,
                shape: features.isEmpty ? nil : MLNShapeCollectionFeature(shapes: features),
                options: nil))
        }
        if let source = style.source(withIdentifier: sourceId),
           style.layer(withIdentifier: Self.layerId) == nil {
            let layer = MLNSymbolStyleLayer(identifier: Self.layerId, source: source)
            layer.iconImageName = NSExpression(forConstantValue: "vela-satellite-icon")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            layer.iconScale = NSExpression(forConstantValue: 0.9)
            layer.text = NSExpression(forKeyPath: "label")
            layer.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            layer.textFontSize = NSExpression(forConstantValue: 10)
            layer.textColor = NSExpression(forConstantValue: SatellitePalette.label)
            layer.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            layer.textHaloWidth = NSExpression(forConstantValue: 1.4)
            layer.textOffset = NSExpression(forConstantValue: NSValue(
                cgVector: CGVector(dx: 0, dy: 1.2)))
            layer.textAllowsOverlap = NSExpression(forConstantValue: true)
            layer.textIgnoresPlacement = NSExpression(forConstantValue: true)
            if let anchor = MapLayers.labelAnchor(in: style) {
                style.insertLayer(layer, below: anchor)
            } else {
                style.addLayer(layer)
            }
        }
        style.layer(withIdentifier: Self.layerId)?.isVisible = !satellites.isEmpty
        drawOrbit(in: style)
    }

    /// The selected satellite's ground track and marker. Rebuilt on every style pass, so a
    /// projection switch and a refresh keep it; removed with the layer while offline.
    private func drawOrbit(in style: MLNStyle) {
        let selected = selectedCatalog.flatMap { catalog in
            snapshot?.satellites.first { $0.catalogNumber == catalog }
        }
        guard let selected else {
            SatelliteOrbitLayer.remove(from: style)
            return
        }
        let track = store.orbitTrack(
            catalogNumber: selected.catalogNumber,
            fromMs: propagationMs,
            minutes: 100,
            stepSeconds: 60)
        SatelliteOrbitLayer.draw(
            track: track,
            selectedLat: selected.latDeg,
            selectedLng: selected.lonDeg,
            in: style)
    }

    /// The name, altitude and velocity shown by the symbol's label and by the card, built once.
    static func values(_ satellite: SatelliteSky) -> [LayerInfoValue] {
        let contract = LayerInfoCatalog.contract(.satellite)
        return [
            contract.value("name", satellite.name),
            contract.value("altitude", "\(Int64(satellite.altitudeKm.rounded()))"),
            contract.value("velocity", String(format: "%.2f", satellite.speedKmS)),
        ]
    }

    static func label(_ satellite: SatelliteSky) -> String {
        LayerInfoCatalog.contract(.satellite).mapLabel(values(satellite))
    }

    private func clear(_ style: MLNStyle) {
        SatelliteOrbitLayer.remove(from: style)
        if let layer = style.layer(withIdentifier: Self.layerId) { style.removeLayer(layer) }
        if let source = style.source(withIdentifier: Self.sourceId) { style.removeSource(source) }
    }

    // MARK: - Selection and card

    private func select(_ catalogNumber: Int32) {
        selectedCatalog = catalogNumber
        if let style { draw() }
        guard let satellite = snapshot?.satellites.first(where: {
            $0.catalogNumber == catalogNumber
        }) else { return }
        present(satellite)
    }

    private func present(_ satellite: SatelliteSky) {
        guard !cardOpen else { return }
        guard let top = Self.topController() else { return }
        let pass = store.nextPass(
            catalogNumber: satellite.catalogNumber,
            observerLatDeg: observerLat,
            observerLonDeg: observerLng,
            fromMs: propagationMs)
        let debug = debugLine(satellite, pass: pass)
        let card = SatelliteDetailCard(
            satellite: satellite,
            pass: pass,
            referenceMs: propagationMs,
            debug: debug,
            sourceLine: sourceLine)
        let host = SatelliteCardHost(rootView: card)
        host.modalPresentationStyle = .overFullScreen
        host.view.backgroundColor = .clear
        host.onDisappear = { [weak self] in self?.cardOpen = false }
        cardOpen = true
        top.present(host, animated: false)
    }

    private var sourceLine: String {
        if fixture { return VelaL10n.text("map_satellite_source_fixture") }
        let live = snapshot?.live == true
        return live
            ? VelaL10n.text("map_satellite_source_live")
            : VelaL10n.text("map_satellite_source_cached")
    }

    private func debugLine(_ satellite: SatelliteSky, pass: SatellitePass?) -> String {
        let nextMinutes: Int
        if let pass {
            nextMinutes = Int(((Double(pass.startMs - propagationMs) / 60_000.0)).rounded())
        } else {
            nextMinutes = -1
        }
        let source = fixture ? "fixture" : (snapshot?.live == true ? "celestrak" : "cache")
        let ageHours = Double(propagationMs - satellite.tleEpochMs) / 3_600_000.0
        let gpsCount = snapshot?.satellites.filter { $0.name.hasPrefix("GPS ") }.count ?? 0
        return "sat_count=\(snapshot?.satellites.count ?? 0)"
            + " sat_groups=\(SatelliteStore.companion.groupCount())"
            + " sat_gps=\(gpsCount)"
            + " sat_projection=\(MapGlobeSettings.projection.rawValue)"
            + " sat_next_pass_min=\(nextMinutes)"
            + " sat_source=\(source)"
            + " sat_alt_km=\(Int(satellite.altitudeKm.rounded()))"
            + " sat_speed_km_s=\(String(format: "%.2f", satellite.speedKmS))"
            + " sat_tle_age_h=\(String(format: "%.1f", ageHours))"
    }

    /// The sheet row carries the satellite coordinate. Match it exactly: a row from another layer
    /// never opens a satellite card.
    private func rowFocused(_ note: Notification) {
        guard let lat = note.userInfo?[WorldLayers.latitudeKey] as? Double,
              let lng = note.userInfo?[WorldLayers.longitudeKey] as? Double,
              let satellite = snapshot?.satellites.first(where: {
                  abs($0.latDeg - lat) < 1e-7 && abs($0.lonDeg - lng) < 1e-7
              }) else { return }
        selectedCatalog = satellite.catalogNumber
        if let style { draw() }
        present(satellite)
    }

    private func attachTapIfNeeded() {
        guard tap == nil else { return }
        guard let map = Self.mapInKeyWindow() else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        map.addGestureRecognizer(recognizer)
        tap = recognizer
        mapView = map
    }

    @objc private func mapTapped(_ recognizer: UITapGestureRecognizer) {
        guard let map = recognizer.view as? MLNMapView, map.style != nil else { return }
        let point = recognizer.location(in: map)
        let hits = map.visibleFeatures(at: point, styleLayerIdentifiers: [Self.layerId])
        guard let feature = hits.first as? MLNPointFeature,
              let catalog = (feature.attributes["catalog"] as? NSNumber)?.int32Value else { return }
        select(catalog)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // MARK: - Helpers

    private static let sourceId = "vela-satellites"
    private static let layerId = "vela-satellite-dots"

    private static func installImage(in style: MLNStyle) {
        guard style.image(forName: "vela-satellite-icon") == nil else { return }
        let side: CGFloat = 26
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.cgContext.setFillColor(SatellitePalette.dot.cgColor)
            context.cgContext.fillEllipse(in: circle)
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(1.4)
            context.cgContext.strokeEllipse(in: circle)
            let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let satellite = UIImage(systemName: "satellite", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                satellite.draw(in: CGRect(
                    x: (side - satellite.size.width) / 2,
                    y: (side - satellite.size.height) / 2,
                    width: satellite.size.width,
                    height: satellite.size.height))
            }
        }
        style.setImage(image, forName: "vela-satellite-icon")
    }

    /// The user's fix when the map has one, null otherwise. The pass is then computed from the view
    /// center and the card says so.
    private static func observerCoordinate() -> CLLocationCoordinate2D? {
        guard let map = mapInKeyWindow(),
              let coordinate = map.userLocation?.location?.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return coordinate
    }

    private static func mapInKeyWindow() -> MLNMapView? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first
        guard let window else { return nil }
        return findMap(in: window)
    }

    private static func findMap(in view: UIView) -> MLNMapView? {
        if let map = view as? MLNMapView { return map }
        for sub in view.subviews {
            if let found = findMap(in: sub) { return found }
        }
        return nil
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Presentation host that clears the "card is open" flag when the card is dismissed.
private final class SatelliteCardHost: UIHostingController<SatelliteDetailCard> {
    var onDisappear: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDisappear?()
    }
}

/// The satellite card: identification, altitude, velocity, the next pass over the observer and the
/// element set's age. Nothing is predicted outside the element set: the position is SGP4's.
private struct SatelliteDetailCard: View {
    let satellite: SatelliteSky
    let pass: SatellitePass?
    let referenceMs: Int64
    let debug: String
    let sourceLine: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(satellite.name)
                        .font(.headline)
                        .accessibilityIdentifier("satellite-detail-name")
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("satellite-detail-close")
                }
                Text(altitudeLine)
                    .font(.subheadline)
                    .accessibilityIdentifier("satellite-detail-altitude")
                Text(velocityLine)
                    .font(.subheadline)
                    .accessibilityIdentifier("satellite-detail-velocity")
                Text(skyLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(passLine)
                    .font(.subheadline)
                    .accessibilityIdentifier("satellite-detail-pass")
                if let pass {
                    Text(passTimes(pass))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(sourceLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                #if DEBUG
                Text(debug)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("satellite-debug")
                #endif
            }
            .padding(16)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 12)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("satellite-detail-card")
    }

    private var lines: [(id: String, text: String)] {
        LayerInfoCatalog.contract(.satellite)
            .infoLines(SatelliteLayer.values(satellite))
    }

    private var altitudeLine: String {
        lines.first(where: { $0.id == "altitude" })?.text ?? ""
    }

    private var velocityLine: String {
        lines.first(where: { $0.id == "velocity" })?.text ?? ""
    }

    private var skyLine: String {
        VelaL10n.text(
            "map_satellite_sky",
            Int64(satellite.elevationDeg.rounded()),
            Int64(satellite.azimuthDeg.rounded()))
    }

    private var passLine: String {
        guard let pass else { return VelaL10n.text("map_satellite_pass_none") }
        let minutes = Int((Double(pass.startMs - referenceMs) / 60_000.0).rounded())
        return VelaL10n.text(
            "map_satellite_pass_next",
            Int64(minutes),
            Int64(pass.maxElevationDeg.rounded()))
    }

    private func passTimes(_ pass: SatellitePass) -> String {
        let start = Date(timeIntervalSince1970: Double(pass.startMs) / 1_000)
        let end = Date(timeIntervalSince1970: Double(pass.endMs) / 1_000)
        return VelaL10n.text(
            "map_satellite_pass_times",
            start.formatted(date: .abbreviated, time: .shortened),
            end.formatted(date: .omitted, time: .shortened))
    }
}

/// The layer's two colours, kept out of the shared `UIColor` extensions.
private enum SatellitePalette {
    static let dot = UIColor(red: 0.96, green: 0.62, blue: 0.06, alpha: 1)
    static let label = UIColor(red: 0.42, green: 0.25, blue: 0.0, alpha: 1)
}

#if DEBUG
/// Debug-only fixture switch: `-VelaSatelliteFixture YES` reads the near-Earth element sets in
/// `Resources/world/satellite-fixture.txt` and propagates them at a fixed instant. The file holds
/// a CelesTrak snapshot; no fixture coordinate is used in production.
enum SatelliteTestSupport {
    static let enabled: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaSatelliteFixture"),
              index + 1 < arguments.count else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }()

    static let fixtureText: String = {
        let url = Bundle.main.url(forResource: "satellite-fixture", withExtension: "txt",
                                  subdirectory: "world")
            ?? Bundle.main.url(forResource: "satellite-fixture", withExtension: "txt")
        guard let url else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()
}
#endif
