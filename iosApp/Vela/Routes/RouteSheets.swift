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
                            if model.mode != .transit {
                                Button("Try again", action: model.retry)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    ForEach(model.choices) { choice in
                        RouteChoiceRow(choice: choice, selected: choice.id == model.activeIndex) {
                            model.select(choice.id)
                        }
                        Divider()
                    }
                    if model.mode == .walk && model.hasRoute {
                        Text("Google's walking route; Vela's own foot router comes later on iOS.")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .padding(.top, 8)
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

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onStart) {
                Label("Start", systemImage: "location.north.line.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasRoute)
            .accessibilityIdentifier("route-start")
            Button {
                model.setShowsSteps(true)
            } label: {
                Label("Steps", systemImage: "list.bullet")
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
                if let active = model.choices.first(where: { $0.id == model.activeIndex }) {
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
                    ForEach(model.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: Self.symbol(step.kind))
                                .font(.title3)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.instruction)
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
                    if !model.steps.contains(where: { $0.kind == "ARRIVE" }) && !model.destinationName.isEmpty {
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
