import Foundation
import VelaCore

/// The live transit panel's state: the reachable area and the colored lines, each loaded by one user
/// action. In a Debug UI test it answers from `TransitLiveFixtures` and never touches the network;
/// production asks the shared `TransitLiveService`, which caches and counts every call against the
/// Transitous fair-use budget. There is no timer: nothing refreshes until the user asks.
final class TransitLiveModel: ObservableObject {
    @Published private(set) var area: TransitReachArea?
    @Published private(set) var reachLoading = false
    @Published private(set) var reachError = ""
    @Published private(set) var lines: [TransitLiveLine] = []
    @Published private(set) var linesLoading = false
    @Published private(set) var linesError = ""
    @Published private(set) var linesTruncated = false
    @Published private(set) var linesSegments = 0
    @Published private(set) var minutes = 20
    @Published private(set) var fixture = false
    @Published private(set) var errorKeys: [String: String] = [:]

    private let service: TransitLiveService?
    private var reachObservation: Task<Void, Never>?
    private var linesObservation: Task<Void, Never>?
    private var started = false

    init(service: TransitLiveService?) {
        self.service = service
    }

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        fixture = ProcessInfo.processInfo.arguments.contains("-VelaTransitAdvancedFixture")
        #endif
        guard let service else { return }
        reachObservation = Task { @MainActor [weak self] in
            for await state in service.reach.state {
                self?.applyReach(state)
            }
        }
        linesObservation = Task { @MainActor [weak self] in
            for await state in service.lines.state {
                self?.applyLines(state)
            }
        }
    }

    func loadReach(lat: Double, lng: Double) {
        #if DEBUG
        if fixture {
            area = TransitLiveFixtures.reachArea(minutes: minutes)
            reachLoading = false
            reachError = ""
            TransitOverlayHub.shared.publish(reach: area)
            return
        }
        #endif
        guard let service else {
            reachError = "no_service"
            return
        }
        reachLoading = true
        reachError = ""
        service.requestReach(lat: lat, lng: lng, minutes: Int32(minutes))
    }

    func loadLines(lat: Double, lng: Double) {
        #if DEBUG
        if fixture {
            lines = TransitLiveFixtures.lines
            linesSegments = Int(lines.reduce(0) { $0 + Int($1.segmentCount) })
            linesLoading = false
            linesError = ""
            linesTruncated = false
            TransitOverlayHub.shared.publish(lines: lines)
            return
        }
        #endif
        guard let service else {
            linesError = "no_service"
            return
        }
        let now = Int64(Date().timeIntervalSince1970)
        linesLoading = true
        linesError = ""
        service.requestLines(
            south: lat - 0.02, west: lng - 0.02, north: lat + 0.02, east: lng + 0.02,
            zoom: 15, startEpochSec: now - 120, endEpochSec: now + 600)
    }

    func setMinutes(_ value: Int) {
        minutes = min(max(value, 5), 60)
    }

    private func applyReach(_ state: TransitReachState) {
        reachLoading = state.loading
        if let area = state.area {
            self.area = area
            TransitOverlayHub.shared.publish(reach: area)
        }
        reachError = state.error ?? ""
        errorKeys["reach"] = reachError
    }

    private func applyLines(_ state: TransitLiveLinesState) {
        linesLoading = state.loading
        lines = state.lines
        linesTruncated = state.truncated
        linesSegments = Int(state.segmentCount)
        linesError = state.error ?? ""
        errorKeys["lines"] = linesError
        // A loading or failed state keeps the previous answer, as the panel promises, and a
        // panel that closes publishes nothing: the hub keeps the map drawn.
        if !lines.isEmpty { TransitOverlayHub.shared.publish(lines: lines) }
    }

    var isRateLimited: Bool { reachError == "rate_limited" || linesError == "rate_limited" }
    var isBudgetExhausted: Bool { reachError == "budget_exhausted" || linesError == "budget_exhausted" }

    var reachDebugLine: String {
        "reach=\(area == nil ? 0 : 1) stops=\(area?.stops.count ?? 0) hull=\(area?.hull.count ?? 0)"
            + " minutes=\(minutes) fixture=\(fixture ? 1 : 0)"
            + " rate=\(area?.rateLimited == true || reachError == "rate_limited" ? 1 : 0)"
            + " error=\(reachError.isEmpty ? "none" : reachError)"
    }

    var linesDebugLine: String {
        let green = lines.filter { $0.delayLevel == "green" }.count
        let amber = lines.filter { $0.delayLevel == "amber" }.count
        let red = lines.filter { $0.delayLevel == "red" }.count
        let colored = lines.filter { $0.feedColorHex != nil }.count
        let live = lines.filter { $0.live }.count
        let head = "lines=\(lines.count) segs=\(linesSegments) colored=\(colored) live=\(live)"
        let bands = " green=\(green) amber=\(amber) red=\(red)"
        let tail = " truncated=\(linesTruncated ? 1 : 0) fixture=\(fixture ? 1 : 0)"
        return head + bands + tail + " error=\(linesError.isEmpty ? "none" : linesError)"
    }
}
