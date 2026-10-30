import CoreLocation
import Foundation
import UIKit
import VelaCore

/// The line sheet's SwiftUI state, mirrored from `TransitLineStore`. Everything shown comes from
/// the feed: the stop order and times from `/api/v1/trip`, the departures and the transfers from
/// the stop's board, the color from `routeColor` or the mode color. In a Debug UI test it answers
/// from `TransitLineFixtures` and never touches the network.
@MainActor
final class TransitLineModel: ObservableObject {
    @Published private(set) var label = ""
    @Published private(set) var mode = ""
    @Published private(set) var direction = ""
    @Published private(set) var directions: [String] = []
    @Published private(set) var stopName = ""
    @Published private(set) var colorHex = "#5f6368"
    @Published private(set) var colorSource = "mode"
    @Published private(set) var live = false
    @Published private(set) var fromName = ""
    @Published private(set) var toName = ""
    @Published private(set) var departures: [TransitLineDeparture] = []
    @Published private(set) var stops: [TransitLineStop] = []
    @Published private(set) var position: TransitLinePosition?
    @Published private(set) var transfers: [TransitLineBadge] = []
    @Published private(set) var shape: [LatLng] = []
    @Published private(set) var shapeSource = "stops"
    @Published private(set) var sequenceUnavailable = false
    @Published private(set) var loading = false
    @Published private(set) var errorKey: String?
    @Published private(set) var fetchedAt: Int64 = 0
    @Published private(set) var fixture = false
    @Published private(set) var mapSent = false
    @Published private(set) var revision: Int32 = 0

    private let request: TransitLineRequest
    private let store: TransitLineStore?
    private var observation: Task<Void, Never>?
    private var started = false

    init(request: TransitLineRequest, service: TransitLineService?) {
        self.request = request
        #if DEBUG
        let onFixture = ProcessInfo.processInfo.arguments.contains("-VelaTransitLineFixture")
        #else
        let onFixture = false
        #endif
        fixture = onFixture
        if onFixture {
            store = TransitLineFixtures.shared.store()
        } else {
            store = service?.store
        }
    }

    /// Starts the observation, then opens the line at the stop the calling surface named. One
    /// board request and one run request; nothing refreshes on a timer.
    func start() {
        guard !started else { return }
        started = true
        guard let store else {
            errorKey = "no_service"
            return
        }
        observation = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
        let stop = request.stop
        store.open(
            target: TransitLineTarget(
                label: request.line,
                direction: request.direction,
                stopId: stop?.stopId,
                parentId: stop?.parentId,
                stopName: stop?.name ?? "",
                lat: stop?.latitude ?? 0,
                lng: stop?.longitude ?? 0,
                siblingIds: stop?.siblingIds ?? [],
                modes: []),
            direction: request.direction)
    }

    func selectDirection(_ value: String) {
        store?.selectDirection(direction: value)
    }

    func refresh() {
        store?.refresh()
    }

    func close() {
        observation?.cancel()
        observation = nil
        store?.close()
    }

    /// Sends the whole line to the map through the one hook the map layer listens to. The request
    /// carries the feed's shape when there is one, the ordered stops, and the estimated position.
    /// No map file is touched here.
    func sendWholeLineToMap() {
        guard !stops.isEmpty else { return }
        let stopPoints = stops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let shapePoints = shape.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        let request = TransitLineMapRequest(
            label: label,
            direction: direction,
            colorHex: colorHex,
            colorSource: colorSource,
            live: live,
            estimated: position?.estimated == true,
            shapeSource: shapeSource,
            stops: stopPoints,
            shape: shapePoints.count >= 2 ? shapePoints : stopPoints,
            vehicle: vehicleCoordinate(),
            fraction: position?.fraction ?? 0,
            stopNames: stops.map { $0.name })
        TransitLineLink.shared.publish(request)
        mapSent = true
    }

    /// The interpolated point between the two calls that bracket the clock, never a GPS fix.
    private func vehicleCoordinate() -> CLLocationCoordinate2D? {
        guard let position, stops.count >= 1 else { return nil }
        let fromIndex = min(max(Int(position.fromIndex), 0), stops.count - 1)
        let toIndex = min(max(Int(position.toIndex), 0), stops.count - 1)
        let from = stops[fromIndex]
        let to = stops[toIndex]
        let fraction = position.fraction
        return CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * fraction)
    }

    private func apply(_ state: TransitLineState) {
        label = state.label
        mode = state.mode
        direction = state.direction
        directions = state.directions
        stopName = state.stopName
        colorHex = state.colorHex
        colorSource = state.colorSource
        live = state.live
        fromName = state.fromName
        toName = state.toName
        departures = state.departures
        stops = state.stops
        position = state.position
        transfers = state.transfers
        shape = state.shape
        shapeSource = state.shapeSource
        sequenceUnavailable = state.sequenceUnavailable
        loading = state.loading
        errorKey = state.error
        fetchedAt = state.fetchedAtMillis
        revision = state.revision
    }

    // MARK: Presentation helpers

    var color: UIColor { UIColor(transitHex: colorHex) ?? .systemBlue }

    var colorSourceNote: String {
        colorSource == "feed"
            ? "Agency color, from the feed"
            : "Vela mode color: the feed sent none for this line"
    }

    var countdownReference: Int64 { fetchedAt > 0 ? fetchedAt / 1000 : Int64(Date().timeIntervalSince1970) }

    /// "Now" / "2 min" from the moment the feed answered, not from the device clock, so a
    /// screenshot and the sheet agree with the times the feed sent.
    func minutesText(_ departure: TransitLineDeparture) -> String {
        let seconds = departure.epochSec - countdownReference
        if seconds <= 30 { return "Now" }
        let minutes = Int((seconds + 59) / 60)
        return minutes <= 1 ? "1 min" : "\(minutes) min"
    }

    func clockText(_ departure: TransitLineDeparture) -> String {
        guard departure.epochSec > 0 else { return "" }
        return Date(timeIntervalSince1970: TimeInterval(departure.epochSec))
            .formatted(date: .omitted, time: .shortened)
    }

    var debugLine: String {
        let color = colorSource == "feed"
            ? colorHex.replacingOccurrences(of: "#", with: "").lowercased()
            : "mode"
        return "line_stops=\(stops.count) line_color=\(color) line_source=\(colorSource)"
            + " line_estimated=\(position?.estimated == true ? 1 : 0) line_live=\(live ? 1 : 0)"
            + " line_fixture=\(fixture ? 1 : 0) line_seq=\(sequenceUnavailable ? 0 : 1)"
    }
}
