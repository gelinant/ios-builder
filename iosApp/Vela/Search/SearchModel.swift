import Foundation
import UIKit
import VelaCore

/// One result row as the list and the pins show it, copied out of the Kotlin `Place`.
struct SearchRow: Identifiable, Equatable {
    /// Index in SearchStore.results, used to open the row. Stable source identities are separate.
    let id: Int
    let stableId: String
    let featureId: String?
    let name: String
    let address: String?
    let rating: Double?
    let reviewCount: Int?
    let priceText: String?
    let category: String?
    let distanceMeters: Double?
    let openNow: Bool?
    let statusText: String?
    let permanentlyClosed: Bool
    let phone: String?
    let photoURL: String?
    let isSaved: Bool
    let latitude: Double
    let longitude: Double

    /// The status line as Android's cards show it: Google's own words, else a plain Open/Closed.
    var status: String? {
        if permanentlyClosed { return "Permanently closed" }
        if let text = statusText, !text.isEmpty { return text }
        switch openNow {
        case true: return "Open"
        case false: return "Closed"
        case nil: return nil
        }
    }

    /// Green when open, red when closed or dead, as on Android.
    var statusIsPositive: Bool { !permanentlyClosed && openNow != false }

    /// Google, one star, the count, then distance, price and kind, cut when the card is narrow.
    var summary: String {
        var parts: [String] = []
        if let count = reviewCount { parts.append("(\(count))") }
        if let meters = distanceMeters { parts.append(SearchRow.distance(meters)) }
        if let price = priceText, !price.isEmpty { parts.append(price) }
        if let category, !category.isEmpty { parts.append(category) }
        return parts.joined(separator: " · ")
    }

    /// What VoiceOver reads for the card: the same facts the eye sees, not a debug line.
    var accessibilityLabel: String {
        var parts = [name]
        if let rating { parts.append(String(format: "%.1f stars", rating)) }
        if let count = reviewCount { parts.append("\(count) reviews") }
        if let status { parts.append(status) }
        if let address, !address.isEmpty { parts.append(address) }
        if let price = priceText, !price.isEmpty { parts.append(price) }
        if let category, !category.isEmpty { parts.append(category) }
        return parts.joined(separator: ", ")
    }

    /// Debug UI tests can prove source-id, feature-id and location deduplication through XCUI.
    var debugAccessibilityValue: String {
        "\(stableId)|\(featureId ?? "")|\(address ?? "")|\(latitude)|\(longitude)"
    }

    static func distance(_ meters: Double) -> String {
        let imperial = AppGraph.session.settings?.imperial
            ?? (Locale.current.measurementSystem == .us)
        if imperial {
            let feet = meters * 3.28084
            if feet < 1000 { return "\(Int((feet / 10).rounded() * 10)) ft" }
            return String(format: "%.1f mi", meters / 1609.344)
        }
        if meters < 1000 { return "\(Int((meters / 10).rounded() * 10)) m" }
        return String(format: "%.1f km", meters / 1000)
    }
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
    /// True for the leading rows backed by the user's recent or saved places.
    let local: Bool

    /// The return arrow puts this text in the box without searching, as Android does.
    var fillText: String { query ?? name }
}

/// The visible map, as `SearchStore.onViewport` takes it.
struct MapViewport: Equatable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
    let zoom: Double
}

/// The card and suggestion actions reach the model without changing MapScreen's call sites:
/// MapScreen.swift is serialized by the hive (BACKLOG section 3), so this lot may not add
/// parameters there. The single live model owns the handlers; the views fall back to it.
enum SearchActions {
    static weak var model: SearchModel?

    static func fill(_ row: SuggestionRow) { model?.fill(row) }
    static func directions(_ row: SearchRow) { model?.directions(row) }
    static func call(_ row: SearchRow) { model?.call(row) }
    static func toggleSave(_ row: SearchRow) { model?.toggleSave(row) }
    static func loadMore() { model?.loadMore() }
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
    @Published private(set) var moreAvailable = false
    @Published private(set) var loadingMore = false

    private let store: SearchStore?
    private let session: MapSession?
    private var observing: Task<Void, Never>?
    private var savedObserving: Task<Void, Never>?
    private var mirroringState = false
    /// The Kotlin places behind [rows], for the card actions that need the whole object.
    private var places: [Place] = []

