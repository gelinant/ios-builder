import SwiftUI
import UIKit
import VelaCore

/// A position supplied by the interpolated vehicle layer (TRANSIT-INTERP). It is always an
/// estimate; the screen keeps the word "Estimated" visible. `nil` keeps the feed-time estimate
/// that the GO machine derives from the ride's own adjacent live times.
struct TransitGoVehicleHint: Equatable {
    let line: String
    let fraction: Double
    let fromStop: String
    let toStop: String
}

/// The GO screen: one current action on the top half, a live countdown read from the clock, the
/// remaining stops of the ride, the get-off cue and the four Citymapper-shaped bottom controls.
/// Every time and stop comes from the selected itinerary through the Kotlin step machine; a
/// degraded plan says Scheduled, an offline one keeps the last itinerary and says so.
struct TransitGoScreen: View {
    @ObservedObject var model: TransitGoModel
    /// The shared session, when one is running. GO follows its stop position; without it the
    /// manual controls and the clock still drive the screen.
    var transit: TransitModel?
    let onClose: () -> Void
    var onNextDepartures: (() -> Void)?
    var onLeaveLater: ((Int, Int64) -> Void)?
    var onWholeTrip: (() -> Void)?
    /// The map host's line sheet when it exists; otherwise the local stop list opens.
    var onOpenLine: (() -> Void)?
    /// The interpolated vehicle layer's marker for the current line, when that lot is mounted.
    var vehicleHint: TransitGoVehicleHint?

    @State private var showsLine = false
    @State private var showsLater = false

    private var state: TransitGoState? { model.state }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            Group {
                if let state {
                    content(state)
                } else if !model.error.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: Design.Spacing.s) {
                        ProgressView()
                        Text(VelaL10n.text("transit_preparing_go_guidance"))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("transit-go-preparing")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            // A11Y-SPLIT: the same bar was a navigation toolbar, whose items are laid out inside
            // the bar's inset content height: Close measured 68x36 and no frame could grow it.
            // The navigation stack stays the screen's accessibility container, as the scenarios
            // rely on it, but its bar is hidden and the content draws the same bar with a real
            // 44 point Close.
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("transit-go-screen")
        .accessibilityElement(children: .contain)
        .onAppear {
            model.start()
            attachNetworkProviderIfNeeded()
            syncFromSession()
        }
        .onDisappear { model.stop() }
        .onChange(of: transit?.content) { _, _ in syncFromSession() }
        .sheet(isPresented: $showsLine) {
            if let state {
                TransitGoLineDetail(state: state, now: Date())
            }
        }
        .confirmationDialog(
            VelaL10n.text("transit_leave_later"),
            isPresented: $showsLater,
            titleVisibility: .visible
        ) {
            Button(VelaL10n.text("transit_leave_in_5_min")) { leaveLater(5) }
                .accessibilityIdentifier("transit-go-later-5")
            Button(VelaL10n.text("transit_leave_in_15_min")) { leaveLater(15) }
                .accessibilityIdentifier("transit-go-later-15")
            Button(VelaL10n.text("transit_leave_in_30_min")) { leaveLater(30) }
                .accessibilityIdentifier("transit-go-later-30")
            Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
        } message: {
            Text(VelaL10n.text("transit_vela_replans_from_the_chosen_departure"))
        }
    }

