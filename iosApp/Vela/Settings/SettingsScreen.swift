import SwiftUI

/// The first iOS settings screen: language, measurement units, clock, and the shared Google switch.
struct SettingsScreen: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var offline: OfflineModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                #if DEBUG
                Section {
                    Text("language=\(model.languageTag.isEmpty ? "system" : model.languageTag) units=\(model.units) clock=\(model.clockMode) google=\(offline.googleDisabled ? 1 : 0)")
                        .font(.caption2.monospaced())
                        .dynamicTypeSize(.xSmall)
                        .lineLimit(1)
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
                    Text(VelaL10n.text("settings_data_privacy_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(VelaL10n.text("settings_privacy_button"), destination: model.privacyURL)
                        .padding(.vertical, 5)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings-privacy-link")
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
private struct SettingsMenu: View {
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
    }
}
