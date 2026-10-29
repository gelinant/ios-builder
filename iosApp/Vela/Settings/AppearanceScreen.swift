import SwiftUI

/// The appearance page. The Settings form keeps its first rows (language, units, clock) and opens
/// this page from one row, so the Google switch stays near the top of the form.
///
/// Theme and map look are separate choices with separate keys: the app can be dark over a light
/// map, as Android allows. Every row writes the same preference key Android uses where one exists.
struct AppearanceScreen: View {
    @StateObject private var appearance = AppearanceSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
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
                    Text("Light, dark or the system setting. This changes the app chrome only; the map keeps its own choice below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Map") {
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
                    Text("Vela, Bright, Positron, Fiord and Black are the six local style documents. A look and a light/dark choice reload the map without a request.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Navigation chrome") {
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
                    Text("The label step multiplies the Dynamic Type size. It never replaces the system setting, so a larger iPhone text size and this step add up.")
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
                    Text("Full keeps the road name and the next instruction. Compact drops the road name. Minimal keeps the maneuver card and the safety alerts only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Chrome preview") {
                    AppearanceChromePreview(appearance: appearance)
                }

            }
            .accessibilityIdentifier("appearance-screen")
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("appearance-done")
                }
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
                        Text(appearance.speedUnit.isImperial(modelImperial: false) ? "mph" : "km/h")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("appearance-preview-speed-unit")
                    }
                }
                Spacer(minLength: 0)
            }
            Text("Turn right onto Market Street")
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
