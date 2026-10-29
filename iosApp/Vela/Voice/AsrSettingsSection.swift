import SwiftUI
import VelaCore

/// Settings > Voice > voice search: the downloadable speech engines. Same ids, archives and sizes
/// as Android (`AsrCatalog` in `:core-common`). Without one, voice search falls back to Apple's
/// on-device recognizer for the app language; with one, recognition works offline in the languages
/// the engine covers.
struct AsrSettingsSection: View {
    @ObservedObject private var store = AsrStore.shared

    private var language: String {
        DirectionsLanguage.shared.appLanguage(tag: DevicePlatformLocale.effectiveTag())
    }

    private var recommended: AsrEntry? {
        AsrCatalogView.defaultEngine(language: language)
    }

    var body: some View {
        Section("Voice search") {
            if store.installed.isEmpty {
                Text("Download a speech model to search by voice without a network. With none installed, Vela uses Apple's on-device recognition when it is available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.installed.compactMap { store.entry($0) }) { entry in
                    installedRow(entry)
                }
            }

            if let id = store.downloadingId {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.installing
                         ? "Installing \(store.entry(id)?.name ?? id)"
                         : "Downloading \(store.entry(id)?.name ?? id) \(Int(store.progress * 100))%")
                        .font(.footnote)
                    ProgressView(value: store.progress)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("asr-progress")
            } else if let recommended, !store.isInstalled(recommended.id) {
                Button {
                    store.install(recommended.id)
                } label: {
                    Label("Download \(recommended.name) (\(recommended.sizeMb) MB)",
                          systemImage: "arrow.down.circle")
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("asr-install-recommended")
            }

            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("asr-error")
            }

            #if DEBUG
            Text("ASR \(store.installed.isEmpty ? "none" : store.installed.joined(separator: ",")) lang=\(language)")
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(2)
                .accessibilityIdentifier("asr-debug")
            #endif
        }
    }

    private func installedRow(_ entry: AsrEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text("\(entry.sizeMb) MB · on-device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if store.isInUse(entry.id) {
                Text("In use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("asr-in-use-\(entry.id)")
            } else {
                Button("Use") { store.select(entry.id) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("asr-use-\(entry.id)")
            }
            Button(role: .destructive) {
                store.remove(entry.id)
            } label: {
                Image(systemName: "trash")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Remove \(entry.name)")
            .accessibilityIdentifier("asr-remove-\(entry.id)")
        }
        .frame(minHeight: 44)
    }
}
