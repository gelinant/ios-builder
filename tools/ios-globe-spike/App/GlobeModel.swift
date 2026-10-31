// Holds the MLNMapView, the projection switch and the frame counter used by the autopilot.
import MapLibre
import SwiftUI
import UIKit

final class GlobeModel: NSObject, ObservableObject, MLNMapViewDelegate {
    @Published var projection: String
    @Published var readout = "loading"

    private(set) weak var mapView: MLNMapView?
    private var readoutTimer: Timer?
    private var styleRequestedAt: CFTimeInterval = 0
    private var styleLoadedAt: CFTimeInterval = 0
    private var autopilotStarted = false
    private var autopilot: Autopilot?
    private var gestureConfigured = false
    private var watchdogFired = false

    private var measuring = false
    private var frameCount = 0
    private var renderMs = 0.0

    var onStyleLoaded: ((MLNMapView) -> Void)?
    var onFrame: (() -> Void)?

    override init() {
        // A normal launch starts in Mercator so the autopilot can prove the switch; the gesture
        // test starts directly on the globe.
        projection = CommandLine.arguments.contains("--gesture") ? "globe" : "mercator"
        super.init()
    }

    var styleLoadSeconds: Double {
        guard styleLoadedAt > 0, styleRequestedAt > 0 else { return 0 }
        return styleLoadedAt - styleRequestedAt
    }

    func makeMapView() -> MLNMapView {
        let view = MLNMapView(
            frame: .zero,
            styleURL: GlobeStyle.write(projection: projection)
        )
        view.delegate = self
        view.minimumZoomLevel = 0
        view.maximumZoomLevel = 22
        view.maximumPitch = 60
        view.isRotateEnabled = true
        view.isPitchEnabled = true
        view.isZoomEnabled = true
        mapView = view
        startReadoutTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            guard let self, self.styleLoadedAt == 0, !self.watchdogFired else { return }
            self.watchdogFired = true
            SpikeFiles.writeJSON("globe-report.json", [
                "styleLoaded": false,
                "projection": self.projection,
                "error": "style did not load within 90 s",
            ])
            SpikeFiles.write("globe-done")
        }
        return view
    }

    func setProjection(_ value: String) {
        guard value != projection else { return }
        projection = value
        guard let map = mapView else { return }
        styleRequestedAt = CACurrentMediaTime()
        map.styleURL = GlobeStyle.write(projection: value)
    }

    private func startReadoutTimer() {
        readoutTimer?.invalidate()
        readoutTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateReadout()
        }
    }

    private func updateReadout() {
        guard let camera = mapView?.camera else { return }
        readout = String(
            format: "zoom=%.2f bearing=%.1f pitch=%.1f lat=%.2f lon=%.2f",
            mapView?.zoomLevel ?? 0,
            camera.heading,
            camera.pitch,
            camera.centerCoordinate.latitude,
            camera.centerCoordinate.longitude
        )
    }

    func startMeasuring() {
        frameCount = 0
        renderMs = 0
        measuring = true
    }

    func stopMeasuring() -> (frames: Int, renderMs: Double) {
        measuring = false
        return (frameCount, renderMs)
    }

    // MARK: MLNMapViewDelegate

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        styleLoadedAt = CACurrentMediaTime()
        if CommandLine.arguments.contains("--gesture"), !gestureConfigured {
            gestureConfigured = true
            mapView.setCenter(CLLocationCoordinate2D(latitude: 20, longitude: 0), animated: false)
            mapView.setZoomLevel(2, animated: false)
        }
        updateReadout()
        onStyleLoaded?(mapView)
        guard !autopilotStarted, CommandLine.arguments.contains("--autopilot") else { return }
        autopilotStarted = true
        let run = Autopilot(model: self, mapView: mapView)
        autopilot = run
        run.start()
    }

    func mapViewDidFinishRenderingFrame(
        _ mapView: MLNMapView,
        fullyRendered: Bool,
        frameEncodingTime: Double,
        frameRenderingTime: Double
    ) {
        if measuring {
            frameCount += 1
            renderMs += frameRenderingTime
        }
        onFrame?()
    }
}

struct GlobeMapView: UIViewRepresentable {
    @ObservedObject var model: GlobeModel

    func makeUIView(context: Context) -> MLNMapView {
        model.makeMapView()
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}
}
