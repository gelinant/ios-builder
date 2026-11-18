import Foundation
import UIKit
import VelaCore

/// One card of the trip screen, mapped from the shared Kotlin `TransitTripSegment`. Every value is
/// the feed's; [live] is true only when a stop carried the realtime pair.
struct TripSegment: Identifiable, Equatable {
    let id: Int
    let stepIndex: Int
    let kind: String
    let lineLabel: String?
    let lineColor: String?
    let lineTextColor: String?
    let mode: String
    let direction: String?
    let boardName: String?
    let alightName: String?
    let boardCode: String?
    let alightCode: String?
    let scheduledDeparture: String?
    let estimatedDeparture: String?
    let scheduledArrival: String?
    let estimatedArrival: String?
    let delayMinutes: Int?
    let durationText: String?
    let distanceText: String?
    let stopCount: Int
    let boardLat: Double?
    let boardLng: Double?
    let alightLat: Double?
    let alightLng: Double?
    let hasBoardPoint: Bool
    let waitUntil: String?
    let live: Bool
    let skippable: Bool
    /// The planner's own mode name for a ride, so the card can read "RER B".
    let modeName: String?
    /// The operator named on this leg, when the planner gave one per leg.
    let agencyName: String?
    /// On a wait card, the planned minutes from the previous arrival to this departure.
    let waitMinutes: Int?

    var isRide: Bool { kind == "RIDE" }
    var isWalk: Bool { kind == "WALK" || kind == "TRANSFER" }

    init(_ segment: TransitTripSegment) {
        id = Int(segment.index)
        stepIndex = Int(segment.stepIndex)
        kind = segment.kind
        lineLabel = segment.lineLabel
        lineColor = segment.lineColor
        lineTextColor = segment.lineTextColor
        mode = segment.mode
        direction = segment.direction
        boardName = segment.boardName
        alightName = segment.alightName
        boardCode = segment.boardCode
        alightCode = segment.alightCode
        scheduledDeparture = segment.scheduledDeparture
        estimatedDeparture = segment.estimatedDeparture
        scheduledArrival = segment.scheduledArrival
        estimatedArrival = segment.estimatedArrival
        delayMinutes = segment.delayMinutes?.intValue
        durationText = segment.durationText
        distanceText = segment.distanceText
        stopCount = Int(segment.stopCount)
        boardLat = segment.boardLat?.doubleValue
        boardLng = segment.boardLng?.doubleValue
        alightLat = segment.alightLat?.doubleValue
        alightLng = segment.alightLng?.doubleValue
        hasBoardPoint = segment.hasBoardPoint
        waitUntil = segment.waitUntil
        live = segment.live
        skippable = segment.skippable
        modeName = segment.modeName
        agencyName = segment.agencyName
        waitMinutes = segment.waitMinutes?.intValue
    }
}

/// One departure of the header or of the nearby lines.
struct TripDeparture: Identifiable, Equatable {
    let id: Int64
    let clockText: String?
    let epochSec: Int64
    let realtime: Bool
    let minutes: Int

    func minutesFrom(_ now: Date) -> Int {
        let seconds = TimeInterval(epochSec) - now.timeIntervalSince1970
        if seconds <= 0 { return 0 }
        return Int((seconds + 59) / 60)
    }

    init(_ departure: TransitTripDeparture) {
        id = departure.epochSec
        clockText = departure.clockText
        epochSec = departure.epochSec
        realtime = departure.realtime
        minutes = Int(departure.minutes)
    }
}

/// The next departures of the selected leg's own line at its boarding stop.
struct TripHeader: Equatable {
    let stopName: String?
    let lineLabel: String?
    let lineColor: String?
    let direction: String?
    let departures: [TripDeparture]
    let available: Bool

    init(_ header: TransitTripHeader) {
        stopName = header.stopName
        lineLabel = header.lineLabel
        lineColor = header.lineColor
        direction = header.direction
        departures = header.departures.map(TripDeparture.init)
        available = header.available
    }
}

/// One line served at the nearby stop, with its next runs.
struct TripNearbyRow: Identifiable, Equatable {
    let id: String
    let label: String?
    let mode: String
    let headsign: String?
    let color: String?
    let departures: [TripDeparture]

