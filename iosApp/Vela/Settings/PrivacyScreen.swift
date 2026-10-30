import SwiftUI

/// The Privacy page: what reaches Google, what stays on the phone, every switch that decides what
/// Google is asked, the request counter with its own clear action, and how to delete stored
/// history. The same controls also sit on the Settings screen; this page is the full list Android
/// shows, with the limits iOS really has.
struct PrivacyScreen: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var offline: OfflineModel
    @ObservedObject var privacy: PrivacySettings
    let initialAnchor: String?
    @Environment(\.dismiss) private var dismiss

    /// Bumped after a counter clear or a history clear, so the page redraws from the stores.
    @State private var revision = 0
    @State private var confirmClearHistory = false
    @State private var historyCleared = false
    @State private var countCleared = false
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var exportFailed = false

    var body: some View {
        Form {
            whatReachesGoogle
            whatStays
            googleSwitch
            if !offline.googleDisabled {
                googleUses
                sessionSection
            }
            requestsSection.id(revision)
            deleteSection
            limitsSection
            diagnosticsSection
        }
        .accessibilityIdentifier("privacy-screen")
        .settingsAnchorScroll(initialAnchor)
        .navigationTitle(VelaL10n.text("settings_privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("privacy-done")
            }
        }
        .onAppear { PrivacyRequestCounter.saveNow() }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .alert(VelaL10n.text("settings_diagnostics"), isPresented: $exportFailed) {
            Button(VelaL10n.text("settings_trip_select_done"), role: .cancel) {}
        } message: {
            Text(VelaL10n.text("settings_diag_nothing"))
        }
        .confirmationDialog(
            VelaL10n.text("settings_clear_history_confirm_title"),
            isPresented: $confirmClearHistory,
            titleVisibility: .visible
        ) {
            Button(VelaL10n.text("settings_clear_history_action"), role: .destructive) {
                clearAllHistory()
            }
            Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
        } message: {
            Text(VelaL10n.text("settings_clear_history_confirm_body"))
        }
    }

    // MARK: - What reaches Google and what stays

    private var whatReachesGoogle: some View {
        Section(VelaL10n.text("settings_privacy_what_google")) {
            Text(VelaL10n.text("settings_privacy_what_google_hint"))
                .font(.footnote)
            Text(VelaL10n.text("settings_data_privacy_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var whatStays: some View {
        Section(VelaL10n.text("settings_privacy_what_local")) {
            Text(VelaL10n.text("settings_privacy_what_local_hint"))
                .font(.footnote)
        }
    }

    // MARK: - The switches

    private var googleSwitch: some View {
        Section(VelaL10n.text("settings_google_free")) {
            Toggle(VelaL10n.text("settings_google_free"), isOn: Binding(
                get: { offline.googleDisabled },
                set: { offline.setGoogleDisabled($0) }))
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-no-google")
                .id("settings-no-google")
            Text(VelaL10n.text("settings_google_free_hint_ios"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if offline.googleDisabled {
                Toggle(VelaL10n.text("settings_google_free_links"), isOn: Binding(
                    get: { privacy.resolveShortLinks },
                    set: { privacy.setResolveShortLinks($0) }))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("privacy-resolve-links")
                    .id("settings-resolve-links")
                Text(VelaL10n.text("settings_google_free_links_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Every switch that decides what Google is asked on iOS. Android's page carries a few more
    /// (the open places source, other locations, live traffic): those controls do not exist on
    /// iOS, so they are absent here rather than shown doing nothing.
    private var googleUses: some View {
        Section(VelaL10n.text("settings_google_uses")) {
            Text(VelaL10n.text("settings_google_uses_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(VelaL10n.text("settings_places_lookup"), isOn: Binding(
                get: { privacy.lookupTappedPlaces },
                set: { privacy.setLookupTappedPlaces($0) }))
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-lookup")
                .id("settings-lookup-tapped")
            Text(VelaL10n.text("settings_places_lookup_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(VelaL10n.text("settings_show_reviews"), isOn: Binding(
                get: { model.showReviews }, set: model.setShowReviews))
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-reviews")
            Text(VelaL10n.text("settings_show_reviews_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(VelaL10n.text("settings_load_photos"), isOn: Binding(
                get: { model.loadPhotos }, set: model.setLoadPhotos))
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-photos")
            Text(VelaL10n.text("settings_load_photos_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(VelaL10n.text("settings_full_place_load"), isOn: Binding(
                get: { model.fullPlaceLoad }, set: model.setFullPlaceLoad))
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-full-place")
            Text(VelaL10n.text("settings_full_place_load_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(VelaL10n.text("settings_details_retry"), isOn: Binding(
                get: { model.detailsRetry }, set: model.setDetailsRetry))
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-details-retry")
            Text(VelaL10n.text("settings_details_retry_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionSection: some View {
        Section(VelaL10n.text("settings_google_session")) {
            Text(VelaL10n.text("settings_google_session_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            SettingsMenu(
                id: "privacy-session-mode",
                title: VelaL10n.text("settings_google_session"),
                selection: Binding(get: { privacy.rotationMode }, set: { privacy.setRotationMode($0) }),
                options: [
                    (title: VelaL10n.text("settings_google_session_week"), value: "week"),
                    (title: VelaL10n.text("settings_google_session_day"), value: "day"),
                    (title: VelaL10n.text("settings_google_session_launch"), value: "launch"),
                ])
            .id("settings-session-mode")
            if let started = privacy.sessionStarted {
                Text(VelaL10n.text("settings_google_session_started",
                                   started.formatted(date: .abbreviated, time: .shortened)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(VelaL10n.text("settings_google_session_now")) { privacy.startNewNow() }
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-session-new")
                .id("settings-session-new")
            Toggle(VelaL10n.text("settings_block_google_telemetry"), isOn: Binding(
                get: { privacy.telemetryBlocked },
                set: { privacy.setTelemetryBlocked($0) }))
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-telemetry")
                .id("settings-telemetry")
            Text(VelaL10n.text("settings_block_google_telemetry_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Requests to Google

    private var requestsSection: some View {
        Section(VelaL10n.text("settings_google_usage")) {
            Text(VelaL10n.text("settings_google_usage_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(VelaL10n.text("settings_google_usage_scope"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(VelaL10n.text("settings_google_usage_summary",
                               PrivacyRequestCounter.sentToday,
                               PrivacyRequestCounter.dailyAverage))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("privacy-counter-total")

            if PrivacyRequestCounter.purposeRows.isEmpty {
                Text(VelaL10n.text("settings_google_usage_none"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("privacy-counter-none")
            } else {
                ForEach(PrivacyRequestCounter.purposeRows, id: \.label) { row in
                    Text(VelaL10n.text("settings_google_usage_row",
                                       purposeLabel(row.label), row.today, row.week))
                        .font(.footnote)
                        .accessibilityIdentifier("privacy-counter-row")
                }
                Text(VelaL10n.text("settings_google_usage_hosts"))
                    .font(.footnote.weight(.semibold))
                ForEach(PrivacyRequestCounter.hostRows, id: \.label) { row in
                    Text(VelaL10n.text("settings_google_usage_row", row.label, row.today, row.week))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("privacy-counter-host")
                }
            }

            if PrivacyRequestCounter.blockedToday > 0 {
                Text(VelaL10n.text("settings_google_usage_blocked",
                                   PrivacyRequestCounter.blockedToday))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("privacy-counter-blocked")
            }

            Button(VelaL10n.text("settings_google_usage_clear")) {
                PrivacyRequestCounter.clear()
                countCleared = true
                revision += 1
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("privacy-counter-clear")
            if countCleared {
                Text(VelaL10n.text("settings_google_usage_cleared"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("privacy-counter-cleared")
            }
        }
    }

    // MARK: - Delete what is stored

    private var deleteSection: some View {
        Section(VelaL10n.text("settings_privacy_delete")) {
            Text(VelaL10n.text("settings_clear_history_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(VelaL10n.text("settings_privacy_delete_saved"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(VelaL10n.text("settings_clear_history"), role: .destructive) {
                confirmClearHistory = true
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("privacy-clear-history")
            if historyCleared {
                Text(VelaL10n.text("settings_clear_history_done"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("privacy-history-cleared")
            }
        }
    }

    private var limitsSection: some View {
        Section(VelaL10n.text("settings_privacy_limits")) {
            Text(VelaL10n.text("settings_privacy_limits_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(VelaL10n.text("settings_privacy_button"), destination: model.privacyURL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("privacy-link")
        }
    }

    // MARK: - Actions

    private var diagnosticsSection: some View {
        Section(VelaL10n.text("settings_diagnostics")) {
            Button(VelaL10n.text("settings_export_diagnostics")) {
                exportDiagnostics()
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings-export-diagnostics")
            .id("settings-export-diagnostics")
            Text(VelaL10n.text("settings_exports_the_same_text_file_as"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func exportDiagnostics() {
        do {
            shareItems = [try DiagnosticsExport.fileURL()]
            showShare = true
        } catch {
            exportFailed = true
        }
    }

    /// Recent searches, recent places, parking history and every recorded trip, in one go. Saved
    /// places and lists are deliberately untouched, as is the Google request count (it has its own
    /// button above).
    private func clearAllHistory() {
        let session = AppGraph.session
        session.saved.clearRecents()
        session.saved.clearParkingHistory()
        _ = session.trips.deleteAll()
        historyCleared = true
        revision += 1
    }

    /// The counter stores the same purpose names Android uses; the catalog carries their labels.
    private func purposeLabel(_ kind: String) -> String {
        let key: String
        switch kind {
        case "search": key = "google_usage_kind_search"
        case "nearby places": key = "google_usage_kind_nearby"
        case "place details": key = "google_usage_kind_details"
        case "photos": key = "google_usage_kind_photos"
        case "reviews": key = "google_usage_kind_reviews"
        case "images": key = "google_usage_kind_images"
        case "directions": key = "google_usage_kind_directions"
        case "suggestions": key = "google_usage_kind_suggestions"
        case "street view": key = "google_usage_kind_streetview"
        case "session": key = "google_usage_kind_session"
        case "shared list": key = "google_usage_kind_lists"
        default: key = "google_usage_kind_other"
        }
        return VelaL10n.text(key)
    }
}
