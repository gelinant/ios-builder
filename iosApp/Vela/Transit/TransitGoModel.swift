import Foundation
import UIKit
import VelaCore

/// SwiftUI's owner of the GO step machine. The Kotlin `TransitGoMachine` decides the current
/// action and the get-off cue; this object only ticks its clock, forwards the shared session's
/// progress, and plays each new cue once. No request is sent by the timer: the countdown is the
/// feed's target epoch compared with the device clock.
final class TransitGoModel: ObservableObject {
    @Published private(set) var state: TransitGoState?
    @Published private(set) var error = ""
    @Published private(set) var cueEvents = 0
    @Published private(set) var starts = 0
    /// Where the last leave-later request started: `board` when the stop board listed this run's
    /// own departure, `now` for the now-plus-minutes fallback. Empty before the first request.
    @Published private(set) var anchorSource = ""
    /// Says the board had no departure for this stop. Never set for a board anchor.
    @Published private(set) var anchorNotice = ""

    /// The selected itinerary, kept so the line sheet and the host can show the same trip.
    let trip: TransitItinerary?
    let destinationName: String
    /// Whether the itinerary carried real-time fields when it was chosen. The machine still drops
    /// every live claim when the plan is stale or the device is offline.
    private let liveInput: Bool
    /// Production reads the offline store on each tick; a fixture can leave the default.
    var networkAvailableProvider: (() -> Bool)?
    /// The open stop board, read when a later departure is requested. Both stay nil outside the
    /// app host, where GO simply reports the now-plus-minutes fallback.
    var boardStopNameProvider: (() -> String)?
    var boardDeparturesProvider: (() -> [TransitGoBoardDeparture])?
    /// The Debug host sets this to false: its degraded scene must not be overridden by the
    /// simulator's real network path.
    var usesHostNetwork = true
    /// The Debug prepare scene turns this off so the screen keeps its loading line.
    var autoStart = true
    private var networkAvailable: Bool
    private let fetchedAtEpochSec: Int64
    private let now: () -> Date
    private var fixturePlan: TransitGoPlan?
    private var plan: TransitGoPlan?
    private var machine: TransitGoMachine?
    private var timer: Timer?
    private var lastCueSerial: Int32 = 0
    private var lastFiredCue = ""

    init(
        trip: TransitItinerary?,
        destinationName: String,
        networkAvailable: Bool = true,
        fetchedAt: Date = Date(),
        now: @escaping () -> Date = Date.init
    ) {
        self.trip = trip
        self.destinationName = destinationName.isEmpty ? "the destination" : destinationName
        self.liveInput = Self.hasLiveFields(trip)
        self.networkAvailable = networkAvailable
        self.fetchedAtEpochSec = Int64(fetchedAt.timeIntervalSince1970)
        self.now = now
    }

    /// The Debug UI scenario builds a plan directly, with no planner and no network.
    init(
        plan: TransitGoPlan,
        networkAvailable: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.trip = nil
        self.destinationName = plan.destinationName
        self.liveInput = plan.liveData
        self.networkAvailable = networkAvailable
        self.fetchedAtEpochSec = plan.fetchedAtEpochSec
        self.now = now
        self.fixturePlan = plan
        self.plan = plan
        self.machine = TransitGoMachine(plan: plan, networkAvailable: networkAvailable)
    }

