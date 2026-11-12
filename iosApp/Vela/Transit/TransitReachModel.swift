import Foundation
import VelaCore

/// The "Reachable in N minutes" screen's state. One `one-to-all` request per budget change, served
/// from the shared store's five-minute cache when the rider comes back to the same point and
/// budget. The screen is honest about the network: it never polls, it keeps its own empty state
/// when the feed reaches nothing, and it drops the last area when the device is offline or Vela is
/// in NoGoogle mode instead of showing a stale hull.
final class TransitReachModel: ObservableObject {
    static let minuteOptions = [15, 30, 45, 60]

    @Published private(set) var minutes = 30
    @Published private(set) var area: TransitReachArea?
    @Published private(set) var loading = false
    @Published private(set) var errorKey = ""
    @Published private(set) var networkAvailable = true
    @Published private(set) var googleDisabled = false
    @Published private(set) var fixture = false
    @Published private(set) var hullPublished = false

    let originName: String
    private let originLat: Double
    private let originLng: Double
    private let service: TransitLiveService?
    private let offline: OfflineStore?

    private var reachTask: Task<Void, Never>?
    private var offlineTask: Task<Void, Never>?
    private var started = false
    private var requests = 0

    init(
        service: TransitLiveService?,
        offline: OfflineStore?,
        originLat: Double,
        originLng: Double,
        originName: String
    ) {
        self.service = service
        self.offline = offline
        self.originLat = originLat
        self.originLng = originLng
        self.originName = originName
    }

    /// True when Vela must not ask Transitous: no network, or the rider's NoGoogle choice. Both
    /// leave the screen with its "needs Transitous" state and no hull at all.
    var isBlocked: Bool { !networkAvailable || googleDisabled }

    var stops: [TransitReachStop] { area?.stopsByTime ?? [] }

    var hull: [LatLng] { area?.hull ?? [] }

    var isEmpty: Bool { area != nil && (area?.stops.isEmpty ?? true) }

    var canPublishHull: Bool { !isBlocked && hull.count >= 3 }

    var stateName: String {
        if isBlocked { return "needs_transitous" }
        if loading { return "loading" }
        if let area { return area.stops.isEmpty ? "empty" : "ready" }
        return errorKey.isEmpty ? "idle" : errorKey
    }

