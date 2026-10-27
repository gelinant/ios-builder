import SceneKit
import SwiftUI
import UIKit
import VelaCore

/// The interactive Street View viewer: a full-screen panorama the user drags and pinches, with a
/// compass, a return-to-north action, zoom controls, walk arrows from the pano's neighbor graph,
/// and Google's attribution (place label, capture date, copyright).
struct StreetViewView: View {
    @StateObject private var model: StreetViewModel
    @StateObject private var tiles: StreetViewTilesModel
    @StateObject private var scene = StreetViewSceneRenderer()

    @State private var yaw = 0.0
    @State private var pitch = 0.0
    @State private var fov = 75.0
    @State private var dragStart: (yaw: Double, pitch: Double)?
    @State private var pinchStart: Double?
    @State private var viewportSize = CGSize(width: 1, height: 1)

    private let onClose: () -> Void

    init(store: StreetViewStore?, request: StreetViewRequest, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: StreetViewModel(store: store, request: request))
        _tiles = StateObject(wrappedValue: StreetViewTilesModel(store: store, fixture: request.fixture))
        self.onClose = onClose
    }

    private var pano: StreetViewPano? { model.pano }
    private var heading: Double { pano?.headingDeg ?? 0 }
    private var aspect: Double {
        max(0.05, Double(viewportSize.width / max(1, viewportSize.height)))
    }
    private var bearing: Double {
        StreetViewTiles.shared.compassForYaw(yawDeg: yaw, panoHeadingDeg: heading)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let viewport = ViewportKey(yaw: yaw, pitch: pitch, fov: fov,
                                       aspect: Double(size.width / max(1, size.height)))
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                PanoSceneView(
                    scene: scene, tiles: tiles, pano: pano,
                    yaw: yaw, pitch: pitch, fov: fov)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(dragGesture(height: size.height, aspect: aspect))
                    .simultaneousGesture(pinchGesture)

                walkArrows(size: size)
                loadingOverlay
                errorOverlay

                topBar
                attribution
                compass(size: size)
                controls
                debugLine
            }
            .onAppear { viewportSize = size }
            .onChange(of: size) { _, new in viewportSize = new }
            .onChange(of: viewport) { _, v in
                tiles.updateView(yawDeg: v.yaw, pitchDeg: v.pitch,
                                 fovXDeg: v.fov, aspect: v.aspect)
            }
            .task(id: model.pano?.panoId) {
                guard let pano = model.pano else { return }
                yaw = StreetViewTiles.shared.yawForCompass(
                    compassDeg: model.facingDeg, panoHeadingDeg: pano.headingDeg)
                pitch = 0
                fov = 75
                tiles.load(pano: pano)
                tiles.updateView(yawDeg: yaw, pitchDeg: pitch, fovXDeg: fov, aspect: aspect)
            }
        }
        .task { model.start() }
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("street-view")
    }

    // MARK: Gestures

    /// Drag the world: a horizontal drag wraps past 360 degrees, a vertical one stops at 85
    /// degrees up or down, and the speed follows the current field of view as on Android.
    private func dragGesture(height: CGFloat, aspect: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil { dragStart = (yaw, pitch) }
                guard let start = dragStart else { return }
                let vFov = verticalFovDeg()
                let perPixel = vFov / Double(max(1, height)) * 1.7
                yaw = Self.normalize(start.yaw - Double(value.translation.width) * perPixel)
                pitch = min(85, max(-85, start.pitch + Double(value.translation.height) * perPixel))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchStart == nil { pinchStart = fov }
                guard let start = pinchStart, scale > 0 else { return }
                fov = min(110, max(30, start / Double(scale)))
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func verticalFovDeg() -> Double {
        let half = (fov / 2) * .pi / 180
        return 2 * atan(tan(half) / aspect) * 180 / .pi
    }

    private func zoom(by factor: Double) {
        fov = min(110, max(30, fov * factor))
    }

    private func faceNorth() {
        yaw = StreetViewTiles.shared.yawForCompass(compassDeg: 0, panoHeadingDeg: heading)
        pitch = 0
    }

    // MARK: Overlays

    private var topBar: some View {
        HStack(alignment: .top) {
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Close Street View")
            .accessibilityIdentifier("street-view-close")
            Spacer()
            if let pano {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pano.addressLabel ?? model.request.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let credit = captureAndCopyright {
                        Text(credit).font(.caption2).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("street-view-place")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 54)
    }

    private var captureAndCopyright: String? {
        guard let pano else { return nil }
        var parts: [String] = []
        if let year = pano.captureYear?.intValue {
            let month = pano.captureMonth?.intValue
            parts.append(Self.monthYear(year: year, month: month) ?? "\(year)")
        }
        if let copyright = pano.copyright, !copyright.isEmpty { parts.append(copyright) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var attribution: some View {
        VStack {
            Spacer()
            HStack {
                Text(attributionLine)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .accessibilityIdentifier("street-view-credit")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 26)
        }
    }

    private var attributionLine: String {
        var parts: [String] = []
        if let label = pano?.addressLabel, !label.isEmpty { parts.append(label) }
        if let date = captureAndCopyright { parts.append(date) }
        if parts.isEmpty { return "© Google" }
        return parts.joined(separator: "  ·  ")
    }

    private func compass(size: CGSize) -> some View {
        let diameter = min(58, size.width * 0.16)
        return VStack {
            ZStack {
                Circle().fill(.black.opacity(0.5))
                Circle().stroke(.white.opacity(0.5), lineWidth: 1)
                Image(systemName: "location.north.fill")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-bearing))
            }
            .frame(width: diameter, height: diameter)
            Text(Self.compassLabel(bearing))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.black.opacity(0.5), in: Capsule())
                .accessibilityIdentifier("street-view-compass")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 76)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Button(action: faceNorth) {
                        Image(systemName: "safari")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Face north")
                    .accessibilityIdentifier("street-view-north")
                    Button { zoom(by: 0.8) } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Zoom in")
                    .accessibilityIdentifier("street-view-zoom-in")
                    Button { zoom(by: 1.25) } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Zoom out")
                    .accessibilityIdentifier("street-view-zoom-out")
                }
            }
            .padding(.trailing, 12)
            .padding(.bottom, 76)
        }
    }

    /// One arrow per neighbor within the visible arc. The arrow's angle is the neighbor's
    /// bearing relative to the current view; tapping it walks to that pano by id.
    @ViewBuilder private func walkArrows(size: CGSize) -> some View {
        if let pano, !model.loading, !pano.neighbors.isEmpty {
            ForEach(Array(pano.neighbors.enumerated()), id: \.element.panoId) { index, link in
                let delta = Self.signedDelta(Double(link.bearingDeg) - bearing)
                if abs(delta) < 55 {
                    let x = size.width / 2 + CGFloat(delta / 55) * size.width * 0.36
                    Button {
                        model.walk(link)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.88), in: Circle())
                            .rotationEffect(.degrees(delta))
                    }
                    .position(x: x, y: size.height * 0.63)
                    .accessibilityLabel("Move down the street")
                    .accessibilityIdentifier("street-view-step-\(index)")
                }
            }
        }
    }

    @ViewBuilder private var loadingOverlay: some View {
        if model.loading || (pano != nil && !tiles.baseLoaded && !model.request.fixture) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("street-view-loading")
        }
    }

    @ViewBuilder private var errorOverlay: some View {
        if let error = model.error, pano == nil {
            VStack(spacing: 10) {
                Image(systemName: "binoculars")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.75))
                Text(error == "no_imagery" ? "No Street View imagery here" : "Street View is unavailable")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Try another place or another day.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("street-view-error")
        }
    }

    @ViewBuilder private var debugLine: some View {
        #if DEBUG
        Text(debugText)
            .font(.caption2.monospaced())
            .foregroundStyle(.white.opacity(0.65))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
            .padding(.leading, 12)
            .padding(.top, 148)
            .allowsHitTesting(false)
            .accessibilityIdentifier("street-view-debug")
        #else
        EmptyView()
        #endif
    }

    #if DEBUG
    private var debugText: String {
        let tileCount = "\(tiles.loadedTileCount)"
        let level = tiles.detailLevel.map { "\($0.zoom)" } ?? "none"
        let error = model.error ?? "none"
        return "pano=\(pano?.panoId ?? "none") loading=\(model.loading ? 1 : 0) error=\(error) " +
            "yaw=\(Int(yaw.rounded())) pitch=\(Int(pitch.rounded())) fov=\(Int(fov.rounded())) " +
            "bearing=\(Int(bearing.rounded())) tiles=\(tileCount) base=\(tiles.baseLoaded ? 1 : 0) " +
            "level=\(level) neighbors=\(pano?.neighbors.count ?? 0) " +
            "fixture=\(model.request.fixture ? 1 : 0)"
    }
    #endif

    private func close() {
        tiles.cancel()
        scene.clear()
        model.close()
        onClose()
    }

    // MARK: Formatting

    private static func normalize(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func signedDelta(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private static func compassLabel(_ bearing: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalize(bearing) + 22.5) / 45) % 8
        return "\(points[index]) \(Int(normalize(bearing).rounded()))°"
    }

    private static func monthYear(year: Int, month: Int?) -> String? {
        guard let month, (1...12).contains(month) else { return nil }
        let names = DateFormatter().monthSymbols ?? []
        guard names.count >= month else { return "\(year)" }
        return "\(names[month - 1]) \(year)"
    }
}

