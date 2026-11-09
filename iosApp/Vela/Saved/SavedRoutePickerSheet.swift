import SwiftUI
import UIKit

extension RouteChoice {
    /// SavedRouteDirections uses a negative duration only as an unknown-ETA marker.
    var isSavedLine: Bool { seconds < 0 }
}

/// The route chooser used only while a stored line is on offer. Unlike an ordinary route, the
/// line has no stored ETA, traffic or steps. It is a map preview; a computed route supplies Start.
struct SavedRoutePickerSheet: View {
    @ObservedObject var model: RouteModel
    let onClose: () -> Void
    let onStart: () -> Void
    let onStartTransit: () -> Void

    @StateObject private var time: TimeChoiceModel

    init(model: RouteModel, onClose: @escaping () -> Void,
         onStart: @escaping () -> Void, onStartTransit: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        _time = StateObject(wrappedValue: TimeChoiceModel(
            mode: Int32(model.timeMode.rawValue),
            epochSec: model.timeEpochSec,
            ids: .savedRoute,
            onApply: { mode, epoch in
                let chosen = RouteTimeMode(rawValue: Int(mode)) ?? .now
                model.setTime(
                    chosen,
                    date: epoch > 0 ? Date(timeIntervalSince1970: TimeInterval(epoch)) : nil)
            }))
        self.onClose = onClose
        self.onStart = onStart
        self.onStartTransit = onStartTransit
    }

    private var savedLineSelected: Bool {
        model.choices.contains { $0.id == model.activeIndex && $0.isSavedLine }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            header
            modeChips
            if model.mode == .drive && model.avoidSupported { avoids }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    timeEditor
                    Divider()
                    if model.loading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(VelaL10n.text("saved_finding_routes"))
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                        .padding(.vertical, 12)
                    } else if let message = model.message {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message).accessibilityIdentifier("route-message")
                            Button(VelaL10n.text("voice_error_retry"), action: model.retry)
                        }
                        .padding(.vertical, 12)
                    }
                    ForEach(model.choices) { choice in
                        if choice.isSavedLine {
                            SavedLineRouteRow(choice: choice, selected: choice.id == model.activeIndex) {
                                model.select(choice.id)
                            }
                        } else {
                            SavedComputedRouteRow(choice: choice, selected: choice.id == model.activeIndex) {
                                model.select(choice.id)
                            }
                        }
                        Divider()
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
        .onAppear {
            time.sync(mode: Int32(model.timeMode.rawValue), epochSec: model.timeEpochSec)
        }
        .onChange(of: model.timeMode) { _, _ in
            time.sync(mode: Int32(model.timeMode.rawValue), epochSec: model.timeEpochSec)
        }
        .onChange(of: model.timeEpochSec) { _, epoch in
            time.sync(mode: Int32(model.timeMode.rawValue), epochSec: epoch)
        }
    }

    /// The saved picker shares the one control, so a reopened stored route carries the same query
    /// and the same clock as the route sheet it replaces.
    private var timeEditor: some View {
        TimeChoiceBar(model: time)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.reversed ? fromText : model.destinationName)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("route-destination")
                Text(VelaL10n.text("route_from_prefix") + (model.reversed ? model.destinationName : fromText))
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: model.swap) {
                Image(systemName: "arrow.up.arrow.down").font(.title3)
            }
            .accessibilityLabel(VelaL10n.text("saved_reverse"))
            .accessibilityIdentifier("route-swap")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .accessibilityLabel(VelaL10n.text("place_close"))
            .accessibilityIdentifier("route-close")
        }
    }

    private var fromText: String {
        if let origin = model.originName { return origin }
        return model.fromMapCenter ? "the map's center" : "your location"
    }

    private var modeChips: some View {
        HStack(spacing: 6) {
            ForEach(RouteMode.allCases) { mode in
                Button {
                    model.setMode(mode)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.symbol)
                        Text(model.modeSeconds[mode].map(RouteFormat.duration) ?? mode.label)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(mode == model.mode ? Color.white : Color(uiColor: .label))
                    .background(
                        mode == model.mode ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
                .accessibilityIdentifier("route-mode-\(mode.rawValue)")
            }
        }
    }

    private var avoids: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                SavedAvoidToggle(label: "Avoid highways", on: model.avoidHighways, id: "route-avoid-highways") {
                    model.setAvoidHighways(!model.avoidHighways)
                }
                SavedAvoidToggle(label: "Avoid tolls", on: model.avoidTolls, id: "route-avoid-tolls") {
                    model.setAvoidTolls(!model.avoidTolls)
                }
                SavedAvoidToggle(label: "Avoid ferries", on: model.avoidFerries, id: "route-avoid-ferries") {
                    model.setAvoidFerries(!model.avoidFerries)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                if model.mode == .transit { onStartTransit() } else { onStart() }
            } label: {
                Label(
                    model.mode == .transit ? VelaL10n.text("transit_start_transit") : VelaL10n.text("place_start"),
                    systemImage: model.mode == .transit ? VelaL10n.text("saved_tram_fill") : VelaL10n.text("saved_location_north_line_fill"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasRoute || savedLineSelected)
            .accessibilityIdentifier("route-start")
            Button {
                model.setShowsSteps(true)
            } label: {
                Label(VelaL10n.text("place_steps"), systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!model.hasRoute || savedLineSelected)
            .accessibilityIdentifier("route-steps")
        }
    }
}

private struct SavedAvoidToggle: View {
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
                .background(
                    on ? Color.accentColor.opacity(0.2) : Color(uiColor: .secondarySystemBackground),
                    in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

private struct SavedLineRouteRow: View {
    let choice: RouteChoice
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? Color.accentColor : Color.clear)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.via ?? VelaL10n.text("saved_saved_route"))
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                    Text(VelaL10n.text("saved_saved_line", String(describing: (RouteFormat.distance(choice.meters)))))
                        .font(.subheadline)
                    Text(VelaL10n.text("saved_preview_only_no_stored_eta_live"))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saved-line-route")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SavedComputedRouteRow: View {
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
                        Text(RouteFormat.duration(choice.seconds)).font(.title3.weight(.semibold))
                        Text(RouteFormat.distance(choice.meters))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    if let via = choice.via { Text(VelaL10n.text("exp_chooser_via", String(describing: (via)))).font(.subheadline).lineLimit(1) }
                    if choice.delaySeconds >= 60 {
                        Text(VelaL10n.text("saved_slower_than_usual_with_traffic", String(describing: (RouteFormat.duration(choice.delaySeconds)))))
                            .font(.caption)
                    } else if choice.hasTraffic {
                        Text(VelaL10n.text("saved_traffic_is_light"))
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
}
