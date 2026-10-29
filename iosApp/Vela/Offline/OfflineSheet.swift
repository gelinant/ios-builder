import SwiftUI

struct OfflineSheet: View {
    @ObservedObject var model: OfflineModel
    let onFrameArea: () -> Void
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
                        Button("Reset offline data for test") { model.resetOfflineForTest() }
                            .accessibilityIdentifier("offline-test-reset")
                    }
                    if OfflineFixtureSupport.isEnabled {
                        Button("Fixture: use update manifest") { model.useUpdateFixtureManifest() }
                            .accessibilityIdentifier("offline-test-update-manifest")
                    }
                    #endif
                }

                Section(VelaL10n.text("settings_offline_download_viewport")) {
                    Button {
                        onFrameArea()
                    } label: {
                        Label(VelaL10n.text("offline_frame_an_area_on_the_map"), systemImage: "viewfinder")
                    }
                    .accessibilityIdentifier("offline-area-start")
                    Text(VelaL10n.text("offline_pan_and_pinch_under_the_frame"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(VelaL10n.text("offline_downloaded_areas_include_the_map_places"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("offline-area-note")
                }

                if model.areaId != nil {
                    Section(VelaL10n.text("offline_area_download")) {
                        if model.areaDownloading {
                            Text(stageLabel)
                            Text(VelaL10n.text("offline_of_pieces_complete", String(describing: (model.completedPieces)), String(describing: (model.pieceCount))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("area-sheet-pieces")
                            ProgressView(value: Double(model.progress), total: 100) {
                                Text("\(model.progress)%")
                            }
                            .accessibilityIdentifier("area-sheet-progress")
                        } else if model.areaReady {
                            Text(VelaL10n.text("offline_area_ready"))
                                .accessibilityIdentifier("area-sheet-ready")
                            Text(VelaL10n.text("offline_the_map_is_saved_offline_routing"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if model.errorKey == "no_space" {
                            Text(VelaL10n.text("offline_not_enough_free_space_nothing_was"))
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("area-sheet-no-space")
                        } else if model.errorKey != nil {
                            Text(VelaL10n.text("offline_the_area_did_not_finish_of", String(describing: (model.completedPieces)), String(describing: (model.pieceCount))))
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("area-sheet-error")
                        }
                        if model.areaDataStage == "cameras" {
                            Text(VelaL10n.text("offline_saving_camera_data"))
                                .font(.caption)
                                .accessibilityIdentifier("area-sheet-cameras")
                        } else if model.areaDataStage == "addresses" {
                            Text(VelaL10n.text("offline_saving_address_data"))
                                .font(.caption)
                                .accessibilityIdentifier("area-sheet-addresses")
                        } else if model.areaCameraRows != -1 || model.areaAddressRows != -1 {
                            Text(VelaL10n.text("offline_camera_data_address_data", String(describing: (rows(model.areaCameraRows))), String(describing: (rows(model.areaAddressRows)))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("area-sheet-data")
                        }
                    }
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
                            Text(VelaL10n.text("offline_of_pieces_complete", String(describing: (model.completedPieces)), String(describing: (model.pieceCount))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("offline-pieces")
                            ProgressView(value: Double(model.progress), total: 100) {
                                Text("\(model.progress)%")
                            }
                            .accessibilityIdentifier("offline-progress")
                            Button(VelaL10n.text("settings_cancel"), role: .cancel) { model.cancel() }
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
                    Section(VelaL10n.text("offline_updating")) {
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
                        Text(VelaL10n.text("offline_updated_deltas_re_downloaded", String(describing: (regionName(updated))), String(describing: (model.updateDeltaPieces)), String(describing: (model.updateFullPieces))))
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
                            Text(VelaL10n.text("offline_not_enough_free_space_free_some"))
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("offline-no-space")
                        } else {
                            Text(VelaL10n.text("offline_download_failed_of_pieces_are_complete", String(describing: (model.completedPieces)), String(describing: (model.pieceCount))))
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("offline-error")
                        }
                    }
                }

                if let completed = model.completedId {
                    Section {
                        Text(VelaL10n.text("offline_is_ready", String(describing: (regionName(completed)))))
                            .accessibilityIdentifier("offline-ready")
                    }
                }

                Section(VelaL10n.text("offline_installed_regions")) {
                    if model.installedRows.isEmpty {
                        Text(VelaL10n.text("offline_no_regions_installed"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.installedRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(row.name)
                                    Text(VelaL10n.text("offline_installed", String(describing: (bytes(row.installedBytes)))))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityIdentifier("offline-installed-\(row.id)")
                                }
                                Spacer()
                                if row.updatable {
                                    Button(VelaL10n.text("offline_update", String(describing: (megabytes(row.updateMb))))) { model.update(row.id) }
                                        .disabled(model.downloadingId != nil || model.updatingId != nil)
                                        .accessibilityIdentifier("offline-update-\(row.id)")
                                }
                                Button(role: .destructive) { model.delete(row.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel(VelaL10n.text("list_delete_title", String(describing: (row.name))))
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

                Section(VelaL10n.text("offline_available_regions")) {
                    TextField(VelaL10n.text("offline_filter_regions"), text: $filter)
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
                            Button(VelaL10n.text("settings_download")) { model.download(row.id) }
                                .disabled(model.downloadingId != nil)
                                .accessibilityIdentifier("offline-download-\(row.id)")
                        }
                    }
                }

                Section(VelaL10n.text("offline_storage_by_category")) {
                    categoryRow("Basemap", model.basemapBytes, "basemap")
                    categoryRow("Places", model.placesBytes, "places")
                    categoryRow("Place packs", model.packBytes, "pack")
                    categoryRow("Map fonts", model.glyphBytes, "glyphs")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offline-sheet")
            .navigationTitle(VelaL10n.text("settings_offline"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
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
        case "cameras": return "Camera data"
        case "addresses": return "Address data"
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
                .accessibilityLabel(VelaL10n.text("offline_delete_for", String(describing: (label)), String(describing: (regionName(region)))))
                .accessibilityIdentifier("offline-delete-\(key)-\(region)")
            }
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func rows(_ count: Int) -> String {
        if count < 0 { return "no answer" }
        return "\(count) rows"
    }

    private func megabytes(_ value: Int) -> String {
        if value >= 1024 { return String(format: "%.1f GB", Double(value) / 1024) }
        return "\(value) MB"
    }
}
