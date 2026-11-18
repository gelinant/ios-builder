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
    @Environment(\.dynamicTypeSize) private var typeSize

    @StateObject private var time: TimeChoiceModel
    /// TRANSIT-CITYMAPPER: the tapped line becomes the Stops tab of this same shell. No second
    /// sheet is presented, so the board, the ribbon and the line's departures share one header.
    @State private var lineModel: TransitLineModel?
    @State private var tab: TransitShellTab = .stops
    @State private var showsTrip = false
    /// The inline line model is optional, so its changes are forwarded into this view's state.
    @State private var lineTick = 0
    @ObservedObject private var selection = EntitySelection.shared

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
        TimelineView(.periodic(from: .now, by: 15)) { context in
            TransitShell(
                header: shellHeader(now: context.date),
                tab: $tab,
                closeIdentifier: "transit-board-close",
                surfaceIdentifier: "transit-board",
                onClose: { close() },
                stops: { stopsTab(now: context.date) },
                trip: { tripTab },
                nearby: { nearbyTab(now: context.date) }
            )
        }
        .fullScreenCover(isPresented: $showsTrip) {
            if let trip = model.tripScreenTrip {
                TransitTripScreen(
                    model: model.trip,
                    destination: model.destinationName,
                    live: model.live,
                    transit: model,
                    onClose: {
                        model.trip.close()
                        showsTrip = false
                    })
                .onAppear {
                    model.trip.onAdopt = { [weak model] chosen in model?.adoptAlternative(chosen) }
                    model.trip.open(trip: trip)
                }
            }
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

    // MARK: Header

    private func shellHeader(now: Date) -> TransitShellHeader {
        _ = lineTick
        if let line = lineModel {
            return TransitShellHeader(
                label: line.label,
                colorHex: line.colorHex,
                direction: line.direction.isEmpty ? line.stopName : line.direction,
                countdown: line.departures.first.map { line.minutesText($0) } ?? "",
                subtitle: line.stopName,
                live: line.live)
        }
        let next = nextBoardDeparture(now: now)
        return TransitShellHeader(
            countdown: next,
            subtitle: model.boardName.isEmpty ? VelaL10n.text("transit_transit_stop") : model.boardName,
            live: model.boardLines.contains { $0.departures.contains { $0.realtime } })
    }

    private func nextBoardDeparture(now: Date) -> String {
        let upcoming = model.boardLines.flatMap { $0.departures }
            .filter { $0.epochSec >= Int64(now.timeIntervalSince1970) }
        guard let first = upcoming.min(by: { $0.epochSec < $1.epochSec }) else { return "" }
        let minutes = first.minutesFrom(now)
        return minutes <= 0 ? VelaL10n.text("place_transit_now")
            : VelaL10n.text("transit_min_3", String(describing: minutes))
    }

    // MARK: Stops

    private func stopsTab(now: Date) -> some View {
        let _ = lineTick
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let line = lineModel {
                    lineStops(line)
                        .onReceive(line.objectWillChange) { _ in lineTick &+= 1 }
                } else {
                    boardContent(now: now)
                }
            }
            .padding(16)
        }
    }

    private func boardContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            whenSection
            if model.boardLoading && model.boardLines.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(VelaL10n.text("transit_loading_departures"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)
            } else if model.boardLines.isEmpty {
                emptyState
            } else {
                if model.boardOffline {
                    Label(
                        VelaL10n.text("transit_offline_from", String(describing: (offlineTime))),
                        systemImage: "wifi.slash")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("transit-board-offline")
                } else if model.boardStale {
                    Text(VelaL10n.text("transit_the_last_board_is_shown_refresh"))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("transit-board-stale")
                }
                ForEach(model.boardLines) { line in
                    lineRow(line, now: now)
                }
            }
            if let fetched = model.boardFetchedAt {
                Text(model.boardOffline
                    ? VelaL10n.text("transit_saved", String(describing: (fetched.formatted(date: .omitted, time: .shortened))))
                    : VelaL10n.text("transit_updated", String(describing: (fetched.formatted(date: .omitted, time: .shortened)))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(model.boardOffline
                ? VelaL10n.text("transit_these_departures_come_from_the_last")
                : VelaL10n.text("transit_times_and_live_marks_come_from"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// The tapped line inside the same surface: a way back to the whole board, the line's next
    /// departures and its ribbon. The header above now carries the line's colour and countdown.
    private func lineStops(_ line: TransitLineModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                line.close()
                lineModel = nil
            } label: {
                Label(VelaL10n.text("transit_shell_all_lines"), systemImage: "chevron.left")
                    .frame(minHeight: Design.Size.hitTarget)
            }
            .accessibilityIdentifier("transit-board-all-lines")

            Text(line.colorSourceNote)
                .font(.caption)
                .foregroundStyle(.secondary)

            if line.departures.isEmpty {
                Text(line.loading
                    ? VelaL10n.text("transit_loading_the_line")
                    : VelaL10n.text("transit_the_feed_lists_no_departure_for"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-board-line-empty")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(line.departures.prefix(5).enumerated()), id: \.offset) { _, departure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.minutesText(departure))
                                    .font(.callout.weight(.bold).monospacedDigit())
                                Text(line.clockText(departure))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(departure.live ? VelaL10n.text("place_transit_live") : VelaL10n.text("place_transit_scheduled"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(departure.live ? Color.green : Color.secondary)
                            }
                            .padding(10)
                            .frame(minHeight: 68, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "\(line.minutesText(departure)), \(line.clockText(departure)), "
                                    + (departure.live ? "live" : "scheduled"))
                            .accessibilityIdentifier("transit-board-line-departure")
                        }
                    }
                }
            }

            if line.stops.isEmpty {
                Text(line.loading
                    ? VelaL10n.text("transit_loading_the_line")
                    : VelaL10n.text("transit_transitous_did_not_send_this_run"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("transit-line-no-sequence")
            } else {
                if line.position?.estimated == true {
                    Text(VelaL10n.text("transit_estimated_not_gps"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                TransitRouteRibbon(
                    stops: line.stops,
                    position: line.position,
                    color: Color(uiColor: line.color),
                    colorHex: line.colorHex)
            }
            Text(VelaL10n.text("transit_colors_times_and_live_marks_come"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Trip and nearby

    private var tripTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.tripScreenTrip != nil {
                Button {
                    showsTrip = true
                } label: {
                    Label(VelaL10n.text("transit_trip_view"), systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, minHeight: Design.Size.hitTarget)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("transit-board-trip-open")
            }
            TransitShellEmptyTab(
                title: VelaL10n.text("transit_shell_no_trip"),
                message: VelaL10n.text("transit_shell_board_trip_body"),
                identifier: "transit-board-no-trip")
        }
        .padding(16)
    }

    private func nearbyTab(now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(VelaL10n.text("transit_shell_other_lines"))
                    .font(.headline)
                if model.boardLines.isEmpty {
                    Text(VelaL10n.text("transit_shell_no_other_lines"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transit-board-nearby-empty")
                }
                ForEach(model.boardLines) { line in
                    nearbyRow(line)
                }
                Text(VelaL10n.text("transit_shell_other_lines_note"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }


    private func nearbyRow(_ line: StopBoardLine) -> some View {
        let label = line.label ?? modeLabel(line.mode)
        let selected = selection.isSelected(.line, id: label)
        return HStack(alignment: .center, spacing: 10) {
            TransitLinePill(label: label, color: line.color)
            VStack(alignment: .leading, spacing: 2) {
                if let headsign = line.headsign, !headsign.isEmpty {
                    Text(headsign).font(.subheadline.weight(.semibold))
                }
                Text(modeLabel(line.mode)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .frame(minHeight: Design.Size.hitTarget)
        .contentShape(Rectangle())
        .onTapGesture { openLine(line) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + ", " + (line.headsign ?? VelaL10n.text("transit_no_direction")))
        .accessibilityValue(selected ? "selected" : "unselected")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("transit-board-nearby-line")
    }

    /// The board's share of the shared control. A stop board lists what leaves next, so a future
    /// choice re-asks the board and the trip search it belongs to; the line under the buttons names
    /// the instant of that ask instead of pretending the feed took a date.
    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimeChoiceBar(model: time)
            Text(VelaL10n.text("transit_board_time_note"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transit-board-time-note")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.boardName.isEmpty ? VelaL10n.text("transit_transit_stop") : model.boardName)
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("transit-board-station")
                Spacer(minLength: 0)
                Button {
                    model.refreshBoard()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                }
                .accessibilityLabel(VelaL10n.text("transit_refresh"))
                .accessibilityIdentifier("transit-board-refresh")
            }
            Text(VelaL10n.text("transit_next_departures"))
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
            Text(VelaL10n.text("transit_no_departures_found_here"))
                .font(.headline)
            Text(VelaL10n.text("transit_transitous_may_not_cover_this_stop"))
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
                let countdown = countdown(departure, now: now)
                let state = departure.realtime
                    ? VelaL10n.text("place_transit_live")
                    : VelaL10n.text("place_transit_scheduled")
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(countdown)
                                    .font(.title3.weight(.semibold).monospacedDigit())
                                stateBadge(departure)
                                Spacer(minLength: 0)
                            }
                            if let clock = departure.clockText {
                                Text(clock)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(countdown)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .frame(minWidth: 64, alignment: .leading)
                            stateBadge(departure)
                            Spacer(minLength: 0)
                            if let clock = departure.clockText {
                                Text(clock)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(countdown), \(state)\(departure.clockText.map { ", \($0)" } ?? "")")
                .accessibilityIdentifier("transit-board-departure")
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        // TRANSIT-WIRE: the row (its departure times included) opens the line sheet at this stop.
        .onTapGesture { openLine(line) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: VelaL10n.text(
            "transit_open_line", line.label ?? modeLabel(line.mode))) { openLine(line) }
        .accessibilityIdentifier("transit-board-line")
    }

    /// TRANSIT-CITYMAPPER: the tapped line replaces the board inside this same shell, on the Stops
    /// tab. Nothing is presented on top, so the header keeps one line identity and one countdown.
    /// `TransitBoardState` carries the stop's name and coordinate but not its Transitous id, so the
    /// line resolves the board by proximity; no value is guessed.
    private func openLine(_ line: StopBoardLine) {
        let state = AppGraph.session.board.state.value
        let name = state.stopName.isEmpty ? model.boardName : state.stopName
        guard state.latitude != 0 || state.longitude != 0 else { return }
        let label = line.label ?? modeLabel(line.mode)
        let next = TransitLineLink.shared.makeModel(
            line: label,
            direction: line.headsign,
            stop: TransitLineStopRef(
                stopId: nil,
                name: name,
                latitude: state.latitude,
                longitude: state.longitude))
        selection.select(
            kind: .line, id: label, label: label,
            latitude: state.latitude, longitude: state.longitude, source: .list)
        next?.start()
        lineModel = next
        tab = .stops
    }

    private func close() {
        lineModel?.close()
        lineModel = nil
        model.closeBoard()
        dismiss()
    }

    private var offlineTime: String {
        (model.boardCachedAt ?? model.boardFetchedAt ?? Date())
            .formatted(date: .omitted, time: .shortened)
    }

    private func countdown(_ departure: StopBoardDeparture, now: Date) -> String {
        let minutes = departure.minutesFrom(now)
        if minutes <= 0 { return VelaL10n.text("place_transit_now") }
        return VelaL10n.text("transit_min_3", String(describing: (minutes)))
    }

    private func stateBadge(_ departure: StopBoardDeparture) -> some View {
        Group {
            if departure.realtime {
                Text(VelaL10n.text("place_transit_live"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green, in: Capsule())
            } else {
                Text(VelaL10n.text("place_transit_scheduled"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "BUS": return VelaL10n.text("place_transit_bus")
        case "TRAM": return VelaL10n.text("place_transit_tram")
        case "SUBWAY": return VelaL10n.text("place_transit_subway")
        case "TRAIN": return VelaL10n.text("place_transit_train")
        case "FERRY": return VelaL10n.text("place_transit_ferry")
        default: return VelaL10n.text("place_mode_transit")
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
