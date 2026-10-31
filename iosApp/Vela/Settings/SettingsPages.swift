import SwiftUI

/// Every Settings sub-page the top-level list can push. The associated value is an optional
/// scroll anchor: the About hub uses it to open the page that now owns a control and land on it.
enum SettingsRoute: Hashable {
    case appearance(String?)
    case privacy(String?)
    case navigation(String?)
    case voice(String?)
    case content(String?)
    case trips(String?)
    case about

    /// The page that owns an anchor listed by `SettingsIndex`. The anchors are unchanged, so a
    /// search hit keeps its identifier even when the control moved behind a row.
    static func route(for anchor: String) -> SettingsRoute {
        switch anchor {
        case "settings-language", "settings-units", "settings-clock":
            return .appearance(anchor)
        case "settings-no-google", "settings-resolve-links", "settings-lookup-tapped",
             "settings-telemetry", "settings-session-mode", "settings-session-new",
             "settings-privacy-page", "settings-export-diagnostics":
            return .privacy(anchor == "settings-privacy-page" ? nil : anchor)
        case "settings-nav-auto-zoom", "settings-nav-turn-floor", "settings-nav-tilt",
             "settings-nav-lower-third", "settings-keep-north-up", "settings-prefer-buttons",
             "settings-map-buttons", "settings-start-view", "settings-bike-safe",
             "settings-bike-hills", "settings-bike-steps", "settings-bike-unpaved":
            return .navigation(anchor)
        case "settings-voice":
            return .voice(anchor)
        case "settings-quick-chips", "settings-place-content", "settings-show-reviews",
             "settings-load-photos", "settings-photos-wifi", "settings-photo-quality",
             "settings-photo-cache-size", "settings-photo-cache-clear",
             "settings-full-place-load", "settings-details-retry", "settings-hide-adult",
             "settings-hide-external", "settings-low-data", "settings-low-ram":
            return .content(anchor)
        case "settings-redact-exports", "settings-trips-size", "settings-trips-delete":
            return .trips(anchor)
        default:
            return .about
        }
    }
}

/// Scrolls a pushed page to a control named by the About hub. The delay lets the push animation
/// place the Form before the anchor is resolved.
private struct SettingsAnchorScroll: ViewModifier {
    let anchor: String?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onAppear {
                guard let anchor else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(anchor, anchor: .center)
                    }
                }
            }
        }
    }
}

extension View {
    func settingsAnchorScroll(_ anchor: String?) -> some View {
        modifier(SettingsAnchorScroll(anchor: anchor))
    }
}

// MARK: - Navigation

/// Settings > Navigation: the drive camera, the map gestures and the bike routing preference.
struct NavigationSettingsPage: View {
    @ObservedObject var model: SettingsModel
    let initialAnchor: String?

