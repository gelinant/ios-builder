#if DEBUG
import SwiftUI

/// The WebMap half of the Mapbox spike's FPS comparison (docs/ios/MAPBOX-SPIKE.md).
///
/// `-VelaFpsProbe <seconds>` waits that long after the main map's first style load, then asks the
/// page to wait until every tile of the view is loaded (`settled`, 90 s at most), to wait 3 s more
/// for a screenshot, then to turn the bearing through 360 degrees over 10 s, one camera step per
/// `requestAnimationFrame`, counting GL JS `render` events. The Mapbox spike waits for its idle
/// event and runs the same motion with a CADisplayLink, counting `onRenderFrameFinished`.
final class MapFpsProbe: ObservableObject {
    static let shared = MapFpsProbe()

    /// Same motion as `MapboxSpikeModel`.
    static let seconds: Double = 10
    static let degrees: Double = 360

    /// The delay after the first style load, or nil without the launch argument.
    static let delay: Double? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaFpsProbe"), index + 1 < arguments.count,
              let value = Double(arguments[index + 1]), value >= 0 else { return nil }
        return min(value, 120)
    }()

    @Published private(set) var line = "fps=pending"

    /// `settled` or `timeout`, and how long the page waited for its tiles.
    private var settle = "-"

    func started() {
        line = "fps=waiting"
    }

    func settled(state: String, milliseconds: Double) {
        settle = "\(state) waited_ms=\(Int(milliseconds))"
        line = "fps=\(settle)"
    }

    func report(renders: Int, ticks: Int, milliseconds: Double) {
        let seconds = milliseconds / 1000
        let fps = seconds > 0 ? Double(renders) / seconds : 0
        let numbers = String(format: "fps=%.1f frames=%d ticks=%d seconds=%.2f", fps, renders, ticks, seconds)
        line = "\(numbers) settle=\(settle)"
    }
}

/// The probe's result for MapboxSpikeUITests, invisible and untouchable like the other map
/// overlay lines.
struct MapFpsProbeLabel: View {
    @ObservedObject private var probe = MapFpsProbe.shared

    var body: some View {
        Text(probe.line)
            .font(.caption2.monospaced())
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1, alignment: .topLeading)
            .accessibilityIdentifier("map-fps-debug")
            .allowsHitTesting(false)
    }
}
#endif
