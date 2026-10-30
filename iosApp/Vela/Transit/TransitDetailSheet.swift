import SwiftUI
import UIKit
import VelaCore

/// The selected transit itinerary in detail: every walk and ride, the board and alight stops with
/// their times, the intermediate stops the planner returned, and any service alerts and fare the
/// feed carried. Start hands the same itinerary to the process-owned TransitSession.
struct TransitDetailSheet: View {
    @ObservedObject var model: TransitModel
    let onClose: () -> Void
    let onStart: () -> Void

    @State private var showsTrip = false
    @StateObject private var time: TimeChoiceModel

    init(model: TransitModel, onClose: @escaping () -> Void, onStart: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        _time = StateObject(wrappedValue: TimeChoiceModel(
            mode: Int32(model.timeMode),
            epochSec: model.timeEpoch,
            ids: .detail,
            onApply: { mode, epoch in
                model.setTimeMode(Int(mode), epochSec: epoch)
            }))
        self.onClose = onClose
        self.onStart = onStart
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let detail = model.detail {
                // A GeometryReader keeps the scroll view from adding its whole content height to
                // the sheet's ideal height. Without it the time control pushed the fixed action
                // row below the window on the live itinerary.
                GeometryReader { _ in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                TimeChoiceBar(model: time)
                                Text(VelaL10n.text("transit_time_clock_note", String(describing: (time.zone.identifier))))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("transit-detail-time-note")
                            }
                            summary(detail)
                            modeStrip(detail)
                            if !detail.alerts.isEmpty {
                                alerts(detail.alerts)
                            }
                            ForEach(Array(detail.legs.enumerated()), id: \.element.id) { index, leg in
                                // A transfer row sits at the transfer point, after the walk between the
                                // two rides and before the ride that leaves it.
                                if !leg.isWalk,
                                   let previous = detail.legs[..<index].last(where: { !$0.isWalk }) {
                                    transferRow(detail, before: leg, after: previous)
                                }
                                TransitDetailLegCard(leg: leg, onOpenLine: { openLine(leg) })
                            }
                            #if DEBUG
                            Text(detailDebugLine(detail))
                                .font(.caption2.monospaced())
                                .lineLimit(2)
                                .accessibilityIdentifier("transit-modes-debug")
                            Text(model.optionsDebugLine)
                                .font(.caption2.monospaced())
                                .accessibilityIdentifier("transit-detail-debug")
                            #endif
                            Text(VelaL10n.text("transit_times_are_scheduled_unless_the_feed_2"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                    }
                    .accessibilityIdentifier("transit-detail-scroll")
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        // The action row is pinned below the scroll view, so a long itinerary can never push Close
        // and Start under the window edge. The scroll view keeps its own inset above it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    Button(VelaL10n.text("place_close")) { onClose() }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("steps-close")
                    Spacer()
                    Button {
                        showsTrip = true
                    } label: {
                        Label(VelaL10n.text("transit_trip_view"), systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .disabled(model.tripScreenTrip == nil)
                    .accessibilityIdentifier("transit-trip-open")
                    Button {
                        onStart()
                    } label: {
                        Label(VelaL10n.text("transit_start_transit"), systemImage: "tram.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.detail == nil)
                    .accessibilityIdentifier("transit-start")
                }
                .padding(.horizontal, Design.Spacing.m)
                .padding(.vertical, Design.Spacing.m)
            }
            .background(Design.Colors.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        // Without containment the sheet's buttons are published under this identifier instead of
        // their own, which hides Close and Start from VoiceOver and from the tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("steps-sheet")
        .onAppear {
            time.sync(mode: Int32(model.timeMode), epochSec: model.timeEpoch)
        }
        .onChange(of: model.timeMode) { _, _ in
            time.sync(mode: Int32(model.timeMode), epochSec: model.timeEpoch)
        }
        .onChange(of: model.timeEpoch) { _, epoch in
            time.sync(mode: Int32(model.timeMode), epochSec: epoch)
        }
        .fullScreenCover(isPresented: $showsTrip) {
            TransitTripScreen(
                model: model.trip,
                destination: model.destinationName,
                live: model.live,
                onClose: {
                    model.trip.close()
                    showsTrip = false
                })
            .onAppear {
                model.trip.onAdopt = { [weak model] chosen in model?.adoptAlternative(chosen) }
                if let trip = model.tripScreenTrip { model.trip.open(trip: trip) }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(VelaL10n.text("transit_trip_details"))
                    .font(.headline)
                Text(model.destinationName.isEmpty ? VelaL10n.text("settings_mode_transit") : model.destinationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func summary(_ detail: TransitDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let depart = detail.departureText {
                    Label(depart, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                if let duration = detail.durationText {
                    Text(duration)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let arrive = detail.arrivalText {
                    Label(arrive, systemImage: "arrow.down.left")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if let agency = detail.agency, !agency.isEmpty {
                Text(agency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let fare = detail.fare, !fare.isEmpty {
                Label(fare, systemImage: "creditcard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func alerts(_ alerts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(VelaL10n.text("transit_service_alerts"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(Array(alerts.enumerated()), id: \.offset) { _, alert in
                Text(alert)
                    .font(.caption)
                    .accessibilityIdentifier("transit-detail-alert")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The whole trip's modes at a glance, in travel order: "Walk · M1 · RER A · Walk". It is drawn
    /// from the planner's modes, so a leg never disappears behind the sheet's fold.
    private func modeStrip(_ detail: TransitDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VelaL10n.text("transit_whole_trip"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(detail.legs.enumerated()), id: \.element.id) { index, leg in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 3) {
                            Image(systemName: leg.mode.symbol)
                                .font(.caption2)
                            Text(leg.title)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
                    }
                }
            }
            .accessibilityIdentifier("transit-detail-modes")
            .accessibilityLabel(detail.modeSequence)
        }
    }

    /// The transfer point between two rides and the planned waiting time from the arrival to the
    /// next departure. The planner's own clocks decide it; an unknown wait shows the point alone.
    private func transferRow(_ detail: TransitDetail, before next: TransitDetailLeg, after previous: TransitDetailLeg) -> some View {
        let wait = detail.waitMinutes(after: previous)
        let point = next.board?.name ?? previous.alight?.name
        return HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(point.map { VelaL10n.text("transit_transfer_at", String(describing: ($0))) } ?? VelaL10n.text("transit_transfer"))
                    .font(.caption.weight(.semibold))
                if let wait {
                    Text(wait == 1 ? VelaL10n.text("transit_1_min_wait") : VelaL10n.text("transit_min_wait_2", String(describing: (wait))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transit-detail-transfer")
    }

    /// The leg's line, opened at its board stop. The detail mirror carries neither the Transitous id
    /// nor the coordinate, so the planner's own step is read by the leg's index; a step with
    /// neither value opens nothing rather than inventing a stop.
    private func openLine(_ leg: TransitDetailLeg) {
        guard !leg.isWalk else { return }
        let steps = model.activeTrip?.steps ?? []
        guard leg.id >= 0, leg.id < steps.count else { return }
        guard let board = steps[leg.id].boardStop,
              board.stopId != nil || board.location != nil else { return }
        TransitLineLink.shared.open(
            line: leg.line ?? "",
            direction: leg.headsign,
            stop: TransitLineStopRef(
                stopId: board.stopId,
                name: board.name,
                latitude: board.location?.lat ?? 0,
                longitude: board.location?.lng ?? 0))
    }

    #if DEBUG
    private func detailDebugLine(_ detail: TransitDetail) -> String {
        let modes = detail.legs.map { leg in
            leg.mode.isWalk ? "walk" : leg.mode.name.lowercased()
        }
        return "legs=\(detail.legs.count) modes=\(modes.joined(separator: ","))"
            + " transfers=\(detail.transferCount)"
    }
    #endif
}

/// One leg of the selected itinerary: the vehicle's glyph and readable name first, then the line's
/// own times and stops. The intermediate stops stay one tap away, so a long first ride cannot push
/// the transfer and the remaining legs out of the sheet.
private struct TransitDetailLegCard: View {
    let leg: TransitDetailLeg
    let onOpenLine: () -> Void

    @State private var showsStops = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: leg.mode.symbol)
                    .font(.title3)
                    .foregroundStyle(leg.isWalk ? Color.secondary : Color.primary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if !leg.isWalk, let color = Color(hex: leg.color) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color)
                                .frame(width: 4, height: 16)
                        }
                        Text(leg.title)
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("transit-detail-mode")
                        if let delay = leg.delayText, !delay.isEmpty {
                            Text(delay)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(leg.mode.subtitle(line: leg.line, agency: leg.agency))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transit-detail-mode-name")
                    if let headsign = leg.headsign, !headsign.isEmpty, !leg.isWalk {
                        Text(VelaL10n.text("transit_nav_towards", String(describing: (headsign))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        if let duration = leg.durationText {
                            Text(duration)
                        }
                        if let distance = leg.distanceText, !distance.isEmpty {
                            Text(distance)
                        }
                        if leg.stopCount > 0 {
                            Text(VelaL10n.text("transit_stops", String(describing: (leg.stopCount))))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !leg.isWalk, let line = leg.line, !line.isEmpty {
                    // TRANSIT-WIRE: the leg's line, opened on the planner's own board stop.
                    Button(action: onOpenLine) {
                        Image(systemName: "arrow.up.forward.circle")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(VelaL10n.text("transit_open_line_2", String(describing: (line))))
                    .accessibilityIdentifier("transit-detail-line")
                }
            }
            if let board = leg.board {
                stopRow(VelaL10n.text("transit_board"), board)
            }
            if leg.intermediate.count > 0, !leg.isWalk {
                Button {
                    showsStops.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(showsStops
                            ? VelaL10n.text("transit_hide_intermediate_stops", String(describing: (leg.intermediate.count)))
                            : VelaL10n.text("transit_intermediate_stops", String(describing: (leg.intermediate.count))))
                        Image(systemName: showsStops ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("transit-detail-stops-toggle")
                if showsStops {
                    ForEach(leg.intermediate) { stop in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.leading, 14)
                            Text(stop.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if let time = stop.timeText ?? stop.scheduledText {
                                Text(time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("transit-detail-stop")
                    }
                }
            }
            if let alight = leg.alight {
                stopRow(VelaL10n.text("transit_get_off_title"), alight)
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        // No identifier on this container: SwiftUI would republish every child under it and hide
        // the per-leg mode ids the tests and VoiceOver read.
    }

    private func stopRow(_ title: String, _ stop: TransitDetailStop) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name)
                    .font(.subheadline)
                    .strikethrough(stop.canceled)
                if let code = stop.code, !code.isEmpty {
                    Text(VelaL10n.text("place_transit_stop_id", String(describing: (code))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let scheduled = stop.scheduledText, let time = stop.timeText, scheduled != time {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(time)
                        .font(.caption.monospacedDigit())
                    Text(scheduled)
                        .font(.caption2.monospacedDigit())
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
            } else if let time = stop.timeText ?? stop.scheduledText {
                Text(time)
                    .font(.caption.monospacedDigit())
            }
        }
    }
}

/// A "#rrggbb" color, nil for anything else. The sheet never invents a line color.
private extension Color {
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16)
        else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255)
    }
}