    init(_ line: TransitNearbyLine) {
        id = "\(line.label ?? "?")|\(line.headsign ?? "")|\(line.mode)"
        label = line.label
        mode = line.mode
        headsign = line.headsign
        color = line.color
        departures = line.departures.map(TripDeparture.init)
    }
}

/// One trip of a new option set. Rows never rewrite the trip above them.
struct TripOptionRow: Identifiable, Equatable {
    let id: Int
    let departureText: String?
    let arrivalText: String?
    let durationText: String?
    let lines: [String]
    let live: Bool
    /// The whole option's modes in travel order, walks included.
    let modeNames: [String]

    init(_ option: TransitTripOption) {
        id = Int(option.index)
        departureText = option.departureText
        arrivalText = option.arrivalText
        durationText = option.durationText
        lines = option.lines
        live = option.live
        modeNames = option.modeNames
    }
}

/// One intermediate stop offered for a via search.
struct TripViaCandidate: Identifiable, Equatable {
    let id: Int
    let name: String
    let stopId: String?
    let clockText: String?
    let kotlin: TransitViaCandidate

    init(_ candidate: TransitViaCandidate, index: Int) {
        id = index
        name = candidate.name
        stopId = candidate.stopId
        clockText = candidate.clockText
        kotlin = candidate
    }
}

private enum TripBoardMode {
    case none, header, nearby
}

/// The trip screen's state. It reads the itinerary RouteStore selected (the same object the detail
/// sheet shows), asks its own `TransitBoardStore` for the header and the nearby lines, and turns a
/// time change into a fresh `/api/v1/plan` search through RouteStore. It never edits the times of
/// the trip on screen: new answers arrive as a separate option set.
final class TransitTripModel: ObservableObject {
    @Published private(set) var trip: TransitItinerary?
    @Published private(set) var segments: [TripSegment] = []
    @Published private(set) var header: TripHeader?
    @Published private(set) var headerLoading = false
    @Published private(set) var headerStale = false
    @Published private(set) var headerOffline = false
    @Published private(set) var nearby: [TripNearbyRow] = []
    @Published private(set) var nearbyStop = ""
    @Published private(set) var nearbyLoading = false
    @Published private(set) var nearbyOffline = false
    @Published private(set) var selectedSegment = -1
    @Published private(set) var skippedSegment = -1
    @Published private(set) var notice = ""
    @Published private(set) var options: [TripOptionRow] = []
    @Published private(set) var optionsLoading = false
    @Published private(set) var optionsQuery = ""
    @Published private(set) var optionsError = ""
    /// Where the last segment time change took its departure: `board` when the chosen line's own
    /// departure at that stop anchored it, `now` when the board had no time and now plus the
    /// requested minutes was used instead.
    @Published private(set) var anchorSource = ""
    @Published private(set) var viaCandidates: [TripViaCandidate] = []
    @Published private(set) var viaOptions: [TripOptionRow] = []
    @Published private(set) var viaQuery = ""
    @Published private(set) var viaName = ""
    @Published private(set) var viaLoading = false
    @Published private(set) var viaError = ""
    @Published private(set) var progress: Double = -1
    @Published private(set) var progressText = ""
    /// The whole-trip time choice, mirrored from RouteStore so the control and the plan agree.
    @Published private(set) var timeMode: Int32 = 0
    @Published private(set) var timeEpoch: Int64 = 0

    /// True when the screen runs on `TransitTripFixtures` (Debug, `-VelaTransitFixture`). No fixture
    /// answer is ever adopted as a trip or presented as feed data outside a scenario.
    @Published private(set) var fixture = false

    private let session: MapSession?
    private let service: TransitTripService?
    private var boardObservation: Task<Void, Never>?
    private var routeObservation: Task<Void, Never>?
    private var transitObservation: Task<Void, Never>?
    private var boardMode: TripBoardMode = .none
    private var kotlinTrip: TransitItinerary?
    private var kotlinSegments: [TransitTripSegment] = []
    private var kotlinHeader: TransitTripHeader?
    private var optionTrips: [TransitItinerary] = []
    private var viaTrips: [TransitItinerary] = []
    private var awaitingOptions = false

    /// Called with a via option the user picked, so the detail sheet can show the same itinerary.
    /// RouteStore has no via parameter, so a via trip that is not in its list is adopted directly.
    var onAdopt: ((TransitItinerary) -> Void)?
    private var started = false

