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
            .navigationTitle(tab == 0 ? "Trip" : "Lines nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsLive = true
                    } label: {
                        Label("Live map", systemImage: "map")
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("transit-live-open")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
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
            Text(destination.isEmpty ? "Transit trip" : destination)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Refresh")
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
                Text("Times are scheduled unless the feed marked the run Live. Vela does not estimate the missing ones.")
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
                Text("Next departures")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            if let stop = header.stopName, !stop.isEmpty {
                Text(stop).font(.caption).foregroundStyle(.secondary)
            }
            if !header.available {
                Text("The board did not answer for this stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if header.departures.isEmpty {
                Text("No departure of this line is listed at this stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(header.departures) { departure in
                    departureRow(departure, now: now)
                }
            }
            if model.headerOffline {
                Text("Offline: the last saved board is shown.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if model.headerStale {
                Text("The last board is shown. Refresh failed.")
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
            Text(departure.realtime ? "Live" : "Scheduled")
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
            "\(countdown(departure, now: now)), \(departure.realtime ? "live" : "scheduled")"
                + (departure.clockText.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("transit-trip-departure")
    }

    private var progression: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live progression")
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
        .accessibilityLabel("Live progression, \(model.progressText)")
        .accessibilityIdentifier("transit-trip-progress")
    }

    private func segmentCard(_ segment: TripSegment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                segmentRail(segment)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
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
                        Text("towards \(direction)")
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
        }
    }

    @ViewBuilder private func segmentTimes(_ segment: TripSegment) -> some View {
        if segment.kind == "WAIT" {
            if let until = segment.waitUntil {
                Text("Departs \(until)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
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
                    Text(delay > 0 ? "\(delay) min late" : "\(-delay) min early")
                        .foregroundStyle(.orange)
                }
                if segment.stopCount > 0 {
                    Text("\(segment.stopCount) stops")
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
                stopLine("Board", board, segment.boardCode)
                if let alight = segment.alightName {
                    stopLine("Get off", alight, segment.alightCode)
                }
            }
        } else if segment.kind == "WAIT", let stop = segment.boardName {
            Text(stop).font(.caption).foregroundStyle(.secondary)
        } else if let target = segment.alightName {
            Text("to \(target)").font(.caption).foregroundStyle(.secondary)
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
                Button("Leave later") {
                    showsLaterChoices.toggle()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("transit-trip-leave-later")

                Button("Arrive by") {
                    model.arriveBy()
                    showsLaterChoices = false
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("transit-trip-arrive-by")

                if segment.skippable {
                    Button("Via") {
                        showsViaChoices.toggle()
                        if showsViaChoices { model.offerVia() }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("transit-trip-via")
                }

                if segment.skippable {
                    Button("Skip this one") {
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
                    Text("Leave").font(.caption).foregroundStyle(.secondary)
                    ForEach([5, 15, 30], id: \.self) { minutes in
                        Button("+\(minutes) min") {
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
                    Text("Route through")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.viaCandidates.isEmpty {
                        Text(model.viaError.isEmpty ? "No intermediate stop is listed for this ride." : model.viaError)
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
                        .accessibilityLabel("Route through \(candidate.name)")
                        .accessibilityIdentifier("transit-trip-via-candidate-\(candidate.id)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
            Text("Via \(model.viaName)")
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
                    Text("Asking Transitous for a route through \(model.viaName)").font(.caption).foregroundStyle(.secondary)
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
                            Text("Live").font(.caption2.weight(.bold)).foregroundStyle(.green)
                        }
                        Spacer(minLength: 0)
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
                Text("These pass through \(model.viaName). Picking one keeps the trip screen and the detail sheet on the same itinerary.")
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
            Text("New options")
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
                    Text("Asking Transitous").font(.caption).foregroundStyle(.secondary)
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
                            Text("Live").font(.caption2.weight(.bold)).foregroundStyle(.green)
                        }
                        Spacer(minLength: 0)
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
                Text("These come from a new Transitous search. The trip above keeps its own times until you pick one.")
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
            Label("Reported by the operator", systemImage: "exclamationmark.triangle.fill")
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
                    Text(model.nearbyStop.isEmpty ? "Lines nearby" : model.nearbyStop)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                if model.nearbyLoading && model.nearby.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading lines").font(.caption).foregroundStyle(.secondary)
                    }
                } else if model.nearby.isEmpty {
                    Text("No lines found around the trip origin. Transitous did not list any service here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transit-trip-nearby-empty")
                }
                if model.nearbyOffline {
                    Text("Offline: the last saved board is shown.").font(.caption2).foregroundStyle(.orange)
                }
                ForEach(model.nearby) { line in
                    nearbyRow(line, now: now)
                }
                Text("Lines and times come from the Transitous open feed. A line it does not serve is never listed.")
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
                    Text(departure.realtime ? "Live" : "Scheduled")
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
                    "\(line.label ?? modeLabel(line.mode)) towards \(line.headsign ?? "unknown")"
                        + ", \(countdown(departure, now: now)), \(departure.realtime ? "live" : "scheduled")")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transit-trip-nearby-line")
    }

    // MARK: Helpers

    private func segmentTitle(_ segment: TripSegment) -> String {
        switch segment.kind {
        case "WAIT": return "Wait"
        case "TRANSFER": return "Transfer walk"
        case "WALK": return "Walk"
        default:
            let line = segment.lineLabel ?? "Transit"
            return "\(modeLabel(segment.mode)) \(line)"
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
        case "WALK": return "Walk"
        default: return "Transit"
        }
    }
}
