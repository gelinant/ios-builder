import SwiftUI
import VelaCore

/// SwiftUI's mirror of the Kotlin SettingsStore. Setters write through before updating the view,
/// so PlatformLocale, VelaL10n and the place content policy immediately see the same values.
final class SettingsModel: ObservableObject {
    @Published private(set) var languageTag = ""
    /// Empty follows the app language; otherwise one of the shared navigation table tags.
    @Published private(set) var directionsLanguage = ""
    @Published private(set) var units = "system"
    @Published private(set) var clockMode = "system"
    @Published private(set) var imperial = false
    @Published private(set) var use24h = false

    @Published private(set) var lowDataMode = false
    @Published private(set) var lowRamMode = false
    @Published private(set) var placeContent = "full"
    @Published private(set) var showReviews = true
    @Published private(set) var loadPhotos = true
    @Published private(set) var photosWifiOnly = false
    @Published private(set) var photoQuality = "standard"
    @Published private(set) var photoCacheMb = 200
    @Published private(set) var fullPlaceLoad = false
    @Published private(set) var detailsRetry = true
    @Published private(set) var hideAdult = false
    @Published private(set) var hideExternalLinks = false
    @Published private(set) var redactPlacesInExports = false
    @Published private(set) var recordedTripCount = 0
    @Published private(set) var recordedTripBytes: Int64 = 0

    private let store: SettingsStore?
    private let defaults: UserDefaults
    private var observing: Task<Void, Never>?

    /// Android's key in the same `vela_settings` suite. The type marker matches the Kotlin
    /// `UserDefaultsKeyValueStores` layout, so a future Kotlin reader sees a String, not a cast.
    static let directionsKey = "directions_language"
    private static let typeMarkerKey = "__type__.directions_language"

    init(store: SettingsStore?) {
        self.store = store
        defaults = UserDefaults(suiteName: SettingsPersistence.settingsSuite) ?? .standard
        directionsLanguage = defaults.string(forKey: Self.directionsKey) ?? ""
        if let state = store?.state.value { apply(state) }
        applyDirectionsLanguage()
        refreshTrips()
    }

    var locale: Locale {
        Locale(identifier: VelaL10n.catalogLanguage(for: DevicePlatformLocale.effectiveTag()))
    }

    var layoutDirection: LayoutDirection {
        VelaL10n.isRightToLeft ? .rightToLeft : .leftToRight
    }

    var privacyURL: URL {
        URL(string: VelaLinks.shared.privacy())!
    }