    @StateObject private var bike = BikeProfileSettings()
    @ObservedObject private var gestures = MapGestureSettings.shared
    @StateObject private var navCamera = NavCameraSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Form {
            navigationCameraSection
            gestureSection
            bikeSection
        }
        .accessibilityIdentifier("settings-navigation-screen")
        .settingsAnchorScroll(initialAnchor)
        .navigationTitle(VelaL10n.text("settings_navigation"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                    .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("settings-navigation-done")
            }
        }
        .onAppear { bike.start() }
    }

    private var navigationCameraSection: some View {
        Section {
            Toggle(VelaL10n.text("settings_zoom_next_turn"), isOn: Binding(
                get: { navCamera.autoZoom },
                set: { navCamera.setAutoZoom($0) }))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-nav-auto-zoom")
                .id("settings-nav-auto-zoom")
            Text(VelaL10n.text("settings_navigation_camera_hint"))
                .settingsHint()

            if navCamera.autoZoom {
                SettingsMenu(
                    id: "settings-nav-turn-floor",
                    title: VelaL10n.text("settings_zoom_far_as"),
                    selection: Binding(
                        get: { String(NavCameraSettings.floors.first { $0.value == navCamera.floor }?.value ?? 12) },
                        set: { raw in
                            if let value = Double(raw) { navCamera.setFloor(value) }
                        }),
                    options: NavCameraSettings.floors.map {
                        (title: $0.title, value: String($0.value))
                    })
                    .id("settings-nav-turn-floor")
                Text(VelaL10n.text("settings_zoom_next_turn_hint"))
                    .settingsHint()
            }

            Toggle(VelaL10n.text("settings_tilt_driving_map"), isOn: Binding(
                get: { navCamera.tilt },
                set: { navCamera.setTilt($0) }))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-nav-tilt")
                .id("settings-nav-tilt")
            Text(VelaL10n.text("settings_tilt_driving_map_hint"))
                .settingsHint()

            Toggle(VelaL10n.text("settings_keep_car_lower_third"), isOn: Binding(
                get: { navCamera.lowerThird },
                set: { navCamera.setLowerThird($0) }))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-nav-lower-third")
                .id("settings-nav-lower-third")
            Text(VelaL10n.text("settings_keep_car_lower_third_hint"))
                .settingsHint()

            #if DEBUG
            Text("autoZoom=\(navCamera.autoZoom ? 1 : 0) floor=\(Int(navCamera.floor)) tilt=\(navCamera.tilt ? 1 : 0) third=\(navCamera.lowerThird ? 1 : 0)")
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("settings-nav-camera-debug")
            #endif
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_navigation_camera"))
        }
    }

    private var gestureSection: some View {
        Section {
            Toggle(VelaL10n.text("settings_keep_north_up"), isOn: Binding(
                get: { gestures.keepNorthUp },
                set: { gestures.setKeepNorthUp($0) }))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-keep-north-up")
                .id("settings-keep-north-up")
            Text(VelaL10n.text("settings_keep_north_up_hint"))
                .settingsHint()

            Toggle(VelaL10n.text("settings_prefer_buttons"), isOn: Binding(
                get: { gestures.preferButtons },
                set: { gestures.setPreferButtons($0) }))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-prefer-buttons")
                .id("settings-prefer-buttons")
            Text(VelaL10n.text("settings_adds_zoom_in_and_zoom_out"))
                .settingsHint()

            SettingsMenu(
                id: "settings-map-buttons",
                title: "Map buttons",
                selection: Binding(
                    get: { gestures.buttonShape.rawValue },
                    set: { gestures.setButtonShape(MapButtonShape(rawValue: $0) ?? .round) }),
                options: MapButtonShape.allCases.map { (title: $0.title, value: $0.rawValue) })
                .id("settings-map-buttons")
            Text(VelaL10n.text("settings_the_buttons_floating_over_the_map"))
                .settingsHint()

            SettingsMenu(
                id: "settings-start-view",
                title: "Where the map opens",
                selection: Binding(
                    get: { gestures.startView.rawValue },
                    set: { gestures.setStartView(MapStartView(rawValue: $0) ?? .here) }),
                options: MapStartView.allCases.map { (title: $0.title, value: $0.rawValue) })
                .id("settings-start-view")
            Text(VelaL10n.text("settings_a_link_from_another_app_still"))
                .settingsHint()

            #if DEBUG
            Text("north=\(gestures.keepNorthUp ? 1 : 0) zoomButtons=\(gestures.preferButtons ? 1 : 0) buttons=\(gestures.buttonShape.rawValue) start=\(gestures.startView.rawValue)")
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("settings-gesture-debug")
            #endif
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_map_gestures"))
        }
    }

    /// Android's single bike preference, under its own `bike_safe` key, plus the three knobs this
    /// router cannot honour named honestly. A disabled switch that did nothing would be worse than
    /// saying so.
    private var bikeSection: some View {
        Section {
            Toggle(VelaL10n.text("settings_bike_safe"), isOn: Binding(
                get: { bike.safe },
                set: { bike.setSafe($0) }))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-bike-safe")
                .id("settings-bike-safe")
            Text(VelaL10n.text("settings_on_the_open_bicycle_router_favors"))
                .settingsHint()

            unsupportedBikeKnob("Avoid hills", id: "settings-bike-hills")
            unsupportedBikeKnob("Avoid steps", id: "settings-bike-steps")
            unsupportedBikeKnob("Avoid unpaved surfaces", id: "settings-bike-unpaved")

            #if DEBUG
            Text("bikeSafe=\(bike.safe ? 1 : 0) unsupported=hills,steps,unpaved")
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("settings-bike-debug")
            #endif
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("place_mode_bike"))
        }
    }

    private func unsupportedBikeKnob(_ title: String, id: String) -> some View {
        let label = Text(title)
            .font(Design.Typography.body)
            .foregroundStyle(Design.Colors.secondaryLabel)
            .accessibilityIdentifier(id)
        let note = Text(VelaL10n.text("settings_not_supported_by_this_open_router"))
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Colors.secondaryLabel)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    label
                    note.multilineTextAlignment(.leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                    label
                    Spacer(minLength: Design.Spacing.s)
                    note
                }
            }
        }
        .frame(minHeight: Design.Size.hitTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VelaL10n.text("settings_not_supported_by_this_open_router_2", String(describing: (title))))
        .accessibilityIdentifier("\(id)-row")
    }
}

