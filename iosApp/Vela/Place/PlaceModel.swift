import Foundation
import VelaCore

/// One review as the sheet shows it, copied out of the Kotlin `Review`.
struct ReviewRow: Identifiable, Equatable {
    let id: Int
    let author: String
    let avatar: String?
    let stars: Int
    let age: String?
    let text: String?
}

/// One hour of a day's popular times.
struct BusyHour: Identifiable, Equatable {
    var id: Int { hour }
    let hour: Int
    let occupancy: Int
}

/// The open place as the sheet shows it, copied out of the Kotlin `Place`.
struct PlaceCard: Equatable {
    let key: String
    let name: String
    let category: String?
    let rating: Double?
    let reviewCount: Int?
    let priceText: String?
    let statusText: String?
    let openNow: Bool?
    let hours: [String]
    let address: String?
    let phone: String?
    let website: String?
    let summary: String?
    let photos: [String]
    /// Today's popular times, from the Kotlin day numbers (1 = Monday ... 7 = Sunday).
    let busyToday: [BusyHour]
    let latitude: Double
    let longitude: Double
}

/// SwiftUI's side of the Kotlin `PlaceStore`: forwards the intents and mirrors the state, read
/// through SKIE. Main thread only.
final class PlaceModel: ObservableObject {
    @Published private(set) var card: PlaceCard?
    @Published private(set) var reviews: [ReviewRow] = []
    @Published private(set) var loadingDetails = false
    @Published private(set) var reviewsLoading = false
    @Published private(set) var reviewsFound = 0
    @Published private(set) var reviewsLimited = false
    @Published private(set) var reviewsFrom: String?
    @Published private(set) var canLoadMoreReviews = false
    @Published private(set) var photosLoading = false
    @Published private(set) var canLoadMorePhotos = false

    private let session: MapSession?
    private var observing: Task<Void, Never>?

    init(session: MapSession?) {
        self.session = session
    }

    var isOpen: Bool { card != nil }

    func start() {
        guard let store = session?.place, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func open(resultIndex: Int) {
        session?.openResult(index: Int32(resultIndex))
    }

    func close() {
        session?.place.close()
    }

    /// The reviews section came on screen.
    func reviewsVisible() {
        session?.place.ensureReviews()
    }

    func loadMoreReviews() {
        session?.place.loadMoreReviews()
    }

    func loadMorePhotos() {
        session?.place.loadMorePhotos()
    }

    /// The headers a place photo is asked for with.
    func photoHeaders() -> [String: String] {
        var out: [String: String] = [:]
        for h in session?.photoHeaders() ?? [] {
            out[h.name] = h.value
        }
        return out
    }

    private func apply(_ state: PlaceState) {
        loadingDetails = state.loadingDetails
        reviewsLoading = state.reviewsLoading
        reviewsFound = Int(state.reviewsFound)
        reviewsLimited = state.reviewsLimited
        reviewsFrom = state.reviewsFrom
        canLoadMoreReviews = state.reviewsNextToken != nil && !state.reviewsMoreLoading
        photosLoading = state.photosLoading
        canLoadMorePhotos = state.photosNextToken != nil && !state.photosLoading
        reviews = state.reviews.enumerated().map { index, r in
            ReviewRow(id: index, author: r.author, avatar: r.authorPhoto, stars: Int(r.rating), age: r.relativeTime, text: r.text)
        }
        card = state.selected.map(Self.card)
    }

    private static func card(_ p: Place) -> PlaceCard {
        PlaceCard(
            key: p.featureId ?? p.name,
            name: p.name,
            category: p.category,
            rating: p.rating?.doubleValue,
            reviewCount: p.reviewCount.map { Int($0.int32Value) },
            priceText: p.priceText,
            statusText: p.statusText,
            openNow: p.openNow?.boolValue,
            hours: p.hours,
            address: p.address,
            phone: p.phone,
            website: p.website,
            summary: p.editorialSummary,
            photos: p.photoUrls,
            busyToday: busyToday(p.popularTimes),
            latitude: p.location.lat,
            longitude: p.location.lng)
    }

    private static func busyToday(_ times: PopularTimes?) -> [BusyHour] {
        guard let times else { return [] }
        // Calendar weekday: 1 = Sunday ... 7 = Saturday; Kotlin: 1 = Monday ... 7 = Sunday.
        let weekday = Calendar.current.component(.weekday, from: Date())
        let today = weekday == 1 ? 7 : weekday - 1
        guard let day = times.days.first(where: { Int($0.dayOfWeek) == today }) else { return [] }
        return day.hours.map { BusyHour(hour: Int($0.hour), occupancy: Int($0.occupancy)) }
    }
}
