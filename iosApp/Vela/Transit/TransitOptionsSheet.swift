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
                Section("When") {
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
                            Button("Apply time") {
                                applyTime()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("transit-option-apply")
                        }
                    }
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
