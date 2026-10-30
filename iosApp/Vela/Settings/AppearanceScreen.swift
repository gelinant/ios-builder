import SwiftUI

/// The appearance page. The Settings form keeps its first rows (language, units, clock) and opens
/// this page from one row, so the Google switch stays near the top of the form.
///
/// Theme and map look are separate choices with separate keys: the app can be dark over a light
/// map, as Android allows. Every row writes the same preference key Android uses where one exists.
struct AppearanceScreen: View {
    @ObservedObject var model: SettingsModel
    let initialAnchor: String?
    @StateObject private var appearance = AppearanceSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(VelaL10n.text("settings_language")) {
                SettingsMenu(
                    id: "settings-language",
                    title: VelaL10n.text("settings_language"),
                    selection: Binding(get: { model.languageTag }, set: model.setLanguage),
                    options: [(title: VelaL10n.text("settings_follow_system_language"), value: "")]
                        + VelaL10n.languages.map { (title: $0.endonym, value: $0.code) })
                .id("settings-language")

                SettingsMenu(
                    id: "settings-units",
                    title: VelaL10n.text("settings_units"),
                    selection: Binding(get: { model.units }, set: model.setUnits),
                    options: [
                        (title: VelaL10n.text("settings_follow_system"), value: "system"),
                        (title: VelaL10n.text("settings_units_metric"), value: "metric"),
                        (title: VelaL10n.text("settings_units_imperial"), value: "imperial"),
                    ])
                .id("settings-units")

                SettingsMenu(
                    id: "settings-clock",
                    title: VelaL10n.text("settings_clock"),
                    selection: Binding(get: { model.clockMode }, set: model.setClockMode),
                    options: [
                        (title: VelaL10n.text("settings_clock_system"), value: "system"),
                        (title: VelaL10n.text("settings_clock_12"), value: "12"),
                        (title: VelaL10n.text("settings_clock_24"), value: "24"),
                    ])
                .id("settings-clock")
            }

