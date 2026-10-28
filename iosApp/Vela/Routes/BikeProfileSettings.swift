import SwiftUI
import VelaCore

/// The bike profile as the Settings screen sees it. The chooser owns the same preference through
/// `RouteStore.setBikeSafe`, stored under Android's `bike_safe` key and mirrored into
/// `RoutingPrefs.bikeSafe` before any route request. This wrapper only reads that state and
/// forwards changes, so a profile chosen in one place shows in the other.
final class BikeProfileSettings: ObservableObject {
    @Published private(set) var safe = true

    private let store: RouteStore?
    private var observing: Task<Void, Never>?

    init(store: RouteStore? = AppGraph.session.route) {
        self.store = store
        safe = store?.bikeSafeEnabled() ?? true
    }

    func start() {
        guard let store, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.safe = state.bikeSafe
            }
        }
    }

    func setSafe(_ on: Bool) {
        store?.setBikeSafe(on: on)
        safe = on
    }
}
