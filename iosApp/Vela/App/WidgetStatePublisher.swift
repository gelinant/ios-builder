import CoreLocation
import Foundation
import OSLog
import VelaCore
import WidgetKit

/// Writes the Home Screen widget payload from the app's own stores. It reads the Kotlin state
/// flows directly so no SwiftUI screen has to be open, and it never makes a network request: a
/// board carries the update time the feed reported, and the distance carries the fix time.
@MainActor
final class WidgetStatePublisher {
    static let shared = WidgetStatePublisher()

    private let log = Logger(subsystem: "app.vela.ios", category: "widgets")
    private var store: WidgetSnapshotStore?
    private var savedObservation: Task<Void, Never>?
    private var boardObservation: Task<Void, Never>?
    private var parking: WidgetParking?
    private var board: WidgetBoard?
    private var location: WidgetSnapshot.WidgetLocation?
    private var last: WidgetSnapshot?
    private var started = false

    private init() {}

    /// AppGraph builds the session off the main actor; the publisher itself is main-actor bound.
    nonisolated static func startPublishing(session: MapSession) {
        Task { @MainActor in
            WidgetStatePublisher.shared.start(session: session)
        }
    }

    /// Called once from AppGraph after the session exists. Restoring the previous payload keeps a
    /// board visible when the app starts before its owner opens the board again.
    func start(session: MapSession) {
        guard !started else { return }
        started = true
        store = WidgetSnapshotStore.shared
        let existing = store?.load()
        parking = existing?.parking
        board = existing?.board
        location = existing?.location
        last = existing
        if store == nil {
            log.error("App Group \(WidgetSnapshotStore.appGroupID, privacy: .public) is unavailable; widgets stay empty")
        }
        savedObservation = Task { @MainActor [weak self, saved = session.saved] in
            for await state in saved.state {
                self?.applySaved(state)
            }
        }
        boardObservation = Task { @MainActor [weak self, board = session.board] in
            for await state in board.state {
                self?.applyBoard(state)
            }
        }
        // A new fix may have arrived between the previous write and this launch.
        refreshLocation()
        publish()
    }

    private func applySaved(_ state: SavedState) {
        parking = state.parking.flatMap { spot in
            WidgetSnapshotBuilder.parking(
                latitude: spot.lat,
                longitude: spot.lng,
                savedAt: Date(timeIntervalSince1970: TimeInterval(spot.savedAtMillis) / 1000))
        }
        refreshLocation()
        publish()
    }

    private func applyBoard(_ state: TransitBoardState) {
        // A closed board keeps the previous payload: the widget then shows the last stop and its
        // honest update time instead of forgetting it.
        guard state.open, !state.stopName.isEmpty else { return }
        let fetchedAt = state.fetchedAtMillis > 0
            ? Date(timeIntervalSince1970: TimeInterval(state.fetchedAtMillis) / 1000)
            : nil
        let lines = state.lines.map { line in
            WidgetBoardLine(
                label: line.label,
                mode: line.mode,
                headsign: line.headsign,
                color: line.color,
                departures: line.departures.map {
                    WidgetDeparture(
                        epochSec: Int64($0.epochSec),
                        realtime: $0.realtime,
                        clockText: $0.clockText)
                })
        }
        board = WidgetSnapshotBuilder.board(
            stopName: state.stopName,
            latitude: state.latitude,
            longitude: state.longitude,
            fetchedAt: fetchedAt,
            offline: state.offline,
            refreshFailed: state.refreshFailed,
            lines: lines,
            now: Date())
        publish()
    }

    /// Reads the fix the app already holds. The widget never asks Core Location for a new one, and
    /// the fix timestamp travels in the payload so the distance can refuse to be old.
    private func refreshLocation() {
        guard let fix = AppGraph.location.lastKnownFix(maxAge: WidgetSnapshot.WidgetLocation.maxAge),
              fix.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(fix.coordinate) else { return }
        location = WidgetSnapshot.WidgetLocation(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            fixedAt: fix.timestamp)
    }

    private func publish() {
        guard let store else { return }
        let snapshot = WidgetSnapshot(
            parking: parking,
            board: board,
            location: location,
            writtenAt: Date())
        if let last, last.sameContent(as: snapshot) { return }
        guard store.save(snapshot) else {
            log.error("Widget payload could not be encoded")
            return
        }
        last = snapshot
        WidgetCenter.shared.reloadTimelines(ofKind: "VelaParking")
        WidgetCenter.shared.reloadTimelines(ofKind: "VelaDepartures")
    }
}
