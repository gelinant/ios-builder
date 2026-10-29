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
                Section("When") {
                    TimeChoiceBar(model: time)
                    #if DEBUG
                    Text(model.optionsDebugLine)
                        .font(.caption2.monospaced())
                        .accessibilityIdentifier("transit-options-debug")
                    #endif
                }

                Section("Vehicles") {
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
                    Text("Ferry is not offered by the Transitous planner. Leaving every vehicle off asks for all four.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Preference") {
                    Picker("Preference", selection: Binding(
                        get: { model.routePreference },
                        set: { model.setRoutePreference($0) })) {
                        Text("Best").tag(0)
                        Text("Fewer transfers").tag(2)
                        Text("Less walking").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("transit-option-preference")
                    Text("Transitous has no such search field: fewer transfers and less walking reorder the trips it returned, they do not remove trips.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        model.refreshTrips()
                    } label: {
                        Label(model.tripLoading ? "Updating trips" : "Update trips",
                              systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("transit-option-refresh")
                }
            }
            .navigationTitle("Transit options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
