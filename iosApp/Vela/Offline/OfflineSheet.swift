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
                    Toggle("Use Vela without Google", isOn: Binding(
                        get: { model.googleDisabled },
                        set: { model.setGoogleDisabled($0) }))
                        .accessibilityIdentifier("offline-no-google")
                    #if DEBUG
                    if LaunchOptions.current.offlineTest {
                        Button("Block network for test") { model.blockNetworkForTest() }
                            .accessibilityIdentifier("offline-test-block")
                    }
                    #endif
                }

                if let id = model.downloadingId {
                    Section(stageLabel) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(regionName(id))
                            ProgressView(value: Double(model.progress), total: 100) {
                                Text("\(model.progress)%")
                            }
                            .accessibilityIdentifier("offline-progress")
                            Button("Cancel", role: .cancel) { model.cancel() }
                                .accessibilityIdentifier("offline-cancel")
                        }
                    }
                }

                if model.errorKey != nil {
                    Section {
                        Text("Download failed. The completed files were kept for the next attempt.")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("offline-error")
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
                        HStack {
                            VStack(alignment: .leading) {
                                Text(row.name)
                                Text("Installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("offline-installed-\(row.id)")
                            }
                            Spacer()
                            Button(role: .destructive) { model.delete(row.id) } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete \(row.name)")
                            .accessibilityIdentifier("offline-delete-\(row.id)")
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
            }
            .navigationTitle("Offline maps")
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

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func megabytes(_ value: Int) -> String {
        if value >= 1024 { return String(format: "%.1f GB", Double(value) / 1024) }
        return "\(value) MB"
    }
}
