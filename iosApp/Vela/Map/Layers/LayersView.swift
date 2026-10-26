import SwiftUI

/// The map's layers sheet: the overlays this build can draw from common data, the PoI categories,
/// and the two Google rasters this build deliberately does not offer.
struct LayersView: View {
    @ObservedObject var model: LayersModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    layerToggle("Painted road markings", key: "painted",
                                detail: "Lane, center, bike and crossing markings at close zoom.")
                    layerToggle("Speed cameras", key: "speed",
                                detail: "Fixed OSM speed cameras from Overpass.")
                    layerToggle("ALPR cameras", key: "alpr",
                                detail: "Plate readers mapped by DeFlock in OpenStreetMap.")
                    layerToggle("Traffic lights and crossings", key: "controls",
                                detail: "Signals, stop signs, level crossings and speed humps at close zoom.")
                    layerToggle("UK fuel prices", key: "fuel",
                                detail: "Fuel Finder forecourts, only where the UK data covers the view.")
                    layerToggle("Bridge openings", key: "bridges",
                                detail: "Planned and current openings from the Dutch NDW feed.")
                } header: {
                    Text("Layers")
                } footer: {
                    Text("Each layer loads only while it is on and the map is close enough to read it.")
                }

                Section {
                    HStack {
                        Text("Live traffic")
                        Spacer()
                        Text("Not in this build")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("layer-traffic-unavailable")
                    }
                    HStack {
                        Text("Satellite")
                        Spacer()
                        Text("Not in this build")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("layer-satellite-unavailable")
                    }
                } header: {
                    Text("Google layers")
                } footer: {
                    Text("Google's traffic and satellite rasters are not ported to iOS. Their tile endpoints live in the Android app module only, so no switch is offered rather than a broken one.")
                }

                Section {
                    buttonRow("Show places", isOn: model.showPlaces, id: "poi-places") {
                        model.setShowPlaces(!model.showPlaces)
                    }
                    categoryToggle("Food and drink", key: "food", id: "poi-food")
                    categoryToggle("Fuel and charging", key: "fuel", id: "poi-fuel")
                    categoryToggle("Transit stops", key: "transit", id: "poi-transit")
                    categoryToggle("Parking", key: "parking", id: "poi-parking")
                    categoryToggle("Parks, shops and civic places", key: "other", id: "poi-other")
                    Picker("Density", selection: Binding(
                        get: { model.poiDensity },
                        set: { model.setDensity($0) })) {
                        Text("Normal").tag("normal")
                        Text("Compact").tag("compact")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("poi-density")
                } header: {
                    Text("Places on the map")
                } footer: {
                    Text("Compact raises the zoom at which lower-priority place groups appear. Basemap labels keep MapLibre's own collision rules.")
                }

                Section {
                    Text(model.debugLine)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("layers-sheet-debug")
                }
            }
            .navigationTitle("Map layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("layers-close")
                }
            }
        }
    }

    private func layerToggle(_ title: String, key: String, detail: String) -> some View {
        let on = model.enabled.contains(key)
        return Button {
            model.setLayer(key, !on)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(statusText(key, detail: detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("layer-\(key)")
        .accessibilityValue(Text(on ? "on" : "off"))
    }

    private func categoryToggle(_ title: String, key: String, id: String) -> some View {
        buttonRow(title, isOn: model.categories.contains(key), id: id) {
            model.setCategory(key, !model.categories.contains(key))
        }
    }

    /// A checkmark row rather than a Toggle: the whole row is the control, so a tap anywhere
    /// flips it, including from XCUITest (a Toggle's accessibility frame covers its label, which
    /// does not toggle in a Form).
    private func buttonRow(
        _ title: String, isOn: Bool, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(Text(isOn ? "on" : "off"))
    }

    private func statusText(_ key: String, detail: String) -> String {
        let status = model.snapshot(key)
        switch status.phase {
        case "loading": return "Loading"
        case "ready": return status.count == 1 ? "1 shown" : "\(status.count) shown"
        case "error": return "Failed. Pan the map to retry."
        case "zoom": return "Zoom in to load"
        case "unavailable":
            return key == "fuel" ? "Only available in the UK" : "Only available in the Netherlands"
        case "idle": return "Waiting for the map"
        default: return detail
        }
    }
}
