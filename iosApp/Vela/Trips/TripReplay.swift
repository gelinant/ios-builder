import CoreLocation
import MapLibre
import SwiftUI
import UIKit
import VelaCore

/// A request to open the demo replay, from the trips screen or the launch flag.
struct DemoReplayRequest: Identifiable {
    let tripID: String
    var id: String { tripID }
}

/// The state of a recorded-trace demo replay. It only reads a saved trip and walks the pure Kotlin
/// timeline: it never hands a position to navigation, so there is no voice, no ETA and no Live
/// Activity to mistake for live guidance.
@MainActor
final class TripReplayModel: ObservableObject {
    @Published private(set) var detail: TripDetail?
    @Published private(set) var sample: ReplaySample?
    @Published private(set) var playing = true
    @Published private(set) var playheadMs: Int64 = 0
    @Published private(set) var errorText: String?

    private var replay: DemoReplay?
    private static let speedup = 4.0

    init(store: TripsStore?, tripID: String?) {
        let id = tripID ?? store?.list().first?.id
        guard let id, let store, let detail = store.detail(id: id), !detail.points.isEmpty else {
            errorText = "No recorded trace to replay. Record a drive first."
            return
        }
        self.detail = detail
        let timeline = DemoReplay(points: detail.points, speedup: Self.speedup)
        replay = timeline
        sample = timeline.sampleAt(playheadMs: 0)
    }

    var durationMs: Int64 { replay?.durationMs ?? 0 }

    var speedupText: String { "\(Int(Self.speedup))x" }

    var progressText: String {
        guard durationMs > 0 else { return "0:00 / 0:00" }
        let play = min(playheadMs, durationMs) / 1000
        let total = durationMs / 1000
        return String(format: "%d:%02d / %d:%02d", play / 60, play % 60, total / 60, total % 60)
    }

    func advance(_ deltaMs: Int64) {
        guard let replay else { return }
        guard playing else { return }
        playheadMs += max(0, deltaMs)
        if playheadMs > durationMs + 1_500 { playheadMs = 0 }
        sample = replay.sampleAt(playheadMs: playheadMs)
    }

    func toggle() {
        playing.toggle()
    }

    func restart() {
        playheadMs = 0
        sample = replay?.sampleAt(playheadMs: 0)
        playing = true
    }

    /// Drives the timeline from wall time, the same way a video player does. The UI test reads the
    /// debug line to prove the puck moved.
    func run() async {
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            let now = Date()
            let delta = Int64(now.timeIntervalSince(last) * 1000)
            last = now
            advance(delta)
        }
    }
}

/// The demo replay screen: the trace, a moving puck and a banner that says it is a replay.
struct TripReplayView: View {
    @StateObject private var model: TripReplayModel
    let onClose: () -> Void

    init(tripID: String?, store: TripsStore?, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: TripReplayModel(store: store, tripID: tripID))
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let detail = model.detail {
                TripReplayMap(points: detail.points, sample: model.sample)
                    .ignoresSafeArea()
            } else {
                Color(.systemBackground)
                    .ignoresSafeArea()
            }
            VStack(spacing: 8) {
                banner
                Spacer()
                if model.detail == nil {
                    Text(model.errorText ?? VelaL10n.text("trips_no_recorded_trace_to_replay"))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("demo-replay-empty")
                }
                controls
            }
            .padding()
        }
        .task { await model.run() }
        .interactiveDismissDisabled()
    }

    private var banner: some View {
        VStack(spacing: 3) {
            Text(VelaL10n.text("trips_demo_replay"))
                .font(.headline)
                .accessibilityIdentifier("demo-replay-banner")
            Text(VelaL10n.text("trips_not_live_guidance_no_route_no"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("demo-replay-notice")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    private var controls: some View {
        VStack(spacing: 6) {
            Text("\(model.progressText) · \(model.speedupText)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(model.playing ? VelaL10n.text("replay_pause") : VelaL10n.text("replay_play")) { model.toggle() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("demo-replay-toggle")
                Button(VelaL10n.text("trips_restart")) { model.restart() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("demo-replay-restart")
                Button(VelaL10n.text("place_close")) { onClose() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("demo-replay-close")
            }
            #if DEBUG
            Text("t=\(model.playheadMs) d=\(model.durationMs) fixes=\(model.detail?.points.count ?? 0)")
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("demo-replay-debug")
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// The trace and the replay puck. It loads the same public style as the main map, never asks for
/// the user's location and follows the recorded position, not a live fix.
struct TripReplayMap: UIViewRepresentable {
    let points: [TripPoint]
    let sample: ReplaySample?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapDefaults.styleURL)
        mapView.delegate = context.coordinator
        mapView.logoView.isHidden = true
        mapView.showsUserLocation = false
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.update(points: points, sample: sample, on: mapView)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private var shownPoints = -1
        private var puck: MLNPointAnnotation?

        func update(points: [TripPoint], sample: ReplaySample?, on mapView: MLNMapView) {
            if shownPoints != points.count {
                shownPoints = points.count
                let old = (mapView.annotations ?? []).compactMap { $0 as? MLNPolyline }
                mapView.removeAnnotations(old)
                guard !points.isEmpty else { return }
                var coordinates = points.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                }
                let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                mapView.addAnnotation(line)
                let marker = MLNPointAnnotation()
                marker.coordinate = coordinates.first!
                marker.title = "Replay"
                puck = marker
                mapView.addAnnotation(marker)
            }
            guard let sample, let puck else { return }
            puck.coordinate = CLLocationCoordinate2D(
                latitude: sample.latitude, longitude: sample.longitude)
            mapView.setCenter(puck.coordinate, zoomLevel: 16.5, animated: false)
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { 5 }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            UIColor.systemBlue
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let point = annotation as? MLNPointAnnotation else { return nil }
            let view = MLNAnnotationView(annotation: point, reuseIdentifier: "demo-replay-puck")
            view.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
            view.backgroundColor = .systemOrange
            view.layer.cornerRadius = 11
            view.layer.borderWidth = 3
            view.layer.borderColor = UIColor.white.cgColor
            return view
        }
    }
}
