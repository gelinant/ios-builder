import Foundation
import SwiftUI

/// The transit search options the Transitous planner really supports: leave now, depart at and
/// arrive by; the four vehicle filters; fewer transfers or less walking as a client-side order.
/// Ferry has no planner mode, so it is not offered. A time change re-plans through RouteStore.
struct TransitOptionsSheet: View {
    @ObservedObject var model: TransitModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode = 0
    @State private var chosenTime = Date().addingTimeInterval(900)

    init(model: TransitModel) {
        _model = ObservedObject(wrappedValue: model)
        let epoch = model.timeEpoch
        _selectedMode = State(initialValue: model.timeMode)
        _chosenTime = State(initialValue: epoch > 0
            ? Date(timeIntervalSince1970: TimeInterval(epoch))
            : Date().addingTimeInterval(900))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(VelaL10n.text("transit_when")) {
                    HStack(spacing: 6) {
                        timeButton("Leave now", mode: 0, id: "transit-option-now")
                        timeButton("Depart at", mode: 1, id: "transit-option-depart")
                        timeButton("Arrive by", mode: 2, id: "transit-option-arrive")
                    }
                    #if DEBUG
                    Text(model.optionsDebugLine)
                        .font(.caption2.monospaced())
                        .accessibilityIdentifier("transit-options-debug")
                    #endif
                    if selectedMode != 0 {
                        DatePicker("Time", selection: $chosenTime, displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("transit-option-date")
                        HStack {
                            Button("+15 min") {
                                chosenTime = chosenTime.addingTimeInterval(900)
                            }
                            .accessibilityIdentifier("transit-option-plus15")
                            Spacer()
                            Button(VelaL10n.text("transit_apply_time")) {
                                applyTime()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("transit-option-apply")
                        }
                    }
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
    }

    private func timeButton(_ title: String, mode: Int, id: String) -> some View {
        Button(title) {
            selectedMode = mode
            if mode == 0 { applyTime() }
        }
        .buttonStyle(.bordered)
        .tint(selectedMode == mode ? Color.accentColor : Color.secondary)
        .accessibilityIdentifier(id)
    }

    private func applyTime() {
        model.setTimeMode(selectedMode, epochSec: Int64(chosenTime.timeIntervalSince1970))
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
