import SwiftUI

struct OfflineSheet: View {
    @ObservedObject var model: OfflineModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Current region", value: model.currentRegionName ?? "Not located")
                    LabeledContent("Downloaded data", value: bytes(model.totalBytes))
                        .accessibilityIdentifier("offline-total-size")
                    Toggle(VelaL10n.text("settings_google_free"), isOn: Binding(
                        get: { model.googleDisabled },
                        set: { model.setGoogleDisabled($0) }))
                        .accessibilityIdentifier("offline-no-google")
                    LabeledContent("World basemap", value: model.worldInstalled ? "Installed" : "Missing")
                        .accessibilityIdentifier("offline-world-state")
                    #if DEBUG
                    if LaunchOptions.current.offlineTest {
                        Button("Block network for test") { model.blockNetworkForTest() }
                            .accessibilityIdentifier("offline-test-block")
                    }
                    if OfflineFixtureSupport.isEnabled {
                        Button("Fixture: use update manifest") { model.useUpdateFixtureManifest() }
                            .accessibilityIdentifier("offline-test-update-manifest")
                    }
                    #endif
                }


                if let id = model.downloadingId {
                    Section(stageLabel) {
                        VStack(alignment: .leading, spacing: 8) {
                            #if DEBUG
                            if LaunchOptions.current.offlineTest {
                                Text(model.downloadDebugLine)
                                    .font(.caption2)
                                    .accessibilityIdentifier("offline-download-debug")
                            }
                            #endif
                            Text(regionName(id))
                            Text("\(model.completedPieces) of \(model.pieceCount) pieces complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("offline-pieces")
                            ProgressView(value: Double(model.progress), total: 100) {
                                Text("\(model.progress)%")
                            }
                            .accessibilityIdentifier("offline-progress")
                            Button("Cancel", role: .cancel) { model.cancel() }
                                .accessibilityIdentifier("offline-cancel")
                            #if DEBUG
                            if LaunchOptions.current.offlineTest {
                                Button("Suspend for relaunch test") { model.suspendDownloadForTest() }
                                    .accessibilityIdentifier("offline-test-suspend")
                            }
                            #endif
                        }
                    }
                }

                if let id = model.updatingId {
                    Section("Updating") {
                        Text(regionName(id))
                        #if DEBUG
                        if LaunchOptions.current.offlineTest || OfflineFixtureSupport.isEnabled {
                            Text(model.updateDebugLine)
                                .font(.caption2)
                                .accessibilityIdentifier("offline-update-debug")
                        }
                        #endif
                        ProgressView(value: Double(model.progress), total: 100) {
                            Text("\(model.progress)%")
                        }
                        .accessibilityIdentifier("offline-update-progress")
                    }
                }

                if let updated = model.updatedId {
                    Section {
                        Text("\(regionName(updated)) updated: \(model.updateDeltaPieces) deltas, \(model.updateFullPieces) re-downloaded")
                            .accessibilityIdentifier("offline-updated")
                        #if DEBUG
                        if LaunchOptions.current.offlineTest || OfflineFixtureSupport.isEnabled {
                            Text("updated=\(updated) delta=\(model.updateDeltaPieces) full=\(model.updateFullPieces)")
                                .font(.caption2)
                                .accessibilityIdentifier("offline-updated-debug")
                        }
                        #endif
                    }
                }

                if model.errorKey != nil {
                    Section {
                        if model.errorKey == "no_space" {
                            Text("Not enough free space. Free some space and try again; nothing was installed.")
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("offline-no-space")
                        } else {
                            Text("Download failed. \(model.completedPieces) of \(model.pieceCount) pieces are complete and will be reused.")
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("offline-error")
                        }
                    }
                }

                if let completed = model.completedId {
                    Section {
                        Text("\(regionName(completed)) is ready")
                            .accessibilityIdentifier("offline-ready")
                    }
                }

                Section("Installed regions") {
                    if model.installedRows.isEmpty {
                        Text("No regions installed")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.installedRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(row.name)
                                    Text("Installed \(bytes(row.installedBytes))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityIdentifier("offline-installed-\(row.id)")
                                }
                                Spacer()
                                if row.updatable {
                                    Button("Update \(megabytes(row.updateMb))") { model.update(row.id) }
                                        .disabled(model.downloadingId != nil || model.updatingId != nil)
                                        .accessibilityIdentifier("offline-update-\(row.id)")
                                }
                                Button(role: .destructive) { model.delete(row.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Delete \(row.name)")
                                .accessibilityIdentifier("offline-delete-\(row.id)")
                            }
                            if let categories = model.categories(row.id) {
                                categoryLine(row.id, "pack", "Place pack", categories.packBytes)
                                categoryLine(row.id, "places", "Places", categories.placesBytes)
                                categoryLine(row.id, "basemap", "Basemap", categories.basemapBytes)
                            }
                        }
                    }
                }

                Section("Available regions") {
                    TextField("Filter regions", text: $filter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("offline-filter")
                    ForEach(availableRows) { row in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(row.name)
                                Text(megabytes(row.sizeMb))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Download") { model.download(row.id) }
                                .disabled(model.downloadingId != nil)
                                .accessibilityIdentifier("offline-download-\(row.id)")
                        }
                    }
                }

                Section("Storage by category") {
                    categoryRow("Basemap", model.basemapBytes, "basemap")
                    categoryRow("Places", model.placesBytes, "places")
                    categoryRow("Place packs", model.packBytes, "pack")
                    categoryRow("Map fonts", model.glyphBytes, "glyphs")
                }
            }
            .navigationTitle(VelaL10n.text("settings_offline"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("offline-done")
                }
            }
            .onAppear {
                model.start()
                model.refresh()
            }
        }
    }

    private var availableRows: [OfflineRow] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.rows.filter {
            !$0.installed && (query.isEmpty || $0.name.lowercased().contains(query) || $0.id.contains(query))
        }
    }

    private var stageLabel: String {
        switch model.stage {
        case "pack": return "Place pack"
        case "places": return "Places archive"
        case "glyphs": return "Map fonts"
        case "basemap": return "Offline basemap"
        default: return "Preparing download"
        }
    }

    private func regionName(_ id: String) -> String {
        model.rows.first { $0.id == id }?.name ?? id
    }

    @ViewBuilder
    private func categoryRow(_ label: String, _ value: Int64, _ key: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(bytes(value))
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("offline-size-\(key)")
    }

    @ViewBuilder
    private func categoryLine(_ region: String, _ key: String, _ label: String, _ value: Int64) -> some View {
        if value > 0 {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(bytes(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    model.deleteCategory(region, category: key)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .accessibilityLabel("Delete \(label) for \(regionName(region))")
                .accessibilityIdentifier("offline-delete-\(key)-\(region)")
            }
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func megabytes(_ value: Int) -> String {
        if value >= 1024 { return String(format: "%.1f GB", Double(value) / 1024) }
        return "\(value) MB"
    }
}
