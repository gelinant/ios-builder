import Darwin
import Foundation
import MapLibre
import QuartzCore
import UIKit

/// The opt-in for the map's performance overlay. Debug builds start with it on; a release build
/// starts with it off and the user turns it on in Diagnostics. The choice lives in standard
/// UserDefaults, not the settings suite, because it is a developer aid and must not sync anywhere.
enum PerfOverlaySettings {
    static let key = "vela_perf_overlay"
    static let changedNotification = Notification.Name("VelaPerfOverlayChanged")

    static var isEnabled: Bool {
        get {
            if let value = UserDefaults.standard.object(forKey: key) as? Bool { return value }
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: changedNotification, object: nil)
        }
    }
}

/// One reading of the map's cost, shared by the overlay and the diagnostics screen.
struct PerfSnapshot {
    let fps: Double
    let droppedFrames: Int
    let rasterTiles: Int
    let memoryBytes: UInt64
    let zoom: Double

    var memoryMb: Int { Int((Double(memoryBytes) / 1_048_576).rounded()) }

    /// One machine-readable line. `fps` is the display link's delivered frames per second over the
    /// last second, not a render-thread counter: MapLibre owns its render loop, and the app cannot
    /// read its frame count without owning the map delegate.
    var text: String {
        let rate = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), fps)
        let level = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), zoom)
        return "fps=\(rate) dropped=\(droppedFrames) tiles=\(rasterTiles)"
            + " mem=\(memoryMb)MB zoom=\(level)"
    }
}

/// Measures the map without owning it: a `CADisplayLink` counts the frames the screen actually
/// delivers, the gap between two ticks is a dropped frame, and MapLibre's existing raster request
/// counter supplies the tile figure. A map render-thread stall that still lets the display link
/// fire is not seen; a main-thread stall is.
///
/// The only work it does when enabled is one integer add per display frame, one `task_info` read
/// and one label update per second. Disabled, it has no display link and no timer.
final class PerfMonitor: NSObject {
    static let shared = PerfMonitor()

    private weak var mapView: MLNMapView?
    private var hud: PerfHUD?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var windowTicks = 0
    private var measuredFps = 0.0
    private var dropped = 0
    private var memoryBytes: UInt64 = 0
    private var lastDisplayUpdate: CFTimeInterval = 0
    private var observer: NSObjectProtocol?

    private override init() {
        super.init()
        observer = NotificationCenter.default.addObserver(
            forName: PerfOverlaySettings.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyPreference()
        }
    }

    /// Called once the map view exists. The HUD is a subview of the map, so it takes no place in
    /// the SwiftUI layout and can never push the search chrome as the debug block once did.
    func attach(to mapView: MLNMapView) {
        if let current = self.mapView, current === mapView, hud != nil {
            applyPreference()
            return
        }
        hud?.removeFromSuperview()
        self.mapView = mapView
        let hud = PerfHUD()
        hud.place(in: mapView)
        mapView.addSubview(hud)
        self.hud = hud
        applyPreference()
    }

    func snapshot() -> PerfSnapshot {
        PerfSnapshot(
            fps: measuredFps,
            droppedFrames: dropped,
            rasterTiles: MapTileNetwork.shared.rasterRequests,
            memoryBytes: memoryBytes,
            zoom: mapView?.zoomLevel ?? 0)
    }

    private func applyPreference() {
        if PerfOverlaySettings.isEnabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard link == nil else { return }
        hud?.isHidden = false
        lastTimestamp = 0
        windowStart = CACurrentMediaTime()
        windowTicks = 0
        dropped = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        updateLabel(now: windowStart)
    }

    private func stop() {
        link?.invalidate()
        link = nil
        hud?.isHidden = true
        measuredFps = 0
        memoryBytes = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastTimestamp > 0 {
            let delta = now - lastTimestamp
            let nominal = link.duration
            if nominal > 0, delta > nominal * 1.5 {
                dropped += max(0, Int((delta / nominal).rounded()) - 1)
            }
        }
        lastTimestamp = now
        windowTicks += 1
        let span = now - windowStart
        if span >= 1 {
            measuredFps = Double(windowTicks) / span
            windowTicks = 0
            windowStart = now
            memoryBytes = PerfHardware.memoryFootprint()
        }
        if now - lastDisplayUpdate >= 0.25 {
            updateLabel(now: now)
        }
    }

    private func updateLabel(now: CFTimeInterval) {
        lastDisplayUpdate = now
        hud?.label.text = snapshot().text
        hud?.setNeedsLayout()
    }
}

/// A zero-height, non-interactive overlay inside the map. It never becomes an accessibility
/// element and never takes a touch, so it cannot cover a tap target or change the layout.
private final class PerfHUD: UIView {
    let label = UILabel()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.text = "fps=…"
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func place(in map: MLNMapView) {
        frame = map.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.sizeToFit()
        let width = label.bounds.width + 12
        let height = label.bounds.height + 6
        // Bottom left, above the scale bar and the attribution line, below the map buttons.
        let y = max(8, bounds.height - safeAreaInsets.bottom - height - 76)
        label.frame = CGRect(x: 8, y: y, width: width, height: height)
    }
}

private enum PerfHardware {
    /// The process footprint in bytes, the number the system kills the app over.
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
}

/// Marks the first map frame for the diagnostics measurements. A one-shot display link fires
/// after the first screen commit, which is the closest an app can get without owning MapLibre's
/// render loop.
final class FirstFrameProbe: NSObject {
    private var link: CADisplayLink?
    private let onFirst: () -> Void

    init(onFirst: @escaping () -> Void) {
        self.onFirst = onFirst
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        link?.invalidate()
        link = nil
        onFirst()
    }
}
