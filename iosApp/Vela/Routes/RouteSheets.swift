import SwiftUI
import UIKit

// English for now; the String Catalog keys (I-8) come with the strings script.

/// The route chooser over the bottom of the map: the trip's ends, the mode chips with each
/// mode's time, the avoid toggles for driving, the alternates, and Start and Steps.
struct RoutePickerSheet: View {
    @ObservedObject var model: RouteModel
    let onClose: () -> Void
    /// A no-op fallback lets the route chooser ship before its navigation host is wired.
    var onStart: () -> Void = {}
    /// Transit uses its own session; nil keeps the original Start callback for embedding previews.
    var onStartTransit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            header
            modeChips
            if model.mode == .drive && model.avoidSupported {
                avoids
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.loading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Finding routes")
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                        .padding(.vertical, 12)
                    } else if let message = model.message {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message)
                                .accessibilityIdentifier("route-message")
                            Button("Try again", action: model.retry)
                        }
                        .padding(.vertical, 12)
                    }
                    ForEach(model.choices) { choice in
                        RouteChoiceRow(choice: choice, selected: choice.id == model.activeIndex) {
                            model.select(choice.id)
                        }
                        Divider()
                    }
                    if model.mode == .transit {
                        ForEach(model.transit) { trip in
                            TransitChoiceRow(trip: trip, selected: trip.id == model.activeIndex) {
                                model.select(trip.id)
                            }
                            Divider()
                        }
                        if !model.transit.isEmpty {
                            Text("Timetables from Transitous")
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                .padding(.top, 8)
                        }
                    }
                }
            }
            actions
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-sheet")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.reversed ? fromText : model.destinationName)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("route-destination")
                Text("from " + (model.reversed ? model.destinationName : fromText))
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: model.swap) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title3)
            }
            .accessibilityLabel("Reverse")
            .accessibilityIdentifier("route-swap")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("route-close")
        }
    }

    private var fromText: String {
        if let origin = model.originName { return origin }
        return model.fromMapCenter ? "the map's center" : "your location"
    }

    private var modeChips: some View {
        HStack(spacing: 6) {
            ForEach(RouteMode.allCases) { m in
                Button {
                    model.setMode(m)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: m.symbol)
                        Text(model.modeSeconds[m].map(RouteFormat.duration) ?? m.label)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(m == model.mode ? Color.white : Color(uiColor: .label))
                    .background(m == model.mode ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.label)
                .accessibilityIdentifier("route-mode-\(m.rawValue)")
            }
        }
    }

    private var avoids: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                AvoidToggle(label: "Avoid highways", on: model.avoidHighways, id: "route-avoid-highways") {
                    model.setAvoidHighways(!model.avoidHighways)
                }
                AvoidToggle(label: "Avoid tolls", on: model.avoidTolls, id: "route-avoid-tolls") {
                    model.setAvoidTolls(!model.avoidTolls)
                }
                AvoidToggle(label: "Avoid ferries", on: model.avoidFerries, id: "route-avoid-ferries") {
                    model.setAvoidFerries(!model.avoidFerries)
                }
            }
        }
    }

    private func start() {
        if model.mode == .transit, let onStartTransit {
            onStartTransit()
        } else {
            onStart()
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: start) {
                Label(
                    model.mode == .transit ? "Start transit" : VelaL10n.text("place_start"),
                    systemImage: model.mode == .transit ? "tram.fill" : "location.north.line.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasRoute)
            .accessibilityIdentifier("route-start")
            Button {
                model.setShowsSteps(true)
            } label: {
                Label(VelaL10n.text("place_steps"), systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!model.hasRoute)
            .accessibilityIdentifier("route-steps")
        }
    }
}

private struct AvoidToggle: View {
    let label: String
    let on: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: on ? "checkmark" : "plus")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(on ? Color.accentColor.opacity(0.2) : Color(uiColor: .secondarySystemBackground),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

private struct RouteChoiceRow: View {
    let choice: RouteChoice
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(RouteFormat.duration(choice.seconds))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(delayColor)
                        Text(RouteFormat.distance(choice.meters))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    if let via = choice.via {
                        Text("via \(via)")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    if choice.delaySeconds >= 60 {
                        Text("\(RouteFormat.duration(choice.delaySeconds)) slower than usual with traffic")
                            .font(.caption)
                            .foregroundStyle(delayColor)
                    } else if choice.hasTraffic {
                        Text("Traffic is light")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("route-row")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var delayColor: Color {
        if choice.delaySeconds >= 600 { return Color(uiColor: .systemRed) }
        if choice.delaySeconds >= 120 { return Color(uiColor: .systemOrange) }
        return Color(uiColor: .label)
    }
}

/// The selected route's steps, each with its maneuver's symbol and the distance to the next.
struct StepsSheet: View {
    @ObservedObject var model: RouteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            HStack {
                if let trip = model.activeTransit {
                    Text([trip.departText, trip.arriveText].compactMap { $0 }.joined(separator: " – ")
                        + (trip.durationText.map { " · \($0)" } ?? ""))
                        .font(.headline)
                } else if let active = model.choices.first(where: { $0.id == model.activeIndex }) {
                    Text("\(RouteFormat.duration(active.seconds)) · \(RouteFormat.distance(active.meters))")
                        .font(.headline)
                }
                Spacer()
                Button {
                    model.setShowsSteps(false)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .accessibilityLabel("Close steps")
                .accessibilityIdentifier("steps-close")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let trip = model.activeTransit {
                        ForEach(Array(trip.legs.enumerated()), id: \.offset) { _, leg in
                            TransitLegView(leg: leg)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("step-row")
                            Divider()
                        }
                    }
                    ForEach(model.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(systemName: Self.symbol(step.kind))
                                    .font(.title3)
                                if step.exit > 0 {
                                    Text("\(step.exit)")
                                        .font(.caption2.weight(.bold))
                                        .offset(x: 6, y: 4)
                                }
                            }
                            .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    if let ref = step.ref {
                                        Text(ref)
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(uiColor: .label), lineWidth: 1))
                                    }
                                    Text(step.instruction)
                                }
                                if !step.lanes.isEmpty {
                                    LanesView(lanes: step.lanes)
                                } else if let hint = step.laneHint {
                                    Text(hint)
                                        .font(.caption)
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                }
                                if step.meters > 0 && step.kind != "ARRIVE" {
                                    Text(RouteFormat.distance(step.meters))
                                        .font(.caption)
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("step-row")
                        Divider()
                    }
                    if !model.steps.contains(where: { $0.kind == "ARRIVE" }) && !model.destinationName.isEmpty
                        && (model.hasRoute || model.activeTransit != nil) {
                        HStack(spacing: 12) {
                            Image(systemName: Self.symbol("ARRIVE"))
                                .font(.title3)
                                .frame(width: 28)
                            Text(model.reversed ? "Arrive" : "Arrive at \(model.destinationName)")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("steps-sheet")
    }

    /// The SF Symbol of a `ManeuverType` name.
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "DEPART": return "circle.circle"
        case "ARRIVE": return "mappin.circle.fill"
        case "TURN_LEFT", "SHARP_LEFT": return "arrow.turn.up.left"
        case "TURN_RIGHT", "SHARP_RIGHT": return "arrow.turn.up.right"
        case "SLIGHT_LEFT", "KEEP_LEFT", "FORK_LEFT": return "arrow.up.left"
        case "SLIGHT_RIGHT", "KEEP_RIGHT", "FORK_RIGHT": return "arrow.up.right"
        case "RAMP_LEFT": return "arrow.up.left"
        case "RAMP_RIGHT": return "arrow.up.right"
        case "UTURN": return "arrow.uturn.down"
        case "MERGE": return "arrow.merge"
        case "ROUNDABOUT", "EXIT_ROUNDABOUT": return "arrow.triangle.2.circlepath"
        default: return "arrow.up"
        }
    }
}

/// A maneuver's lanes, left to right: the lanes to use bright, the others dimmed.
private struct LanesView: View {
    let lanes: [RouteStep.Lane]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                HStack(spacing: 0) {
                    ForEach(Array(lane.arrows.prefix(2).enumerated()), id: \.offset) { _, arrow in
                        Image(systemName: Self.symbol(arrow))
                            .font(.caption)
                    }
                }
                .frame(minWidth: 22, minHeight: 22)
                .foregroundStyle(lane.valid ? Color.white : Color.white.opacity(0.4))
                .background(Color(uiColor: lane.valid ? .systemBlue : .systemGray), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .accessibilityLabel("Lanes")
    }

    /// The SF Symbol of an OSRM lane indication.
    static func symbol(_ arrow: String) -> String {
        switch arrow {
        case "left", "sharp left": return "arrow.turn.up.left"
        case "right", "sharp right": return "arrow.turn.up.right"
        case "slight left": return "arrow.up.left"
        case "slight right": return "arrow.up.right"
        case "uturn": return "arrow.uturn.down"
        default: return "arrow.up"
        }
    }
}

/// One transit itinerary in the chooser: its times and its legs as line pills.
private struct TransitChoiceRow: View {
    let trip: TransitChoice
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(trip.seconds > 0 ? RouteFormat.duration(trip.seconds) : (trip.durationText ?? ""))
                            .font(.title3.weight(.semibold))
                        Text([trip.departText, trip.arriveText].compactMap { $0 }.joined(separator: " – "))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(trip.legs.enumerated()), id: \.offset) { i, leg in
                                if i > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                }
                                LinePill(leg: leg)
                            }
                        }
                    }
                    if let from = trip.legs.first(where: { $0.kind != "WALK" })?.from {
                        Text("from \(from)")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transit-row")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A leg as a pill: the vehicle's symbol and the line name on the line's color; a walk as a
/// figure and its minutes.
private struct LinePill: View {
    let leg: TransitChoice.Leg

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: TransitLegView.symbol(leg.kind))
            if leg.kind == "WALK" {
                if let d = leg.durationText { Text(d) }
            } else if let line = leg.line {
                Text(line).fontWeight(.semibold)
            }
        }
        .font(.caption)
        .padding(.horizontal, leg.kind == "WALK" ? 0 : 6)
        .padding(.vertical, 2)
        .foregroundStyle(leg.kind == "WALK" ? Color(uiColor: .label) : (Color(hex: leg.textColor) ?? .white))
        .background(leg.kind == "WALK" ? Color.clear : (Color(hex: leg.color) ?? Color(uiColor: .systemBlue)),
                    in: RoundedRectangle(cornerRadius: 4))
    }
}