            Section(VelaL10n.text("settings_theme")) {
                    SettingsMenu(
                        id: "appearance-theme",
                        title: "App theme",
                        selection: Binding(
                            get: { appearance.theme.rawValue.lowercased() },
                            set: { if let theme = AppearanceTheme(rawValue: $0.uppercased()) {
                                appearance.setTheme(theme)
                            } }),
                        options: AppearanceTheme.allCases.map {
                            (title: $0.title, value: $0.rawValue.lowercased())
                        })
                    .id("appearance-theme")
                    Text(VelaL10n.text("settings_light_dark_or_the_system_setting"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(VelaL10n.text("settings_map")) {
                    SettingsMenu(
                        id: "appearance-map-look",
                        title: "Map look",
                        selection: Binding(
                            get: { appearance.mapLook.rawValue },
                            set: { if let look = MapLook(rawValue: $0) { appearance.setMapLook(look) } }),
                        options: MapLook.allCases.map { (title: $0.title, value: $0.rawValue) })
                    .id("appearance-map-look")
                    SettingsMenu(
                        id: "appearance-map-appearance",
                        title: "Map light or dark",
                        selection: Binding(
                            get: { appearance.mapAppearance.rawValue },
                            set: { if let value = MapAppearance(rawValue: $0) {
                                appearance.setMapAppearance(value)
                            } }),
                        options: [
                            (title: "Follow system", value: MapAppearance.system.rawValue),
                            (title: MapAppearance.light.title, value: MapAppearance.light.rawValue),
                            (title: MapAppearance.dark.title, value: MapAppearance.dark.rawValue),
                        ])
                    .id("appearance-map-appearance")
                    Text(VelaL10n.text("settings_vela_bright_positron_fiord_and_black"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(VelaL10n.text("settings_navigation_chrome")) {
                    SettingsMenu(
                        id: "appearance-icon-size",
                        title: "Navigation icon size",
                        selection: Binding(
                            get: { appearance.iconSize.rawValue },
                            set: { if let value = NavIconSize(rawValue: $0) { appearance.setIconSize(value) } }),
                        options: NavIconSize.allCases.map { (title: $0.title, value: $0.rawValue) })
                    .id("appearance-icon-size")
                    SettingsMenu(
                        id: "appearance-label-size",
                        title: "Navigation label size",
                        selection: Binding(
                            get: { appearance.labelSize.rawValue },
                            set: { if let value = NavLabelSize(rawValue: $0) { appearance.setLabelSize(value) } }),
                        options: NavLabelSize.allCases.map { (title: $0.title, value: $0.rawValue) })
                    .id("appearance-label-size")
                    Text(VelaL10n.text("settings_the_label_step_multiplies_the_dynamic"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    SettingsMenu(
                        id: "appearance-speed-display",
                        title: "Show speed and speed limit",
                        selection: Binding(
                            get: { appearance.speedDisplay ? "on" : "off" },
                            set: { appearance.setSpeedDisplay($0 == "on") }),
                        options: [(title: "On", value: "on"), (title: "Off", value: "off")])
                    .id("appearance-speed-display")
                    SettingsMenu(
                        id: "appearance-speed-unit",
                        title: "Speed unit",
                        selection: Binding(
                            get: { appearance.speedUnit.rawValue },
                            set: { if let value = SpeedUnitChoice(rawValue: $0) {
                                appearance.setSpeedUnit(value)
                            } }),
                        options: SpeedUnitChoice.allCases.map { (title: $0.title, value: $0.rawValue) })
                    .id("appearance-speed-unit")
                    SettingsMenu(
                        id: "appearance-vehicle",
                        title: "Vehicle icon",
                        selection: Binding(
                            get: { appearance.vehicle.rawValue },
                            set: { if let value = NavVehicle(rawValue: $0) { appearance.setVehicle(value) } }),
                        options: NavVehicle.allCases.map { (title: $0.title, value: $0.rawValue) })
                    .id("appearance-vehicle")
                    SettingsMenu(
                        id: "appearance-detail",
                        title: "Navigation detail",
                        selection: Binding(
                            get: { appearance.detail.rawValue },
                            set: { if let value = NavDetailLevel(rawValue: $0) { appearance.setDetail(value) } }),
                        options: NavDetailLevel.allCases.map { (title: $0.title, value: $0.rawValue) })
                    .id("appearance-detail")
                    Text(VelaL10n.text("settings_full_keeps_the_road_name_and"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(VelaL10n.text("settings_chrome_preview")) {
                    AppearanceChromePreview(appearance: appearance)
                }

        }
        .accessibilityIdentifier("appearance-screen")
        .settingsAnchorScroll(initialAnchor)
        #if DEBUG
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(appearance.debugLine)
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.regularMaterial)
                .allowsHitTesting(false)
                .accessibilityIdentifier("appearance-debug")
        }
        #endif
        .navigationTitle(VelaL10n.text("settings_appearance"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("appearance-done")
            }
        }
    }
}

/// A small sample of the drive chrome, drawn from the same holder the free-drive and guided
/// chrome read. It proves the icon, label and speed choices without starting a route.
struct AppearanceChromePreview: View {
    @ObservedObject var appearance: AppearanceSettings
    @ScaledMetric(relativeTo: .body) private var labelBase: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: appearance.vehicle.symbol)
                    .font(.system(size: 18 * appearance.iconSize.scale, weight: .semibold))
                    .foregroundStyle(Design.Colors.accentFill)
                    .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                    .accessibilityLabel(appearance.vehicle.title)
                    .accessibilityIdentifier("appearance-preview-vehicle")
                if appearance.speedDisplay {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(appearance.speedUnit.isImperial(modelImperial: false) ? "36" : "58")
                            .font(.system(size: labelBase * 1.35, weight: .bold))
                            .monospacedDigit()
                        Text(appearance.speedUnit.isImperial(modelImperial: false) ? "mph" : VelaL10n.text("settings_km_h"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("appearance-preview-speed-unit")
                    }
                }
                Spacer(minLength: 0)
            }
            Text(VelaL10n.text("settings_turn_right_onto_market_street"))
                .font(.system(size: labelBase * appearance.labelSize.scale, weight: .semibold))
                .lineLimit(2)
                .accessibilityIdentifier("appearance-preview-label")
            Text(appearance.detail.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("appearance-preview-detail")
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appearance-preview")
    }
}
