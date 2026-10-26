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

    private let session: MapSession?
    private let location: CoreLocationPipeline?
    private let activities: TransitActivityController
    private var observing: Task<Void, Never>?
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
