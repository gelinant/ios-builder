import Foundation
import OSLog
import VelaCore
import WidgetKit

/// Writes the Home Screen widget payload from the app's own stores. It reads the Kotlin state
/// flows directly so no SwiftUI screen has to be open, and it never makes a network request: a
/// board is published with the update time Transitous reported to the app.
@MainActor
final class WidgetStatePublisher {
    static let shared = WidgetStatePublisher()

    private let log = Logger(subsystem: "app.vela.ios", category: "widgets")
    private var store: WidgetSnapshotStore?
    private var savedObservation: Task<Void, Never>?
    private var boardObservation: Task<Void, Never>?
    private var shortcuts: [WidgetShortcut] = []
    private var parking: WidgetParking?
    private var board: WidgetBoard?
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
        shortcuts = existing?.shortcuts ?? []
        parking = existing?.parking
        board = existing?.board
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
    }

    /// The last opened stop, also used when `vela://board` arrives from a widget tap.
    var pinnedBoard: WidgetBoard? { store?.load()?.board ?? board }

    private func applySaved(_ state: SavedState) {
        shortcuts = WidgetSnapshotBuilder.shortcuts(
            home: state.home.map { WidgetShortcut(kind: .home, name: $0.name, address: $0.address) },
            work: state.work.map { WidgetShortcut(kind: .work, name: $0.name, address: $0.address) })
        parking = state.parking.map {
            WidgetParking(
                latitude: $0.lat, longitude: $0.lng,
                savedAt: Date(timeIntervalSince1970: TimeInterval($0.savedAtMillis) / 1000))
        }
        publish()
    }

    private func applyBoard(_ state: TransitBoardState) {
        // A closed board keeps the previous payload: the widget then shows the last board and its
        // honest update time instead of forgetting the stop.
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
            refreshFailed: state.refreshFailed,
            lines: lines,
            now: Date())
        publish()
    }

    private func publish() {
        guard let store else { return }
        let snapshot = WidgetSnapshot(
            shortcuts: shortcuts, parking: parking, board: board, writtenAt: Date())
        if let last, last.shortcuts == snapshot.shortcuts,
           last.parking == snapshot.parking, last.board == snapshot.board {
            return
        }
        guard store.save(snapshot) else {
            log.error("Widget payload could not be encoded")
            return
        }
        last = snapshot
        WidgetCenter.shared.reloadAllTimelines()
    }
}
