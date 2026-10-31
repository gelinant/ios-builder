import Foundation
import UIKit
import VelaCore

/// One result row as the list and the pins show it, copied out of the Kotlin `Place`.
struct SearchRow: Identifiable, Equatable {
    /// Index in SearchStore.results, used to open the row. Stable source identities are separate.
    let id: Int
    let stableId: String
    let featureId: String?
    let name: String
    let address: String?
    let rating: Double?
    let reviewCount: Int?
    let priceText: String?
    let category: String?
    let distanceMeters: Double?
    let openNow: Bool?
    let statusText: String?
    let permanentlyClosed: Bool
    let phone: String?
    let photoURL: String?
    let isSaved: Bool
    let latitude: Double
    let longitude: Double

    /// The status line as Android's cards show it: Google's own words, else a plain Open/Closed.
    var status: String? {
        if permanentlyClosed { return "Permanently closed" }
        if let text = statusText, !text.isEmpty { return text }
        switch openNow {
        case true: return "Open"
        case false: return "Closed"
        case nil: return nil
        }
    }

    /// Green when open, red when closed or dead, as on Android.
    var statusIsPositive: Bool { !permanentlyClosed && openNow != false }

    /// Google, one star, the count, then distance, price and kind, cut when the card is narrow.
    var summary: String {
        var parts: [String] = []
        if let count = reviewCount { parts.append("(\(count))") }
        if let meters = distanceMeters { parts.append(SearchRow.distance(meters)) }
        if let price = priceText, !price.isEmpty { parts.append(price) }
        if let category, !category.isEmpty { parts.append(category) }
        return parts.joined(separator: " · ")
    }

    /// What VoiceOver reads for the card: the same facts the eye sees, not a debug line.
    var accessibilityLabel: String {
        var parts = [name]
        if let rating { parts.append(String(format: "%.1f stars", rating)) }
        if let count = reviewCount { parts.append("\(count) reviews") }
        if let status { parts.append(status) }
        if let meters = distanceMeters { parts.append(SearchRow.distance(meters)) }
        if let address, !address.isEmpty { parts.append(address) }
        if let price = priceText, !price.isEmpty { parts.append(price) }
        if let category, !category.isEmpty { parts.append(category) }
        return parts.joined(separator: ", ")
    }

    /// Debug UI tests can prove source-id, feature-id and location deduplication through XCUI.
    var debugAccessibilityValue: String {
        "\(stableId)|\(featureId ?? "")|\(address ?? "")|\(latitude)|\(longitude)"
    }

    static func distance(_ meters: Double) -> String {
        let imperial = AppGraph.session.settings?.imperial
            ?? (Locale.current.measurementSystem == .us)
        if imperial {
            let feet = meters * 3.28084
            if feet < 1000 { return "\(Int((feet / 10).rounded() * 10)) ft" }
            return String(format: "%.1f mi", meters / 1609.344)
        }
        if meters < 1000 { return "\(Int((meters / 10).rounded() * 10)) m" }
        return String(format: "%.1f km", meters / 1000)
    }
}

/// One autocomplete row. A nil query opens the place at the row's index; non-nil runs that search.
struct SuggestionRow: Identifiable, Equatable {
    let id: String
    let index: Int
    let name: String
    let address: String?
    let query: String?
    let latitude: Double?
    let longitude: Double?
    /// True for the leading rows backed by the user's recent or saved places.
    let local: Bool

    /// The return arrow puts this text in the box without searching, as Android does.
    var fillText: String { query ?? name }
}

/// Android's results-header sort: relevance is Google's or Photon's own order.
enum SearchSortChoice: Int, CaseIterable, Identifiable {
    case relevance = 0
    case rating = 1
    case distance = 2

    var id: Int { rawValue }
}

/// The filter sheet's values, mirrored from `SearchStore` so a NoGoogle change also clears them.
struct SearchFilterState: Equatable {
    var openNow = false
    var minRating = 0.0
    /// 0 = off, else the highest price level to keep (1 = $ .. 4 = $$$$).
    var priceMax = 0
    var accessibleOnly = false
    var sort: SearchSortChoice = .relevance

    /// Whether a local filter is on (sort alone does not change membership).
    var isActive: Bool { openNow || minRating > 0 || priceMax > 0 || accessibleOnly }
}

/// Which controls the active source can honour; the sheet draws only these.
struct SearchFilterSupportView: Equatable {
    var openNow = true
    var minRating = true
    var price = true
    var accessible = true
    var sortRating = true
    var sortDistance = true

    /// Whether any filter (not sort) survives here.
    var anyFilter: Bool { openNow || minRating || price || accessible }
}

/// The visible map, as `SearchStore.onViewport` takes it.
struct MapViewport: Equatable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
    let zoom: Double
}

