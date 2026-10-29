import Foundation
import MapLibre
import SwiftUI
import UIKit
import VelaCore

/// A-1: aircraft around the current view from adsb.lol (ODbL 1.0). Positions, headings, altitudes
/// and callsigns only, capped at 300 nearest the view center, with a 10 s cache and a visible
/// quota state. A tap on an aircraft, or on its row in the sheet, opens a small card. Nothing is
/// predicted between polls and no route is guessed.
///
/// The layer owns its file only: WLD-1's host calls `refresh` and `apply`, and both produce data
/// before `installed` is true.
final class AviationLayer: NSObject, WorldLayer, UIGestureRecognizerDelegate {
    static let installed = true

    /// The style layer this class draws. MAP-TAP reads it for its audit.
    static let mapLayerIdentifiers = ["vela-aircraft"]

    let id = "aviation"
    let title = VelaL10n.text("world_layer_aircraft")
    let source = "adsb.lol, ODbL 1.0"
    var isInstalled: Bool { Self.installed }
    private(set) var rows: [WorldLayerRow] = []

    private let store: AviationStore
    private var lastAnswer: AviationFetch?
    private weak var style: MLNStyle?
    private weak var mapView: MLNMapView?
    private var tap: UITapGestureRecognizer?
    private var focusObserver: NSObjectProtocol?
    private var offline = false
    private var cardOpen = false
    private var fixture = false

    override init() {
        store = AviationStore(http: IosGraph.shared.core?.http)
        super.init()
        #if DEBUG
        fixture = AviationTestSupport.enabled
        #endif
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
        let answer: AviationFetch
        if let captured = fixtureAnswer(viewport: viewport, now: now) {
            answer = captured
        } else {
            do {
                answer = try await store.fetch(
                    south: viewport.south, west: viewport.west,
                    north: viewport.north, east: viewport.east, nowMs: now)
            } catch {
                return nil
            }
        }
        lastAnswer = answer
        rows = Self.makeRows(answer)
        await MainActor.run { self.draw() }
        return WorldLayerRefresh(updatedAtMs: answer.updatedAtMs, rows: rows)
    }

    func apply(style: MLNStyle, offline: Bool) {
        self.style = style
        self.offline = offline
        attachTapIfNeeded()
        if offline {
            drawAircraft([], in: style)
            return
        }
        Self.installImage(in: style)
        draw()
    }

    /// Draws the answer at this instant. A late answer carries no aircraft, so a stale position is
    /// never left on the map with a live look; the sheet reads "late" from the host timestamp.
    private func draw() {
        guard let style else { return }
        guard !offline else {
            drawAircraft([], in: style)
            return
        }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let answer = store.snapshot(nowMs: now)
        if answer.phase != AviationPhases.shared.FRESH {
            lastAnswer = answer
        }
        drawAircraft(answer.aircraft, in: style)
    }

    private func drawAircraft(_ aircraft: [AviationAircraft], in style: MLNStyle) {
        let sourceId = "vela-aircraft-src"
        if style.source(withIdentifier: sourceId) == nil {
            style.addSource(MLNShapeSource(identifier: sourceId, shape: nil, options: nil))
        }
        let features = aircraft.map { plane -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: plane.lat, longitude: plane.lng)
            feature.attributes = [
                "hex": plane.hex,
                "callsign": plane.identification,
                "heading": NSNumber(value: plane.headingDeg < 0 ? 0 : plane.headingDeg),
            ]
            return feature
        }
        (style.source(withIdentifier: sourceId) as? MLNShapeSource)?.shape =
            features.isEmpty ? nil : MLNShapeCollectionFeature(shapes: features)

