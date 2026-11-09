import SwiftUI

/// The Settings sheet: a short Google Maps-like list of eight rows. Each row shows its current
/// value on the trailing side and opens the page that owns the detailed controls. The Google
/// choice keeps its switch on this first screen, so it is reachable without scrolling.
struct SettingsScreen: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var offline: OfflineModel
    @StateObject private var privacy = PrivacySettings.shared
    @StateObject private var appearance = AppearanceSettings.shared
    @ObservedObject private var voiceMode = VoiceModeSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var path: [SettingsRoute] = []
    @State private var activeSheet: SettingsSheet?

    /// One sheet at a time: two `.sheet(isPresented:)` on the same view made the second refuse to
    /// present once the map had several (MapScreen's note, and the same iOS 26 behavior here).
    private enum SettingsSheet: String, Identifiable {
        case offline
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                #if DEBUG
                Section {
                    Text("language=\(model.languageTag.isEmpty ? "system" : model.languageTag) units=\(model.units) clock=\(model.clockMode) google=\(offline.googleDisabled ? 1 : 0) rot=\(privacy.rotationMode) telemetry=\(privacy.telemetryBlocked ? 1 : 0) lookup=\(privacy.lookupTappedPlaces ? 1 : 0) links=\(privacy.resolveShortLinks ? 1 : 0) \(PrivacyRequestCounter.debugLine)")
                        .font(.caption2.monospaced())
                        .dynamicTypeSize(.xSmall)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .accessibilityIdentifier("settings-debug")
                }
                #endif

                Section {
                    googleRow
                    settingsRow(
                        .appearance(nil),
                        id: "settings-appearance",
                        title: VelaL10n.text("settings_appearance"),
                        value: appearance.theme.title,
                        detail: "\(languageValue) · \(unitsValue)")
                    settingsRow(
                        .navigation(nil),
                        id: "settings-navigation",
                        title: VelaL10n.text("settings_navigation"),
                        value: appearance.speedUnit.title)
                    settingsRow(
                        .voice(nil),
                        id: "settings-voice",
                        title: VelaL10n.text("settings_voice"),
                        value: VelaL10n.text(voiceMode.mode.labelKey))
                    settingsRow(
                        .content(nil),
                        id: "settings-data-content",
                        title: VelaL10n.text("settings_data_and_content"),
                        value: contentValue)
                    settingsRow(
                        .trips(nil),
                        id: "settings-trips",
                        title: VelaL10n.text("settings_recorded_trips"),
                        value: "\(model.recordedTripCount)")
                    offlineRow
                    settingsRow(
                        .about,
                        id: "settings-about",
                        title: VelaL10n.text("settings_about"),
                        value: AboutInfo.version)
                }
            }
            .accessibilityIdentifier("settings-screen")
            .environment(\.defaultMinListRowHeight, Design.Size.hitTarget)
            .scrollContentBackground(.hidden)
            .background(Design.Colors.surface)
            .tint(Design.Colors.accent)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(route)
            }
            .onAppear {
                model.refreshTrips()
                if offline.installedRows.isEmpty { offline.refresh() }
            }
        }
        // Sheets do not consistently inherit the presenting view's locale and direction.
        .environment(\.locale, model.locale)
        .environment(\.layoutDirection, model.layoutDirection)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .offline:
                OfflineSheet(model: offline, onFrameArea: {
                    activeSheet = nil
                    // The map owns the live viewport. Settings cannot read it, so the framed
                    // download starts without an estimate until MapScreen supplies the hook.
                    offline.startAreaPick(viewport: nil)
                })
                .presentationDetents([.fraction(Design.Sheet.expanded), .fraction(Design.Sheet.full)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Rows

    /// The Google switch stays on the first screen, as `LocalizationUITests` expects. Tapping the
    /// label opens the full privacy page; the switch itself toggles Google without a second tap.
    private var googleRow: some View {
        HStack(spacing: Design.Spacing.s) {
            Button {
                path.append(.privacy(nil))
            } label: {
                HStack(spacing: Design.Spacing.s) {
                    SettingsRowLabel(
                        title: VelaL10n.text("settings_privacy"),
                        subtitle: VelaL10n.text("settings_google_free"))
                    Spacer(minLength: Design.Spacing.s)
                    SettingsChevron()
                }
                .settingsRowFrame()
            }
            .accessibilityIdentifier("settings-privacy-page")

            Toggle("", isOn: Binding(
                get: { offline.googleDisabled },
                set: { offline.setGoogleDisabled($0) }))
                .labelsHidden()
                .accessibilityLabel(VelaL10n.text("settings_google_free"))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-no-google")
        }
    }

    private var offlineRow: some View {
        Button {
            activeSheet = .offline
        } label: {
            HStack(spacing: Design.Spacing.s) {
                SettingsRowLabel(title: VelaL10n.text("settings_offline"), subtitle: nil)
                Spacer(minLength: Design.Spacing.s)
                SettingsValue(text: "\(offline.installedRows.count)")
                SettingsChevron()
            }
            .settingsRowFrame()
        }
        .accessibilityIdentifier("settings-offline")
        .id("settings-offline")
    }

    private func settingsRow(
        _ route: SettingsRoute,
        id: String,
        title: String,
        value: String,
        detail: String? = nil
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Design.Spacing.s) {
                Text(title)
                    .font(Design.Typography.rowTitle)
                    .foregroundStyle(Design.Colors.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Design.Spacing.s)
                VStack(alignment: .trailing, spacing: Design.Spacing.xxs) {
                    SettingsValue(text: value)
                    if let detail {
                        Text(detail)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .settingsRowFrame()
        }
        .accessibilityIdentifier(id)
        .id(id)
    }

    // MARK: - Values

    private var languageValue: String {
        if model.languageTag.isEmpty {
            return VelaL10n.text("settings_follow_system_language")
        }
        return VelaL10n.languages.first { $0.code == model.languageTag }?.endonym
            ?? model.languageTag
    }

    private var unitsValue: String {
        switch model.units {
        case "metric": return "km"
        case "imperial": return "mi"
        default: return "auto"
        }
    }

    private var contentValue: String {
        model.placeContent == "tiles" ? "Tiles only" : "Full place data"
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .appearance(let anchor):
            AppearanceScreen(model: model, initialAnchor: anchor)
        case .privacy(let anchor):
            PrivacyScreen(model: model, offline: offline, privacy: privacy, initialAnchor: anchor)
        case .navigation(let anchor):
            NavigationSettingsPage(model: model, initialAnchor: anchor)
        case .voice(let anchor):
            VoiceSettingsPage(model: model, initialAnchor: anchor)
        case .content(let anchor):
            DataContentSettingsPage(model: model, initialAnchor: anchor)
        case .trips(let anchor):
            TripsSettingsPage(model: model, initialAnchor: anchor)
        case .about:
            AboutScreen { anchor in
                // Replace About with the page that owns the control; a nil route is About itself.
                path = [SettingsRoute.route(for: anchor)]
            }
        }
    }

    /// A toolbar clips its button to 36 points. This header keeps the actual Done target 44 points.
    /// The title takes the `nav` role and the surface is opaque, so no material band cuts the page
    /// in two (`DESIGN.md` 2.6 and 3.4).
    private var header: some View {
        ZStack {
            Text(VelaL10n.text("settings_title"))
                .font(Design.Typography.nav)
                .foregroundStyle(Design.Colors.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Design.Size.hitTarget + Design.Spacing.s)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                    .font(Design.Typography.button)
                    .foregroundStyle(Design.Colors.accentFill)
                    .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("settings-done")
            }
        }
        .frame(minHeight: Design.Size.hitTarget)
        .padding(.horizontal, Design.Padding.page)
        .padding(.vertical, Design.Spacing.xxs)
        .background(Design.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.separator)
                .frame(height: 1 / 3)
        }
    }
}

/// A menu label owns its full 44-point row. Form's menu Picker reports only its 34-point text.
struct SettingsMenu: View {
    let id: String
    let title: String
    @Binding var selection: String
    let options: [(title: String, value: String)]

    @Environment(\.dynamicTypeSize) private var typeSize

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
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text(title)
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.label)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Design.Spacing.s) {
                            SettingsValue(text: selectedTitle)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.secondaryLabel)
                                .accessibilityHidden(true)
                        }
                    }
                } else {
                    HStack(spacing: Design.Spacing.s) {
                        Text(title)
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.label)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Design.Spacing.s)
                        SettingsValue(text: selectedTitle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: Design.Size.hitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
        .accessibilityValue(selection)
    }
}
