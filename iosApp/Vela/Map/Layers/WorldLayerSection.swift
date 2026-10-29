import SwiftUI
import VelaCore

/// The generic "World layers" section of the map layers sheet. It draws one row per entry from
/// `WorldLayersHub`, with the layer's source, its data timestamp and one of three states. An entry
/// whose own lot has not landed yet stays disabled and says "not installed"; a layer that needs a
/// key shows whether one is saved, never the key, and a secure field to replace it.
struct WorldLayerSection: View {
    @ObservedObject private var hub = WorldLayersHub.shared
    @State private var keyDrafts: [String: String] = [:]

    var body: some View {
        Section {
            ForEach(hub.layers.indices, id: \.self) { index in
                layerRow(hub.layers[index])
            }
            Text(hub.debugLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("world-layers-debug")
        } header: {
            Text("World layers")
        } footer: {
            Text("Every layer is off until you turn it on. A layer reads its source only while it is on, shows the age of its last data, and stops drawing when the data is older than its own window. Layers marked not installed do not exist in this build yet.")
        }
        .onAppear { hub.reload() }
    }

    @ViewBuilder
    private func layerRow(_ layer: WorldLayer) -> some View {
        let state = hub.state(layer.id)
        let installed = layer.isInstalled
        VStack(alignment: .leading, spacing: 5) {
            Button {
                hub.setEnabled(layer.id, !hub.isOn(layer.id))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.title)
                        Text(installed ? stateLine(state) : "Not installed in this build")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: hub.isOn(layer.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(hub.isOn(layer.id) ? Color.accentColor : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!installed)
            .accessibilityIdentifier("world-layer-\(layer.id)")
            .accessibilityValue(Text(hub.isOn(layer.id) ? "on"
                                     : (installed ? "off" : "not installed")))

            Text("Source: \(layer.source)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Data: \(timestampText(state))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(stateLine(state))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if state?.needsKey == true {
                keyRow(layer, state: state)
                if state?.keyPresent == true {
                    Text("Key saved in the Keychain.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No key saved. This layer stays unavailable until a key is added.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(hub.rows[layer.id] ?? []) { row in
                Button {
                    if let lat = row.lat, let lng = row.lng {
                        WorldLayers.focus(latitude: lat, longitude: lng)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(.caption)
                        if !row.detail.isEmpty {
                            Text(row.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(row.lat == nil || row.lng == nil)
                .accessibilityIdentifier("world-row-\(row.id)")
            }
        }
    }

    @ViewBuilder
    private func keyRow(_ layer: WorldLayer, state: WorldLayerState?) -> some View {
        HStack(spacing: 8) {
            SecureField("Layer key", text: Binding(
                get: { keyDrafts[layer.id] ?? "" },
                set: { keyDrafts[layer.id] = $0 }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("world-key-field-\(layer.id)")
            Button("Save") {
                hub.setKey(layer.id, keyDrafts[layer.id] ?? "")
                keyDrafts[layer.id] = ""
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("world-key-save-\(layer.id)")
            if state?.keyPresent == true {
                Button("Clear") {
                    hub.clearKey(layer.id)
                    keyDrafts[layer.id] = ""
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("world-key-clear-\(layer.id)")
            }
        }
    }

    /// The three states, plus the two unavailable reasons the user can act on.
    private func stateLine(_ state: WorldLayerState?) -> String {
        guard let state else { return "Unavailable" }
        switch state.status {
        case "fresh":
            return "Fresh, \(state.ageSeconds) s old"
        case "late":
            return "Late, older than \(state.maxAgeSeconds) s"
        default:
            if state.needsKey && !state.keyPresent { return "Unavailable, key required" }
            if !state.installed { return "Unavailable, not installed" }
            return "Unavailable, no data yet"
        }
    }

    private func timestampText(_ state: WorldLayerState?) -> String {
        guard let state, state.updatedAtMs > 0 else { return "no data yet" }
        let date = Date(timeIntervalSince1970: Double(state.updatedAtMs) / 1_000)
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
