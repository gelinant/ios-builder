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
        Section(VelaL10n.text("search_voice_cd")) {
            if store.installed.isEmpty {
                Text(VelaL10n.text("voice_download_a_speech_model_to_search"))
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
                         ? VelaL10n.text("voice_installing_name_id", String(describing: (store.entry(id)?.name ?? id)))
                         : VelaL10n.text("voice_downloading_name_id", String(describing: (store.entry(id)?.name ?? id)), String(describing: (Int(store.progress * 100)))))
                        .font(.footnote)
                    ProgressView(value: store.progress)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("asr-progress")
            } else if let recommended, !store.isInstalled(recommended.id) {
                Button {
                    store.install(recommended.id)
                } label: {
                    Label(VelaL10n.text("voice_download_mb", String(describing: (recommended.name)), String(describing: (recommended.sizeMb))),
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
                Text(VelaL10n.text("voice_mb_on_device", String(describing: (entry.sizeMb))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if store.isInUse(entry.id) {
                Text(VelaL10n.text("voice_in_use"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("asr-in-use-\(entry.id)")
            } else {
                Button(VelaL10n.text("settings_voice_row_use")) { store.select(entry.id) }
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
            .accessibilityLabel(VelaL10n.text("settings_voice_remove_title", String(describing: (entry.name))))
            .accessibilityIdentifier("asr-remove-\(entry.id)")
        }
        .frame(minHeight: 44)
    }
}