    init(store: SearchStore?, session: MapSession? = AppGraph.session) {
        self.store = store
        self.session = session
        SearchActions.model = self
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
        if let saved = session?.saved {
            applyLocalPlaces(saved.state.value)
            savedObserving = Task { @MainActor [weak self] in
                for await state in saved.state {
                    self?.applyLocalPlaces(state)
                }
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
        moreAvailable = false
        loadingMore = false
        places = []
    }

    func viewportChanged(_ v: MapViewport) {
        store?.onViewport(south: v.south, west: v.west, north: v.north, east: v.east, zoom: v.zoom)
    }

    func locationChanged(latitude: Double, longitude: Double) {
        store?.onLocation(lat: latitude, lng: longitude)
    }

    // MARK: - Suggestion and card actions

    /// Android's return arrow: the text lands in the box, no search runs.
    func fill(_ row: SuggestionRow) {
        query = row.fillText
    }

    /// The card's Directions: the route chooser reads the row directly, with no details fetch.
    func directions(_ row: SearchRow) {
        guard let place = place(for: row), let session else { return }
        session.route.directionsTo(p: place)
    }

    func call(_ row: SearchRow) {
        guard let phone = row.phone?.filter({ $0.isNumber || $0 == "+" }), !phone.isEmpty,
              let url = URL(string: "tel://\(phone)") else { return }
        UIApplication.shared.open(url)
    }

    /// Quick save, through the same store the place sheet uses.
    func toggleSave(_ row: SearchRow) {
        guard let session, let place = place(for: row) else { return }
        _ = session.saved.toggleSave(place: place)
        rebuildRows()
    }

    func loadMore() {
        store?.loadMore()
    }

    /// The Safari image identity the place photos use: no new Google request, the search reply
    /// already carried these URLs.
    func photoHeaders() -> [String: String] {
        var out: [String: String] = [:]
        for header in session?.photoHeaders() ?? [] {
            out[header.name] = header.value
        }
        return out
    }

    private func place(for row: SearchRow) -> Place? {
        places.first { $0.id == row.stableId }
    }

    private func update(viewport: MapViewport?) {
        guard let store, let v = viewport else { return }
        store.onViewport(south: v.south, west: v.west, north: v.north, east: v.east, zoom: v.zoom)
    }

    /// Android's own-data order: recently viewed places, then list places, then the shortlist.
    private func applyLocalPlaces(_ state: SavedState) {
        var pool: [Place] = state.recentPlaces.map { $0.place.toPlace() }
        pool += state.lists.flatMap { list in list.places.map { $0.toPlace() } }
        pool += state.saved.map { $0.toPlace() }
        store?.setLocalPlaces(places: pool)
    }

    private func apply(_ state: SearchState) {
        mirroringState = true
        if query != state.query { query = state.query }
        mirroringState = false
        searching = state.searching
        usedOffline = state.usedOffline
        moreAvailable = state.moreAvailable
        loadingMore = state.loadingMore
        places = state.results
        rebuildRows()
        let localCount = Int(state.localSuggestionCount)
        var autocomplete = state.suggestions.enumerated().map { index, place in
            SuggestionRow(
                id: "place-\(index)", index: index, name: place.name,
                address: place.address ?? place.category, query: nil,
                latitude: place.location.lat, longitude: place.location.lng,
                local: index < localCount)
        }
        autocomplete += state.querySuggestions.enumerated().map { index, text in
            SuggestionRow(
                id: "query-\(index)", index: index, name: text, address: nil,
                query: text, latitude: nil, longitude: nil, local: false)
        }
        suggestions = autocomplete
        message = Self.message(for: state.error)
    }

    private func rebuildRows() {
        let savedIds = Set(session?.saved.state.value.saved.map { $0.id } ?? [])
        rows = places.enumerated().map { index, place in
            SearchRow(
                id: index,
                stableId: place.id,
                featureId: place.featureId,
                name: place.name,
                address: place.address,
                rating: place.rating?.doubleValue,
                reviewCount: place.reviewCount.map { Int($0.int32Value) },
                priceText: place.priceText,
                category: place.category,
                distanceMeters: place.distanceMeters?.doubleValue,
                openNow: place.openNow?.boolValue,
                statusText: place.statusText,
                permanentlyClosed: place.permanentlyClosed,
                phone: place.phone,
                photoURL: place.photoUrls.first.map(SearchRow.sizedPhoto),
                isSaved: savedIds.contains(place.id),
                latitude: place.location.lat,
                longitude: place.location.lng)
        }
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

extension SearchRow {
    /// Google's photo host sizes on the URL suffix, as Android asks for a 400 px list cell.
    static func sizedPhoto(_ url: String) -> String {
        guard let equals = url.lastIndex(of: "=") else { return url }
        return String(url[..<equals]) + "=w400-h300"
    }
}
