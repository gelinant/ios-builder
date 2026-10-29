import SwiftUI

/// The first iOS settings screen: language, measurement units, clock, and the shared Google switch.
struct SettingsScreen: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var offline: OfflineModel
    @StateObject private var privacy = PrivacySettings.shared
    @StateObject private var bike = BikeProfileSettings()
    @ObservedObject private var gestures = MapGestureSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var activeSheet: SettingsSheet?
    @State private var shareItems: [Any] = []
    @State private var exportFailed = false
    @State private var confirmTripDelete = false
    @State private var photoBytes: Int64 = 0
    /// Set by an About search hit that names a Settings row. Applied after the sheet closes.
    @State private var pendingAnchor: String?

    /// One sheet at a time: two `.sheet(isPresented:)` on the same view made the second refuse to
    /// present once the map had several (MapScreen's note, and the same iOS 26 behavior here).
    private enum SettingsSheet: String, Identifiable {
        case privacy
        case about
        case quickChips
        case share
        var id: String { rawValue }
    }

    var body: some View {
        ScrollViewReader { proxy in
            NavigationStack {
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

                    Section(VelaL10n.text("settings_appearance")) {
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

                    Section(VelaL10n.text("settings_privacy")) {
                        Toggle(VelaL10n.text("settings_google_free"), isOn: Binding(
                            get: { offline.googleDisabled },
                            set: { offline.setGoogleDisabled($0) }))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("settings-no-google")
                            .id("settings-no-google")
                        Text(VelaL10n.text("settings_google_free_hint_ios"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if offline.googleDisabled {
                            Toggle(VelaL10n.text("settings_google_free_links"), isOn: Binding(
                                get: { privacy.resolveShortLinks },
                                set: { privacy.setResolveShortLinks($0) }))
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("settings-resolve-links")
                                .id("settings-resolve-links")
                            Text(VelaL10n.text("settings_google_free_links_hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Toggle(VelaL10n.text("settings_places_lookup"), isOn: Binding(
                            get: { privacy.lookupTappedPlaces },
                            set: { privacy.setLookupTappedPlaces($0) }))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("settings-lookup-tapped")
                            .id("settings-lookup-tapped")
                        Text(VelaL10n.text("settings_places_lookup_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Toggle(VelaL10n.text("settings_block_google_telemetry"), isOn: Binding(
                            get: { privacy.telemetryBlocked },
                            set: { privacy.setTelemetryBlocked($0) }))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("settings-telemetry")
                            .id("settings-telemetry")
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
                            .id("settings-session-mode")
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
                        .id("settings-session-new")

                        Button(VelaL10n.text("settings_privacy_page")) {
                            activeSheet = .privacy
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings-privacy-page")
                        .id("settings-privacy-page")

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
                        .id("settings-export-diagnostics")
                    }

                    bikeSection
                    gestureSection
                    contentSection
                    searchSection
                    tripsSection

                    VoiceSettingsSection(model: model)
                        .id("settings-voice")
                    aboutSection
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
            .sheet(item: $activeSheet, onDismiss: { scrollAfterAbout(proxy) }) { sheet in
                switch sheet {
                case .privacy:
                    PrivacyScreen(model: model, offline: offline, privacy: privacy)
                        .environment(\.locale, model.locale)
                        .environment(\.layoutDirection, model.layoutDirection)
                case .about:
                    AboutScreen { anchor in
                        pendingAnchor = anchor
                        activeSheet = nil
                    }
                    .environment(\.locale, model.locale)
                    .environment(\.layoutDirection, model.layoutDirection)
                case .quickChips:
                    QuickChipsEditor(model: QuickChipsModel.shared)
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
            .confirmationDialog("Delete all recorded trips?", isPresented: $confirmTripDelete, titleVisibility: .visible) {
                Button("Delete all recorded trips", role: .destructive) {
                    model.deleteAllTrips()
                    photoBytes = model.photoCacheBytes
                }
                Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
            } message: {
                Text("Every recorded drive on this phone will be removed. This cannot be undone. Saved places and lists stay.")
            }
            .onAppear {
                photoBytes = model.photoCacheBytes
                model.refreshTrips()
                bike.start()
            }
        }
    }

    /// A Settings hit in the About search closes the sheet and lands on the real control. Waiting
    /// for the dismissal keeps the Form's scroll position stable.
    private func scrollAfterAbout(_ proxy: ScrollViewProxy) {
        guard let anchor = pendingAnchor else { return }
        pendingAnchor = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(anchor, anchor: .center)
            }
        }
    }

    // MARK: - Bike routing

    /// Android's single bike preference, under its own `bike_safe` key, plus the three knobs this
    /// router cannot honour named honestly. A disabled switch that did nothing would be worse than
    /// saying so.
    private var bikeSection: some View {
        Section("Bike") {
            Toggle(VelaL10n.text("settings_bike_safe"), isOn: Binding(
                get: { bike.safe },
                set: { bike.setSafe($0) }))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-bike-safe")
                .id("settings-bike-safe")
            Text("On: the open bicycle router favors signed cycle routes, bike lanes and quiet streets. Off: the fastest bike route. Applies to the next route and every replan; it never changes the travel mode.")
                .font(.footnote)
                .foregroundStyle(.secondary)

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
        }
    }

    private func unsupportedBikeKnob(_ title: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(id)
            Spacer(minLength: 8)
            Text("Not supported by this open router")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). Not supported by this open router")
        .accessibilityIdentifier("\(id)-row")
    }

    // MARK: - Map gestures

    /// L16-L18, L38-L40 and L264. Every row writes the shared `vela_settings` suite, so a relaunch
    /// reads the same choice; MapController applies north lock and shape without waiting.
    private var gestureSection: some View {
        Section("Map gestures") {
            Toggle("Keep north up", isOn: Binding(
                get: { gestures.keepNorthUp },
                set: { gestures.setKeepNorthUp($0) }))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-keep-north-up")
                .id("settings-keep-north-up")
            Text("The map never turns: two-finger rotation is off and drives stay north-up.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Prefer buttons over swipes", isOn: Binding(
                get: { gestures.preferButtons },
                set: { gestures.setPreferButtons($0) }))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-prefer-buttons")
                .id("settings-prefer-buttons")
            Text("Adds zoom in and zoom out buttons under the compass, for the things a swipe also does.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            SettingsMenu(
                id: "settings-map-buttons",
                title: "Map buttons",
                selection: Binding(
                    get: { gestures.buttonShape.rawValue },
                    set: { gestures.setButtonShape(MapButtonShape(rawValue: $0) ?? .round) }),
                options: MapButtonShape.allCases.map { (title: $0.title, value: $0.rawValue) })
                .id("settings-map-buttons")
            Text("The buttons floating over the map: round, or with square corners.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            SettingsMenu(
                id: "settings-start-view",
                title: "Where the map opens",
                selection: Binding(
                    get: { gestures.startView.rawValue },
                    set: { gestures.setStartView(MapStartView(rawValue: $0) ?? .here) }),
                options: MapStartView.allCases.map { (title: $0.title, value: $0.rawValue) })
                .id("settings-start-view")
            Text("A link from another app still opens on its own place. Where I am moves onto your position when one is available; a city view opens at the default zoom.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            #if DEBUG
            Text("north=\(gestures.keepNorthUp ? 1 : 0) zoomButtons=\(gestures.preferButtons ? 1 : 0) buttons=\(gestures.buttonShape.rawValue) start=\(gestures.startView.rawValue)")
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("settings-gesture-debug")
            #endif
        }
    }

    // MARK: - Data and content

    private var contentSection: some View {
        Section("Data and content") {
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
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-show-reviews")
                .id("settings-show-reviews")

            Toggle(VelaL10n.text("settings_load_photos"), isOn: Binding(
                get: { model.loadPhotos }, set: model.setLoadPhotos))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-load-photos")
                .id("settings-load-photos")

            Toggle("Load photos only on Wi-Fi", isOn: Binding(
                get: { model.photosWifiOnly }, set: model.setPhotosWifiOnly))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-photos-wifi")
                .id("settings-photos-wifi")
            Text("On a mobile connection place pages keep the photo space but download no new photo.")
                .font(.footnote)
                .foregroundStyle(.secondary)

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

            Text("Photo cache: \(bytesText(photoBytes)) used of \(model.photoCacheMb) MB")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings-photo-cache-used")
            Button("Clear photo cache") {
                model.clearPhotoCache()
                photoBytes = model.photoCacheBytes
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings-photo-cache-clear")
            .id("settings-photo-cache-clear")

            Toggle(VelaL10n.text("settings_full_place_load"), isOn: Binding(
                get: { model.fullPlaceLoad }, set: model.setFullPlaceLoad))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-full-place-load")
                .id("settings-full-place-load")
            Text(VelaL10n.text("settings_full_place_load_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(VelaL10n.text("settings_details_retry"), isOn: Binding(
                get: { model.detailsRetry }, set: model.setDetailsRetry))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-details-retry")
                .id("settings-details-retry")
            Text(VelaL10n.text("settings_details_retry_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(VelaL10n.text("settings_hide_adult"), isOn: Binding(
                get: { model.hideAdult }, set: model.setHideAdult))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-hide-adult")
                .id("settings-hide-adult")
            Text(VelaL10n.text("settings_hide_adult_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(VelaL10n.text("settings_hide_external_links"), isOn: Binding(
                get: { model.hideExternalLinks }, set: model.setHideExternalLinks))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-hide-external")
                .id("settings-hide-external")
            Text(VelaL10n.text("settings_hide_external_links_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Low data mode (LowDataMode)", isOn: Binding(
                get: { model.lowDataMode }, set: model.setLowDataMode))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-low-data")
                .id("settings-low-data")
            Text("Skips photos and asks Google for less, as the LowDataMode flag does on Android.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Low RAM mode (LowRamMode)", isOn: Binding(
                get: { model.lowRamMode }, set: model.setLowRamMode))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-low-ram")
                .id("settings-low-ram")
            Text("Trims speculative map work, as the LowRamMode flag does on Android. Off by default on iOS.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            #if DEBUG
            Text(model.contentDebugLine)
                .font(.caption2.monospaced())
                .dynamicTypeSize(.xSmall)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("settings-content-debug")
            #endif
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        Section(VelaL10n.text("settings_quick_chips")) {
            Button {
                activeSheet = .quickChips
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(VelaL10n.text("settings_quick_chips"))
                            .foregroundStyle(.primary)
                        Text(VelaL10n.text("settings_quick_chips_sub"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings-quick-chips")
            .id("settings-quick-chips")
            Text(VelaL10n.text("settings_quick_chips_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recorded trips

    private var tripsSection: some View {
        Section("Recorded trips") {
            Toggle(VelaL10n.text("settings_diag_redact"), isOn: Binding(
                get: { model.redactPlacesInExports }, set: model.setRedactPlacesInExports))
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings-redact-exports")
                .id("settings-redact-exports")
            Text(VelaL10n.text("settings_diag_redact_trips_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("\(model.recordedTripCount) trip(s), \(bytesText(model.recordedTripBytes)) on this phone")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings-trips-size")
                .id("settings-trips-size")
            Button("Delete all recorded trips", role: .destructive) {
                confirmTripDelete = true
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings-trips-delete")
            .id("settings-trips-delete")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(VelaL10n.text("settings_about")) {
            Button {
                activeSheet = .about
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Help, notices and support")
                            .foregroundStyle(.primary)
                        Text("Search every settings row, read a help topic, or check a license.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings-about")
            .id("settings-about")

            Text(AboutInfo.versionLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings-about-version")
        }
    }

    private func bytesText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = bytes >= 1_048_576 ? [.useMB] : [.useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
