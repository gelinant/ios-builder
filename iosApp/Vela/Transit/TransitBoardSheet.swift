import Foundation
import SwiftUI
import UIKit
import VelaCore

/// One departure of the stop board. [minutes] is a snapshot taken when the feed answered; the
/// view recomputes the countdown from [epochSec] so it keeps moving between 30 s refreshes.
struct StopBoardDeparture: Identifiable, Equatable {
    let id: Int64
    let clockText: String?
    let epochSec: Int64
    let realtime: Bool
    let minutes: Int
    let tripId: String?

    func minutesFrom(_ now: Date) -> Int {
        let seconds = TimeInterval(epochSec) - now.timeIntervalSince1970
        if seconds <= 0 { return 0 }
        return Int((seconds + 59) / 60)
    }
}

/// One line and direction of the board, with its colored pill and next departures.
struct StopBoardLine: Identifiable, Equatable {
    let id: String
    let label: String?
    let mode: String
    let headsign: String?
    let color: String?
    let departures: [StopBoardDeparture]
}

/// The next departures at a tapped stop. Transitous is the only source; a miss says so instead of
/// showing invented times. The sheet refreshes every 30 s from the store and on demand.
struct TransitBoardSheet: View {
    @ObservedObject var model: TransitModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var time: TimeChoiceModel

    init(model: TransitModel) {
        _model = ObservedObject(wrappedValue: model)
        _time = StateObject(wrappedValue: TimeChoiceModel(
            mode: Int32(model.timeMode),
            epochSec: model.timeEpoch,
            ids: .board,
            onApply: { mode, epoch in
                model.setTimeMode(Int(mode), epochSec: epoch)
                model.refreshBoard()
            }))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        whenSection
                        if model.boardLoading && model.boardLines.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Loading departures")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                        } else if model.boardLines.isEmpty {
                            emptyState
                        } else {
                            if model.boardOffline {
                                Label(
                                    "Offline, from \(offlineTime)",
                                    systemImage: "wifi.slash")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .accessibilityIdentifier("transit-board-offline")
                            } else if model.boardStale {
                                Text("The last board is shown. Refresh failed.")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                    .accessibilityIdentifier("transit-board-stale")
                            }
                            ForEach(model.boardLines) { line in
                                lineRow(line, now: context.date)
                            }
                        }
                        if let fetched = model.boardFetchedAt {
                            Text(model.boardOffline
                                ? "Saved \(fetched.formatted(date: .omitted, time: .shortened))"
                                : "Updated \(fetched.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(model.boardOffline
                            ? "These departures come from the last saved board. They are not live."
                            : "Times and live marks come from the Transitous open feed.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(model.boardName.isEmpty ? "Departures" : model.boardName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        model.closeBoard()
                        dismiss()
                    }
                    .accessibilityIdentifier("transit-board-close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refreshBoard()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("transit-board-refresh")
                }
            }
            .accessibilityIdentifier("transit-board")
        }
        .onAppear {
            time.sync(mode: Int32(model.timeMode), epochSec: model.timeEpoch)
        }
        .onChange(of: model.timeMode) { _, _ in
            time.sync(mode: Int32(model.timeMode), epochSec: model.timeEpoch)
        }
        .onChange(of: model.timeEpoch) { _, epoch in
            time.sync(mode: Int32(model.timeMode), epochSec: epoch)
        }
    }

    /// The board's share of the shared control. A stop board lists what leaves next, so a future
    /// choice re-asks the board and the trip search it belongs to; the line under the buttons names
    /// the instant of that ask instead of pretending the feed took a date.
    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimeChoiceBar(model: time)
            Text("A stop board always lists the next departures. Apply re-asks the board and any open trip search; the line above gives the time of that ask.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-board-time-note")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.boardName.isEmpty ? "Transit stop" : model.boardName)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("transit-board-station")
            Text("Next departures")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            #if DEBUG
            Text(model.boardDebugLine)
                .font(.caption2.monospaced())
                .accessibilityIdentifier("transit-board-debug")
            #endif
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No departures found here")
                .font(.headline)
            Text("Transitous may not cover this stop, or the feed may be unreachable.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("transit-board-empty")
    }

    private func lineRow(_ line: StopBoardLine, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                TransitLinePill(label: line.label ?? modeLabel(line.mode), color: line.color)
                VStack(alignment: .leading, spacing: 2) {
                    if let headsign = line.headsign, !headsign.isEmpty {
                        Text(headsign)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(modeLabel(line.mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ForEach(line.departures) { departure in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(countdown(departure, now: now))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 64, alignment: .leading)
                    if departure.realtime {
                        Text("Live")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    } else {
                        Text("Scheduled")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let clock = departure.clockText {
                        Text(clock)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("transit-board-departure")
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        // TRANSIT-WIRE: the row (its departure times included) opens the line sheet at this stop.
        .onTapGesture { openLine(line) }
        .accessibilityAction(named: "Open the line") { openLine(line) }
        .accessibilityIdentifier("transit-board-line")
    }

    /// The line sheet's one entry point. `TransitBoardState` carries the stop's name and coordinate
    /// but not its Transitous id, so the sheet resolves the board by proximity; no value is guessed.
    private func openLine(_ line: StopBoardLine) {
        let state = AppGraph.session.board.state.value
        let name = state.stopName.isEmpty ? model.boardName : state.stopName
        guard state.latitude != 0 || state.longitude != 0 else { return }
        TransitLineLink.shared.open(
            line: line.label ?? modeLabel(line.mode),
            direction: line.headsign,
            stop: TransitLineStopRef(
                stopId: nil,
                name: name,
                latitude: state.latitude,
                longitude: state.longitude))
    }

    private var offlineTime: String {
        (model.boardCachedAt ?? model.boardFetchedAt ?? Date())
            .formatted(date: .omitted, time: .shortened)
    }

    private func countdown(_ departure: StopBoardDeparture, now: Date) -> String {
        let minutes = departure.minutesFrom(now)
        if minutes <= 0 { return "Now" }
        return "\(minutes) min"
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "BUS": return "Bus"
        case "TRAM": return "Tram"
        case "SUBWAY": return "Subway"
        case "TRAIN": return "Train"
        case "FERRY": return "Ferry"
        default: return "Transit"
        }
    }
}

/// A colored route pill that stays legible in both themes.
struct TransitLinePill: View {
    let label: String
    let color: String?

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(TransitActivityPalette.text(fill: color, explicit: nil))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(TransitActivityPalette.fill(color), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize()
    }
}
