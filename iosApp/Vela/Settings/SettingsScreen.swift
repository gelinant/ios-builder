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
                        .accessibilityIdentifier("settings-debug")
                }
                #endif

                Section(VelaL10n.text("settings_appearance")) {
                    Picker(VelaL10n.text("settings_language"), selection: Binding(
                        get: { model.languageTag }, set: model.setLanguage)) {
                        Text(VelaL10n.text("settings_follow_system_language")).tag("")
                        ForEach(VelaL10n.languages) { language in
                            Text(language.endonym).tag(language.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("settings-language")

                    Picker(VelaL10n.text("settings_units"), selection: Binding(
                        get: { model.units }, set: model.setUnits)) {
                        Text(VelaL10n.text("settings_follow_system")).tag("system")
                        Text(VelaL10n.text("settings_units_metric")).tag("metric")
                        Text(VelaL10n.text("settings_units_imperial")).tag("imperial")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("settings-units")

                    Picker(VelaL10n.text("settings_clock"), selection: Binding(
                        get: { model.clockMode }, set: model.setClockMode)) {
                        Text(VelaL10n.text("settings_clock_system")).tag("system")
                        Text(VelaL10n.text("settings_clock_12")).tag("12")
                        Text(VelaL10n.text("settings_clock_24")).tag("24")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("settings-clock")
                }

                Section(VelaL10n.text("settings_privacy")) {
                    Toggle(VelaL10n.text("settings_google_free"), isOn: Binding(
                        get: { offline.googleDisabled },
                        set: { offline.setGoogleDisabled($0) }))
                        .accessibilityIdentifier("settings-no-google")
                    Text(VelaL10n.text("settings_google_free_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(VelaL10n.text("settings_data_privacy_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(VelaL10n.text("settings_privacy_button"), destination: model.privacyURL)
                        .accessibilityIdentifier("settings-privacy-link")
                }
            }
            .accessibilityIdentifier("settings-screen")
            .navigationTitle(VelaL10n.text("settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .accessibilityIdentifier("settings-done")
                }
            }
        }
    }
}
