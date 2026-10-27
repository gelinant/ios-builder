import SwiftUI

/// The Privacy page: what reaches Google, what stays on the phone, and the limits. The switches
/// themselves sit on the Settings screen; this page is the explanation behind them.
struct PrivacyScreen: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var privacy: PrivacySettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(VelaL10n.text("settings_privacy_what_google")) {
                    Text(VelaL10n.text("settings_privacy_what_google_hint"))
                        .font(.footnote)
                    Text(VelaL10n.text("settings_data_privacy_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(VelaL10n.text("settings_google_free_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(VelaL10n.text("settings_privacy_what_local")) {
                    Text(VelaL10n.text("settings_privacy_what_local_hint"))
                        .font(.footnote)
                }

                Section(VelaL10n.text("settings_privacy_limits")) {
                    Text(VelaL10n.text("settings_privacy_limits_hint"))
                        .font(.footnote)
                    Text(VelaL10n.text("settings_google_session_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle(VelaL10n.text("settings_block_google_telemetry"), isOn: Binding(
                        get: { privacy.telemetryBlocked },
                        set: { privacy.setTelemetryBlocked($0) }))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("privacy-telemetry")
                    Link(VelaL10n.text("settings_privacy_button"), destination: model.privacyURL)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("privacy-link")
                }
            }
            .accessibilityIdentifier("privacy-screen")
            .navigationTitle(VelaL10n.text("settings_privacy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("privacy-done")
                }
            }
        }
    }
}
