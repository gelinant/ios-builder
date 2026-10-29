import SwiftUI
import VelaCore

/// Settings > Voice. One place explains every spoken state: the Android On / Alerts only / Off
/// mode, the guidance language (which may differ from the menus), the neural voices on disk, the
/// iPhone fallback, the VO-CONTROL volume and speed, and the VO-2 voice-search engines.
///
/// Platform limits are stated where they apply: the iPhone voice cannot be levelled or amplified,
/// and a guidance language with no installed neural voice falls back to it.
struct VoiceSettingsSection: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var library = VoiceLibrary.shared
    @ObservedObject private var control = VoiceControlSettings.shared
    @ObservedObject private var mode = VoiceModeSettings.shared

    var body: some View {
        Group {
            voiceSection
            AsrSettingsSection()
        }
    }

    private var voiceSection: some View {
        Section(VelaL10n.text("settings_voice")) {
            modeRows
            languageRows
            statusRows
            downloadRows
            installedRows
            libraryRow
            testRow
            volumeRows
            speedRows
            #if DEBUG
            debugRow
            #endif
        }
    }

    // MARK: - Mode

    /// The two keys NAV-LIFE writes (`spoken_directions`, `spoken_alerts_only`) through the shared
    /// `NavStore`. This row and the in-drive speaker button read and write the same state.
    @ViewBuilder
    private var modeRows: some View {
        Text(VelaL10n.text("settings_spoken_directions"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        Picker(VelaL10n.text("settings_spoken_directions"), selection: Binding(
            get: { mode.mode },
            set: { mode.setMode($0) })) {
            ForEach(VoiceMode.allCases) { value in
                Text(VelaL10n.text(value.labelKey)).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("voice-mode")
        Text(VelaL10n.text("settings_voice_mode_hint"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        #if DEBUG
        Text(mode.debugLine)
            .font(.caption2.monospaced())
            .dynamicTypeSize(.xSmall)
            .lineLimit(2)
            .accessibilityIdentifier("voice-mode-debug")
        #endif
    }

    // MARK: - Language

    @ViewBuilder
    private var languageRows: some View {
        SettingsMenu(
            id: "voice-directions-language",
            title: VelaL10n.text("settings_directions_language"),
            selection: Binding(get: { model.directionsLanguage }, set: model.setDirectionsLanguage),
            options: model.directionsLanguageOptions)
        Text(VelaL10n.text("settings_directions_language_hint"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        if model.appLanguageHasNoGuidance && model.directionsLanguage.isEmpty {
            Text(VelaL10n.text("settings_voice_app_language_note_ios"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voice-app-language-note")
        }
    }

    // MARK: - What will speak

    @ViewBuilder
    private var statusRows: some View {
        if let entry = library.effectiveEntry {
            Text(VelaL10n.text("settings_voice_current_ios", entry.name, "Vela"))
                .accessibilityIdentifier("voice-current")
        } else {
            Text(VelaL10n.text("settings_voice_current_system_ios"))
                .accessibilityIdentifier("voice-current")
        }

        if !library.hasCatalogVoice {
            Text(VelaL10n.text(
                "settings_voice_no_neural_language_ios",
                DirectionsLanguage.shared.label(tag: library.guidanceLanguageTag)))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voice-no-neural-language")
        } else if library.installed.isEmpty {
            Text(VelaL10n.text("settings_voice_none_hint_ios"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voice-none-hint")
        } else if library.installedForGuidance.isEmpty {
            let language = DirectionsLanguage.shared.label(tag: library.guidanceLanguageTag)
            Text(VelaL10n.text("settings_voice_fallback_ios", language, language))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voice-fallback-hint")
        }
    }

    // MARK: - Download

    @ViewBuilder
    private var downloadRows: some View {
        if let id = library.downloadingId {
            VStack(alignment: .leading, spacing: 6) {
                Text(library.installing
                     ? VelaL10n.text("map_voice_installing")
                     : VelaL10n.text("settings_voice_downloading",
                                     VoiceCatalog.entry(id)?.name ?? id,
                                     Int(library.progress * 100)))
                    .font(.footnote)
                    .accessibilityIdentifier("voice-progress")
                ProgressView(value: library.progress)
                    .accessibilityIdentifier("voice-progress-bar")
            }
            .frame(minHeight: 44)
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
            Text(VelaL10n.text("settings_voice_install_hint_ios"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let error = library.lastError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("voice-error")
        }
    }

    // MARK: - Installed voices

    @ViewBuilder
    private var installedRows: some View {
        ForEach(library.installedEntries) { entry in
            installedRow(entry)
        }
    }

    private func installedRow(_ entry: VoiceEntry) -> some View {
        let status = library.rowStatus(entry.id)
        let language = DirectionsLanguage.shared.label(tag: library.guidanceLanguageTag)
        let entryLanguage = DirectionsLanguage.shared.label(tag: entry.language)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text("Piper · \(entry.sizeMb) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.language != library.voiceLanguage {
                    Text(VelaL10n.text(
                        "settings_voice_row_other_language", language, entryLanguage))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if status.inUse {
                Text(VelaL10n.text(
                    "settings_voice_row_in_use", entry.name, "Piper", String(entry.sizeMb)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("voice-in-use-\(entry.id)")
            } else if status.canUse && entry.language == library.voiceLanguage {
                Button(VelaL10n.text("settings_voice_row_use")) {
                    library.select(entry.id)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("voice-use-\(entry.id)")
            }
            if status.canRemove {
                Button(role: .destructive) {
                    library.remove(entry.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(VelaL10n.text("settings_voice_row_remove", entry.name))
                .accessibilityIdentifier("voice-remove-\(entry.id)")
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: - Library and test

    private var libraryRow: some View {
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
    }

    @ViewBuilder
    private var testRow: some View {
        if library.effectiveId != nil {
            Button(VelaL10n.text("settings_voice_test")) {
                AppGraph.navVoice.speakSample(VelaL10n.text("settings_voice_nav_sample_text"))
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("voice-test")
            Text(VelaL10n.text("settings_voice_test_hint_ios"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Volume and speed

    /// VO-CONTROL: the Android tiers and presets. The volume is a relative gain on a levelled
    /// voice, never the phone's media volume; the iPhone voice only responds below Normal.
    @ViewBuilder
    private var volumeRows: some View {
        Group {
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
            Text(VelaL10n.text("settings_voice_level_hint_ios"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var speedRows: some View {
        Group {
            HStack(spacing: 12) {
                Text(VelaL10n.text("settings_voice_speed", control.speedLabel))
                Spacer(minLength: 8)
                Button {
                    stepSpeed(-GuidanceSpeed.step)
                } label: {
                    Image(systemName: "minus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(VelaL10n.text("settings_voice_speed", control.speedLabel))
                .accessibilityIdentifier("voice-speed-decrease")
                Button {
                    stepSpeed(GuidanceSpeed.step)
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
        }
    }

    /// The Android hint says the speed buttons speak a sample; this makes that true on iOS.
    private func stepSpeed(_ delta: Float) {
        control.stepRate(delta)
        AppGraph.navVoice.speakSample(VelaL10n.text("settings_voice_nav_sample_text"))
    }

    #if DEBUG
    private var debugRow: some View {
        let line = "\(mode.debugLine) lang=\(model.effectiveDirectionsLanguage) "
            + "app=\(DevicePlatformLocale.effectiveTag()) "
            + "speed=\(control.speedLabel) tier=\(String(format: "%.1f", control.gain))"
        return VStack(alignment: .leading, spacing: 2) {
            Text(library.engineDebug)
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(2)
                .accessibilityIdentifier("voice-debug")
            Text(verbatim: line)
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(3)
                .accessibilityIdentifier("voice-control-debug")
        }
    }
    #endif
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
                if left.0 == library.voiceLanguage { return true }
                if right.0 == library.voiceLanguage { return false }
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
                         : VelaL10n.text("settings_voice_downloading",
                                         VoiceCatalog.entry(id)?.name ?? id,
                                         Int(library.progress * 100)))
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
        let status = library.rowStatus(entry.id)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text("Piper · \(entry.sizeMb) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if status.installed && entry.language != library.voiceLanguage {
                    Text(VelaL10n.text(
                        "settings_voice_row_other_language",
                        DirectionsLanguage.shared.label(tag: library.guidanceLanguageTag),
                        DirectionsLanguage.shared.label(tag: entry.language)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if status.inUse {
                Text(VelaL10n.text(
                    "settings_voice_row_in_use", entry.name, "Piper", String(entry.sizeMb)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("voice-in-use-\(entry.id)")
            } else if status.canUse && entry.language == library.voiceLanguage {
                Button(VelaL10n.text("settings_voice_row_use")) { library.select(entry.id) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("voice-use-\(entry.id)")
            }
            if status.downloading {
                HStack(spacing: 6) {
                    ProgressView(value: library.progress)
                        .frame(width: 56)
                    Text(VelaL10n.text("settings_voice_row_downloading", Int(status.progressPercent)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if !status.installed {
                Button {
                    library.install(entry.id)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(!status.canDownload)
                .accessibilityLabel(VelaL10n.text("settings_voice_install_vela", entry.sizeMb))
                .accessibilityIdentifier("voice-download-\(entry.id)")
            }
            if status.canRemove {
                Button(role: .destructive) { library.remove(entry.id) } label: {
                    Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(VelaL10n.text("settings_voice_row_remove", entry.name))
                .accessibilityIdentifier("voice-remove-\(entry.id)")
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("voice-row-\(entry.id)")
    }
}