/// The card and suggestion actions reach the model without changing MapScreen's call sites:
/// MapScreen.swift is serialized by the hive (BACKLOG section 3), so this lot may not add
/// parameters there. The single live model owns the handlers; the views fall back to it.
enum SearchActions {
    static weak var model: SearchModel?

    static func fill(_ row: SuggestionRow) { model?.fill(row) }
    static func directions(_ row: SearchRow) { model?.directions(row) }
    static func call(_ row: SearchRow) { model?.call(row) }
    static func toggleSave(_ row: SearchRow) { model?.toggleSave(row) }
    static func loadMore() { model?.loadMore() }
    static func searchArea() { model?.searchThisArea() }
    static func pickUnified(_ row: UnifiedRow) { model?.pickUnified(row) }
    static func searchEverywhere() { model?.searchEverywhere() }
}

/// SwiftUI's side of the Kotlin `SearchStore`: forwards the intents and mirrors the state, which
/// it reads through SKIE (`StateFlow` as an `AsyncSequence`). Main thread only.
final class SearchModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard !mirroringState else { return }
            store?.setQuery(q: query)
            // The local ranking is synchronous; the online sources wait for the same 320 ms pause.
            unified?.setQuery(text: query)
        }
    }
    @Published private(set) var rows: [SearchRow] = []
    @Published private(set) var suggestions: [SuggestionRow] = []
    @Published private(set) var searching = false
    @Published private(set) var message: String?
    @Published private(set) var usedOffline = false
    @Published private(set) var moreAvailable = false
    @Published private(set) var loadingMore = false
    /// The view moved beyond Android's pan step: the results header offers "Search this area".
    @Published private(set) var searchAreaAvailable = false
    /// Rows the merge or "More results" dropped as duplicates of a row already shown.
    @Published private(set) var droppedDuplicates = 0
    /// Accepted submissions, so a test can tell a refresh from a list that never reloaded.
    @Published private(set) var submissions = 0
    /// The filter sheet's current values; setting one goes straight to the Kotlin store.
    @Published var filters = SearchFilterState()
    /// What the active source can answer, so the sheet hides the rest and explains why.
    @Published private(set) var filterSupport = SearchFilterSupportView()
    /// The one field's other answers (UNIFIED-SEARCH): saved places, lists, stops, lines, wiki
    /// articles, settings and coordinates, ranked ahead of the online place rows.
    @Published private(set) var unifiedRows: [UnifiedRow] = []
    /// The sources that finished with nothing, so the panel says which one, not a vague "none".
    @Published private(set) var unifiedEmpty: [String] = []
    @Published private(set) var unifiedLoading = 0
    @Published private(set) var unifiedLocalMillis = 0
    @Published private(set) var unifiedDebug = ""
    /// Set by a local row; `SearchBar` presents the list, Settings or article sheet.
    @Published var unifiedDestination: UnifiedDestination?
    /// Incremented when a row takes over: `SearchBar` drops focus, as MapScreen's own blur does.
    @Published private(set) var unifiedBlurTick = 0
    /// The last typed or spoken command, and what the corridor pass found. The UI scenarios read
    /// these through the debug line; an ordinary place search leaves the fields empty.
    @Published private(set) var commandKind = ""
    /// Length of the last committed field text the parser read, for the debug line only.
    @Published private(set) var commandInputLength = 0
    @Published private(set) var contactsState = ""
    @Published private(set) var corridorMeters = 0
    @Published private(set) var corridorFound = 0
    @Published private(set) var corridorTotal = 0
    /// Where the corridor started: `progress` during a drive, `origin` otherwise.
    @Published private(set) var corridorFrom = "origin"
    /// The route length the corridor actually ran on, for the debug line and the scenario.
    @Published private(set) var corridorRouteMeters = 0
    /// The whole line the corridor read, so the scenario can compare the remaining part with it.
    @Published private(set) var corridorLineMeters = 0
    /// How far the drive had gone on that line, the figure the corridor cut at.
    @Published private(set) var corridorTraveledMeters = 0
    /// `nav`, `chooser` or `fixture`: which line the along-route command read.
    @Published private(set) var corridorSource = ""
    /// Debug fixture only: `armed`, `fired` or `-`, so a scenario can tell a hook that never
    /// started from one that ran and found no progress.
    @Published private(set) var duringNavState = ""

    private let store: SearchStore?
    private let session: MapSession?
    private var observing: Task<Void, Never>?
    private var savedObserving: Task<Void, Never>?
    private var duringNavCommand: Task<Void, Never>?
    private var mirroringState = false
    /// The Kotlin places behind [rows], for the card actions that need the whole object.
    private var places: [Place] = []

    private var unified: UnifiedSearchStore?
    private var unifiedObserving: Task<Void, Never>?
    private var stopsObserving: Task<Void, Never>?
    private var boardObserving: Task<Void, Never>?
    private var lastViewport: MapViewport?
    private var lastLocation: (lat: Double, lng: Double)?
    private var boardMemory: UnifiedBoardMemory?

    init(store: SearchStore?, session: MapSession? = AppGraph.session) {
        self.store = store
        self.session = session
        SearchActions.model = self
    }

    /// Whether there is anything for the results panel to show.
    var hasContent: Bool { searching || !rows.isEmpty || message != nil }
    var hasSuggestions: Bool { !suggestions.isEmpty || !unifiedRows.isEmpty || !unifiedEmpty.isEmpty }
    var debugLine: String {
        "offline=\(usedOffline ? 1 : 0) results=\(rows.count) suggestions=\(suggestions.count)"
            + " area=\(searchAreaAvailable ? 1 : 0) dropped=\(droppedDuplicates)"
            + " searches=\(submissions) unified=\(unifiedRows.count) ulocal=\(unifiedLocalMillis)ms"
            + " cmd_kind=\(commandKind.isEmpty ? "-" : commandKind)"
            + " cmd_len=\(commandInputLength)"
            + " cmd_contacts=\(contactsState.isEmpty ? "-" : contactsState)"
            + " cmd_corridor_m=\(corridorMeters) cmd_found=\(corridorFound) cmd_total=\(corridorTotal)"
            + " cmd_from=\(corridorFrom) cmd_route_m=\(corridorRouteMeters)"
            + " cmd_line_m=\(corridorLineMeters) cmd_traveled_m=\(corridorTraveledMeters)"
            + " cmd_line=\(corridorSource.isEmpty ? "-" : corridorSource)"
            + " cmd_hook=\(duringNavState.isEmpty ? "-" : duringNavState)"
    }

    func start() {
        SearchCommandTestSupport.prepareIfNeeded()
        guard let store, observing == nil else { return }
        // Android appends the app language's "open now" words to the Google query.
        store.setOpenNowPhrase(phrase: VelaL10n.text("search_open_now_phrase"))
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
        if let saved = session?.saved {
            applyLocalPlaces(saved.state.value)
            savedObserving = Task { @MainActor [weak self] in
                for await state in saved.state {
                    self?.applyLocalPlaces(state)
                    self?.refreshUnifiedLocal()
                }
            }
        }
        startUnified()
        armDuringNavCommand()
    }

    /// Debug scenarios only: the drive chrome has no search field, so the along-route fixture
    /// submits one command once the car has moved. It goes through `submit`, the same path the
    /// field uses, and does nothing in a normal launch or in Release.
    private func armDuringNavCommand() {
        guard duringNavCommand == nil,
              let text = SearchCommandTestSupport.duringNavCommand() else { return }
        let threshold = SearchCommandTestSupport.duringNavMeters
        duringNavState = "armed"
        duringNavCommand = Task { @MainActor [weak self] in
            // Two independent proofs of movement, so a fixture drive fires even if one figure is
            // momentarily zero: the session's monotonic progress and the drop of the remaining
            // distance it publishes. There is deliberately no time fallback: the host replay can
            // start late, and a clock would fire before the car has actually moved.
            var baseline: Double?
            while !Task.isCancelled {
                guard let self, let nav = self.session?.nav else { return }
                let state = nav.state.value
                if state.navigating, state.remainingDistanceMeters > 0 {
                    if baseline == nil { baseline = state.remainingDistanceMeters }
                    let dropped = (baseline ?? 0) - state.remainingDistanceMeters
                    if nav.traveledMeters() >= threshold || dropped >= threshold {
                        self.duringNavState = "fired"
                        self.submit(text: text, viewport: self.lastViewport)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    /// The unified store needs the core graph; a launch that could not build it keeps the plain
    /// place search, with no error shown for a feature that is only additive.
    private func startUnified() {
        guard unified == nil, let core = IosGraph.shared.core else { return }
        let unifiedStore = UnifiedSearchResources.shared
            .services(core: core, language: nil)
            .store()
        unified = unifiedStore
        refreshUnifiedLocal()
        pushUnifiedArea()
        unifiedObserving = Task { @MainActor [weak self] in
            for await state in unifiedStore.state {
                self?.applyUnified(state)
            }
        }
        if let stops = session?.stops {
            stopsObserving = Task { @MainActor [weak self] in
                for await state in stops.state {
                    _ = state
                    self?.refreshUnifiedLocal()
                }
            }
        }
        if let board = session?.board {
            boardObserving = Task { @MainActor [weak self] in
                for await state in board.state {
                    self?.rememberBoard(state)
                }
            }
        }
    }

    /// The local snapshot is small and cheap to rebuild: a few hundred rows at most.
    private func refreshUnifiedLocal() {
        guard let unified, let saved = session?.saved else { return }
        let stops = session?.stops.state.value.stops ?? []
        unified.setLocal(items: UnifiedLocalSources.items(
            saved: saved.state.value, stops: stops, board: boardMemory))
    }

    /// A stop board outlives its sheet here: its lines stay searchable after the user closes it.
    private func rememberBoard(_ state: TransitBoardState) {
        guard state.open, !state.stopName.isEmpty, !state.lines.isEmpty else { return }
        let lines = state.lines.map { line in
            UnifiedBoardLine(
                label: line.label, mode: line.mode, headsign: line.headsign, color: line.color,
                nextMinutes: line.departures.map { Int($0.minutes) })
        }
        let memory = UnifiedBoardMemory(
            name: state.stopName, latitude: state.latitude, longitude: state.longitude, lines: lines)
        guard memory != boardMemory else { return }
        boardMemory = memory
        refreshUnifiedLocal()
    }

    private func applyUnified(_ state: UnifiedState) {
        unifiedRows = state.rows.map(UnifiedRow.init)
        unifiedEmpty = state.empty
        unifiedLoading = Int(state.loading)
        unifiedLocalMillis = Int(state.localMillis)
        unifiedDebug = "unified local=\(state.localMillis)ms rows=\(state.rows.count)"
            + " loading=\(state.loading) timeouts=\(state.timedOut.isEmpty ? "-" : state.timedOut)"
            + " failed=\(state.failed.isEmpty ? "-" : state.failed) rounds=\(state.rounds)"
    }

    /// The bias and visible box the online sources may use, from the live map rather than from the
    /// viewport of the previous search.
    private func pushUnifiedArea() {
        guard let unified else { return }
        if let viewport = lastViewport {
            let lat = lastLocation?.lat ?? (viewport.south + viewport.north) / 2
            let lng = lastLocation?.lng ?? (viewport.west + viewport.east) / 2
            unified.setArea(
                nearLat: lat, nearLng: lng,
                south: viewport.south, west: viewport.west,
                north: viewport.north, east: viewport.east)
        } else if let location = lastLocation {
            unified.setArea(
                nearLat: location.lat, nearLng: location.lng,
                south: location.lat - 0.06, west: location.lng - 0.09,
                north: location.lat + 0.06, east: location.lng + 0.09)
        } else {
            unified.clearArea()
        }
    }

    func submit(viewport: MapViewport?) {
        submit(text: query, viewport: viewport)
    }

    /// Submits [text], the string the field actually committed. The command parser runs first, on
    /// that same string, so a command is never sent to Google or Photon and a plain query searches
    /// exactly the words that were typed.
    func submit(text: String, viewport: MapViewport?) {
        let committed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        update(viewport: viewport)
        // A submitted search owns the screen: the live rows under the field go away with it.
        dismissUnified()
        guard !committed.isEmpty else { return }
        if handleTypedCommand(text: committed, viewport: viewport) { return }
        query = committed
        store?.submit()
    }

    /// A query suggestion, recent query or quick category bypasses the autocomplete debounce.
    func search(_ text: String, viewport: MapViewport?) {
        update(viewport: viewport)
        dismissUnified()
        store?.search(query: text)
    }

    /// Reads the field as a command before submitting it. True means the field's words became an
    /// action and the caller must not run the plain search path; false means an ordinary query.
    func handleTypedCommand(text: String, viewport: MapViewport?) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let language = DirectionsLanguage.shared.appLanguage(tag: DevicePlatformLocale.effectiveTag())
        guard let plan = SearchCommands.shared.parse(text: text, lang: language.isEmpty ? "en" : language)
        else {
            // A phrase the parser does not know stays an ordinary search; the debug line keeps
            // its length so a truncated commit can be told apart from an unknown phrase, and the
            // previous command no longer describes the new submission.
            resetCommandState()
            commandInputLength = text.count
            return false
        }
        commandInputLength = text.count
        resetCommandState()
        switch plan.kind {
        case "home", "work":
            commandKind = plan.kind
            openShortcut(home: plan.kind == "home")
            return true
        case "directions":
            commandKind = "directions"
            guard !plan.query.trimmingCharacters(in: .whitespaces).isEmpty else {
                message = "Name where to go, for example: directions to the Ferry Building."
                return true
            }
            dismissUnified()
            update(viewport: viewport)
            query = plan.query
            Task { @MainActor [weak self] in
                await self?.navigate(to: plan.query, viewport: viewport)
            }
            return true
        case "along":
            commandKind = "along"
            dismissUnified()
            update(viewport: viewport)
            if !plan.query.isEmpty { query = plan.query }
            Task { @MainActor [weak self] in
                await self?.runAlongRoute(query: plan.query)
            }
            return true
        case "call":
            commandKind = "call"
            dismissUnified()
            if !plan.query.isEmpty { query = plan.query }
            Task { @MainActor [weak self] in
                await self?.runCall(query: plan.query)
            }
            return true
        case "search":
            commandKind = "search"
            dismissUnified()
            update(viewport: viewport)
            query = plan.query
            store?.setQuery(q: plan.query)
            store?.submit()
            return true
        default:
            // Routes and ETA belong to guidance, not to this field; keep them plain searches so a
            // typed sentence is never silently swallowed.
            resetCommandState()
            return false
        }
    }

    /// "directions to X": the ordinary search answers, then the chooser opens on its top hit, as
    /// Android's directed result and the voice dialog do.
    @MainActor
    private func navigate(to text: String, viewport: MapViewport?) async {
        guard let store else { return }
        let baseline = store.state.value.submissions
        store.search(query: text)
        guard let place = await waitForFirstResult(after: baseline, timeout: 45) else {
            message = "No result for \(text). Try a different name."
            return
        }
        session?.place.select(p: place)
        session?.route.directionsTo(p: place)
    }

    /// "search along the route with a query": one ordinary search, then the corridor pass. The
    /// route line comes from the live chooser; the Debug scenario may supply a fixed SF line so the
    /// corridor can be checked without waiting for a route calculation.
    @MainActor
    func runAlongRoute(query text: String) async {
        resetCommandState()
        commandKind = "along"
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            message = "Name what to look for along the route, for example: coffee along the route."
            return
        }
        guard let route = activeRoute() else {
            message = "Plan a route first, then search along it."
            return
        }
        guard let store else { return }
        let baseline = store.state.value.submissions
        store.search(query: q)
        let places = await waitForSearch(after: baseline, timeout: 60)
        let selection = SearchCommandCorridor.shared.selectFlat(
            places: places, routeFlat: route.line, maxMeters: 3000.0,
            traveledMeters: route.traveledMeters, startsAtCar: route.source == "nav")
        self.places = selection.places
        rebuildRows()
        corridorMeters = Int(selection.corridorMeters)
        corridorFound = Int(selection.found)
        corridorTotal = Int(selection.total)
        corridorFrom = selection.fromProgress ? "progress" : "origin"
        corridorRouteMeters = Int(selection.routeMeters)
        corridorLineMeters = Int(route.lineMeters)
        corridorTraveledMeters = Int(route.traveledMeters)
        corridorSource = route.source
        message = selection.found == 0
            ? "No place found within \(Int(selection.corridorMeters / 1000)) km of the route."
            : nil
    }

    /// "call X": asks for Contacts access at this moment only, then resolves a number. A refusal
    /// says so and falls back to the ordinary place search, so the command never ends in silence.
    @MainActor
    func runCall(query text: String) async {
        resetCommandState()
        commandKind = "call"
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            message = "Name who to call, for example: call Ada."
            return
        }
        contactsState = ContactsBridge.permission().label
        message = ContactsBridge.rationale
        let (access, match) = await ContactsBridge.resolve(name: name)
        contactsState = access.label
        guard access == .granted else {
            let baseline = store?.state.value.submissions ?? 0
            store?.search(query: name)
            _ = await waitForSearch(after: baseline, timeout: 45)
            message = "Contacts access is off, so Vela cannot call \(name). Searching Google and OpenStreetMap for \(name) instead."
            return
        }
        guard let match else {
            message = "No contact named \(name) has a phone number. Try a place search instead."
            return
        }
        guard !ContactsBridge.usesFixture else {
            message = "Calling \(match.name)."
            return
        }
        let digits = match.phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel:\(digits)"), UIApplication.shared.canOpenURL(url) else {
            message = "\(match.name)'s number cannot be dialled on this device. Try a place search instead."
            return
        }
        await UIApplication.shared.open(url)
        message = "Calling \(match.name)."
    }

    private func resetCommandState() {
        commandKind = ""
        contactsState = ""
        corridorMeters = 0
        corridorFound = 0
        corridorTotal = 0
        corridorFrom = "origin"
        corridorRouteMeters = 0
        corridorLineMeters = 0
        corridorTraveledMeters = 0
        corridorSource = ""
    }

    /// An active line, its whole length and how far the drive has already travelled along it.
    /// During navigation the live guidance route wins, so a reroute or a stop changes what "the
    /// route" means; otherwise the chooser's active line is used, exactly as before.
    private struct ActiveRoute {
        let line: KotlinDoubleArray
        let traveledMeters: Double
        let lineMeters: Double
        /// `nav`, `chooser` or `fixture`, reported by the debug line.
        let source: String
    }

    /// The live guidance line as last seen. A replan can leave the store's route unset for a
    /// frame; keeping the last drawn line means the corridor never silently reads the chooser
    /// instead of the drive.
    private var lastNavLine: KotlinDoubleArray?

    private func activeRoute() -> ActiveRoute? {
        if let nav = session?.nav {
            let state = nav.state.value
            let live = nav.line()
            if live.size >= 4 { lastNavLine = live }
            // While the car is guided, the corridor starts at the car, never at the chooser's
            // origin: a search that ran behind the driver was the bug this path exists to fix.
            let line: KotlinDoubleArray? = live.size >= 4 ? live : lastNavLine
            if state.navigating, let line {
                let meters = Self.lineMeters(line)
                let traveled = Self.traveledMeters(
                    reported: nav.traveledMeters(), state: state, lineMeters: meters)
                return ActiveRoute(
                    line: line, traveledMeters: traveled, lineMeters: meters, source: "nav")
            }
        }
        if let store = session?.route {
            let state = store.state.value
            if state.open, state.activeIndex >= 0 {
                let line = store.line(index: Int32(state.activeIndex))
                if line.size >= 4 {
                    return ActiveRoute(
                        line: line, traveledMeters: 0, lineMeters: Self.lineMeters(line),
                        source: "chooser")
                }
            }
        }
        #if DEBUG
        if let values = SearchCommandTestSupport.routeFixture() {
            let flat = KotlinDoubleArray(size: Int32(values.count))
            for (index, value) in values.enumerated() {
                flat.set(index: Int32(index), value: value)
            }
            return ActiveRoute(
                line: flat, traveledMeters: 0, lineMeters: Self.lineMeters(flat), source: "fixture")
        }
        #endif
        return nil
    }

    /// The drive's progress along [line]. Three figures describe the same travelled distance and
    /// any of them can be momentarily unset, so the largest one wins: the store's monotonic
    /// progress, the route distance it published, and the whole line minus what is left of it.
    /// Zero only before the car has moved or when the remaining distance is unknown, so a drive
    /// that has really started never reports an origin corridor.
    static func traveledMeters(
        reported: Double, state: NavUiState, lineMeters: Double
    ) -> Double {
        let remaining = state.remainingDistanceMeters
        guard remaining > 0 else { return max(0, reported) }
        let byDistance = max(0, state.routeDistanceMeters - remaining)
        let byLine = max(0, lineMeters - remaining)
        return max(max(0, reported), byDistance, byLine)
    }

    /// Length of a flat lat,lng polyline, on the same local projection the corridor uses.
    static func lineMeters(_ line: KotlinDoubleArray) -> Double {
        let slots = Int(line.size)
        guard slots >= 4 else { return 0 }
        var total = 0.0
        var index = 0
        while index + 3 < slots {
            let aLat = line.get(index: Int32(index))
            let aLng = line.get(index: Int32(index + 1))
            let bLat = line.get(index: Int32(index + 2))
            let bLng = line.get(index: Int32(index + 3))
            let mid = (aLat + bLat) / 2.0 * Double.pi / 180.0
            let dx = (bLng - aLng) * 111_320.0 * cos(mid)
            let dy = (bLat - aLat) * 111_320.0
            total += (dx * dx + dy * dy).squareRoot()
            index += 2
        }
        return total
    }

    /// Polls the same store the panel shows, so no second search path exists.
    @MainActor
    private func waitForSearch(after baseline: Int32, timeout: TimeInterval) async -> [Place] {
        guard let store else { return [] }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = store.state.value
            if state.submissions > baseline && !state.searching { return state.results }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return store.state.value.results
    }

    @MainActor
    private func waitForFirstResult(after baseline: Int32, timeout: TimeInterval) async -> Place? {
        await waitForSearch(after: baseline, timeout: timeout).first
    }

    private func openShortcut(home: Bool) {
        guard let state = session?.saved.state.value,
              let place = (home ? state.home : state.work)?.toPlace() else {
            message = home
                ? "No Home saved yet. Open Saved to set it, then ask again."
                : "No Work saved yet. Open Saved to set it, then ask again."
            return
        }
        session?.place.select(p: place)
        session?.route.directionsTo(p: place)
    }

    func clear() {
        store?.clear()
        unified?.clear()
        unifiedRows = []
        unifiedEmpty = []
        unifiedLoading = 0
        unifiedDebug = ""
        unifiedDestination = nil
        query = ""
        moreAvailable = false
        loadingMore = false
        searchAreaAvailable = false
        droppedDuplicates = 0
        submissions = 0
        filters = SearchFilterState()
        places = []
        resetCommandState()
    }

    func viewportChanged(_ v: MapViewport) {
        store?.onViewport(south: v.south, west: v.west, north: v.north, east: v.east, zoom: v.zoom)
        lastViewport = v
        pushUnifiedArea()
        // A cheap retry in case the fixture could not arm at start; a normal launch has no command.
        armDuringNavCommand()
    }

    func locationChanged(latitude: Double, longitude: Double) {
        store?.onLocation(lat: latitude, lng: longitude)
        lastLocation = (latitude, longitude)
        pushUnifiedArea()
        armDuringNavCommand()
    }

    /// The field's other answers, actioned without leaving the map where the surface lives there:
    /// a saved place opens its sheet, a stop or line the board, a coordinate a dropped pin.
    func pickUnified(_ row: UnifiedRow) {
        dismissUnified()
        switch row.kind {
        case .saved:
            guard let placeId = row.placeId else { return }
            session?.openSavedPlace(listId: row.listId, placeId: placeId)
        case .list:
            guard let listId = row.listId else { return }
            unifiedDestination = .list(id: listId, name: row.title)
        case .stop, .line:
            guard let lat = row.lat, let lng = row.lng else { return }
            session?.board.open(lat: lat, lng: lng, name: row.stopName ?? row.title)
        case .wiki:
            unifiedDestination = .wiki(row)
        case .setting:
            unifiedDestination = .settings(
                anchor: row.anchor ?? "", label: row.title, section: row.subtitle ?? "Settings")
        case .coordinate:
            guard let lat = row.lat, let lng = row.lng else { return }
            session?.mapPoi.longPress(lat: lat, lng: lng)
        case .place, .address, .query:
            // The panel routes these through MapScreen's own suggestion path.
            if let text = row.query { session?.search.search(query: text) }
        }
    }

    /// Android's "search everywhere" under the user's own rows: the same words on the place path.
    func searchEverywhere() {
        let text = query
        dismissUnified()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        update(viewport: lastViewport)
        store?.setQuery(q: text)
        store?.submit()
    }

    /// Hides the live rows and the keyboard without touching the words in the field.
    private func dismissUnified() {
        unified?.clear()
        unifiedRows = []
        unifiedEmpty = []
        unifiedLoading = 0
        suggestions = []
        store?.dismissSuggestions()
        unifiedBlurTick += 1
    }

    // MARK: - Suggestion and card actions

    /// Android's return arrow: the text lands in the box, no search runs.
    func fill(_ row: SuggestionRow) {
        query = row.fillText
    }

    /// The card's Directions: the route chooser reads the row directly, with no details fetch.
    func directions(_ row: SearchRow) {
        guard let place = place(for: row), let session else { return }
        session.route.directionsTo(p: place)
    }

    func call(_ row: SearchRow) {
        guard let phone = row.phone?.filter({ $0.isNumber || $0 == "+" }), !phone.isEmpty,
              let url = URL(string: "tel://\(phone)") else { return }
        UIApplication.shared.open(url)
    }

    /// Quick save, through the same store the place sheet uses.
    func toggleSave(_ row: SearchRow) {
        guard let session, let place = place(for: row) else { return }
        _ = session.saved.toggleSave(place: place)
        rebuildRows()
    }

    func loadMore() {
        store?.loadMore()
    }

    /// Android's "Search this area": the Kotlin store reads the live viewport, so a pan is never
    /// answered with the center of the previous search.
    func searchThisArea() {
        store?.searchThisArea()
    }

    // MARK: - Filters and sort

    func setOpenNow(_ on: Bool) { changeFilters { $0.openNow = on } }
    func setMinRating(_ value: Double) { changeFilters { $0.minRating = value } }
    func setPriceMax(_ value: Int) { changeFilters { $0.priceMax = value } }
    func setAccessibleOnly(_ on: Bool) { changeFilters { $0.accessibleOnly = on } }
    func setSort(_ sort: SearchSortChoice) { changeFilters { $0.sort = sort } }

    /// One entry point for the sheet: the store applies the filters to the answer it already holds,
    /// and re-runs the same query only when Open now changes (Android's own behaviour).
    private func changeFilters(_ change: (inout SearchFilterState) -> Void) {
        var next = filters
        change(&next)
        guard next != filters else { return }
        filters = next
        store?.setFilters(
            openNow: next.openNow,
            minRating: next.minRating,
            priceMax: Int32(next.priceMax),
            accessibleOnly: next.accessibleOnly,
            sort: Int32(next.sort.rawValue))
    }

    /// The Safari image identity the place photos use: no new Google request, the search reply
    /// already carried these URLs.
    func photoHeaders() -> [String: String] {
        var out: [String: String] = [:]
        for header in session?.photoHeaders() ?? [] {
            out[header.name] = header.value
        }
        return out
    }

    private func place(for row: SearchRow) -> Place? {
        places.first { $0.id == row.stableId }
    }

    private func update(viewport: MapViewport?) {
        guard let store, let v = viewport else { return }
        store.onViewport(south: v.south, west: v.west, north: v.north, east: v.east, zoom: v.zoom)
    }

    /// Android's own-data order: recently viewed places, then list places, then the shortlist.
    private func applyLocalPlaces(_ state: SavedState) {
        var pool: [Place] = state.recentPlaces.map { $0.place.toPlace() }
        pool += state.lists.flatMap { list in list.places.map { $0.toPlace() } }
        pool += state.saved.map { $0.toPlace() }
        store?.setLocalPlaces(places: pool)
    }

    private func apply(_ state: SearchState) {
        mirroringState = true
        if query != state.query { query = state.query }
        mirroringState = false
        searching = state.searching
        usedOffline = state.usedOffline
        moreAvailable = state.moreAvailable
        loadingMore = state.loadingMore
        if searchAreaAvailable != state.searchAreaAvailable { searchAreaAvailable = state.searchAreaAvailable }
        droppedDuplicates = Int(state.droppedDuplicates)
        submissions = Int(state.submissions)
        let mirrored = SearchFilterState(
            openNow: state.filters.openNow,
            minRating: state.filters.minRating,
            priceMax: Int(state.filters.priceMax),
            accessibleOnly: state.filters.accessibleOnly,
            sort: SearchSortChoice(rawValue: Int(state.filters.sort)) ?? .relevance)
        if filters != mirrored { filters = mirrored }
        let support = state.filterSupport
        let mirroredSupport = SearchFilterSupportView(
            openNow: support.openNow,
            minRating: support.minRating,
            price: support.price,
            accessible: support.accessible,
            sortRating: support.sortRating,
            sortDistance: support.sortDistance)
        if filterSupport != mirroredSupport { filterSupport = mirroredSupport }
        places = state.results
        rebuildRows()
        let localCount = Int(state.localSuggestionCount)
        var autocomplete = state.suggestions.enumerated().map { index, place in
            SuggestionRow(
                id: "place-\(index)", index: index, name: place.name,
                address: place.address ?? place.category, query: nil,
                latitude: place.location.lat, longitude: place.location.lng,
                local: index < localCount)
        }
        autocomplete += state.querySuggestions.enumerated().map { index, text in
            SuggestionRow(
                id: "query-\(index)", index: index, name: text, address: nil,
                query: text, latitude: nil, longitude: nil, local: false)
        }
        suggestions = autocomplete
        pushUnifiedRemote(state)
        message = Self.message(for: state.error)
    }

    /// The place and query rows the existing search answered, in the order it ranked them. The
    /// unified ranker keeps that order among online rows and drops a place a saved row already
    /// names.
    private func pushUnifiedRemote(_ state: SearchState) {
        guard let unified else { return }
        var items: [UnifiedHit] = state.suggestions.enumerated().map { index, place in
            UnifiedHits.shared.place(
                index: Int32(index), title: place.name,
                subtitle: place.address ?? place.category,
                lat: place.location.lat, lng: place.location.lng,
                featureId: place.featureId,
                address: place.category?.caseInsensitiveCompare("Address") == .orderedSame)
        }
        items += state.querySuggestions.map { UnifiedHits.shared.query(text: $0) }
        unified.setRemote(items: items)
    }

    private func rebuildRows() {
        let savedIds = Set(session?.saved.state.value.saved.map { $0.id } ?? [])
        rows = places.enumerated().map { index, place in
            SearchRow(
                id: index,
                stableId: place.id,
                featureId: place.featureId,
                name: place.name,
                address: place.address,
                rating: place.rating?.doubleValue,
                reviewCount: place.reviewCount.map { Int($0.int32Value) },
                priceText: place.priceText,
                category: place.category,
                distanceMeters: place.distanceMeters?.doubleValue,
                openNow: place.openNow?.boolValue,
                statusText: place.statusText,
                permanentlyClosed: place.permanentlyClosed,
                phone: place.phone,
                photoURL: place.photoUrls.first.map(SearchRow.sizedPhoto),
                isSaved: savedIds.contains(place.id),
                latitude: place.location.lat,
                longitude: place.location.lng)
        }
    }

    private static func message(for error: (any SearchError)?) -> String? {
        guard let error else { return nil }
        if error is SearchErrorNoResults {
            return "No results"
        }
        if error is SearchErrorNeedsRecalibration {
            return "Search needs an update: Google changed its answers"
        }
        if let failed = error as? SearchErrorFailed, let reason = failed.reason {
            return "Search failed: \(reason)"
        }
        return "Search failed"
    }
}

extension SearchRow {
    /// Google's photo host sizes on the URL suffix, as Android asks for a 400 px list cell.
    static func sizedPhoto(_ url: String) -> String {
        guard let equals = url.lastIndex(of: "=") else { return url }
        return String(url[..<equals]) + "=w400-h300"
    }
}
