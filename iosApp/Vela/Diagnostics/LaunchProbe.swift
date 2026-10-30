import Darwin
import Foundation
import MapLibre
import SwiftUI
import UIKit

/// PERF-1: one read-only line that a UI test can parse, built from the measurements TRIP-DIAG
/// already records plus the process footprint. It exists only when the launch argument
/// `-VelaLaunchProbe YES` is present (docs/ios/QUALITY.md): no timer, no view and no sample
/// otherwise, and nothing is written to disk or sent anywhere.
///
/// The values are milliseconds since the kernel's process start record, so they include dyld and
/// the pre-main work, as the diagnostics screen already does. `cold_peak_mb` is the largest
/// `phys_footprint` seen between the first view and eight seconds, which covers the first frame,
/// the first style load and the first fix.
final class LaunchProbe: ObservableObject {
    static let shared = LaunchProbe()
    static let argument = "-VelaLaunchProbe"
    static let identifier = "launch-probe"
    /// How long the footprint is sampled. Long enough for the first fix and the style, short
    /// enough that the test's three launches stay quick.
    static let sampleSeconds: TimeInterval = 8

    /// The line the accessibility element carries. Starts as `cold_complete=0` so the test can
    /// tell a partial reading from a finished one.
    @Published private(set) var text = "cold_complete=0"
    /// True once the probe was asked for. `VelaApp` mounts the badge only then.
    private(set) var isActive = false

    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var peakBytes: UInt64 = 0
    private var startedAt: CFTimeInterval = 0
    private var mapMarked = false

    private init() {}

    /// Starts the sampling. Safe to call more than once.
    func startIfRequested() {
        guard !isActive, LaunchOptions.current.launchProbe else { return }
        isActive = true
        startedAt = CACurrentMediaTime()
        sample()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // A mark can land after the footprint window, a slow first fix above all. Keep the line
        // current without keeping the sampler alive.
        observer = NotificationCenter.default.addObserver(
            forName: DiagnosticsMeasurements.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.text = self.line(peakBytes: self.peakBytes, complete: self.timer == nil)
        }
    }

    private func sample() {
        let footprint = LaunchProbeHardware.memoryFootprint()
        peakBytes = max(peakBytes, footprint)
        markMapInteractiveIfReady()
        let elapsed = CACurrentMediaTime() - startedAt
        let complete = elapsed >= Self.sampleSeconds
        if complete {
            timer?.invalidate()
            timer = nil
        }
        text = line(peakBytes: peakBytes, complete: complete)
    }

    /// The map accepts a tap once MapLibre has a style (a tap can then select a feature) and the
    /// view carries its recognizers. Both are read from the live view, without touching the map
    /// controller or the delegate.
    private func markMapInteractiveIfReady() {
        guard !mapMarked, let map = LaunchProbeHardware.mapViewInKeyWindow() else { return }
        guard map.style != nil, (map.gestureRecognizers?.isEmpty == false) else { return }
        mapMarked = true
        DiagnosticsMeasurements.shared.mark(.mapInteractive)
    }

    private func line(peakBytes: UInt64, complete: Bool) -> String {
        func ms(_ mark: DiagnosticsMeasurements.Mark) -> String {
            guard let entry = DiagnosticsMeasurements.shared.entry(mark) else { return "-1" }
            return String(format: "%.0f", entry.elapsed * 1000)
        }
        let peakMb = Int((Double(peakBytes) / 1_048_576).rounded())
        return "cold_launch_ms=\(ms(.launch))"
            + " cold_first_frame_ms=\(ms(.firstMapFrame))"
            + " cold_map_tap_ms=\(ms(.mapInteractive))"
            + " cold_first_fix_ms=\(ms(.firstFix))"
            + " cold_peak_mb=\(peakMb)"
            + " cold_complete=\(complete ? 1 : 0)"
    }
}

/// The badge the probe publishes. A one-point view at the leading edge, transparent and outside
/// every layout: it exists only for the UI test, which reads its accessibility label.
struct LaunchProbeBadge: UIViewRepresentable {
    @ObservedObject var probe = LaunchProbe.shared

    func makeUIView(context: Context) -> LaunchProbeView {
        let view = LaunchProbeView()
        view.accessibilityIdentifier = LaunchProbe.identifier
        view.accessibilityLabel = probe.text
        return view
    }

    func updateUIView(_ view: LaunchProbeView, context: Context) {
        view.accessibilityLabel = probe.text
    }
}

final class LaunchProbeView: UIView {
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

private enum LaunchProbeHardware {
    static func memoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// The first MapLibre view in the key window, found by walking the view tree. The probe never
    /// keeps it: a weak read per sample, after the map has been created.
    static func mapViewInKeyWindow() -> MLNMapView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows where window.isKeyWindow {
            if let found = find(in: window) { return found }
        }
        return nil
    }

    private static func find(in view: UIView) -> MLNMapView? {
        if let map = view as? MLNMapView { return map }
        for child in view.subviews {
            if let found = find(in: child) { return found }
        }
        return nil
    }
}
