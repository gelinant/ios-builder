import SwiftUI
import UIKit
import VelaCore

enum RoutePlacePickKind: String, Identifiable {
    case origin
    case waypoint

    var id: String { rawValue }
}

/// Endpoint and stop search kept separate from the map's search state. Saved rows include quick
/// saves, list entries and the parking marker supplied by MapScreen.
struct RoutePlacePicker: View {
    let kind: RoutePlacePickKind
    @ObservedObject var model: RouteModel
    let savedPlaces: [SavedMapMarker]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField(VelaL10n.text("route_search_for_a_place"), text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("route-place-search-field")
                        .onSubmit(search)
                    Button(VelaL10n.text("settings_search"), action: search)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
                        .accessibilityIdentifier("route-place-search")
                }
                .padding()
                List {
                    Section {
                        if kind == .origin {
                            Button {
                                model.useCurrentLocationAsOrigin()
                                dismiss()
                            } label: {
                                Label(VelaL10n.text("mapscreen_your_location"), systemImage: "location.fill")
                            }
                            .accessibilityIdentifier("route-origin-current")
                        }
                        Button {
                            if kind == .origin {
                                model.useMapCenterAsOrigin()
                            } else {
                                model.addMapCenterWaypoint()
                            }
                            dismiss()
                        } label: {
                            Label(kind == .origin ? VelaL10n.text("route_use_map_center") : VelaL10n.text("route_add_map_center_as_stop"), systemImage: "mappin.and.ellipse")
                        }
                        .accessibilityIdentifier(kind == .origin ? "route-origin-map-center" : "route-waypoint-map-center")
                    }
                    if searching {
                        Section {
                            HStack {
                                ProgressView()
                                Text(VelaL10n.text("route_searching"))
                            }
                        }
                    } else if let message {
                        Section {
                            Text(message)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                .accessibilityIdentifier("route-place-message")
                        }
                    } else if !results.isEmpty {
                        Section(VelaL10n.text("route_search_results")) {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, place in
                                Button {
                                    pick(place)
                                } label: {
                                    RoutePlaceLabel(name: place.name, address: place.address)
                                }
                                .accessibilityIdentifier("route-place-result")
                            }
                        }
                    }
                    if !savedPlaces.isEmpty {
                        Section(VelaL10n.text("settings_saved_places")) {
                            ForEach(savedPlaces) { place in
                                Button {
                                    if kind == .origin {
                                        model.useSavedOrigin(place)
                                    } else {
                                        model.addSavedWaypoint(place)
                                    }
                                    dismiss()
                                } label: {
                                    RoutePlaceLabel(name: place.name, address: nil)
                                }
                                .accessibilityIdentifier("route-saved-place")
                            }
                        }
                    }
                }
            }
            .navigationTitle(kind == .origin ? VelaL10n.text("route_choose_origin") : VelaL10n.text("place_add_stop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(VelaL10n.text("place_close")) { dismiss() }
                        .accessibilityIdentifier("route-place-close")
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func pick(_ place: Place) {
        if kind == .origin {
            model.useSearchedOrigin(place)
        } else {
            model.addSearchedWaypoint(place)
        }
        dismiss()
    }

    private func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        searchTask?.cancel()
        searching = true
        message = nil
        searchTask = Task { @MainActor in
            do {
                let places = try await model.findPlaces(term)
                guard !Task.isCancelled else { return }
                results = places
                searching = false
                message = places.isEmpty ? "No results" : nil
            } catch {
                guard !Task.isCancelled else { return }
                searching = false
                message = "Search failed"
            }
        }
    }
}

