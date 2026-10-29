import SwiftUI
import VelaCore

/// The first-run Google question (SET-PRIVACY), the iOS counterpart of Android's welcome screen.
/// Nothing behind it is usable until it is answered, and the HTTP client refuses every Google host
/// until then (`PrivacyConsent`). The answer is stored in Android's own keys: `welcome_done` for
/// the question and `ios_google_disabled` for "Use Vela without Google".
///
/// Android also asks about plate cameras on this page. iOS has no camera avoidance, so offering
/// those switches here would promise a behaviour the app does not have; they are absent.
struct ConsentScreen: View {
    /// Called once the answer and the per-feature choices are stored.
    let onFinish: () -> Void

    @ObservedObject private var privacy = PrivacySettings.shared
    @State private var useGoogle = true
    @State private var showUses = false
    @State private var lookupTapped = true
    @State private var showReviews = true
    @State private var loadPhotos = true
    @State private var fullPlaceLoad = false
    @State private var detailsRetry = true

    var body: some View {
        NavigationStack {
            if showUses {
                usesPage
            } else {
                choicePage
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: loadChoices)
    }

    // MARK: - The question

    private var choicePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(VelaL10n.text("welcome_google_title"))
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("consent-title")
                Text(VelaL10n.text("welcome_google_intro"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(VelaL10n.text("welcome_google_consent_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                choice(
                    id: "consent-use-google",
                    selected: useGoogle,
                    title: VelaL10n.text("welcome_google_on_title"),
                    gives: VelaL10n.text("welcome_google_on_gives"),
                    sends: VelaL10n.text("welcome_google_on_sends_open_routes")
                ) { useGoogle = true }

                choice(
                    id: "consent-no-google",
                    selected: !useGoogle,
                    title: VelaL10n.text("welcome_google_off_title"),
                    gives: VelaL10n.text("welcome_google_off_gives"),
                    sends: VelaL10n.text("welcome_google_off_sends_short_links")
                ) { useGoogle = false }

                Button {
                    showUses = true
                } label: {
                    Text(VelaL10n.text("welcome_google_customize"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("consent-customize")

                Button(action: finish) {
                    Text(VelaL10n.text("welcome_continue"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("consent-continue")
            }
            .padding(24)
        }
        .accessibilityIdentifier("consent-screen")
        .navigationTitle(VelaL10n.text("settings_privacy"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One answer: a radio mark, what it gives, and what Google sees. The whole card is the target.
    private func choice(
        id: String,
        selected: Bool,
        title: String,
        gives: String,
        sends: String,
        select: @escaping () -> Void
    ) -> some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(gives).font(.subheadline)
                    Text(sends).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - What Google is used for

    private var usesPage: some View {
        Form {
            Section(VelaL10n.text("settings_google_uses")) {
                Text(VelaL10n.text("settings_google_uses_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(VelaL10n.text("settings_places_lookup"), isOn: $lookupTapped)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("consent-lookup")
                Toggle(VelaL10n.text("settings_show_reviews"), isOn: $showReviews)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("consent-reviews")
                Toggle(VelaL10n.text("settings_load_photos"), isOn: $loadPhotos)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("consent-photos")
                Toggle(VelaL10n.text("settings_full_place_load"), isOn: $fullPlaceLoad)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("consent-full-place")
                Toggle(VelaL10n.text("settings_details_retry"), isOn: $detailsRetry)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("consent-details-retry")
            }
            Section {
                Button {
                    storeChoices()
                    showUses = false
                } label: {
                    Text(VelaL10n.text("welcome_continue"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("consent-uses-done")
            }
        }
        .accessibilityIdentifier("consent-uses-screen")
        .navigationTitle(VelaL10n.text("settings_google_uses"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(VelaL10n.text("settings_cancel")) { showUses = false }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("consent-back")
            }
        }
    }

    // MARK: - Reading and storing

    private func loadChoices() {
        lookupTapped = privacy.lookupTappedPlaces
        guard let state = AppGraph.session.settings?.state.value else { return }
        showReviews = state.showReviews
        loadPhotos = state.loadPhotos
        fullPlaceLoad = state.fullPlaceLoad
        detailsRetry = state.detailsRetry
    }

    /// Writes the per-feature answers through the same stores as Settings, so the map sees them
    /// before its next request.
    private func storeChoices() {
        privacy.setLookupTappedPlaces(lookupTapped)
        let store = AppGraph.session.settings
        store?.setShowReviews(on: showReviews)
        store?.setLoadPhotos(on: loadPhotos)
        store?.setFullPlaceLoad(on: fullPlaceLoad)
        store?.setDetailsRetry(on: detailsRetry)
    }

    /// The two writes the map cannot make for itself: the Google answer and the fact that it was
    /// answered. Both keys are Android's.
    private func finish() {
        storeChoices()
        let defaults = UserDefaults(suiteName: SettingsPersistence.settingsSuite)
        let noGoogle = !useGoogle
        defaults?.set(noGoogle, forKey: PrivacySettings.noGoogleKey)
        defaults?.set(true, forKey: PrivacySettings.welcomeDoneKey)
        defaults?.synchronize()
        AppGraph.session.offline?.setGoogleDisabled(disabled: noGoogle)
        onFinish()
    }
}
