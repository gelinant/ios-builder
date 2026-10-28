import SwiftUI
import VelaCore

/// The Settings section for the downloadable neural voice. One line in `SettingsScreen` mounts it;
/// everything else (download, remove, selection, test) lives here and in `VoiceLibrary`.
struct VoiceSettingsSection: View {
    @ObservedObject private var library = VoiceLibrary.shared
    @ObservedObject private var control = VoiceControlSettings.shared

    var body: some View {
        Group {
            voiceSection
            // VO-2: the downloadable voice-search engines, next to the spoken-guidance voices.
            AsrSettingsSection()
        }
    }

    private var voiceSection: some View {
        Section(VelaL10n.text("settings_voice")) {
            if library.installed.isEmpty {
                Text(VelaL10n.text("settings_voice_none_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.installedEntries) { entry in
                    installedRow(entry)
                }
            }

            if let id = library.downloadingId {
                VStack(alignment: .leading, spacing: 6) {
                    Text(library.installing
                         ? VelaL10n.text("map_voice_installing")
                         : VelaL10n.text("settings_voice_downloading", VoiceCatalog.entry(id)?.name ?? id, Int(library.progress * 100)))
                        .font(.footnote)
                    ProgressView(value: library.progress)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("voice-progress")
            } else if let recommended = library.recommended, !library.isInstalled(recommended.id) {
                Button {
                    library.install(recommended.id)
                } label: {
                    Label(
                        VelaL10n.text("settings_voice_install_vela", recommended.sizeMb),
                        systemImage: "arrow.down.circle")
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("voice-install-recommended")
            }

            // A push inside Settings' NavigationStack: presenting this catalog as a sheet from a
            // view that is itself inside a sheet did not reliably appear on iOS 26.
            NavigationLink {
                VoiceLibrarySheet(library: library)
            } label: {
                HStack {
                    Text(VelaL10n.text("settings_voice_library"))
                    Spacer()
                    Text("\(library.installed.count)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("voice-library")

            if library.effectiveId != nil {
                Button(VelaL10n.text("settings_voice_test")) {
                    AppGraph.navVoice.speakSample(VelaL10n.text("settings_voice_nav_sample_text"))
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("voice-test")
            }

            if let error = library.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("voice-error")
            }

            #if DEBUG
            Text(library.engineDebug)
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(2)
                .accessibilityIdentifier("voice-debug")
            #endif

            // VO-CONTROL: the Android volume tiers and speed presets. The volume is a relative
            // gain on a levelled voice, not the phone's media volume; see docs/ios/VOICE.md.
            Text(VelaL10n.text("settings_voice_volume"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker(VelaL10n.text("settings_voice_volume"), selection: Binding(
                get: { control.tier },
                set: { control.setTier($0) })) {
                ForEach(GuidanceVolumeTier.allCases) { tier in
                    Text(VelaL10n.text(tier.labelKey)).tag(tier)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("voice-volume")
            Text(VelaL10n.text("settings_voice_volume_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(VelaL10n.text("settings_voice_speed", control.speedLabel))
                Spacer(minLength: 8)
                Button {
                    control.stepRate(-GuidanceSpeed.step)
                } label: {
                    Image(systemName: "minus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(VelaL10n.text("settings_voice_speed", control.speedLabel))
                .accessibilityIdentifier("voice-speed-decrease")
                Button {
                    control.stepRate(GuidanceSpeed.step)
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(VelaL10n.text("settings_voice_speed", control.speedLabel))
                .accessibilityIdentifier("voice-speed-increase")
            }
            .frame(minHeight: 44)
            Text(VelaL10n.text("settings_voice_speed_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            #if DEBUG
            Text("speed=\(control.speedLabel) tier=\(control.gain, specifier: "%.1f") level=\(library.engineDebug)")
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .accessibilityIdentifier("voice-control-debug")
            #endif
        }
    }

    private func installedRow(_ entry: VoiceEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text("Piper · \(entry.sizeMb) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if library.isInUse(entry.id) {
                Text(VelaL10n.text("settings_voice_row_in_use", entry.name, "Piper", String(entry.sizeMb)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("voice-in-use-\(entry.id)")
            } else {
                Button(VelaL10n.text("settings_voice_row_use")) {
                    library.select(entry.id)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("voice-use-\(entry.id)")
            }
            Button(role: .destructive) {
                library.remove(entry.id)
            } label: {
                Image(systemName: "trash")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(VelaL10n.text("settings_voice_row_remove", entry.name))
            .accessibilityIdentifier("voice-remove-\(entry.id)")
        }
        .frame(minHeight: 44)
    }
}

/// The full catalog, grouped by language. Same ids as Android; a row downloads, uses or removes a
/// voice. Downloads run one at a time and stay visible while the sheet is open.
private struct VoiceLibrarySheet: View {
    @ObservedObject var library: VoiceLibrary
    @Environment(\.dismiss) private var dismiss

    private var groups: [(String, [VoiceEntry])] {
        Dictionary(grouping: VoiceCatalog.all, by: \.language)
            .map { ($0.key, $0.value) }
            .sorted { left, right in
                if left.0 == library.guidanceLanguage { return true }
                if right.0 == library.guidanceLanguage { return false }
                return VoiceCatalog.languageLabel(left.0) < VoiceCatalog.languageLabel(right.0)
            }
            .map { code, voices in
                (code, voices.sorted {
                    if $0.id == library.recommended?.id { return true }
                    if $1.id == library.recommended?.id { return false }
                    return $0.name < $1.name
                })
            }
    }

    var body: some View {
        List {
                if let error = library.lastError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                ForEach(groups, id: \.0) { code, voices in
                    Section(VoiceCatalog.languageLabel(code)) {
                        ForEach(voices) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .accessibilityIdentifier("voice-library-list")
            .navigationTitle(VelaL10n.text("settings_voice_library"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("voice-library-done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let id = library.downloadingId {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(library.installing
                             ? VelaL10n.text("map_voice_installing")
                             : VelaL10n.text("settings_voice_downloading", VoiceCatalog.entry(id)?.name ?? id, Int(library.progress * 100)))
                            .font(.footnote)
                        ProgressView(value: library.progress)
                    }
                    .padding(12)
                    .background(.regularMaterial)
                }
            }
        }

    @ViewBuilder
    private func row(_ entry: VoiceEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text("Piper · \(entry.sizeMb) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if library.isInUse(entry.id) {
                Text(VelaL10n.text("settings_voice_row_in_use", entry.name, "Piper", String(entry.sizeMb)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if library.isInstalled(entry.id) {
                Button(VelaL10n.text("settings_voice_row_use")) { library.select(entry.id) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("voice-use-\(entry.id)")
                Button(role: .destructive) { library.remove(entry.id) } label: {
                    Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(VelaL10n.text("settings_voice_row_remove", entry.name))
                .accessibilityIdentifier("voice-remove-\(entry.id)")
            } else if library.downloadingId == entry.id {
                ProgressView(value: library.progress)
                    .frame(width: 60)
            } else {
                Button {
                    library.install(entry.id)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(VelaL10n.text("settings_voice_install_vela", entry.sizeMb))
                .accessibilityIdentifier("voice-download-\(entry.id)")
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("voice-row-\(entry.id)")
    }
}
