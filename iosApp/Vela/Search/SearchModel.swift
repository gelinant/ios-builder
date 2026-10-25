import Foundation
import VelaCore

/// One result row as the list and the pins show it, copied out of the Kotlin `Place`.
struct SearchRow: Identifiable, Equatable {
    let id: Int
    let name: String
    let address: String?
    let rating: Double?
    let reviewCount: Int?
    let latitude: Double
    let longitude: Double
}

/// The visible map, as `SearchStore.onViewport` takes it.
struct MapViewport: Equatable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
    let zoom: Double
}

/// SwiftUI's side of the Kotlin `SearchStore`: forwards the intents and mirrors the state, which
/// it reads through SKIE (`StateFlow` as an `AsyncSequence`). Main thread only.
final class SearchModel: ObservableObject {
    @Published var query = "" {
        didSet { store?.setQuery(q: query) }
    }
    @Published private(set) var rows: [SearchRow] = []
    @Published private(set) var searching = false
    @Published private(set) var message: String?

    private let store: SearchStore?
    private var observing: Task<Void, Never>?

    init(store: SearchStore?) {
        self.store = store
    }

    /// Whether there is anything for the results panel to show.
    var hasContent: Bool { searching || !rows.isEmpty || message != nil }

    func start() {
        guard let store, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func submit(viewport: MapViewport?) {
        guard let store else { return }
        if let v = viewport {
            store.onViewport(south: v.south, west: v.west, north: v.north, east: v.east, zoom: v.zoom)
        }
        store.setQuery(q: query)
        store.submit()
    }

    func clear() {
        store?.clear()
        query = ""
    }

    func viewportChanged(_ v: MapViewport) {
        store?.onViewport(south: v.south, west: v.west, north: v.north, east: v.east, zoom: v.zoom)
    }

    func locationChanged(latitude: Double, longitude: Double) {
        store?.onLocation(lat: latitude, lng: longitude)
    }

    private func apply(_ state: SearchState) {
        searching = state.searching
        let places = state.results
        rows = places.enumerated().map { index, place in
            SearchRow(
                id: index,
                name: place.name,
                address: place.address,
                rating: place.rating?.doubleValue,
                reviewCount: place.reviewCount.map { Int($0.int32Value) },
                latitude: place.location.lat,
                longitude: place.location.lng)
        }
        message = Self.message(for: state.error)
    }

    private static func message(for error: (any SearchError)?) -> String? {
        guard let error else { return nil }
        if error is SearchErrorNoResults {
            return "No results"
        }
        if error is SearchErrorNeedsRecalibration {
            return "Search needs an update: Google changed its answers"
        }
        if let failed = error as? SearchErrorFailed, let reason = failed.reason {
            return "Search failed: \(reason)"
        }
        return "Search failed"
    }
}