    init(session: MapSession?, service: TransitTripService?) {
        self.session = session
        self.service = service
    }

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        fixture = ProcessInfo.processInfo.arguments.contains("-VelaTransitFixture")
        #endif
        if let board = service?.board {
            boardObservation = Task { @MainActor [weak self] in
                for await state in board.state {
                    self?.applyBoard(state)
                }
            }
        }
        if let route = session?.route {
            routeObservation = Task { @MainActor [weak self] in
                for await state in route.state {
                    self?.applyRoute(state)
                }
            }
        }
        if let transit = session?.transit {
            transitObservation = Task { @MainActor [weak self] in
                for await state in transit.state {
                    self?.applyTransit(state)
                }
            }
        }
    }

    /// Opens the screen on the itinerary the detail sheet shows. [trip] is the same Kotlin object.
    func open(trip: TransitItinerary) {
        start()
        kotlinTrip = trip
        self.trip = trip
        kotlinSegments = TransitTrip.shared.segmentsOf(trip: trip)
        segments = kotlinSegments.map(TripSegment.init)
        selectedSegment = segments.firstIndex(where: { $0.isRide }) ?? -1
        skippedSegment = -1
        notice = ""
        options = []
        optionTrips = []
        optionsQuery = ""
        optionsError = ""
        anchorSource = ""
        awaitingOptions = false
        viaCandidates = []
        viaOptions = []
        viaTrips = []
        viaQuery = ""
        viaName = ""
        viaLoading = false
        viaError = ""
        loadHeader()
    }

    func close() {
        service?.close()
        boardMode = .none
        header = nil
        kotlinHeader = nil
        nearby = []
        nearbyStop = ""
        notice = ""
        options = []
        optionTrips = []
        optionsQuery = ""
        optionsError = ""
        anchorSource = ""
        awaitingOptions = false
        viaCandidates = []
        viaOptions = []
        viaTrips = []
        viaQuery = ""
        viaName = ""
        viaLoading = false
        viaError = ""
    }

    // MARK: Selection

    func select(segment index: Int) {
        guard index >= 0, index < segments.count else { return }
        selectedSegment = index
        notice = ""
        anchorSource = ""
        loadHeader()
    }

    /// The leg whose next departures the header lists: the picked ride, or the next ride after a
    /// walk, wait or transfer.
    private func headerSegment() -> TransitTripSegment? {
        guard !kotlinSegments.isEmpty else { return nil }
        let index = selectedSegment >= 0 ? selectedSegment : 0
        guard index < kotlinSegments.count else { return nil }
        let picked = kotlinSegments[index]
        if picked.kind == "RIDE" { return picked }
        return kotlinSegments.dropFirst(index + 1).first { $0.kind == "RIDE" }
    }

    private func loadHeader() {
        guard let segment = headerSegment() else {
            header = nil
            kotlinHeader = nil
            return
        }
        if fixture {
            let now = Int64(Date().timeIntervalSince1970)
            let board = TransitTripFixtures.shared.headerBoard(nowSec: now)
            let mapped = TransitTrip.shared.header(board: board, segment: segment, nowSec: now)
            kotlinHeader = mapped
            header = TripHeader(mapped)
            headerLoading = false
            headerStale = false
            headerOffline = false
            return
        }
        guard segment.hasBoardPoint, let service else {
            headerLoading = false
            kotlinHeader = nil
            header = nil
            notice = "Transitous did not give this stop's coordinates, so Vela cannot ask for its board."
            return
        }
        headerLoading = true
        boardMode = .header
        service.openAt(
            lat: segment.boardLat?.doubleValue ?? 0,
            lng: segment.boardLng?.doubleValue ?? 0,
            name: segment.boardName ?? "")
    }

    private func applyBoard(_ state: TransitBoardState) {
        switch boardMode {
        case .header:
            headerLoading = state.loading
            headerStale = state.refreshFailed
            headerOffline = state.offline
            guard let segment = headerSegment() else { return }
            let mapped = TransitTrip.shared.header(state: state, segment: segment)
            kotlinHeader = mapped
            header = TripHeader(mapped)
        case .nearby:
            nearbyLoading = state.loading
            nearbyOffline = state.offline
            nearbyStop = state.stopName
            nearby = TransitTrip.shared.nearby(state: state).map(TripNearbyRow.init)
        case .none:
            break
        }
    }

    // MARK: Nearby lines

    /// The lines at the trip's origin stop. The origin is the first coordinate the itinerary gave;
    /// when it gave none the tab says so instead of listing invented lines.
    func loadNearby() {
        guard let segment = segments.first(where: { $0.hasBoardPoint }) else {
            nearby = []
            nearbyStop = ""
            notice = "Transitous did not give the trip's origin, so there are no nearby lines to list."
            return
        }
        notice = ""
        if fixture {
            let now = Int64(Date().timeIntervalSince1970)
            let board = TransitTripFixtures.shared.nearbyBoard(nowSec: now)
            nearbyStop = board.stationName ?? "Van Ness Station"
            nearby = TransitTrip.shared.nearby(board: board, nowSec: now).map(TripNearbyRow.init)
            nearbyLoading = false
            nearbyOffline = false
            return
        }
        guard let service else { return }
        nearbyLoading = true
        nearby = []
        boardMode = .nearby
        service.openAt(
            lat: segment.boardLat ?? 0,
            lng: segment.boardLng ?? 0,
            name: segment.boardName ?? "")
    }

    func refreshBoard() {
        if fixture {
            if boardMode == .nearby { loadNearby() } else { loadHeader() }
            return
        }
        service?.refresh()
    }

    /// Re-asks for the selected leg's board when the trip tab comes back.
    func reloadHeader() {
        loadHeader()
    }

    // MARK: Time change

    /// Leave later on the selected segment. The planner is asked for a departure at the stop's own
    /// run plus [minutes]; the answer becomes a new option set.
    func leaveLater(minutes: Int) {
        requestShift(mode: 1, minutes: minutes, label: "Depart at")
    }

    /// Arrive by on the selected segment. Transitous only constrains the destination, so a segment
    /// other than the last one is refused with that explanation.
    func arriveBy(minutes: Int = 0) {
        requestShift(mode: 2, minutes: minutes, label: "Arrive by")
    }

    private func requestShift(mode: Int32, minutes: Int, label: String) {
        notice = ""
        optionsError = ""
        anchorSource = ""
        guard let trip = kotlinTrip, selectedSegment >= 0, selectedSegment < kotlinSegments.count else {
            notice = "Pick a segment first."
            return
        }
        let segment = kotlinSegments[selectedSegment]
        let plan = kotlinHeader.flatMap { header in
            TransitTrip.shared.shift(
                trip: trip, segment: segment, header: header, mode: mode, deltaMinutes: Int32(minutes))
        }
        // Leave later is honest only when the board lists this line's own departure at this stop.
        // The itinerary's start is not that departure, so a silent trip-start anchor is refused
        // here and reported as the now-plus-minutes fallback instead.
        if let plan, mode == 1, plan.anchorSource == "board" {
            anchorSource = "board"
            applyShift(plan: plan, label: label, fixtureMinutes: minutes)
            return
        }
        if mode == 2 {
            guard let plan else {
                notice = "Transitous has no per-stop arrival constraint: pick the last segment to arrive by a time."
                return
            }
            anchorSource = plan.anchorSource
            applyShift(plan: plan, label: label, fixtureMinutes: minutes)
            return
        }
        // No board time for this stop: say it, then fall back to now plus the requested minutes.
        let epoch = Int64(Date().timeIntervalSince1970) + Int64(minutes) * 60
        applyTimeChoice(mode: 1, epochSec: epoch)
        anchorSource = "now"
        notice = VelaL10n.text(
            "transit_board_has_no_time_for_this_stop", String(describing: minutes))
    }

    /// The control at the top of the screen: re-asks the same trip search at the chosen time and
    /// keeps the answer as a separate option set. The trip above the options keeps its own times.
    func applyTimeChoice(mode: Int32, epochSec: Int64) {
        notice = ""
        optionsError = ""
        let normalisedMode = TimeChoice.shared.normalizedMode(mode: mode)
        let label = TimeChoice.shared.label(
            mode: normalisedMode, epochSec: epochSec, zoneId: TimeZone.current.identifier)
        let stop = segments.first(where: { $0.isRide })?.boardName
        optionsQuery = stop.map { "\(label) from \($0)" } ?? label
        options = []
        optionTrips = []
        timeMode = normalisedMode
        timeEpoch = epochSec
        if fixture {
            guard let trip = kotlinTrip else { return }
            let later = TransitTripFixtures.shared.shifted(trip: trip, minutes: 15)
            options = TransitTrip.shared.options(trips: later).map(TripOptionRow.init)
            optionsQuery += " · fixture, display only"
            optionsLoading = false
            return
        }
        guard let route = session?.route else {
            notice = "Transitous needs an open trip search to re-plan."
            return
        }
        optionsLoading = true
        awaitingOptions = true
        route.setTime(mode: normalisedMode, epochSec: epochSec)
        route.retry()
    }

    /// Lets the selected run pass: the header jumps to the next run of the same line and a new
    /// option set is asked for that departure. The trip itself stays on screen.
    func skipSelected() {
        notice = ""
        optionsError = ""
        guard selectedSegment >= 0, selectedSegment < kotlinSegments.count,
              let currentHeader = kotlinHeader else {
            notice = "The board has not answered for this stop yet."
            return
        }
        let segment = kotlinSegments[selectedSegment]
        guard let skip = TransitTrip.shared.skip(header: currentHeader, segment: segment) else {
            notice = segment.skippable
                ? "Transitous lists no later run of this line at this stop."
                : "Only a ride can be let pass."
            return
        }
        skippedSegment = selectedSegment
        let clock = skip.clockText ?? Self.clock(skip.epochSec)
        notice = "Let \(segment.lineLabel ?? "this run") pass. Next at \(clock) "
            + "(\(skip.realtime ? "Live" : "Scheduled"))."
        let advanced = TransitTrip.shared.withoutDeparture(header: currentHeader, epochSec: skip.passedEpochSec)
        kotlinHeader = advanced
        header = TripHeader(advanced)
        guard let trip = kotlinTrip else { return }
        let plan = TransitTrip.shared.shiftTo(trip: trip, segment: segment, epochSec: skip.epochSec)
        applyShift(plan: plan, label: "Depart at", fixtureMinutes: 15)
    }

    private func applyShift(plan: TransitTripShift, label: String, fixtureMinutes: Int) {
        anchorSource = plan.anchorSource
        let stop = plan.stopName.map { " from \($0)" } ?? ""
        optionsQuery = "\(label) \(Self.clock(plan.epochSec))\(stop)"
        options = []
        optionTrips = []
        optionsError = ""
        if fixture {
            guard let trip = kotlinTrip else { return }
            let later = TransitTripFixtures.shared.shifted(trip: trip, minutes: Int32(fixtureMinutes))
            options = TransitTrip.shared.options(trips: later).map(TripOptionRow.init)
            optionsQuery += " · fixture, display only"
            optionsLoading = false
            return
        }
        guard let route = session?.route else {
            notice = "Transitous needs an open trip search to re-plan."
            return
        }
        optionsLoading = true
        awaitingOptions = true
        route.setTime(mode: plan.timeMode, epochSec: plan.epochSec)
        // The chosen time may repeat an earlier query, in which case setTime does not re-route.
        route.retry()
    }

    /// Picks one of the new answers. RouteStore selects the same index, so the detail sheet and
    /// this screen then show the same itinerary.
    func selectOption(_ index: Int) {
        guard index >= 0, index < optionTrips.count else { return }
        guard !fixture else {
            notice = "The fixture option set is display only."
            return
        }
        session?.route.select(index: Int32(index))
        open(trip: optionTrips[index])
    }

    // MARK: Via alternatives

    /// Offers the intermediate stops of the selected ride. Nothing is sent yet: the user picks one
    /// first, so one tap is one `plan` call.
    func offerVia() {
        notice = ""
        viaError = ""
        viaOptions = []
        viaTrips = []
        viaQuery = ""
        viaName = ""
        guard let trip = kotlinTrip, selectedSegment >= 0, selectedSegment < kotlinSegments.count else {
            notice = "Pick a segment first."
            return
        }
        let segment = kotlinSegments[selectedSegment]
        guard segment.kind == "RIDE" else {
            notice = "Only a ride can be routed through an intermediate stop."
            return
        }
        let candidates = TransitAlternatives.shared.candidates(trip: trip, segment: segment)
        viaCandidates = candidates.enumerated().map { TripViaCandidate($0.element, index: $0.offset) }
        if candidates.isEmpty {
            viaError = "Transitous listed no intermediate stop for this ride, so there is no via search to make."
        }
    }

    /// Asks the planner to pass through the chosen stop. The trip at the top keeps its own times;
    /// the answer becomes a separate option set, as a shifted departure does.
    func requestVia(_ candidate: TripViaCandidate) {
        notice = ""
        viaError = ""
        viaOptions = []
        viaTrips = []
        viaName = candidate.name
        guard let trip = kotlinTrip, selectedSegment >= 0, selectedSegment < kotlinSegments.count else {
            viaError = "Pick a ride first."
            return
        }
        let segment = kotlinSegments[selectedSegment]
        if fixture {
            let later = TransitTripFixtures.shared.via(trip: trip)
            viaTrips = later
            viaOptions = TransitTrip.shared.options(trips: later).map(TripOptionRow.init)
            viaQuery = "Via \(candidate.name) · fixture, display only"
            viaLoading = false
            return
        }
        guard let service else {
            viaError = "Transitous needs an open trip search to re-plan."
            return
        }
        viaLoading = true
        Task { @MainActor [weak self] in
            let answer = try? await service.viaOptions(trip: trip, segment: segment, candidate: candidate.kotlin)
            guard let self else { return }
            self.viaLoading = false
            guard let answer else {
                self.viaError = "Transitous did not answer for a route through \(candidate.name). The trip above is unchanged."
                return
            }
            self.viaTrips = answer.trips
            self.viaOptions = answer.options.map(TripOptionRow.init)
            self.viaQuery = answer.query
            if self.viaOptions.isEmpty {
                self.viaError = "No option passes through \(candidate.name). The trip above is unchanged."
            }
        }
    }

    /// Picks a via option. The trip screen opens it at once and the detail sheet follows through
    /// `onAdopt`, so the two surfaces never show different itineraries.
    func selectViaOption(_ index: Int) {
        guard index >= 0, index < viaTrips.count else { return }
        guard !fixture else {
            notice = "The fixture via option set is display only."
            return
        }
        let chosen = viaTrips[index]
        let name = viaName
        let query = viaQuery
        onAdopt?(chosen)
        open(trip: chosen)
        viaName = name
        viaQuery = query
        notice = "Via option selected. The trip and the detail sheet show the same itinerary."
    }

    private func applyRoute(_ state: RouteState) {
        timeMode = Int32(state.timeMode)
        timeEpoch = Int64(state.timeEpoch)
        guard awaitingOptions else { return }
        guard state.modeName == "TRANSIT" else {
            awaitingOptions = false
            optionsLoading = false
            optionsError = "The trip search is closed."
            return
        }
        guard !state.loading else {
            optionsLoading = true
            return
        }
        awaitingOptions = false
        optionsLoading = false
        optionTrips = state.transit
        options = TransitTrip.shared.options(trips: state.transit).map(TripOptionRow.init)
        if options.isEmpty {
            optionsError = "No option at that time. The trip above is unchanged."
        }
    }

    // MARK: Live progression

    private func applyTransit(_ state: TransitState) {
        guard state.active, !state.arrived else {
            progress = state.arrived ? 1.0 : -1
            progressText = state.arrived ? "Arrived" : ""
            return
        }
        progress = state.progress
        let current = state.current()
        let line = current?.line ?? ""
        let index = Int(state.legIndex) + 1
        progressText = line.isEmpty
            ? "Leg \(index) of \(state.legs.count)"
            : "Leg \(index) of \(state.legs.count) · \(line)"
    }

    // MARK: Debug

    var debugLine: String {
        "trip=\(trip == nil ? 0 : 1) segments=\(segments.count)"
            + " rides=\(segments.filter(\.isRide).count)"
            + " header=\(header?.departures.count ?? -1)"
            + " available=\(header?.available == true ? 1 : 0)"
            + " nearby=\(nearby.count)"
            + " options=\(options.count) skipped=\(skippedSegment >= 0 ? 1 : 0)"
            + " shift=\(optionsQuery.isEmpty ? 0 : 1)"
            + " anchor=\(anchorSource.isEmpty ? "none" : anchorSource)"
            + " fixture=\(fixture ? 1 : 0) progress=\(progress >= 0 ? 1 : 0)"
            + " via=\(viaOptions.count) viacand=\(viaCandidates.count)"
            + " error=\(optionsError.isEmpty ? "none" : "set")"
    }

    private static func clock(_ epochSec: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(epochSec))
            .formatted(date: .omitted, time: .shortened)
    }
}
