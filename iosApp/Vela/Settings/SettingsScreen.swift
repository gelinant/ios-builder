import SwiftUI

/// The first iOS settings screen: language, measurement units, clock, and the shared Google switch.
struct SettingsScreen: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var offline: OfflineModel
    @StateObject private var privacy = PrivacySettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var activeSheet: SettingsSheet?
    @State private var shareItems: [Any] = []
    @State private var exportFailed = false

    /// One sheet at a time: two `.sheet(isPresented:)` on the same view made the second refuse to
    /// present once the map had several (MapScreen's note, and the same iOS 26 behavior here).
    private enum SettingsSheet: String, Identifiable {
        case privacy
        case share
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                #if DEBUG
                Section {
                    Text("language=\(model.languageTag.isEmpty ? "system" : model.languageTag) units=\(model.units) clock=\(model.clockMode) google=\(offline.googleDisabled ? 1 : 0) rot=\(privacy.rotationMode) telemetry=\(privacy.telemetryBlocked ? 1 : 0) \(GoogleRequestCounter.debugLine)")
                        .font(.caption2.monospaced())
                        .dynamicTypeSize(.xSmall)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .accessibilityIdentifier("settings-debug")
                }
                #endif

                Section(VelaL10n.text("settings_appearance")) {
                    SettingsMenu(
                        id: "settings-language",
                        title: VelaL10n.text("settings_language"),
                        selection: Binding(get: { model.languageTag }, set: model.setLanguage),
                        options: [(title: VelaL10n.text("settings_follow_system_language"), value: "")]
                            + VelaL10n.languages.map { (title: $0.endonym, value: $0.code) })

                    SettingsMenu(
                        id: "settings-units",
                        title: VelaL10n.text("settings_units"),
                        selection: Binding(get: { model.units }, set: model.setUnits),
                        options: [
                            (title: VelaL10n.text("settings_follow_system"), value: "system"),
                            (title: VelaL10n.text("settings_units_metric"), value: "metric"),
                            (title: VelaL10n.text("settings_units_imperial"), value: "imperial"),
                        ])

                    SettingsMenu(
                        id: "settings-clock",
                        title: VelaL10n.text("settings_clock"),
                        selection: Binding(get: { model.clockMode }, set: model.setClockMode),
                        options: [
                            (title: VelaL10n.text("settings_clock_system"), value: "system"),
                            (title: VelaL10n.text("settings_clock_12"), value: "12"),
                            (title: VelaL10n.text("settings_clock_24"), value: "24"),
                        ])
                }

                VoiceSettingsSection()

                Section(VelaL10n.text("settings_privacy")) {
                    Toggle(VelaL10n.text("settings_google_free"), isOn: Binding(
                        get: { offline.googleDisabled },
                        set: { offline.setGoogleDisabled($0) }))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings-no-google")
                    Text(VelaL10n.text("settings_google_free_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle(VelaL10n.text("settings_block_google_telemetry"), isOn: Binding(
                        get: { privacy.telemetryBlocked },
                        set: { privacy.setTelemetryBlocked($0) }))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings-telemetry")
                    Text(VelaL10n.text("settings_block_google_telemetry_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    SettingsMenu(
                        id: "settings-session-mode",
                        title: VelaL10n.text("settings_google_session"),
                        selection: Binding(get: { privacy.rotationMode }, set: { privacy.setRotationMode($0) }),
                        options: [
                            (title: VelaL10n.text("settings_google_session_week"), value: "week"),
                            (title: VelaL10n.text("settings_google_session_day"), value: "day"),
                            (title: VelaL10n.text("settings_google_session_launch"), value: "launch"),
                        ])
                    if let started = privacy.sessionStarted {
                        Text(VelaL10n.text("settings_google_session_started", started.formatted(date: .abbreviated, time: .shortened)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-session-started")
                    }
                    Button(VelaL10n.text("settings_google_session_now")) {
                        privacy.startNewNow()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("settings-session-new")

                    Button(VelaL10n.text("settings_privacy_page")) {
                        activeSheet = .privacy
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("settings-privacy-page")

                    Text(VelaL10n.text("settings_data_privacy_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(VelaL10n.text("settings_privacy_button"), destination: model.privacyURL)
                        .padding(.vertical, 5)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings-privacy-link")

                    Button(VelaL10n.text("settings_diag_export")) {
                        exportDiagnostics()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("settings-export-diagnostics")
                }
            }
            .accessibilityIdentifier("settings-screen")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
        }
        // Sheets do not consistently inherit the presenting view's locale and direction.
        .environment(\.locale, model.locale)
        .environment(\.layoutDirection, model.layoutDirection)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .privacy:
                PrivacyScreen(model: model, privacy: privacy)
                    .environment(\.locale, model.locale)
                    .environment(\.layoutDirection, model.layoutDirection)
            case .share:
                ShareSheet(items: shareItems)
            }
        }
        .alert(VelaL10n.text("settings_diagnostics"), isPresented: $exportFailed) {
            Button(VelaL10n.text("settings_trip_select_done"), role: .cancel) {}
        } message: {
            Text(VelaL10n.text("settings_diag_nothing"))
        }
    }

    private func exportDiagnostics() {
        do {
            shareItems = [try DiagnosticsExport.fileURL()]
            activeSheet = .share
        } catch {
            exportFailed = true
        }
    }

    /// A toolbar clips its button to 36 points. This header keeps the actual Done target 44 points.
    private var header: some View {
        ZStack {
            Text(VelaL10n.text("settings_title"))
                .font(.headline)
            HStack {
                Spacer()
                Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("settings-done")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .background(.regularMaterial)
    }
}

/// A menu label owns its full 44-point row. Form's menu Picker reports only its 34-point text.
struct SettingsMenu: View {
    let id: String
    let title: String
    @Binding var selection: String
    let options: [(title: String, value: String)]

    private var selectedTitle: String {
        options.first { $0.value == selection }?.title ?? selection
    }

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.value
                } label: {
                    HStack {
                        Text(option.title)
                        if option.value == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityAddTraits(option.value == selection ? .isSelected : [])
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(selectedTitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
        .accessibilityValue(selection)
    }
}
