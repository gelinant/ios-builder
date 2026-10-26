import SwiftUI
import VelaCore

/// SwiftUI's mirror of the Kotlin SettingsStore. Setters write through before updating the view,
/// so PlatformLocale and VelaL10n immediately see the same persisted language.
final class SettingsModel: ObservableObject {
    @Published private(set) var languageTag = ""
    @Published private(set) var units = "system"
    @Published private(set) var clockMode = "system"
    @Published private(set) var imperial = false
    @Published private(set) var use24h = false

    private let store: SettingsStore?
    private var observing: Task<Void, Never>?

    init(store: SettingsStore?) {
        self.store = store
        if let state = store?.state.value { apply(state) }
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
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func setLanguage(_ tag: String) {
        store?.setLanguage(tag: tag)
        languageTag = tag
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

    private func apply(_ state: SettingsState) {
        if languageTag != state.languageTag { languageTag = state.languageTag }
        if units != state.units { units = state.units }
        if clockMode != state.clockMode { clockMode = state.clockMode }
        if imperial != state.imperial { imperial = state.imperial }
        if use24h != state.use24h { use24h = state.use24h }
    }
}