private struct RoutePlaceLabel: View {
    let name: String
    let address: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .foregroundStyle(Color(uiColor: .label))
            if let address, !address.isEmpty {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Intermediate stops in travel order. Explicit arrows make reordering available to accessibility
/// and UI tests as well as touch users.
struct RouteStopsOptions: View {
    @ObservedObject var model: RouteModel
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.waypoints) { stop in
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Color(uiColor: .systemOrange))
                    Text(stop.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.waypoints.count > 1 {
                        Button {
                            model.moveWaypoint(from: stop.id, to: stop.id - 1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(stop.id == 0)
                        .accessibilityLabel(VelaL10n.text("place_move_stop_up"))
                        .accessibilityIdentifier("route-waypoint-up-\(stop.id)")
                        Button {
                            model.moveWaypoint(from: stop.id, to: stop.id + 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(stop.id == model.waypoints.count - 1)
                        .accessibilityLabel(VelaL10n.text("place_move_stop_down"))
                        .accessibilityIdentifier("route-waypoint-down-\(stop.id)")
                    }
                    Button {
                        model.removeWaypoint(stop.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(VelaL10n.text("nav_stop_offer_remove"))
                    .accessibilityIdentifier("route-waypoint-remove-\(stop.id)")
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("route-waypoint-row")
            }
            Button(action: onAdd) {
                Label(VelaL10n.text("place_add_stop"), systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(!model.canAddWaypoint || model.mode == .transit)
            .accessibilityIdentifier("route-add-stop")
            if model.mode == .transit && !model.waypoints.isEmpty {
                Text(VelaL10n.text("route_transitous_plans_between_the_two_ends"))
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .padding(.vertical, 4)
    }
}

/// The bike profile step of the chooser. Both profiles plan this bike trip again; neither changes
/// the travel mode, so a tap can never silently turn a ride into a drive. The three Android knobs
/// this open router cannot honour are named as unsupported instead of being offered as switches
/// that would do nothing.
struct RouteBikeProfileStep: View {
    @ObservedObject var model: RouteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(VelaL10n.text("route_bike_profile"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            HStack(spacing: 6) {
                profile(
                    "Bike lanes and quiet streets", safe: true,
                    id: "route-bike-profile-safe")
                profile(
                    "Fastest route", safe: false,
                    id: "route-bike-profile-fast")
            }
            Text(VelaL10n.text("route_replans_this_bike_trip_only_the"))
                .font(.caption2)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Text(VelaL10n.text("route_avoid_hills_steps_and_unpaved_surfaces"))
                .font(.caption2)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityIdentifier("route-bike-unsupported")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-bike-profile")
    }

    private func profile(_ title: String, safe: Bool, id: String) -> some View {
        Button {
            model.setBikeSafe(safe)
        } label: {
            Label(title, systemImage: safe ? VelaL10n.text("route_checkmark_shield") : "bolt")
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .background(model.bikeSafe == safe
                    ? Color.accentColor.opacity(0.2)
                    : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(model.bikeSafe == safe ? .isSelected : [])
    }
}

/// The route sheet's use of the shared time control. A date edit stays local until Apply, so the
/// picker cannot send a request for every intermediate value. In transit the store re-runs the plan;
/// in driving the estimate changes without a keyless refetch, which the summary says.
struct RouteTimeOptions: View {
    @ObservedObject var model: RouteModel
    @StateObject private var time: TimeChoiceModel

    init(model: RouteModel) {
        _model = ObservedObject(wrappedValue: model)
        _time = StateObject(wrappedValue: TimeChoiceModel(
            mode: Int32(model.timeMode.rawValue),
            epochSec: model.timeEpochSec,
            ids: .route,
            onApply: { mode, epoch in
                let chosen = RouteTimeMode(rawValue: Int(mode)) ?? .now
                model.setTime(
                    chosen,
                    date: epoch > 0 ? Date(timeIntervalSince1970: TimeInterval(epoch)) : nil)
            }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimeChoiceBar(model: time)
            if model.mode == .transit {
                Text(VelaL10n.text("route_time_zone_note", String(describing: (time.zone.identifier))))
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("route-time-zone-note")
            }
            if model.mode == .drive,
               let summary = RouteFormat.driveTimeSummary(mode: model.timeMode, date: model.timeDate, choice: model.activeChoice) {
                Text(summary.0)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("route-time-summary")
                Text(summary.1)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityIdentifier("route-time-note")
            }
        }
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
}
