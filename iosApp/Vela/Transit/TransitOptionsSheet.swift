import Foundation
import SwiftUI

/// The transit search options the Transitous planner really supports: leave now, depart at and
/// arrive by; the four vehicle filters; fewer transfers or less walking as a client-side order.
/// Ferry has no planner mode, so it is not offered. A time change re-plans through RouteStore.
struct TransitOptionsSheet: View {
    @ObservedObject var model: TransitModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var time: TimeChoiceModel

    init(model: TransitModel) {
        _model = ObservedObject(wrappedValue: model)
        _time = StateObject(wrappedValue: TimeChoiceModel(
            mode: Int32(model.timeMode),
            epochSec: model.timeEpoch,
            ids: .transitOptions,
            onApply: { mode, epoch in
                model.setTimeMode(Int(mode), epochSec: epoch)
            }))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(VelaL10n.text("transit_when")) {
                    TimeChoiceBar(model: time)
                    Text(VelaL10n.text("route_time_zone_note", String(describing: (time.zone.identifier))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transit-option-zone-note")
                    #if DEBUG
                    Text(model.optionsDebugLine)
                        .font(.caption2.monospaced())
                        .accessibilityIdentifier("transit-options-debug")
                    #endif
                }

                Section(VelaL10n.text("transit_vehicles")) {
                    vehicleRow("Bus", on: model.prefersBus, id: "transit-option-bus") {
                        model.setVehicles(bus: !model.prefersBus, subway: model.prefersSubway,
                                         train: model.prefersTrain, tram: model.prefersTram)
                    }
                    vehicleRow("Subway", on: model.prefersSubway, id: "transit-option-subway") {
                        model.setVehicles(bus: model.prefersBus, subway: !model.prefersSubway,
                                         train: model.prefersTrain, tram: model.prefersTram)
                    }
                    vehicleRow("Rail", on: model.prefersTrain, id: "transit-option-rail") {
                        model.setVehicles(bus: model.prefersBus, subway: model.prefersSubway,
                                         train: !model.prefersTrain, tram: model.prefersTram)
                    }
                    vehicleRow("Tram", on: model.prefersTram, id: "transit-option-tram") {
                        model.setVehicles(bus: model.prefersBus, subway: model.prefersSubway,
                                         train: model.prefersTrain, tram: !model.prefersTram)
                    }
                    Text(VelaL10n.text("transit_ferry_is_not_offered_by_the"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(VelaL10n.text("transit_preference")) {
                    Picker(VelaL10n.text("transit_preference"), selection: Binding(
                        get: { model.routePreference },
                        set: { model.setRoutePreference($0) })) {
                        Text(VelaL10n.text("transit_best")).tag(0)
                        Text(VelaL10n.text("place_transit_fewer_transfers")).tag(2)
                        Text(VelaL10n.text("place_transit_less_walking")).tag(3)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("transit-option-preference")
                    Text(VelaL10n.text("transit_transitous_has_no_such_search_field"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        model.refreshTrips()
                    } label: {
                        Label(model.tripLoading ? VelaL10n.text("transit_updating_trips") : VelaL10n.text("transit_update_trips"),
                              systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("transit-option-refresh")
                }
            }
            .navigationTitle(VelaL10n.text("transit_transit_options"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .accessibilityIdentifier("transit-options-close")
                }
            }
            .accessibilityIdentifier("transit-options")
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

    private func vehicleRow(_ title: String, on: Bool, id: String, _ toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
        }
        .accessibilityIdentifier(id)
    }
}