        let layerId = "vela-aircraft"
        if style.layer(withIdentifier: layerId) == nil,
           let source = style.source(withIdentifier: sourceId) {
            let layer = MLNSymbolStyleLayer(identifier: layerId, source: source)
            layer.iconImageName = NSExpression(forConstantValue: "vela-aircraft-icon")
            layer.iconRotation = NSExpression(forKeyPath: "heading")
            layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            layer.iconScale = NSExpression(forConstantValue: 0.85)
            layer.text = NSExpression(forKeyPath: "callsign")
            layer.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            layer.textFontSize = NSExpression(forConstantValue: 10)
            layer.textColor = NSExpression(forConstantValue: UIColor(rgb: 0x0B2E59))
            layer.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            layer.textHaloWidth = NSExpression(forConstantValue: 1.4)
            layer.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.1)))
            layer.textAllowsOverlap = NSExpression(forConstantValue: true)
            layer.textIgnoresPlacement = NSExpression(forConstantValue: true)
            if let anchor = MapLayers.labelAnchor(in: style) {
                style.insertLayer(layer, below: anchor)
            } else {
                style.addLayer(layer)
            }
        }
        style.layer(withIdentifier: layerId)?.isVisible = !aircraft.isEmpty
    }

    /// A small card with the identification and altitude. Reached by tapping a drawn aircraft or
    /// its row in the World layers sheet; no route or airport is inferred.
    private func present(_ plane: AviationAircraft) {
        guard !cardOpen else { return }
        guard let top = Self.topController() else { return }
        let debug = debugLine(count: lastAnswer?.aircraft.count ?? 0)
        let card = AviationDetailCard(plane: plane, debug: debug)
        let host = AviationCardHost(rootView: card)
        host.modalPresentationStyle = .overFullScreen
        host.view.backgroundColor = .clear
        host.onDisappear = { [weak self] in self?.cardOpen = false }
        cardOpen = true
        top.present(host, animated: false)
    }

    /// Debug builds only: the captured answer instead of a request. Production returns nil.
    private func fixtureAnswer(viewport: MapViewport, now: Int64) -> AviationFetch? {
        #if DEBUG
        if fixture, let json = AviationTestSupport.fixtureJSON {
            return store.parseFixture(
                json: json, south: viewport.south, west: viewport.west,
                north: viewport.north, east: viewport.east, nowMs: now)
        }
        #endif
        return nil
    }

    private func debugLine(count: Int) -> String {
        let source = fixture ? "fixture" : "adsb.lol"
        let live = !fixture && (lastAnswer?.live == true) ? 1 : 0
        return "aviation_source=\(source) aviation_live=\(live) aviation_count=\(count)"
    }

    /// The sheet row carries the aircraft coordinate. Match it exactly: a row from another layer
    /// never opens an aircraft card.
    private func rowFocused(_ note: Notification) {
        guard let lat = note.userInfo?[WorldLayers.latitudeKey] as? Double,
              let lng = note.userInfo?[WorldLayers.longitudeKey] as? Double,
              let plane = lastAnswer?.aircraft.first(where: {
                  abs($0.lat - lat) < 1e-7 && abs($0.lng - lng) < 1e-7
              }) else { return }
        present(plane)
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
        let hits = map.visibleFeatures(at: point, styleLayerIdentifiers: ["vela-aircraft"])
        guard let feature = hits.first as? MLNPointFeature,
              let hex = feature.attributes["hex"] as? String,
              let plane = lastAnswer?.aircraft.first(where: { $0.hex == hex }) else { return }
        present(plane)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private static func makeRows(_ answer: AviationFetch) -> [WorldLayerRow] {
        var rows = answer.aircraft.map { plane -> WorldLayerRow in
            WorldLayerRow(
                id: "aircraft-\(plane.hex)",
                title: plane.identification,
                detail: detailLine(plane),
                lat: plane.lat,
                lng: plane.lng)
        }
        if answer.phase != AviationPhases.shared.FRESH {
            rows.insert(WorldLayerRow(
                id: "aviation-status",
                title: answer.detail,
                detail: "adsb.lol, ODbL 1.0"), at: 0)
        }
        return rows
    }

    private static func detailLine(_ plane: AviationAircraft) -> String {
        var parts: [String] = []
        if plane.onGround {
            parts.append("On ground")
        } else if plane.altitudeFt >= 0 {
            parts.append("\(plane.altitudeFt) ft")
        } else {
            parts.append("Altitude unknown")
        }
        if plane.headingDeg >= 0 {
            parts.append("\(Int(plane.headingDeg.rounded())) deg")
        }
        if plane.groundSpeedKt >= 0 {
            parts.append("\(Int(plane.groundSpeedKt.rounded())) kt")
        }
        parts.append("adsb.lol")
        return parts.joined(separator: ", ")
    }

    private static func installImage(in style: MLNStyle) {
        guard style.image(forName: "vela-aircraft-icon") == nil else { return }
        let side: CGFloat = 26
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.cgContext.setFillColor(UIColor(rgb: 0x1A73E8).cgColor)
            context.cgContext.fillEllipse(in: circle)
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(1.4)
            context.cgContext.strokeEllipse(in: circle)
            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            if let plane = UIImage(systemName: "airplane", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                plane.draw(in: CGRect(x: (side - plane.size.width) / 2,
                                      y: (side - plane.size.height) / 2,
                                      width: plane.size.width, height: plane.size.height))
            }
        }
        style.setImage(image, forName: "vela-aircraft-icon")
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
private final class AviationCardHost: UIHostingController<AviationDetailCard> {
    var onDisappear: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDisappear?()
    }
}

/// The small aircraft card: identification, altitude, heading, speed and the source line. No
/// route, origin or destination is shown because adsb.lol does not provide one.
private struct AviationDetailCard: View {
    let plane: AviationAircraft
    let debug: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(plane.identification)
                        .font(.headline)
                        .accessibilityIdentifier("aviation-detail-ident")
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("aviation-detail-close")
                }
                Text(altitude)
                    .font(.subheadline)
                    .accessibilityIdentifier("aviation-detail-altitude")
                if plane.headingDeg >= 0 || plane.groundSpeedKt >= 0 {
                    Text(motion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("aviation-detail-motion")
                }
                Text(VelaL10n.text("map_data_from_adsb_lol_odbl_1"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                #if DEBUG
                Text(debug)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("aviation-detail-debug")
                #endif
            }
            .padding(16)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 12)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("aviation-detail-card")
    }

    private var altitude: String {
        if plane.onGround { return "On ground" }
        if plane.altitudeFt < 0 { return "Altitude unknown" }
        return "\(plane.altitudeFt) ft"
    }

    private var motion: String {
        var parts: [String] = []
        if plane.headingDeg >= 0 {
            parts.append("Heading \(Int(plane.headingDeg.rounded())) deg")
        }
        if plane.groundSpeedKt >= 0 {
            parts.append("\(Int(plane.groundSpeedKt.rounded())) kt")
        }
        return parts.joined(separator: ", ")
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

#if DEBUG
/// Debug-only fixture switch: `-VelaAviationFixture YES` reads the captured adsb.lol answer that
/// ships in `Resources/world/aviation-fixture.json`. No fixture coordinate is used in production.
enum AviationTestSupport {
    static let enabled: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaAviationFixture"),
              index + 1 < arguments.count else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }()

    static let fixtureJSON: String? = {
        guard enabled else { return nil }
        let url = Bundle.main.url(forResource: "aviation-fixture", withExtension: "json",
                                  subdirectory: "world")
            ?? Bundle.main.url(forResource: "aviation-fixture", withExtension: "json")
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
}
#endif
