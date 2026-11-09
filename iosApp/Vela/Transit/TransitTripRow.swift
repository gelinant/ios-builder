import SwiftUI

/// One itinerary in the transit chooser. The leg ribbon comes first: a pill per ride in the line's
/// own color with its mode symbol, the walk minutes between them. Under it, the departure and the
/// arrival, the length, the transfers, the walking and the Live or Scheduled word. The chevron
/// unfolds each leg: line, direction, boarding stop and time, stop count, alighting stop and time.
struct TransitTripRow: View {
    let trip: TransitChoice
    let selected: Bool
    let onSelect: () -> Void
    @State private var showsLegs = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            HStack(alignment: .top, spacing: Design.Spacing.xs) {
                Button(action: onSelect) {
                    summary
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.spokenSummary(trip))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("transit-row")
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsLegs.toggle() }
                } label: {
                    Image(systemName: showsLegs ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsLegs ? VelaL10n.text("transit_trip_hide_legs") : VelaL10n.text("transit_trip_show_legs"))
                .accessibilityIdentifier("transit-row-expand")
            }
            if showsLegs {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(trip.legs.enumerated()), id: \.offset) { _, leg in
                        TransitTripLegDetail(leg: leg)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("transit-row-leg")
                    }
                }
                .padding(.leading, Design.Spacing.s)
            }
        }
        .padding(.horizontal, Design.Spacing.s)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(selected ? Color.accentColor : Color(uiColor: .separator), lineWidth: selected ? 2 : 0.5))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                Text(Self.length(trip))
                    .font(.title3.weight(.semibold))
                if let clock = Self.clock(trip) {
                    Text(clock)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: Design.Spacing.xs)
                TransitTimeWord(live: trip.live)
            }
            FlowLayout(spacing: 4) {
                ForEach(Array(trip.legs.enumerated()), id: \.offset) { i, leg in
                    HStack(spacing: 4) {
                        if i > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        TransitLegPill(leg: leg)
                    }
                }
            }
            Text(Self.counts(trip))
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func length(_ trip: TransitChoice) -> String {
        trip.seconds > 0 ? RouteFormat.duration(trip.seconds) : (trip.durationText ?? "")
    }

    static func times(_ trip: TransitChoice) -> String? {
        guard let depart = trip.departText, let arrive = trip.arriveText else {
            return trip.departText ?? trip.arriveText
        }
        return VelaL10n.text("place_depart_arrive", depart, arrive)
    }

    static func transfers(_ count: Int) -> String {
        count <= 0 ? VelaL10n.text("transit_trip_direct") : VelaL10n.text("transit_transfers_count", count)
    }

    /// "4:30 PM – 4:46 PM", the short form beside the length.
    static func clock(_ trip: TransitChoice) -> String? {
        let ends = [trip.departText, trip.arriveText].compactMap { $0 }
        return ends.isEmpty ? nil : ends.joined(separator: " – ")
    }

    /// "1 change · 6 min walk".
    static func counts(_ trip: TransitChoice) -> String {
        var parts = [transfers(trip.transfers)]
        if trip.walkSeconds > 0 {
            parts.append(VelaL10n.text("transit_trip_walk_total", RouteFormat.duration(trip.walkSeconds)))
        }
        return parts.joined(separator: " · ")
    }

    /// "Depart 4:30 PM · arrive 4:46 PM · 1 change · 6 min walk".
    static func facts(_ trip: TransitChoice) -> String {
        ([times(trip)].compactMap { $0 } + [counts(trip)]).joined(separator: " · ")
    }

    static func spokenSummary(_ trip: TransitChoice) -> String {
        let rides = trip.legs.filter { !$0.isWalk }.map(\.spokenTitle).joined(separator: ", ")
        return [length(trip), rides, facts(trip), TransitTimeWord.word(trip.live)].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

/// "Live" when the planner marked the times real-time, "Scheduled" otherwise. Always a word.
struct TransitTimeWord: View {
    let live: Bool

    static func word(_ live: Bool) -> String {
        live ? VelaL10n.text("place_transit_live") : VelaL10n.text("place_transit_scheduled")
    }

    var body: some View {
        Text(Self.word(live))
            .font(.caption.weight(.semibold))
            .foregroundStyle(live ? Color(uiColor: .systemGreen) : Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(live ? Color(uiColor: .systemGreen) : Color(uiColor: .separator), lineWidth: 1))
    }
}

/// A ride as its line's pill (mode symbol and line name on the agency color, else Vela's mode
/// color), a walk as a figure and its minutes.
struct TransitLegPill: View {
    let leg: TransitChoice.Leg

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: leg.mode.symbol)
            if leg.isWalk {
                if let d = leg.durationText { Text(d) }
            } else {
                Text(leg.line ?? leg.mode.name).fontWeight(.semibold)
            }
        }
        .font(.caption)
        .padding(.horizontal, leg.isWalk ? 0 : 6)
        .padding(.vertical, 3)
        .foregroundStyle(leg.isWalk ? Color(uiColor: .label) : TransitActivityPalette.text(fill: leg.fill, explicit: leg.textColor))
        .background(leg.isWalk ? Color.clear : TransitActivityPalette.fill(leg.fill), in: RoundedRectangle(cornerRadius: 5))
        .fixedSize()
    }
}

/// One leg of an unfolded row. A ride: its pill, title and direction, the boarding time and stop,
/// the stop count, the length and the Live or Scheduled word, then the alighting time and stop.
private struct TransitTripLegDetail: View {
    let leg: TransitChoice.Leg

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.s) {
            Image(systemName: leg.mode.symbol)
                .font(.body)
                .frame(width: 24)
                .foregroundStyle(leg.isWalk ? Color(uiColor: .secondaryLabel) : TransitActivityPalette.fill(leg.fill))
            VStack(alignment: .leading, spacing: 2) {
                if leg.isWalk {
                    Text(VelaL10n.text("transit_nav_walk", leg.durationText ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                } else {
                    HStack(spacing: 6) {
                        TransitLegPill(leg: leg)
                        Text(leg.spokenTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    if let headsign = leg.headsign {
                        Text(VelaL10n.text("transit_nav_towards", headsign))
                            .font(.subheadline)
                    }
                    if let from = leg.from {
                        Text([leg.departText, from].compactMap { $0 }.joined(separator: "  "))
                            .font(.subheadline)
                    }
                    Text(rideFacts)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    if let to = leg.to {
                        Text([leg.arriveText, to].compactMap { $0 }.joined(separator: "  "))
                            .font(.subheadline)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    /// "5 stops · 9 min · Scheduled", with the feed's delay when it sent one.
    private var rideFacts: String {
        var parts: [String] = []
        if leg.stops > 0 { parts.append(VelaL10n.text("place_transit_stops", leg.stops)) }
        if let d = leg.durationText { parts.append(d) }
        if let delay = leg.delayText { parts.append(delay) }
        parts.append(TransitTimeWord.word(leg.live))
        return parts.joined(separator: " · ")
    }
}

extension TransitChoice.Leg {
    /// The readable vehicle, from the planner's own mode name when it sent one.
    var mode: TransitLegMode { TransitLegMode.of(kind: modeName ?? kind) }

    /// The line's feed color, else Vela's mode color.
    var fill: String? { color ?? (modeColor.isEmpty ? nil : modeColor) }

    /// "Bus 14R", "Yellow-N", "Funicular CA".
    var spokenTitle: String { mode.title(line: line, agency: agency) }
}