// MARK: - Voice

/// Settings > Voice. The section belongs to the voice lot; this page only gives it a stable
/// destination and the same Done behaviour as the other sub-pages.
struct VoiceSettingsPage: View {
    @ObservedObject var model: SettingsModel
    let initialAnchor: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            VoiceSettingsSection(model: model)
                .id("settings-voice")
        }
        .accessibilityIdentifier("settings-voice-screen")
        .settingsAnchorScroll(initialAnchor)
        .navigationTitle(VelaL10n.text("settings_voice"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                    .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("settings-voice-done")
            }
        }
    }
}

// MARK: - Data and content

/// Settings > Data and content: the place policy, the photo cache and the quick search buttons.
struct DataContentSettingsPage: View {
    @ObservedObject var model: SettingsModel
    let initialAnchor: String?

    @State private var photoBytes: Int64 = 0
    @State private var showQuickChips = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            contentSection
            searchSection
        }
        .accessibilityIdentifier("settings-data-screen")
        .settingsAnchorScroll(initialAnchor)
        .navigationTitle(VelaL10n.text("settings_data_and_content"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                    .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("settings-data-done")
            }
        }
        .sheet(isPresented: $showQuickChips) {
            QuickChipsEditor(model: QuickChipsModel.shared)
        }
        .onAppear { photoBytes = model.photoCacheBytes }
    }

    private var contentSection: some View {
        Section {
            SettingsMenu(
                id: "settings-place-content",
                title: "Place content",
                selection: Binding(get: { model.placeContent }, set: model.setPlaceContent),
                options: [
                    (title: "Full place data", value: "full"),
                    (title: "Tiles only", value: "tiles"),
                ])
                .id("settings-place-content")

            Toggle(VelaL10n.text("settings_show_reviews"), isOn: Binding(
                get: { model.showReviews }, set: model.setShowReviews))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-show-reviews")
                .id("settings-show-reviews")

            Toggle(VelaL10n.text("settings_load_photos"), isOn: Binding(
                get: { model.loadPhotos }, set: model.setLoadPhotos))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-load-photos")
                .id("settings-load-photos")

            Toggle(VelaL10n.text("settings_load_photos_only_on_wi_fi"), isOn: Binding(
                get: { model.photosWifiOnly }, set: model.setPhotosWifiOnly))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-photos-wifi")
                .id("settings-photos-wifi")
            Text(VelaL10n.text("settings_on_a_mobile_connection_place_pages"))
                .settingsHint()

            SettingsMenu(
                id: "settings-photo-quality",
                title: "Photo quality",
                selection: Binding(get: { model.photoQuality }, set: model.setPhotoQuality),
                options: [
                    (title: "High", value: "high"),
                    (title: "Standard", value: "standard"),
                    (title: "Low", value: "low"),
                ])
                .id("settings-photo-quality")

            SettingsMenu(
                id: "settings-photo-cache-size",
                title: "Photo cache size",
                selection: Binding(
                    get: { String(model.photoCacheMb) },
                    set: { if let mb = Int($0) { model.setPhotoCacheMb(mb) } }),
                options: [
                    (title: "50 MB", value: "50"),
                    (title: "100 MB", value: "100"),
                    (title: "200 MB", value: "200"),
                    (title: "400 MB", value: "400"),
                ])
                .id("settings-photo-cache-size")

            Text(VelaL10n.text("settings_photo_cache_used_of_mb", String(describing: (bytesText(photoBytes))), String(describing: (model.photoCacheMb))))
                .settingsHint()
                .accessibilityIdentifier("settings-photo-cache-used")
            Button(VelaL10n.text("settings_clear_photo_cache")) {
                model.clearPhotoCache()
                photoBytes = model.photoCacheBytes
            }
            .frame(minHeight: Design.Size.hitTarget)
            .accessibilityIdentifier("settings-photo-cache-clear")
            .id("settings-photo-cache-clear")

            Toggle(VelaL10n.text("settings_full_place_load"), isOn: Binding(
                get: { model.fullPlaceLoad }, set: model.setFullPlaceLoad))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-full-place-load")
                .id("settings-full-place-load")
            Text(VelaL10n.text("settings_full_place_load_hint"))
                .settingsHint()

            Toggle(VelaL10n.text("settings_details_retry"), isOn: Binding(
                get: { model.detailsRetry }, set: model.setDetailsRetry))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-details-retry")
                .id("settings-details-retry")
            Text(VelaL10n.text("settings_details_retry_hint"))
                .settingsHint()

            Toggle(VelaL10n.text("settings_hide_adult"), isOn: Binding(
                get: { model.hideAdult }, set: model.setHideAdult))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-hide-adult")
                .id("settings-hide-adult")
            Text(VelaL10n.text("settings_hide_adult_hint"))
                .settingsHint()

            Toggle(VelaL10n.text("settings_hide_external_links"), isOn: Binding(
                get: { model.hideExternalLinks }, set: model.setHideExternalLinks))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-hide-external")
                .id("settings-hide-external")
            Text(VelaL10n.text("settings_hide_external_links_hint"))
                .settingsHint()

            Toggle(VelaL10n.text("settings_low_data_mode_lowdatamode"), isOn: Binding(
                get: { model.lowDataMode }, set: model.setLowDataMode))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-low-data")
                .id("settings-low-data")
            Text(VelaL10n.text("settings_skips_photos_and_asks_google_for"))
                .settingsHint()

            Toggle(VelaL10n.text("settings_low_ram_mode_lowrammode"), isOn: Binding(
                get: { model.lowRamMode }, set: model.setLowRamMode))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-low-ram")
                .id("settings-low-ram")
            Text(VelaL10n.text("settings_trims_speculative_map_work_as_the"))
                .settingsHint()

            #if DEBUG
            Text(model.contentDebugLine)
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("settings-content-debug")
            #endif
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_data_and_content"))
        }
    }

    private var searchSection: some View {
        Section {
            Button {
                showQuickChips = true
            } label: {
                HStack(spacing: Design.Spacing.s) {
                    SettingsRowLabel(
                        title: VelaL10n.text("settings_quick_chips"),
                        subtitle: VelaL10n.text("settings_quick_chips_sub"))
                    Spacer(minLength: Design.Spacing.s)
                    SettingsChevron()
                }
                .settingsRowFrame()
            }
            .accessibilityIdentifier("settings-quick-chips")
            .id("settings-quick-chips")
            Text(VelaL10n.text("settings_quick_chips_hint"))
                .settingsHint()
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_quick_chips"))
        }
    }

    private func bytesText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = bytes >= 1_048_576 ? [.useMB] : [.useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Saved and trips

/// Settings > Saved and trips: the recorded-trip purge and the export redaction choice.
struct TripsSettingsPage: View {
    @ObservedObject var model: SettingsModel
    let initialAnchor: String?

    @State private var confirmTripDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            tripsSection
            #if DEBUG
            Section {
                Text(model.contentDebugLine)
                    .font(.caption2.monospaced())
                    .dynamicTypeSize(.xSmall)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .accessibilityIdentifier("settings-trips-debug")
            }
            #endif
        }
        .accessibilityIdentifier("settings-trips-screen")
        .settingsAnchorScroll(initialAnchor)
        .navigationTitle(VelaL10n.text("settings_recorded_trips"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                    .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("settings-trips-done")
            }
        }
        .confirmationDialog(
            VelaL10n.text("settings_delete_all_recorded_trips_2"),
            isPresented: $confirmTripDelete,
            titleVisibility: .visible
        ) {
            Button(VelaL10n.text("settings_delete_all_recorded_trips"), role: .destructive) {
                model.deleteAllTrips()
            }
            Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
        } message: {
            Text(VelaL10n.text("settings_every_recorded_drive_on_this_phone"))
        }
        .onAppear { model.refreshTrips() }
    }

    private var tripsSection: some View {
        Section {
            Toggle(VelaL10n.text("settings_diag_redact"), isOn: Binding(
                get: { model.redactPlacesInExports }, set: model.setRedactPlacesInExports))
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("settings-redact-exports")
                .id("settings-redact-exports")
            Text(VelaL10n.text("settings_diag_redact_trips_hint"))
                .settingsHint()

            Text(VelaL10n.text("settings_trip_s_on_this_phone", String(describing: (model.recordedTripCount)), String(describing: (bytesText(model.recordedTripBytes)))))
                .settingsHint()
                .accessibilityIdentifier("settings-trips-size")
                .id("settings-trips-size")
            Button(VelaL10n.text("settings_delete_all_recorded_trips"), role: .destructive) {
                confirmTripDelete = true
            }
            .frame(minHeight: Design.Size.hitTarget)
            .accessibilityIdentifier("settings-trips-delete")
            .id("settings-trips-delete")
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_recorded_trips"))
        }
    }

    private func bytesText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = bytes >= 1_048_576 ? [.useMB] : [.useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