    func start() {
        guard let store, observing == nil else { return }
        // MapSession.start has just applied the app language; the guidance choice is applied
        // after it, because the shared registry holds only one language at a time.
        applyDirectionsLanguage()
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func setLanguage(_ tag: String) {
        store?.setLanguage(tag: tag)
        languageTag = tag
        applyDirectionsLanguage()
    }

    // MARK: - Guidance language

    /// The language turns are shown and spoken in, after the follow-app and English fallbacks.
    var effectiveDirectionsLanguage: String {
        DirectionsLanguage.shared.effectiveTag(
            configured: directionsLanguage,
            appTag: DevicePlatformLocale.effectiveTag(),
            systemTag: DevicePlatformLocale.deviceLanguageTags().first ?? "en")
    }

    var directionsLanguageLabel: String {
        DirectionsLanguage.shared.label(tag: effectiveDirectionsLanguage)
    }

    /// "Same as app language" then the languages the shared navigation tables actually have.
    var directionsLanguageOptions: [(title: String, value: String)] {
        [(title: VelaL10n.text("settings_directions_language_same_app"), value: "")]
            + DirectionsLanguage.shared.tags().map {
                (title: DirectionsLanguage.shared.label(tag: $0), value: $0)
            }
    }

    /// True when the app language itself has no navigation table, so English is used.
    var appLanguageHasNoGuidance: Bool {
        let app = DirectionsLanguage.shared.normalize(tag: DevicePlatformLocale.effectiveTag())
        return !DirectionsLanguage.shared.tags().contains(app)
    }

    func setDirectionsLanguage(_ tag: String) {
        let normalized = DirectionsLanguage.shared.normalize(tag: tag)
        directionsLanguage = DirectionsLanguage.shared.tags().first { $0 == normalized } ?? ""
        defaults.set(directionsLanguage, forKey: Self.directionsKey)
        defaults.set("String", forKey: Self.typeMarkerKey)
        defaults.synchronize()
        applyDirectionsLanguage()
        VoiceLibrary.shared.refresh()
    }

    /// Pushes the explicit guidance choice into the shared navigation tables. Only one registry
    /// exists, so this runs after any SettingsStore language application, never before it.
    private func applyDirectionsLanguage() {
        let parts = DirectionsLanguage.shared.parts(tag: effectiveDirectionsLanguage)
        NavStringsRegistry.shared.setLanguage(
            language: parts.language, region: parts.region, script: parts.script)
    }

    func setUnits(_ mode: String) {
        store?.setUnits(mode: mode)
        units = mode
        if let state = store?.state.value { apply(state) }
    }

    func setClockMode(_ mode: String) {
        store?.setClockMode(mode: mode)
        clockMode = mode
        if let state = store?.state.value { apply(state) }
    }

    // MARK: - Data and content

    func setLowDataMode(_ on: Bool) { store?.setLowDataMode(on: on); lowDataMode = on }
    func setLowRamMode(_ on: Bool) { store?.setLowRamMode(on: on); lowRamMode = on }
    func setPlaceContent(_ mode: String) { store?.setPlaceContent(mode: mode); placeContent = mode }
    func setShowReviews(_ on: Bool) { store?.setShowReviews(on: on); showReviews = on }
    func setLoadPhotos(_ on: Bool) { store?.setLoadPhotos(on: on); loadPhotos = on }

    func setPhotosWifiOnly(_ on: Bool) {
        store?.setPhotosWifiOnly(on: on)
        photosWifiOnly = on
        ImageLoader.shared.applySettings()
    }

    func setPhotoQuality(_ quality: String) {
        store?.setPhotoQuality(quality: quality)
        photoQuality = quality
        ImageLoader.shared.applySettings()
    }

    func setPhotoCacheMb(_ mb: Int) {
        store?.setPhotoCacheMb(mb: Int32(mb))
        photoCacheMb = mb
        ImageLoader.shared.applySettings()
    }

    func setFullPlaceLoad(_ on: Bool) { store?.setFullPlaceLoad(on: on); fullPlaceLoad = on }
    func setDetailsRetry(_ on: Bool) { store?.setDetailsRetry(on: on); detailsRetry = on }
    func setHideAdult(_ on: Bool) { store?.setHideAdult(on: on); hideAdult = on }
    func setHideExternalLinks(_ on: Bool) { store?.setHideExternalLinks(on: on); hideExternalLinks = on }
    func setRedactPlacesInExports(_ on: Bool) { store?.setRedactPlacesInExports(on: on); redactPlacesInExports = on }

    /// The photo loader is not observable; the row asks it when it appears and after a purge.
    var photoCacheBytes: Int64 { ImageLoader.shared.currentBytes }

    func clearPhotoCache() {
        ImageLoader.shared.purge()
    }

    func refreshTrips() {
        let store = AppGraph.session.trips
        recordedTripCount = store.list().count
        recordedTripBytes = store.totalBytes()
    }

    func deleteAllTrips() {
        _ = AppGraph.session.trips.deleteAll()
        refreshTrips()
    }

    /// One line for the Debug UI scenario. Kept short enough to fit the screen.
    var contentDebugLine: String {
        "lowData=\(lowDataMode ? 1 : 0) lowRam=\(lowRamMode ? 1 : 0) place=\(placeContent) "
            + "reviews=\(showReviews ? 1 : 0) photos=\(loadPhotos ? 1 : 0) wifi=\(photosWifiOnly ? 1 : 0) "
            + "quality=\(photoQuality) cacheMb=\(photoCacheMb) full=\(fullPlaceLoad ? 1 : 0) "
            + "retry=\(detailsRetry ? 1 : 0) adult=\(hideAdult ? 1 : 0) ext=\(hideExternalLinks ? 1 : 0) "
            + "redact=\(redactPlacesInExports ? 1 : 0) "
            + "trips=\(recordedTripCount) tripBytes=\(recordedTripBytes) photoBytes=\(photoCacheBytes)"
    }

    private func apply(_ state: SettingsState) {
        let languageChanged = languageTag != state.languageTag
        if languageChanged { languageTag = state.languageTag }
        if units != state.units { units = state.units }
        if clockMode != state.clockMode { clockMode = state.clockMode }
        if imperial != state.imperial { imperial = state.imperial }
        if use24h != state.use24h { use24h = state.use24h }
        if lowDataMode != state.lowDataMode { lowDataMode = state.lowDataMode }
        if lowRamMode != state.lowRamMode { lowRamMode = state.lowRamMode }
        if placeContent != state.placeContent { placeContent = state.placeContent }
        if showReviews != state.showReviews { showReviews = state.showReviews }
        if loadPhotos != state.loadPhotos { loadPhotos = state.loadPhotos }
        if photosWifiOnly != state.photosWifiOnly { photosWifiOnly = state.photosWifiOnly }
        if photoQuality != state.photoQuality { photoQuality = state.photoQuality }
        let cacheMb = Int(state.photoCacheMb)
        if photoCacheMb != cacheMb { photoCacheMb = cacheMb }
        if fullPlaceLoad != state.fullPlaceLoad { fullPlaceLoad = state.fullPlaceLoad }
        if detailsRetry != state.detailsRetry { detailsRetry = state.detailsRetry }
        if hideAdult != state.hideAdult { hideAdult = state.hideAdult }
        if hideExternalLinks != state.hideExternalLinks { hideExternalLinks = state.hideExternalLinks }
        if redactPlacesInExports != state.redactPlacesInExports { redactPlacesInExports = state.redactPlacesInExports }
        ImageLoader.shared.applySettings()
        if languageChanged { applyDirectionsLanguage() }
    }
}
