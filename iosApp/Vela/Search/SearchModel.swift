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

/// One autocomplete row. A nil query opens the place at the row's index; non-nil runs that search.
struct SuggestionRow: Identifiable, Equatable {
    let id: String
    let index: Int
    let name: String
    let address: String?
    let query: String?
    let latitude: Double?
    let longitude: Double?
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
        didSet {
            if !mirroringState { store?.setQuery(q: query) }
        }
    }
    @Published private(set) var rows: [SearchRow] = []
    @Published private(set) var suggestions: [SuggestionRow] = []
    @Published private(set) var searching = false
    @Published private(set) var message: String?
    @Published private(set) var usedOffline = false

    private let store: SearchStore?
    private var observing: Task<Void, Never>?
    private var mirroringState = false

    init(store: SearchStore?) {
        self.store = store
    }

    /// Whether there is anything for the results panel to show.
    var hasContent: Bool { searching || !rows.isEmpty || message != nil }
    var hasSuggestions: Bool { !suggestions.isEmpty }
    var debugLine: String { "offline=\(usedOffline ? 1 : 0) results=\(rows.count) suggestions=\(suggestions.count)" }

    func start() {
        guard let store, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func submit(viewport: MapViewport?) {
        update(viewport: viewport)
        store?.setQuery(q: query)
        store?.submit()
    }

    /// A query suggestion, recent query or quick category bypasses the autocomplete debounce.
    func search(_ text: String, viewport: MapViewport?) {
        update(viewport: viewport)
        store?.search(query: text)
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

    private func update(viewport: MapViewport?) {
        guard let store, let v = viewport else { return }
        store.onViewport(south: v.south, west: v.west, north: v.north, east: v.east, zoom: v.zoom)
    }

    private func apply(_ state: SearchState) {
        mirroringState = true
        if query != state.query { query = state.query }
        mirroringState = false
        searching = state.searching
        usedOffline = state.usedOffline
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
        var autocomplete = state.suggestions.enumerated().map { index, place in
            SuggestionRow(
                id: "place-\(index)", index: index, name: place.name,
                address: place.address ?? place.category, query: nil,
                latitude: place.location.lat, longitude: place.location.lng)
        }
        autocomplete += state.querySuggestions.enumerated().map { index, text in
            SuggestionRow(
                id: "query-\(index)", index: index, name: text, address: nil,
                query: text, latitude: nil, longitude: nil)
        }
        suggestions = autocomplete
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