/// The values that should trigger a new detail-tile selection, rounded so a frame-by-frame drag
/// does not recompute the grid. The actual fetch waits for a short debounce too.
private struct ViewportKey: Equatable {
    let yaw: Double
    let pitch: Double
    let fov: Double
    let aspect: Double

    init(yaw: Double, pitch: Double, fov: Double, aspect: Double) {
        self.yaw = (yaw / 2).rounded() * 2
        self.pitch = (pitch / 2).rounded() * 2
        self.fov = (fov * 2).rounded() / 2
        self.aspect = (aspect * 50).rounded() / 50
    }
}

/// The SceneKit view. Textures and camera are pushed from SwiftUI state; node rebuilding is
/// skipped when the visible tile set is unchanged.
private struct PanoSceneView: UIViewRepresentable {
    let scene: StreetViewSceneRenderer
    @ObservedObject var tiles: StreetViewTilesModel
    let pano: StreetViewPano?
    let yaw: Double
    let pitch: Double
    let fov: Double

    func makeUIView(context: Context) -> SCNView { scene.view }

    func updateUIView(_ view: SCNView, context: Context) {
        if let pano { scene.setPano(pano) }
        scene.setBase(tiles.base)
        scene.setDetail(tiles.tiles, level: tiles.detailLevel)
        scene.updateCamera(yawDeg: yaw, pitchDeg: pitch, fovDeg: fov)
    }
}
