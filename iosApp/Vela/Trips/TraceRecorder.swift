import CoreLocation
import Foundation
import SwiftUI
import VelaCore

/// Records a full drive trace from the map, with no destination and no guidance.
///
/// It writes the same `TripLog` CSV the guided recorder writes, through the same `TripsStore`, so
/// a drive recorded here survives a relaunch, appears in Trips, opens on the detail map and can be
/// replayed. It owns its own `CLLocationManager`: guided navigation keeps its own pipeline, and the
/// map entry is hidden while a drive is being guided.
final class TraceRecorder: NSObject, ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var fixes = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var savedSummary: TripSummary?
    @Published var errorMessage: String?
    @Published private(set) var notice: String?

    private let store: TripsStore?
    private let manager = CLLocationManager()
    private var pendingStart = false

    init(store: TripsStore?) {
        self.store = store
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 2
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    var elapsedSeconds: Int {
        guard let startedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    var elapsedText: String {
        let seconds = elapsedSeconds
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Starts a new trace, asking for location once if the app has never had it.
    func start() {
        guard !active else { return }
        errorMessage = nil
        notice = nil
        savedSummary = nil
        switch manager.authorizationStatus {
        case .denied, .restricted:
            errorMessage = "Location is off. Allow it for Vela in Settings to record a drive."
        case .notDetermined:
            pendingStart = true
            manager.requestWhenInUseAuthorization()
        default:
            begin()
        }
    }

    /// Stops the receiver and closes the file. A drive under five fixes is discarded by the store.
    func stop() {
        guard active else { return }
        manager.stopUpdatingLocation()
        active = false
        startedAt = nil
        fixes = 0
        let summary = store?.finishTrip()
        savedSummary = summary
        if summary == nil {
            notice = "This drive was too short to keep (under five fixes)."
        }
    }

    /// Throws the trace away without listing it.
    func discard() {
        manager.stopUpdatingLocation()
        active = false
        startedAt = nil
        fixes = 0
        store?.discard()
        notice = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func clearNotice() {
        notice = nil
    }

    private func begin() {
        guard let store else {
            errorMessage = "Trip recording is not available in this build."
            return
        }
        guard !store.isRecording else {
            errorMessage = "A drive is already being recorded."
            return
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard store.startTrip(label: "Recorded drive", dest: nil, startedAt: now) != nil else {
            errorMessage = "The trace file could not be created."
            return
        }
        startedAt = Date()
        fixes = 0
        active = true
        manager.startUpdatingLocation()
    }
}

extension TraceRecorder: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingStart else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            pendingStart = false
            begin()
        case .denied, .restricted:
            pendingStart = false
            errorMessage = "Location is off. Allow it for Vela in Settings to record a drive."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active, let store, let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }
        let speed = location.speed.isFinite && location.speed > 0 ? location.speed : 0
        let course = location.course.isFinite && location.course >= 0 ? location.course : 0
        store.recordFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            t: Int64(location.timestamp.timeIntervalSince1970 * 1000),
            bearingDeg: course,
            speedMps: speed,
            offRoute: false,
            accuracyM: location.horizontalAccuracy,
            provider: "ios-trace",
            offRouteHits: 0)
        fixes += 1
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard active else { return }
        errorMessage = "No location fix. Move where the sky is visible and try again."
    }
}

/// The map's recording card. It states the fix count and elapsed time, the two facts that tell a
/// user the trace is being written; stopping it opens the trips list to show the saved drive.
struct TraceRecordingCard: View {
    @ObservedObject var model: TraceRecorder
    let onStop: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording drive")
                        .font(.subheadline.weight(.semibold))
                    Text("\(model.elapsedText) · \(model.fixes) fixes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("trace-recording-count")
                }
                Spacer()
                Button("Discard") { onDiscard() }
                    .font(.caption)
                    .accessibilityIdentifier("trace-record-discard")
                Button("Stop") { onStop() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("trace-record-stop")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trace-recording")
    }
}
