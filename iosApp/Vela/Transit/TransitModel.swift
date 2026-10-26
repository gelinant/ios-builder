import CoreLocation
import Foundation
import UIKit
import VelaCore

/// SwiftUI's mirror of the process-owned TransitSession. The session owns progression; this model
/// forwards Core Location fixes, renders its map line and publishes ActivityKit snapshots.
final class TransitModel: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var hasRun = false
    @Published private(set) var arrived = false
    @Published private(set) var destinationName = ""
    @Published private(set) var content: TransitActivityAttributes.ContentState?
    @Published private(set) var activityActive = false
    @Published private(set) var activityEnabled = false
    @Published private(set) var activityRequests = 0
    @Published private(set) var activityUpdates = 0
    @Published private(set) var activityEnds = 0
    @Published private(set) var activityError = false

    /// The open stop board, copied from `TransitBoardStore.state`; nil while closed.
    @Published private(set) var boardName = ""
    @Published private(set) var boardLines: [StopBoardLine] = []
    @Published private(set) var boardOpenState = false
    @Published private(set) var boardLoading = false
    @Published private(set) var boardStale = false
    @Published private(set) var boardError: String?
    @Published private(set) var boardFetchedAt: Date?
    /// Transitous stop pins around the viewport, empty below z15.
    @Published private(set) var stopMarkers: [TransitStopMarker] = []
    /// The transit options of the open chooser, mirrored from `RouteStore`.
    @Published private(set) var timeMode = 0
    @Published private(set) var timeEpoch: Int64 = 0
    @Published private(set) var prefersBus = false
    @Published private(set) var prefersSubway = false
    @Published private(set) var prefersTrain = false
    @Published private(set) var prefersTram = false
    @Published private(set) var routePreference = 0
    @Published private(set) var tripLoading = false
    /// The selected itinerary in detail, only while the chooser shows its steps.
    @Published private(set) var detail: TransitDetail?

    private let session: MapSession?
    private let location: CoreLocationPipeline?
    private let activities: TransitActivityController
    private var observing: Task<Void, Never>?
    private var boardObservation: Task<Void, Never>?
    private var stopsObservation: Task<Void, Never>?
    private var routeObservation: Task<Void, Never>?
    private weak var map: MapController?
    private var shownSessionId: Int64 = -1

    init(
        session: MapSession?,
        location: CoreLocationPipeline? = nil,
        activities: TransitActivityController? = nil
    ) {
        self.session = session
        self.location = location
        self.activities = activities ?? TransitActivityController()
    }

    func start() {
        guard observing == nil else { return }
        activities.start()
        syncActivityDebug()
        location?.onTransitFix = { [weak self] fix in
            #if DEBUG
            if LaunchOptions.current.transitFixture { return }
            #endif
            let accuracy = fix.horizontalAccuracy >= 0 ? fix.horizontalAccuracy : Double.nan
            self?.session?.transit.onLocation(
                lat: fix.coordinate.latitude,
                lng: fix.coordinate.longitude,
                accuracyM: accuracy)
        }
        location?.start()
        guard let store = session?.transit else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
        if let board = session?.board {
            boardObservation = Task { @MainActor [weak self] in
                for await state in board.state {
                    self?.applyBoard(state)
                }
            }
        }
        if let stops = session?.stops {
            stopsObservation = Task { @MainActor [weak self] in
                for await state in stops.state {
                    self?.stopMarkers = state.stops.map(Self.marker)
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
    }

    func attach(map: MapController) {
        self.map = map
        if active { showLine() }
    }

    /// The production Start action uses the selected Transitous itinerary held by RouteStore.
    func startIfAvailable() {
        _ = session?.startTransit()
    }

    #if DEBUG
    /// UI-test hook: starts the recorded San Francisco itinerary without a network dependency.
    func startFixture() {
        guard let session else { return }
        if session.transit.start(trip: TransitPreview.shared.sf, destinationName: "Ferry Building") {
            session.route.close()
        }
    }
    #endif

    func advanceForPreview() {
        session?.transit.advanceForPreview()
    }

    func stop() {
        session?.transit.end()
    }

    // MARK: Stop boards

    var boardOpen: Bool { boardOpenState }

    private func applyBoard(_ state: TransitBoardState) {
        boardOpenState = state.open
        boardName = state.stopName
        boardLoading = state.loading
        boardStale = state.refreshFailed
        boardError = state.error
        boardFetchedAt = state.fetchedAtMillis > 0
            ? Date(timeIntervalSince1970: TimeInterval(state.fetchedAtMillis) / 1000)
            : nil
        boardLines = state.lines.enumerated().map { index, line in
            StopBoardLine(
                id: "\(index)|\(line.label ?? "?")|\(line.headsign ?? "")|\(line.mode)",
                label: line.label,
                mode: line.mode,
                headsign: line.headsign,
                color: line.color,
                departures: line.departures.map { departure in
                    StopBoardDeparture(
                        id: departure.epochSec,
                        clockText: departure.clockText,
                        epochSec: Int64(departure.epochSec),
                        realtime: departure.realtime,
                        minutes: Int(departure.minutes),
                        tripId: departure.tripId)
                })
        }
    }

    /// A tapped basemap transit label or a place: resolve the stop group by its coordinate.
    func openBoard(latitude: Double, longitude: Double, name: String) {
        session?.board.open(lat: latitude, lng: longitude, name: name)
    }

    /// A tapped Transitous stop icon: query its own stop id so a hub's parent station is used.
    func openBoard(for stop: TransitStopMarker) {
        session?.board.openStop(
            stopId: stop.id, name: stop.name, lat: stop.latitude, lng: stop.longitude,
            modes: stop.modes, parentId: stop.parentId, siblingIds: stop.siblingIds)
    }

    func refreshBoard() {
        session?.board.refresh()
    }

    func closeBoard() {
        session?.board.close()
    }

    func viewportChanged(_ viewport: MapViewport) {
        session?.stops.viewport(
            south: viewport.south, west: viewport.west, north: viewport.north,
            east: viewport.east, zoom: viewport.zoom)
    }

    func clearStops() {
        session?.stops.clear()
    }

    // MARK: Transit options

    /// 0 leave now, 1 depart at, 2 arrive by; [epochSec] is ignored for leave now.
    func setTimeMode(_ mode: Int, epochSec: Int64) {
        session?.route.setTime(mode: Int32(mode), epochSec: epochSec)
    }

    func setVehicles(bus: Bool, subway: Bool, train: Bool, tram: Bool) {
        session?.route.setTransitPreferFlags(bus: bus, subway: subway, train: train, tram: tram)
    }

    /// 0 best, 2 fewer transfers, 3 less walking (the planner reorders, it does not filter).
    func setRoutePreference(_ pref: Int) {
        session?.route.setTransitRoutePreference(pref: Int32(pref))
    }

    func refreshTrips() {
        session?.route.retry()
    }

    private func applyRoute(_ state: RouteState) {
        timeMode = Int(state.timeMode)
        timeEpoch = Int64(state.timeEpoch)
        prefersBus = state.prefersBus
        prefersSubway = state.prefersSubway
        prefersTrain = state.prefersTrain
        prefersTram = state.prefersTram
        routePreference = Int(state.transitRoutePref)
        tripLoading = state.loading
        guard state.modeName == "TRANSIT", state.showSteps, state.activeTransit >= 0,
              Int(state.activeTransit) < state.transit.count else {
            detail = nil
            return
        }
        detail = TransitDetail(state.transit[Int(state.activeTransit)])
    }

    private static func marker(_ stop: TransitStopPin) -> TransitStopMarker {
        TransitStopMarker(
            id: stop.stopId, name: stop.name,
            latitude: stop.latitude, longitude: stop.longitude,
            modes: stop.modes, parentId: stop.parentId, siblingIds: stop.siblingIds)
    }

    /// `UITEST`/summary counts for the stop board even when no line is drawn on screen.
    var boardDebugLine: String {
        guard boardOpenState else { return "board=0" }
        let deps = boardLines.reduce(0) { $0 + $1.departures.count }
        let live = boardLines.reduce(0) { total, line in total + line.departures.filter(\.realtime).count }
        let soon = boardLines.compactMap { $0.departures.first?.minutes }.min() ?? -1
        return "board=1 loading=\(boardLoading ? 1 : 0) lines=\(boardLines.count)"
            + " deps=\(deps) live=\(live)"
            + " soon=\(soon) stale=\(boardStale ? 1 : 0)"
            + " error=\(boardError ?? "none")"
            + " name=\(boardName.isEmpty ? "-" : "set")"
    }

    var optionsDebugLine: String {
        "options time=\(timeMode) epoch=\(timeEpoch) bus=\(prefersBus ? 1 : 0)"
            + " subway=\(prefersSubway ? 1 : 0) train=\(prefersTrain ? 1 : 0) tram=\(prefersTram ? 1 : 0)"
            + " pref=\(routePreference) loading=\(tripLoading ? 1 : 0) legs=\(detail?.legs.count ?? 0)"
            + " alerts=\(detail?.alerts.count ?? 0)"
    }

    var debugLine: String {
        let state = content
        return "transit=\(active ? 1 : 0) active=\(active ? 1 : 0) arrived=\(arrived ? 1 : 0)"
            + " leg=\(state?.legIndex ?? -1) legs=\(state?.legCount ?? 0) stops=\(state?.stopsRemaining ?? -1)"
            + " boarded=\(state?.boarded == true ? 1 : 0) delay=\(state?.delayMinutes ?? 0)"
            + " activity=\(activityActive ? 1 : 0) actenabled=\(activityEnabled ? 1 : 0)"
            + " actrequests=\(activityRequests) actupdates=\(activityUpdates) actended=\(activityEnds)"
            + " acterror=\(activityError ? 1 : 0)"
            + " background=\(location?.backgroundUpdatesEnabled == true ? 1 : 0)"
    }

    private func apply(_ state: TransitState) {
        let wasActive = active
        active = state.active
        if state.sessionId > 0 { hasRun = true }
        arrived = state.arrived
        destinationName = state.destinationName
        let input = TransitActivityInput(state)
        let sample = TransitActivityStateMapper.map(input)
        content = state.active ? sample.content : nil
        activities.publish(input)
        syncActivityDebug()
        location?.setTransitActive(state.active && !state.arrived)

        if state.active, shownSessionId != input.sessionId {
            showLine()
        } else if !state.active && wasActive {
            map?.clearRoutes()
            shownSessionId = -1
        }
    }

    private func syncActivityDebug() {
        activityActive = activities.hasActivity
        activityEnabled = activities.activitiesEnabled
        activityRequests = activities.requestCount
        activityUpdates = activities.updateCount
        activityEnds = activities.endCount
        activityError = activities.requestFailed
    }

    private func showLine() {
        guard let store = session?.transit else { return }
        let coordinates = Self.coordinates(store.line())
        guard !coordinates.isEmpty else { return }
        shownSessionId = Int64(store.state.value.sessionId)
        map?.showRoutes(
            [RouteLine(index: 0, coordinates: coordinates, traffic: [])],
            selected: 0,
            fit: true,
            insets: UIEdgeInsets(top: 170, left: 40, bottom: 260, right: 40))
    }

    private static func coordinates(_ flat: KotlinDoubleArray) -> [CLLocationCoordinate2D] {
        let count = Int(flat.size) / 2
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            out.append(CLLocationCoordinate2D(
                latitude: flat.get(index: Int32(index * 2)),
                longitude: flat.get(index: Int32(index * 2 + 1))))
        }
        return out
    }
}