    /// The bar the inline navigation title used to draw: the GO title at the leading edge and
    /// Close at the trailing one, where a thumb reaches it in either reading direction.
    private var topBar: some View {
        HStack(spacing: Design.Spacing.s) {
            Text(VelaL10n.text("settings_voice_variant_go"))
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Design.Spacing.s)
            Button(action: onClose) {
                Text(VelaL10n.text("place_close"))
                    .frame(minWidth: Design.Size.hitTarget,
                           minHeight: Design.Size.hitTarget)
            }
            .accessibilityIdentifier("transit-go-close")
            .accessibilityLabel(VelaL10n.text("transit_close_go_guidance"))
        }
        .padding(.horizontal, Design.Spacing.l)
        .padding(.vertical, Design.Spacing.xs)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func content(_ state: TransitGoState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                degradedBanner(state)
                actionCard(state)
                if !model.anchorNotice.isEmpty {
                    banner(
                        model.anchorNotice,
                        icon: "clock.badge.exclamationmark",
                        identifier: "transit-go-anchor-notice")
                }
                if !state.cue.isEmpty { cueBanner(state) }
                // The manual controls sit under the action, where Citymapper puts the one
                // confirmation a rider needs, and stay reachable before the rail scrolls.
                manualControls(state)
                if state.phase == "RIDE" { rail(state) }
                Text(VelaL10n.text("transit_countdowns_compare_the_feed_s_time"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                #if DEBUG
                Text(model.debugLine)
                    .font(.caption2.monospaced())
                    .lineLimit(3)
                    .accessibilityIdentifier("transit-go-debug")
                #endif
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Citymapper's four controls stay pinned: they are one tap away even when the rail or
        // the action card is taller than the screen at an accessibility size.
        .safeAreaInset(edge: .bottom) {
            bottomControls(state)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
        }
    }

    // MARK: One current action

    private func actionCard(_ state: TransitGoState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if !state.line.isEmpty {
                    lineBadge(state)
                } else {
                    Image(systemName: state.phase == "WALK" ? "figure.walk" : "tram.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                timeStatusChip(state)
            }
            Text(state.action)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .accessibilityIdentifier("transit-go-action")
                .accessibilityLabel(state.action)
            if !state.detail.isEmpty {
                Text(state.detail)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-go-detail")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(state.countdownText(nowEpochSec: Int64(context.date.timeIntervalSince1970)))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("transit-go-countdown")
                }
                Spacer(minLength: 0)
                if let arrival = overallArrival(state) {
                    Text(VelaL10n.text("navservice_notif_eta", String(describing: (arrival))))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if state.phase == "WALK", state.stopsRemaining < 0, state.step != "done" {
                Text(state.step == "transfer" ? VelaL10n.text("transit_on_foot_to_the_next_line") : VelaL10n.text("transit_on_foot_to_the_stop"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: state.progress)
                .tint(state.line.isEmpty ? .accentColor : TransitActivityPalette.fill(state.hexOrNil))
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func lineBadge(_ state: TransitGoState) -> some View {
        Text(state.line)
            .font(.title2.weight(.heavy))
            .foregroundStyle(TransitActivityPalette.text(
                fill: state.hexOrNil, explicit: state.textHexOrNil))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                TransitActivityPalette.fill(state.hexOrNil),
                in: RoundedRectangle(cornerRadius: 9))
            .accessibilityLabel(
                state.direction.isEmpty
                    ? VelaL10n.text("transit_line_3", String(describing: (state.line)))
                    : VelaL10n.text("transit_line_towards", String(describing: (state.line)), String(describing: (state.direction))))
    }

    private func timeStatusChip(_ state: TransitGoState) -> some View {
        Label(state.timeLabel, systemImage: state.estimated ? "dot.radiowaves.left.and.right" : "clock")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .accessibilityLabel(VelaL10n.text("transit_time_status", String(describing: (state.timeLabel))))
            .accessibilityIdentifier("transit-go-time-status")
    }

    // MARK: Get-off cue

    private func cueBanner(_ state: TransitGoState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(VelaL10n.text("transit_get_off_cue"))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(state.cueText)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if state.offline || state.scheduledOnly {
                    Text(VelaL10n.text("transit_based_on_the_timetable_no_live"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VelaL10n.text("transit_get_off_cue_2", String(describing: (state.cueText))))
        .accessibilityIdentifier("transit-go-cue")
    }

    // MARK: Ride rail

    private func rail(_ state: TransitGoState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(VelaL10n.text("transit_remaining_stops"))
                    .font(.headline)
                Spacer()
                Button {
                    if let onOpenLine {
                        onOpenLine()
                    } else {
                        showsLine = true
                    }
                } label: {
                    // A11Y-SPLIT: the floor sat on the Button, so the frame measured was the
                    // label's 90x18. The content carries it now and the hit target is 44 high.
                    Label(VelaL10n.text("transit_see_line"), systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: Design.Size.hitTarget,
                               minHeight: Design.Size.hitTarget)
                }
                .accessibilityIdentifier("transit-go-line")
                .accessibilityLabel(
                    state.direction.isEmpty
                        ? VelaL10n.text("transit_show_the_line", String(describing: (state.line)))
                        : VelaL10n.text("transit_show_the_line_towards", String(describing: (state.line)), String(describing: (state.direction))))
            }
            let position = estimatedPosition(state)
            if position.fraction >= 0 {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(VelaL10n.text("transit_estimated_between_and", String(describing: (position.from)), String(describing: (position.to))))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(VelaL10n.text("transit_estimated"))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    VelaL10n.text("transit_estimated_position_between_and_this_is", String(describing: (position.from)), String(describing: (position.to))))
                .accessibilityIdentifier("transit-go-estimated")
                ProgressView(value: position.fraction)
                    .tint(.orange)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(state.stops.indices, id: \.self) { index in
                    railRow(state, index: index, stop: state.stops[index])
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func railRow(_ state: TransitGoState, index: Int, stop: TransitGoStop) -> some View {
        let last = state.stops.count - 1
        let currentIndex = Int(state.stopIndex)
        let passed = index < currentIndex
        let current = index == currentIndex
        let alight = index == last
        let status: String = {
            if passed { return VelaL10n.text("transit_status_passed") }
            if alight { return VelaL10n.text("transit_get_off_title") }
            if current { return VelaL10n.text("transit_status_you_are_here") }
            if index == currentIndex + 1 { return VelaL10n.text("transit_status_next") }
            return VelaL10n.text("transit_stops_away", String(describing: (last - index)))
        }()
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 3, height: 42)
                    .offset(y: index == 0 ? 21 : (index == last ? -21 : 0))
                Circle()
                    .fill(passed ? Color.secondary
                          : (alight ? Color.orange : TransitActivityPalette.fill(state.hexOrNil)))
                    .frame(width: current ? 18 : 12, height: current ? 18 : 12)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            }
            .frame(width: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(current ? .headline : .body)
                    .foregroundStyle(passed ? .secondary : .primary)
                    .strikethrough(false)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(alight ? .orange : .secondary)
            }
            Spacer(minLength: 0)
            if stop.estimatedEpochSec > 0 {
                Text(clock(stop.estimatedEpochSec))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if stop.scheduledEpochSec > 0 {
                Text(clock(stop.scheduledEpochSec))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onOpenLine {
                onOpenLine()
            } else {
                showsLine = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(stop.name), \(status)\(stop.estimatedEpochSec > 0 ? ", " + VelaL10n.text("transit_estimated_at_prefix") + clock(stop.estimatedEpochSec) : "")")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Manual controls

    private func manualControls(_ state: TransitGoState) -> some View {
        VStack(spacing: 10) {
            if state.canBoard {
                Button {
                    model.board()
                } label: {
                    Label(VelaL10n.text("transit_i_m_on_board"), systemImage: "figure.walk.arrival")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("transit-go-board")
                .accessibilityLabel(
                    state.direction.isEmpty
                        ? VelaL10n.text("transit_i_m_on_board_2", String(describing: (state.line)))
                        : VelaL10n.text("transit_i_m_on_board_the_towards", String(describing: (state.line)), String(describing: (state.direction))))
            }
            if state.canSkip {
                Button {
                    model.skip()
                } label: {
                    Label(VelaL10n.text("transit_skip_this_step"), systemImage: "forward.end")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("transit-go-skip")
                .accessibilityLabel(
                    VelaL10n.text("transit_skip_this_step_2", String(describing: (state.line.isEmpty ? state.action : VelaL10n.text("transit_line_action", String(describing: (state.line)), String(describing: (state.action)))))))
            }
            #if DEBUG
            if state.canAdvanceStop {
                Button {
                    model.advanceStop()
                } label: {
                    Label("Next stop (preview)", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("transit-go-advance")
                .accessibilityLabel("Next stop preview")
            }
            #endif
        }
    }

    // MARK: Bottom controls

    private func bottomControls(_ state: TransitGoState) -> some View {
        let line = state.line.isEmpty ? VelaL10n.text("transit_this_trip") : VelaL10n.text("transit_line_towards", String(describing: (state.line)), String(describing: (state.direction)))
        let departures = control(VelaL10n.text("transit_go_departures"), "clock.arrow.circlepath", "transit-go-departures",
                                 label: VelaL10n.text("transit_go_next_departures_label", String(describing: (line)))) {
            onNextDepartures?()
        }
        let later = control(VelaL10n.text("transit_go_leave_later"), "hourglass", "transit-go-later",
                            label: VelaL10n.text("transit_go_leave_later_label", String(describing: (line)))) {
            showsLater = true
        }
        let trip = control(VelaL10n.text("transit_go_whole_trip"), "list.bullet.rectangle", "transit-go-trip",
                           label: VelaL10n.text("transit_go_whole_trip_label", String(describing: (line)))) {
            onWholeTrip?()
        }
        let end = control(VelaL10n.text("transit_go_end"), "xmark.circle", "transit-go-end",
                          label: VelaL10n.text("transit_go_end_label"), destructive: true) {
            model.end()
            onClose()
        }
        return Group {
            // Four controls in one row clip their translated labels at AX5. The pinned bar becomes
            // a two-column grid at accessibility sizes, as A1 requires.
            if typeSize.isAccessibilitySize {
                VStack(spacing: Design.Spacing.s) {
                    HStack(spacing: Design.Spacing.s) { departures; later }
                    HStack(spacing: Design.Spacing.s) { trip; end }
                }
            } else {
                HStack(spacing: Design.Spacing.s) { departures; later; trip; end }
            }
        }
    }

    private func control(
        _ title: String,
        _ icon: String,
        _ identifier: String,
        label: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    // MARK: Degraded states

    @ViewBuilder
    private func degradedBanner(_ state: TransitGoState) -> some View {
        if state.stale {
            banner(
                "This itinerary may be out of date. Steps stay on screen, times are scheduled and no get-off cue is announced.",
                icon: "exclamationmark.triangle.fill",
                identifier: "transit-go-stale")
        } else if state.offline {
            banner(
                "No network. Showing the last itinerary\(fetchedLabel(state)). Times are scheduled, not live.",
                icon: "wifi.slash",
                identifier: "transit-go-offline")
        } else if state.scheduledOnly {
            banner(
                "Scheduled times. The feed gave no live times for this trip.",
                icon: "clock.badge.questionmark",
                identifier: "transit-go-scheduled")
        }
    }

    private func banner(_ text: String, icon: String, identifier: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier(identifier)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tram")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(model.error)
                .font(.headline)
            Text(VelaL10n.text("transit_start_a_transit_itinerary_first_then"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func syncFromSession() {
        guard let content = transit?.content else { return }
        model.sync(
            legIndex: content.legIndex,
            stopsRemaining: content.stopsRemaining,
            boarded: content.boarded,
            arrived: content.arrived)
    }

    private func attachNetworkProviderIfNeeded() {
        guard model.usesHostNetwork, let offline = AppGraph.session.offline else { return }
        model.attachNetworkProvider { offline.state.value.networkAvailable }
    }

    private func leaveLater(_ minutes: Int) {
        let epoch = model.leaveLaterEpoch(minutes: minutes)
        onLeaveLater?(minutes, epoch)
    }

    private func overallArrival(_ state: TransitGoState) -> String? {
        guard state.overallArrivalEpochSec > 0 else { return nil }
        return clock(state.overallArrivalEpochSec)
    }

    /// The vehicle layer wins when it has the same line, because it is the map's one estimate;
    /// otherwise the machine's adjacent live stop times are used. Neither is ever called measured.
    private func estimatedPosition(_ state: TransitGoState) -> (fraction: Double, from: String, to: String) {
        if let hint = vehicleHint, !state.line.isEmpty,
           hint.line.caseInsensitiveCompare(state.line) == .orderedSame,
           hint.fraction.isFinite {
            return (min(1, max(0, hint.fraction)), hint.fromStop, hint.toStop)
        }
        return (state.estimatedFraction, state.estimatedFromStop, state.estimatedToStop)
    }

    private func clock(_ epoch: Int64) -> String {
        guard epoch > 0 else { return "" }
        return Date(timeIntervalSince1970: TimeInterval(epoch))
            .formatted(date: .omitted, time: .shortened)
    }

    private func fetchedLabel(_ state: TransitGoState) -> String {
        guard state.fetchedAtEpochSec > 0 else { return "" }
        return " from \(clock(state.fetchedAtEpochSec))"
    }
}

private extension TransitGoState {
    var hexOrNil: String? { colorHex.isEmpty ? nil : colorHex }
    var textHexOrNil: String? { textColorHex.isEmpty ? nil : textColorHex }
}

/// The local line sheet. It lists the ride's own stops and times; a map host that owns a richer
/// line sheet passes `onOpenLine` instead and this fallback is not shown.
private struct TransitGoLineDetail: View {
    let state: TransitGoState
    let now: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Text(state.line)
                            .font(.headline)
                            .foregroundStyle(TransitActivityPalette.text(
                                fill: state.hexOrNil, explicit: state.textHexOrNil))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                TransitActivityPalette.fill(state.hexOrNil),
                                in: RoundedRectangle(cornerRadius: 7))
                        if !state.direction.isEmpty {
                            Text(VelaL10n.text("transit_nav_towards", String(describing: (state.direction))))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(VelaL10n.text("transit_stops_on_this_itinerary")) {
                    ForEach(state.stops.indices, id: \.self) { index in
                        let stop = state.stops[index]
                        HStack {
                            Text(stop.name)
                            Spacer()
                            Text(time(stop))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(stop.name), \(index == state.stops.count - 1 ? VelaL10n.text("transit_get_off") : VelaL10n.text("transit_stop_number", String(describing: (index + 1))))")
                    }
                }
                Section {
                    Text(VelaL10n.text("transit_times_come_from_the_selected_itinerary"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(VelaL10n.text("transit_line_3", String(describing: (state.line))))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(VelaL10n.text("place_close")) { dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .accessibilityIdentifier("transit-go-line-sheet")
    }

    private func time(_ stop: TransitGoStop) -> String {
        let epoch = stop.estimatedEpochSec > 0 ? stop.estimatedEpochSec : stop.scheduledEpochSec
        guard epoch > 0 else { return "Scheduled, no time" }
        return Date(timeIntervalSince1970: TimeInterval(epoch))
            .formatted(date: .omitted, time: .shortened)
    }
}

/// The button a map host adds next to Trip and End. Mounting the screen is one line in
/// `TransitGuidanceCard`; the GO model reads the same `TransitModel` session as the card.
struct TransitGoButton: View {
    @ObservedObject var model: TransitModel
    /// At an accessibility size the guidance card keeps GO as an icon, so three actions fit a row
    /// of their own. The label stays on the button for VoiceOver.
    var compact = false
    @State private var showsGo = false

    var body: some View {
        Button {
            showsGo = true
        } label: {
            if compact {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.subheadline.weight(.bold))
            } else {
                Label(VelaL10n.text("settings_voice_variant_go"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.subheadline.weight(.bold))
            }
        }
        .buttonStyle(.borderedProminent)
        .frame(minWidth: compact ? Design.Size.hitTarget : nil,
               minHeight: Design.Size.hitTarget)
        .layoutPriority(1)
        .accessibilityIdentifier("transit-go-open")
        .accessibilityLabel(VelaL10n.text("transit_open_go_step_by_step_guidance"))
        .fullScreenCover(isPresented: $showsGo) {
            TransitGoHostView(transit: model, onClose: { showsGo = false })
        }
    }
}

/// Owns the GO model for the presented screen and wires the four bottom controls to the existing
/// map surfaces: the stop board, the planner time, and the trip screen.
private struct TransitGoHostView: View {
    @ObservedObject var transit: TransitModel
    @StateObject private var go: TransitGoModel
    @State private var showsBoard = false
    @State private var showsTrip = false
    @State private var openedAnchorBoard = false
    let onClose: () -> Void

    init(transit: TransitModel, onClose: @escaping () -> Void) {
        self.transit = transit
        self.onClose = onClose
        let trip = transit.activeTrip ?? transit.tripScreenTrip
        let destination = transit.destinationName.isEmpty ? "the destination" : transit.destinationName
        let network = AppGraph.session.offline?.state.value.networkAvailable ?? true
        let model = TransitGoModel(
            trip: trip,
            destinationName: destination,
            networkAvailable: network)
        // Leave later reads the stop board the host opens for GO, exactly the board T-1 shows.
        model.boardStopNameProvider = { [weak transit] in transit?.boardName ?? "" }
        model.boardDeparturesProvider = { [weak transit] in
            guard let transit, transit.boardOpen else { return [] }
            return transit.boardLines.flatMap { line in
                line.departures.map { departure in
                    TransitGoBoardDeparture(
                        line: line.label ?? "",
                        headsign: line.headsign ?? "",
                        clockText: departure.clockText ?? "",
                        epochSec: departure.epochSec)
                }
            }
        }
        _go = StateObject(wrappedValue: model)
    }

    var body: some View {
        TransitGoScreen(
            model: go,
            transit: transit,
            onClose: onClose,
            onNextDepartures: openBoard,
            onLeaveLater: leaveLater,
            onWholeTrip: { showsTrip = true })
        .onAppear {
            go.start()
            openAnchorBoard()
        }
        .onDisappear {
            if openedAnchorBoard {
                transit.closeBoard()
                openedAnchorBoard = false
            }
        }
        .sheet(isPresented: $showsBoard) {
            TransitBoardSheet(model: transit)
        }
        .fullScreenCover(isPresented: $showsTrip) {
            TransitTripScreen(
                model: transit.trip,
                destination: transit.destinationName,
                live: transit.live,
                onClose: {
                    transit.trip.close()
                    showsTrip = false
                })
            .onAppear {
                transit.trip.onAdopt = { [weak transit] chosen in
                    transit?.adoptAlternative(chosen)
                }
                if let trip = transit.tripScreenTrip {
                    transit.trip.open(trip: trip)
                }
            }
        }
    }

    /// The stop board is the T-1 surface, opened on the boarding stop of the ride being shown.
    private func openBoard() {
        guard let trip = transit.activeTrip ?? transit.tripScreenTrip,
              let step = trip.steps.first(where: { $0.line != nil }),
              let board = step.boardStop,
              let location = board.location else { return }
        transit.openBoard(
            latitude: location.lat,
            longitude: location.lng,
            name: board.name)
        showsBoard = true
    }

    /// Opens the T-1 board on the boarding stop so the anchor can read the same departure the
    /// stop sheet shows. It is not presented: only its state is needed while GO is open.
    private func openAnchorBoard() {
        guard let trip = transit.activeTrip ?? transit.tripScreenTrip,
              let step = trip.steps.first(where: { $0.line != nil }),
              let board = step.boardStop,
              let location = board.location else { return }
        if transit.boardOpen, transit.boardName == board.name { return }
        openedAnchorBoard = true
        transit.openBoard(
            latitude: location.lat,
            longitude: location.lng,
            name: board.name)
    }

    /// "Leave later" replans from the anchor the model chose: the stop board's own departure when
    /// it lists this run, otherwise now plus the minutes with the notice already on screen. It does
    /// not rewrite the itinerary shown by GO; a picked option replaces it through the normal path.
    private func leaveLater(_ minutes: Int, epochSec: Int64) {
        transit.setTimeMode(1, epochSec: epochSec)
    }
}