    func start() {
        guard autoStart else { return }
        guard machine == nil else {
            refresh()
            startTimer()
            return
        }
        let plan = fixturePlan ?? trip.map {
            TransitGoPlanBuilder.shared.fromItinerary(
                trip: $0,
                destinationName: destinationName,
                fetchedAtEpochSec: fetchedAtEpochSec,
                liveData: liveInput)
        }
        guard let plan else {
            error = "No itinerary selected"
            return
        }
        self.plan = plan
        machine = TransitGoMachine(
            plan: plan,
            networkAvailable: networkAvailableProvider?() ?? networkAvailable)
        starts += 1
        refresh()
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func board() {
        machine?.board()
        refresh()
    }

    func skip() {
        machine?.skipStep()
        refresh()
    }

    func advanceStop() {
        machine?.advanceStop()
        refresh()
    }

    func end() {
        machine?.end()
        refresh()
    }

    func setNetworkAvailable(_ available: Bool) {
        networkAvailable = available
        machine?.setNetworkAvailable(available: available)
        refresh()
    }

    /// The same anchor rule as the trip screen: the line's own departure at this stop from the
    /// open board, otherwise now plus [minutes] with a notice the screen shows. The returned epoch
    /// is what the host hands to the planner; GO never rewrites the itinerary on screen.
    func leaveLaterEpoch(minutes: Int) -> Int64 {
        let anchor = TransitGoAnchorSelector.shared.select(
            leg: anchorLeg(),
            boardStopName: boardStopNameProvider?() ?? "",
            boardDepartures: boardDeparturesProvider?() ?? [],
            nowEpochSec: Int64(now().timeIntervalSince1970),
            deltaMinutes: Int32(minutes))
        anchorSource = anchor.source
        anchorNotice = anchor.source == "now"
            ? VelaL10n.text("transit_go_board_has_no_time_for_this_stop", String(minutes))
            : ""
        return anchor.epochSec
    }

    /// The ride whose boarding stop anchors the request: the current ride, or the next ride while
    /// GO is still walking or waiting.
    private func anchorLeg() -> TransitGoLeg? {
        guard let plan else { return nil }
        let legs = plan.legs
        guard !legs.isEmpty else { return nil }
        let start = max(0, Int(state?.legIndex ?? 0))
        if start < legs.count, legs[start].kind == "RIDE" {
            return legs[start]
        }
        return legs.dropFirst(start).first { $0.kind == "RIDE" }
    }

    /// Pushes the shared session's progress. `stopsRemaining` is what the in-app guidance card
    /// already shows, so the rail follows the same positions and never a second estimate.
    func sync(legIndex: Int, stopsRemaining: Int, boarded: Bool, arrived: Bool) {
        guard let machine else { return }
        let sameRide = state?.phase == "RIDE" && Int(state?.legIndex ?? -1) == legIndex
            && (state?.stops.count ?? 0) > 1
        let passed = sameRide ? max(0, (state?.stops.count ?? 1) - 1 - stopsRemaining) : 0
        machine.sync(
            legIndex: Int32(legIndex), passedStops: Int32(passed),
            boarded: boarded, arrived: arrived)
        refresh()
    }

    #if DEBUG
    /// Debug UI hook: puts the machine at a ride and a stop without playing the earlier cues.
    /// The run starts one stop short of the alight, so the scenario can test the stop cue itself.
    func seek(legIndex: Int, stopIndex: Int, boarded: Bool) {
        machine?.sync(
            legIndex: Int32(legIndex), passedStops: Int32(stopIndex),
            boarded: boarded, arrived: false)
        refresh()
    }
    #endif

    /// The host's offline store, read at each tick so losing network degrades the screen in place.
    func attachNetworkProvider(_ provider: @escaping () -> Bool) {
        networkAvailableProvider = provider
        setNetworkAvailable(provider())
    }

    var debugLine: String {
        let base = state?.debugLine ?? "go_step=done go_estimated=0 go_cue=none"
        return base + " go_cues=\(cueEvents) go_cue_last=\(lastFiredCue.isEmpty ? "none" : lastFiredCue)"
            + " go_anchor=\(anchorSource.isEmpty ? "none" : anchorSource)"
            + " go_fallback_notice=\(anchorNotice.isEmpty ? 0 : 1)"
    }

    var hasPlan: Bool { state?.active == true || machine != nil }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard let machine else { return }
        if let provider = networkAvailableProvider, provider() != networkAvailable {
            networkAvailable = provider()
            machine.setNetworkAvailable(available: networkAvailable)
        }
        let next = machine.snapshot(nowEpochSec: Int64(now().timeIntervalSince1970))
        state = next
        guard next.cueSerial != lastCueSerial else { return }
        lastCueSerial = next.cueSerial
        guard !next.cue.isEmpty else { return }
        lastFiredCue = next.cue
        cueEvents += 1
        TransitGoCuePlayer.play(kind: next.cue, text: next.cueText)
    }

    private static func hasLiveFields(_ trip: TransitItinerary?) -> Bool {
        guard let trip else { return false }
        return trip.steps.contains { step in
            [step.boardStop, step.alightStop].compactMap { $0 }.contains {
                $0.delayMin != nil || $0.scheduledText != nil
            }
        }
    }
}