/// One walk or ride of the selected itinerary in the steps sheet.
private struct TransitLegView: View {
    let leg: TransitChoice.Leg

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.symbol(leg.kind))
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                if leg.kind == "WALK" {
                    Text("Walk" + (leg.durationText.map { " \($0)" } ?? ""))
                } else {
                    HStack(spacing: 6) {
                        LinePill(leg: leg)
                        if let headsign = leg.headsign {
                            Text("towards \(headsign)")
                                .lineLimit(1)
                        }
                    }
                    if let from = leg.from {
                        Text([leg.departText, from].compactMap { $0 }.joined(separator: "  "))
                    }
                    let ride = [leg.durationText, leg.stops > 0 ? "\(leg.stops) stops" : nil, leg.delayText]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !ride.isEmpty {
                        Text(ride)
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    if let to = leg.to {
                        Text([leg.arriveText, to].compactMap { $0 }.joined(separator: "  "))
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    /// The SF Symbol of a `TransitMode` name.
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "WALK": return "figure.walk"
        case "BUS": return "bus.fill"
        case "TRAM": return "tram.fill"
        case "SUBWAY": return "tram.fill.tunnel"
        case "TRAIN": return "train.side.front.car"
        case "FERRY": return "ferry.fill"
        default: return "tram.fill"
        }
    }
}

private extension Color {
    /// A `#rrggbb` color, nil for anything else.
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
