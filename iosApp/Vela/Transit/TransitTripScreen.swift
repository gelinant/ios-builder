import SwiftUI
import UIKit
import VelaCore

/// The Citymapper-style trip screen: the next departures of the chosen leg, one card per walk,
/// wait, ride and transfer, a per-segment time change that produces a new option set, "let this
/// one pass", the live progression of the shared guidance session, and the lines nearby.
/// Every time, line and delay comes from Transitous; nothing is invented when the feed is silent.
struct TransitTripScreen: View {
    @ObservedObject var model: TransitTripModel
    let destination: String
    /// The shared reachability and live-line service; nil in a build without it.
    var live: TransitLiveService? = nil
    let onClose: () -> Void

    @State private var tab = 0
    @State private var showsLaterChoices = false
    @State private var showsViaChoices = false
    @State private var showsLive = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summary
                tabs
                Divider()
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    if tab == 0 {
                        tripTab(now: context.date)
                    } else {
                        nearbyTab(now: context.date)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(tab == 0 ? VelaL10n.text("mapvm_trip_default_name") : VelaL10n.text("transit_lines_nearby"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsLive = true
                    } label: {
                        Label(VelaL10n.text("transit_live_map"), systemImage: "map")
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("transit-live-open")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(VelaL10n.text("place_close"), action: onClose)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("transit-trip-close")
                }
            }
        }
        .sheet(isPresented: $showsLive) {
            TransitLiveSheet(
                service: live,
                originLat: originPoint.lat,
                originLng: originPoint.lng,
                originName: originName,
                onClose: { showsLive = false })
        }
        .dynamicTypeSize(.xSmall ... .accessibility3)
        .accessibilityIdentifier("transit-trip")
        .onChange(of: tab) { _, value in
            if value == 1 { model.loadNearby() } else { model.reloadHeader() }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let trip = model.trip, let depart = trip.departureText {
                    Text(depart).font(.title3.weight(.semibold))
                }
                if let trip = model.trip, let arrive = trip.arrivalText {
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(arrive).font(.title3.weight(.semibold))
                }
                if let trip = model.trip, let duration = trip.durationText {
                    Text(duration).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(destination.isEmpty ? VelaL10n.text("transit_transit_trip") : destination)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let trip = model.trip, !trip.steps.isEmpty {
                // The whole trip's modes at a glance, including the transfer walk.
                Text(TransitLegMode.sequence(trip.steps.map {
                    (kind: $0.modeName ?? $0.mode.name, line: $0.line?.name, agency: $0.agencyName)
                }))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("transit-trip-modes")
            }
            #if DEBUG
            Text(model.debugLine)
                .font(.caption2.monospaced())
                .lineLimit(2)
                .accessibilityIdentifier("transit-trip-debug")
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            tabButton("Trip", value: 0, id: "transit-trip-tab-trip")
            tabButton("Lines nearby", value: 1, id: "transit-trip-tab-nearby")
            Spacer(minLength: 0)
            Button {
                model.refreshBoard()
            } label: {
                Label(VelaL10n.text("transit_refresh"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(VelaL10n.text("transit_refresh"))
            .accessibilityIdentifier("transit-trip-refresh")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabButton(_ title: String, value: Int, id: String) -> some View {
        Button(title) { tab = value }
            .buttonStyle(.bordered)
            .tint(tab == value ? Color.accentColor : Color.secondary)
            .frame(minHeight: 44)
            .accessibilityIdentifier(id)
    }

    // MARK: Trip

    private func tripTab(now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let header = model.header {
                    headerBanner(header, now: now)
                }
                if model.progress >= 0 {
                    progression
                }
                ForEach(model.segments) { segment in
                    segmentCard(segment)
                }
                if !model.options.isEmpty || model.optionsLoading || !model.optionsError.isEmpty {
                    newOptions
                }
                if !model.viaOptions.isEmpty || model.viaLoading || !model.viaError.isEmpty || !model.viaName.isEmpty {
                    viaOptionsSection
                }
                if let alerts = model.trip?.alerts, !alerts.isEmpty {
                    alertList(alerts)
                }
                if !model.notice.isEmpty {
                    Text(model.notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("transit-trip-notice")
                }
                Text(VelaL10n.text("transit_times_are_scheduled_unless_the_feed"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .accessibilityIdentifier("transit-trip-scroll")
    }

    private func headerBanner(_ header: TripHeader, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let label = header.lineLabel, !label.isEmpty {
                    TransitLinePill(label: label, color: header.lineColor)
                }
                Text(VelaL10n.text("transit_next_departures"))
                    .font(.headline)
                Spacer(minLength: 0)
            }
            if let stop = header.stopName, !stop.isEmpty {
                Text(stop).font(.caption).foregroundStyle(.secondary)
            }
            if !header.available {
                Text(VelaL10n.text("transit_the_board_did_not_answer_for"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if header.departures.isEmpty {
                Text(VelaL10n.text("transit_no_departure_of_this_line_is"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(header.departures) { departure in
                    departureRow(departure, now: now)
                }
            }
            if model.headerOffline {
                Text(VelaL10n.text("transit_offline_the_last_saved_board_is"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if model.headerStale {
                Text(VelaL10n.text("transit_the_last_board_is_shown_refresh"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("transit-trip-header")
    }

    private func departureRow(_ departure: TripDeparture, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(countdown(departure, now: now))
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(minWidth: 60, alignment: .leading)
            Text(departure.realtime ? VelaL10n.text("place_transit_live") : VelaL10n.text("place_transit_scheduled"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(departure.realtime ? Color.white : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(departure.realtime ? Color.green : Color.clear, in: Capsule())
            Spacer(minLength: 0)
            if let clock = departure.clockText {
                Text(clock).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(countdown(departure, now: now)), \(departure.realtime ? VelaL10n.text("transit_live_lower") : VelaL10n.text("transit_scheduled_lower"))"
                + (departure.clockText.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("transit-trip-departure")
    }

    private var progression: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VelaL10n.text("transit_live_progression"))
                .font(.subheadline.weight(.semibold))
            if !model.progressText.isEmpty {
                Text(model.progressText).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(model.progress, 0), 1))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VelaL10n.text("transit_live_progression_2", String(describing: (model.progressText))))
        .accessibilityIdentifier("transit-trip-progress")
    }

    private func segmentCard(_ segment: TripSegment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                segmentRail(segment)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        if segment.isRide {
                            Image(systemName: segmentMode(segment).symbol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(segmentTitle(segment))
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        stateBadge(segment)
                        Spacer(minLength: 0)
                        if model.selectedSegment == segment.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if let direction = segment.direction, segment.isRide {
                        Text(VelaL10n.text("transit_nav_towards", String(describing: (direction))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    segmentTimes(segment)
                    segmentStops(segment)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.select(segment: segment.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel(segment))
            .accessibilityIdentifier("transit-trip-segment")
            if segment.isRide, segment.hasBoardPoint, let label = segment.lineLabel, !label.isEmpty {
                // TRANSIT-WIRE: a separate control, so tapping the card still selects the segment
                // and its time actions exactly as T-3 built them.
                Button { openLine(segment) } label: {
                    Label(VelaL10n.text("transit_open_line", String(describing: (label))), systemImage: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("transit-trip-line-link")
            }
            if model.selectedSegment == segment.id {
                segmentActions(segment)
            }
        }
        .padding(12)
        .background(
            segmentBackground(segment),
            in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(model.selectedSegment == segment.id ? Color.accentColor : Color.clear, lineWidth: 2))
        .frame(minHeight: 44)
    }

    private func segmentRail(_ segment: TripSegment) -> some View {
        Group {
            if segment.isRide, let label = segment.lineLabel {
                TransitLinePill(label: label, color: segment.lineColor)
            } else {
                Image(systemName: segment.kind == "WAIT" ? "clock" : "figure.walk")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 32)
            }
        }
        .accessibilityHidden(true)
    }

    private func stateBadge(_ segment: TripSegment) -> some View {
        Group {
            if segment.kind == "WAIT" {
                EmptyView()
            } else if segment.live {
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

    @ViewBuilder private func segmentTimes(_ segment: TripSegment) -> some View {
        if segment.kind == "WAIT" {
            HStack(spacing: 8) {
                if let minutes = segment.waitMinutes {
                    Text(minutes == 1 ? VelaL10n.text("transit_1_min_wait") : VelaL10n.text("transit_min_wait", String(describing: (minutes))))
                }
                if let until = segment.waitUntil {
                    Text(VelaL10n.text("transit_departs", String(describing: (until))))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        } else if segment.isWalk {
            HStack(spacing: 8) {
                if let duration = segment.durationText { Text(duration) }
                if let distance = segment.distanceText, !distance.isEmpty { Text(distance) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                timeLabel(segment.scheduledDeparture, segment.estimatedDeparture)
                if segment.estimatedArrival != nil || segment.scheduledArrival != nil {
                    Text("→").foregroundStyle(.secondary)
                    timeLabel(segment.scheduledArrival, segment.estimatedArrival)
                }
                if let delay = segment.delayMinutes, delay != 0 {
                    Text(delay > 0 ? VelaL10n.text("transit_min_late_2", String(describing: (delay))) : VelaL10n.text("transit_min_early_2", String(describing: (-delay))))
                        .foregroundStyle(.orange)
                }
                if segment.stopCount > 0 {
                    Text(VelaL10n.text("transit_stops_3", String(describing: (segment.stopCount))))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    /// The timetable time struck through when the feed's live time differs, as the detail sheet does.
    private func timeLabel(_ scheduled: String?, _ estimated: String?) -> some View {
        Group {
            if let estimated, let scheduled, estimated != scheduled {
                HStack(spacing: 4) {
                    Text(scheduled).strikethrough()
                    Text(estimated)
                }
            } else if let shown = estimated ?? scheduled {
                Text(shown)
            }
        }
    }

    @ViewBuilder private func segmentStops(_ segment: TripSegment) -> some View {
        if segment.isRide, let board = segment.boardName {
            VStack(alignment: .leading, spacing: 2) {
                stopLine(VelaL10n.text("transit_board"), board, segment.boardCode)
                if let alight = segment.alightName {
                    stopLine(VelaL10n.text("transit_get_off_title"), alight, segment.alightCode)
                }
            }
        } else if segment.kind == "WAIT", let stop = segment.boardName {
            Text(stop).font(.caption).foregroundStyle(.secondary)
        } else if let target = segment.alightName {
            Text(VelaL10n.text("nav_bar_to_stop", String(describing: (target)))).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stopLine(_ title: String, _ name: String, _ code: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(width: 46, alignment: .leading)
            Text(code.map { "\(name) · \($0)" } ?? name)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func segmentActions(_ segment: TripSegment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(VelaL10n.text("transit_leave_later")) {
                    showsLaterChoices.toggle()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("transit-trip-leave-later")

                Button(VelaL10n.text("place_arrive_by")) {
                    model.arriveBy()
                    showsLaterChoices = false
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("transit-trip-arrive-by")

                if segment.skippable {
                    Button(VelaL10n.text("transit_via")) {
                        showsViaChoices.toggle()
                        if showsViaChoices { model.offerVia() }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("transit-trip-via")
                }

                if segment.skippable {
                    Button(VelaL10n.text("transit_skip_this_one")) {
                        model.skipSelected()
                        showsLaterChoices = false
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("transit-trip-skip")
                }
                Spacer(minLength: 0)
            }
            if showsLaterChoices {
                HStack(spacing: 8) {
                    Text(VelaL10n.text("transit_leave")).font(.caption).foregroundStyle(.secondary)
                    ForEach([5, 15, 30], id: \.self) { minutes in
                        Button(VelaL10n.text("transit_min", String(describing: (minutes)))) {
                            model.leaveLater(minutes: minutes)
                            showsLaterChoices = false
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("transit-trip-later-\(minutes)")
                    }
                    Spacer(minLength: 0)
                }
            }
            if showsViaChoices {
                VStack(alignment: .leading, spacing: 6) {
                    Text(VelaL10n.text("transit_route_through"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.viaCandidates.isEmpty {
                        Text(model.viaError.isEmpty ? VelaL10n.text("transit_no_intermediate_stop_is_listed_for") : model.viaError)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("transit-trip-via-error")
                    }
                    ForEach(model.viaCandidates) { candidate in
                        Button {
                            model.requestVia(candidate)
                            showsViaChoices = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.branch")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(candidate.name).font(.caption)
                                    if let clock = candidate.clockText {
                                        Text(clock).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(VelaL10n.text("transit_route_through_2", String(describing: (candidate.name))))
                        .accessibilityIdentifier("transit-trip-via-candidate-\(candidate.id)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The ride's line, opened on the board stop the segment already carries. A segment without a
    /// board coordinate opens nothing, since the sheet would have no stop to resolve.
    private func openLine(_ segment: TripSegment) {
        guard segment.isRide, segment.hasBoardPoint,
              let lat = segment.boardLat, let lng = segment.boardLng else { return }
        TransitLineLink.shared.open(
            line: segment.lineLabel ?? "",
            direction: segment.direction,
            stop: TransitLineStopRef(
                stopId: nil,
                name: segment.boardName ?? "",
                latitude: lat,
                longitude: lng))
    }

    private var originPoint: (lat: Double, lng: Double) {
        if let segment = model.segments.first(where: { $0.hasBoardPoint }),
           let lat = segment.boardLat, let lng = segment.boardLng {
            return (lat, lng)
        }
        return (0, 0)
    }

    private var originName: String {
        model.segments.first(where: { $0.hasBoardPoint })?.boardName ?? ""
    }

    private var viaOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VelaL10n.text("exp_chooser_via", String(describing: (model.viaName))))
                .font(.headline)
            if !model.viaQuery.isEmpty {
                Text(model.viaQuery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-trip-via-query")
            }
            if model.viaLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(VelaL10n.text("transit_asking_transitous_for_a_route_through", String(describing: (model.viaName)))).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(model.viaOptions) { option in
                Button {
                    model.selectViaOption(option.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(option.departureText ?? "?") – \(option.arrivalText ?? "?")")
                            .font(.subheadline.monospacedDigit())
                        Text(option.durationText ?? "").font(.caption).foregroundStyle(.secondary)
                        if option.live {
                            Text(VelaL10n.text("place_transit_live")).font(.caption2.weight(.bold)).foregroundStyle(.green)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 2) {
                            ForEach(Array(option.modeNames.enumerated()), id: \.offset) { _, mode in
                                Image(systemName: TransitLegMode.of(kind: mode).symbol)
                                    .font(.caption2)
                            }
                        }
                        ForEach(option.lines, id: \.self) { line in
                            TransitLinePill(label: line, color: nil)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("transit-trip-via-option")
            }
            if !model.viaError.isEmpty {
                Text(model.viaError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("transit-trip-via-error")
            }
            if !model.viaOptions.isEmpty {
                Text(VelaL10n.text("transit_these_pass_through_picking_one_keeps", String(describing: (model.viaName))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var newOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VelaL10n.text("transit_new_options"))
                .font(.headline)
            if !model.optionsQuery.isEmpty {
                Text(model.optionsQuery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-trip-options-query")
            }
            if model.optionsLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(VelaL10n.text("transit_asking_transitous")).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(model.options) { option in
                Button {
                    model.selectOption(option.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(option.departureText ?? "?") – \(option.arrivalText ?? "?")")
                            .font(.subheadline.monospacedDigit())
                        Text(option.durationText ?? "").font(.caption).foregroundStyle(.secondary)
                        if option.live {
                            Text(VelaL10n.text("place_transit_live")).font(.caption2.weight(.bold)).foregroundStyle(.green)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 2) {
                            ForEach(Array(option.modeNames.enumerated()), id: \.offset) { _, mode in
                                Image(systemName: TransitLegMode.of(kind: mode).symbol)
                                    .font(.caption2)
                            }
                        }
                        ForEach(option.lines, id: \.self) { line in
                            TransitLinePill(label: line, color: nil)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("transit-trip-option")
            }
            if !model.optionsError.isEmpty {
                Text(model.optionsError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("transit-trip-options-error")
            }
            if !model.options.isEmpty {
                Text(VelaL10n.text("transit_these_come_from_a_new_transitous"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("transit-trip-options")
    }

    private func alertList(_ alerts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(VelaL10n.text("transit_reported_by_the_operator"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(Array(alerts.enumerated()), id: \.offset) { _, alert in
                Text(alert)
                    .font(.caption)
                    .accessibilityIdentifier("transit-trip-alert")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Nearby

    private func nearbyTab(now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(model.nearbyStop.isEmpty ? VelaL10n.text("transit_lines_nearby") : model.nearbyStop)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                if model.nearbyLoading && model.nearby.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(VelaL10n.text("transit_loading_lines")).font(.caption).foregroundStyle(.secondary)
                    }
                } else if model.nearby.isEmpty {
                    Text(VelaL10n.text("transit_no_lines_found_around_the_trip"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transit-trip-nearby-empty")
                }
                if model.nearbyOffline {
                    Text(VelaL10n.text("transit_offline_the_last_saved_board_is")).font(.caption2).foregroundStyle(.orange)
                }
                ForEach(model.nearby) { line in
                    nearbyRow(line, now: now)
                }
                Text(VelaL10n.text("transit_lines_and_times_come_from_the"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .accessibilityIdentifier("transit-trip-nearby")
    }

    private func nearbyRow(_ line: TripNearbyRow, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                TransitLinePill(label: line.label ?? modeLabel(line.mode), color: line.color)
                VStack(alignment: .leading, spacing: 2) {
                    if let headsign = line.headsign, !headsign.isEmpty {
                        Text(headsign).font(.subheadline.weight(.semibold))
                    }
                    Text(modeLabel(line.mode)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ForEach(line.departures) { departure in
                HStack(spacing: 8) {
                    Text(countdown(departure, now: now))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 60, alignment: .leading)
                    Text(departure.realtime ? VelaL10n.text("place_transit_live") : VelaL10n.text("place_transit_scheduled"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(departure.realtime ? Color.white : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(departure.realtime ? Color.green : Color.clear, in: Capsule())
                    Spacer(minLength: 0)
                    if let clock = departure.clockText {
                        Text(clock).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    VelaL10n.text("transit_towards", String(describing: (line.label ?? modeLabel(line.mode))), String(describing: (line.headsign ?? VelaL10n.text("transit_unknown"))))
                        + ", \(countdown(departure, now: now)), \(departure.realtime ? "live" : "scheduled")")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        // TRANSIT-WIRE: a nearby line opens the same line sheet at the trip origin.
        .onTapGesture { openNearbyLine(line) }
        .accessibilityAction(named: "Open the line") { openNearbyLine(line) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-trip-nearby-line")
    }

    /// The nearby line at the trip origin. A trip without a board coordinate has no honest stop to
    /// resolve, so the row opens nothing.
    private func openNearbyLine(_ line: TripNearbyRow) {
        let origin = originPoint
        guard origin.lat != 0 || origin.lng != 0 else { return }
        TransitLineLink.shared.open(
            line: line.label ?? modeLabel(line.mode),
            direction: line.headsign,
            stop: TransitLineStopRef(
                stopId: nil,
                name: model.nearbyStop,
                latitude: origin.lat,
                longitude: origin.lng))
    }

    // MARK: Helpers

    /// The leg's vehicle: the walk and wait cards have their own, a ride reads the planner's mode
    /// and its agency ("M1", "RER B", "Bus 38", "Transit" when the planner left it generic).
    private func segmentMode(_ segment: TripSegment) -> TransitLegMode {
        switch segment.kind {
        case "WAIT": return TransitLegMode.of(kind: "WAIT")
        case "TRANSFER", "WALK": return TransitLegMode.of(kind: "WALK")
        default: return TransitLegMode.of(kind: segment.modeName ?? segment.mode)
        }
    }

    private func segmentTitle(_ segment: TripSegment) -> String {
        switch segment.kind {
        case "WAIT":
            if let minutes = segment.waitMinutes {
                return minutes == 1 ? VelaL10n.text("transit_wait_min", "1") : VelaL10n.text("transit_wait_min", String(describing: (minutes)))
            }
            return VelaL10n.text("transit_wait")
        case "TRANSFER": return VelaL10n.text("transit_transfer_walk")
        case "WALK": return VelaL10n.text("transit_walk")
        default:
            return segmentMode(segment).title(line: segment.lineLabel, agency: segment.agencyName)
        }
    }

    private func segmentBackground(_ segment: TripSegment) -> Color {
        if model.selectedSegment == segment.id {
            return Color.accentColor.opacity(0.10)
        }
        if model.skippedSegment == segment.id {
            return Color.orange.opacity(0.10)
        }
        return Color(uiColor: .secondarySystemBackground)
    }

    private func accessibilityLabel(_ segment: TripSegment) -> String {
        var parts: [String] = [segmentTitle(segment)]
        if let direction = segment.direction, segment.isRide {
            parts.append("towards \(direction)")
        }
        if let board = segment.boardName, let alight = segment.alightName, segment.isRide {
            parts.append("from \(board) to \(alight)")
        } else if let target = segment.alightName {
            parts.append("to \(target)")
        }
        if let depart = segment.estimatedDeparture ?? segment.scheduledDeparture {
            parts.append(segment.isRide ? "departs \(depart)" : "at \(depart)")
        }
        if let arrive = segment.estimatedArrival ?? segment.scheduledArrival {
            parts.append("arrives \(arrive)")
        }
        if segment.isRide {
            parts.append(segment.live ? "Live" : "Scheduled")
        }
        if let delay = segment.delayMinutes, delay != 0 {
            parts.append(delay > 0 ? "\(delay) minutes late" : "\(-delay) minutes early")
        }
        if segment.stopCount > 0 {
            parts.append("\(segment.stopCount) stops")
        }
        if let duration = segment.durationText {
            parts.append(duration)
        }
        if model.selectedSegment == segment.id { parts.append("selected") }
        if model.skippedSegment == segment.id { parts.append("passed") }
        return parts.joined(separator: ", ")
    }

    private func countdown(_ departure: TripDeparture, now: Date) -> String {
        let minutes = departure.minutesFrom(now)
        return minutes <= 0 ? "Now" : "\(minutes) min"
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "BUS": return "Bus"
        case "TRAM": return "Tram"
        case "SUBWAY": return "Subway"
        case "TRAIN": return "Train"
        case "FERRY": return "Ferry"
        case "WALK": return VelaL10n.text("transit_walk")
        default: return "Transit"
        }
    }
}