    /// The single Debug status line the UI scenario reads.
    var debugLine: String {
        "reach_minutes=\(minutes) reach_stops=\(area?.stops.count ?? 0)"
            + " reach_hull=\(hullPublished && hull.count >= 3 ? 1 : 0)"
            + " reach_state=\(stateName) reach_fixture=\(fixture ? 1 : 0)"
            + " reach_requests=\(requests)"
            + " reach_error=\(errorKey.isEmpty ? "none" : errorKey)"
    }

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        fixture = ProcessInfo.processInfo.arguments.contains("-VelaTransitReachFixture")
        #endif
        observeOffline()
        if fixture {
            loadFixture()
            return
        }
        guard let service else {
            errorKey = "needs_transitous"
            return
        }
        reachTask = Task { @MainActor [weak self] in
            for await state in service.reach.state {
                self?.applyReach(state)
            }
        }
        requestReach()
    }

    /// One request per budget change. The store answers the same point and budget from its cache
    /// for five minutes, so switching back and forth does not spend the daily share again.
    func setMinutes(_ value: Int) {
        let clamped = min(max(value, 5), 60)
        guard clamped != minutes else { return }
        minutes = clamped
        errorKey = ""
        if fixture {
            loadFixture()
            return
        }
        requestReach()
    }

    /// The explicit retry after a failure or after the network came back. Never called by a timer.
    func retry() {
        errorKey = ""
        if fixture {
            loadFixture()
        } else {
            requestReach()
        }
    }

    /// Publishes the hull and its dots through the one overlay mailbox the map already listens to.
    /// Without three corners there is no polygon, so the action publishes nothing rather than a
    /// line or a single dot presented as a zone.
    func publishHull() {
        guard canPublishHull, let area else {
            hullPublished = false
            TransitOverlayHub.shared.publish(reach: nil)
            return
        }
        TransitOverlayHub.shared.publish(reach: area)
        hullPublished = true
    }

    /// Leaves the map as the screen found it when the rider closes without asking for the hull.
    func withdrawHull() {
        guard hullPublished else { return }
        hullPublished = false
        TransitOverlayHub.shared.publish(reach: nil)
    }

    private func requestReach() {
        guard !isBlocked else {
            errorKey = "needs_transitous"
            area = nil
            loading = false
            hullPublished = false
            TransitOverlayHub.shared.publish(reach: nil)
            return
        }
        guard let service else {
            errorKey = "needs_transitous"
            return
        }
        loading = true
        requests += 1
        service.requestReach(lat: originLat, lng: originLng, minutes: Int32(minutes))
    }

    private func applyReach(_ state: TransitReachState) {
        // A stale answer must not come back after the device went offline: the screen shows
        // nothing rather than a hull it can no longer justify.
        guard !isBlocked else {
            area = nil
            loading = false
            errorKey = "needs_transitous"
            hullPublished = false
            TransitOverlayHub.shared.publish(reach: nil)
            return
        }
        loading = state.loading
        if let area = state.area {
            self.area = area
        }
        errorKey = state.error ?? ""
        // The map follows a new budget once the rider has asked for the hull, never before.
        if hullPublished, let area, area.hull.count >= 3 {
            TransitOverlayHub.shared.publish(reach: area)
        }
    }

    private func observeOffline() {
        guard let offline else { return }
        offlineTask = Task { @MainActor [weak self] in
            for await state in offline.state {
                self?.applyOffline(state)
            }
        }
    }

    private func applyOffline(_ state: OfflineState) {
        networkAvailable = state.networkAvailable
        googleDisabled = state.googleDisabled
        if isBlocked {
            area = nil
            loading = false
            errorKey = "needs_transitous"
            hullPublished = false
            TransitOverlayHub.shared.publish(reach: nil)
        } else if errorKey == "needs_transitous" {
            // The network came back. The screen still waits for the rider's tap: no retry loop.
            errorKey = ""
        }
    }

    private func loadFixture() {
        #if DEBUG
        guard !isBlocked else { return }
        let result = TransitReachFixtures.reply.result
        guard let result else { return }
        loading = false
        errorKey = ""
        area = TransitReach.shared.area(
            result: result, maxMinutes: Int32(minutes),
            nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
        if hullPublished, let area, area.hull.count >= 3 {
            TransitOverlayHub.shared.publish(reach: area)
        }
        #endif
    }
}

#if DEBUG
/// The recorded `one-to-all` answer behind `-VelaTransitReachFixture`. It is the same captured
/// Ferry Building reply as `TransitLiveFixtures` (GET `/api/v1/one-to-all?one=37.7955,-122.3937`
/// on 2026-10-28), reshaped as the API reply itself so this screen exercises the same
/// `TransitReach.area` path as production. No stop, time or transfer is invented.
enum TransitReachFixtures {
    static var reply: Transitous.OneToAllReply {
        Transitous.OneToAllReply(
            result: Transitous.ReachResult(
                originName: TransitLiveFixtures.reachOriginName,
                originLat: TransitLiveFixtures.reachLat,
                originLon: TransitLiveFixtures.reachLng,
                originEpochSec: nil,
                stops: TransitLiveFixtures.reachStops.map { stop in
                    Transitous.ReachableStop(
                        name: stop.name,
                        stopId: stop.stopId,
                        lat: stop.lat,
                        lon: stop.lng,
                        minutes: Int32(stop.minutes),
                        transfers: Int32(stop.transfers),
                        arrivalEpochSec: nil,
                        modes: [])
                }),
            rateLimited: false)
    }
}
#endif
