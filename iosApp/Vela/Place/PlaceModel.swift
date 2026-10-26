import Foundation
import UIKit
import VelaCore

/// One review as the sheet shows it, copied out of the Kotlin `Review`.
struct ReviewRow: Identifiable, Equatable {
    let id: Int
    let author: String
    let avatar: String?
    let stars: Int
    let age: String?
    let text: String?
    let photos: [String]
}

/// One hour of a day's popular times.
struct BusyHour: Identifiable, Equatable {
    var id: Int { hour }
    let hour: Int
    let occupancy: Int
}

/// One day of Google's popular-times histogram.
struct BusyDay: Identifiable, Equatable {
    var id: Int { dayOfWeek }
    let dayOfWeek: Int
    let hours: [BusyHour]

    static var today: Int {
        // Calendar weekday: 1 = Sunday ... 7 = Saturday; Kotlin: 1 = Monday ... 7 = Sunday.
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }
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
    let photoDates: [String?]
    let photoCategories: [String?]
    let streetViewThumbnail: String?
    let busyDays: [BusyDay]
    var busyToday: [BusyHour] { busyDays.first { $0.dayOfWeek == BusyDay.today }?.hours ?? [] }
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
    @Published private(set) var reviewsMoreLoading = false
    @Published private(set) var canLoadMoreReviews = false
    @Published private(set) var photosLoading = false
    @Published private(set) var canLoadMorePhotos = false
    @Published private(set) var canWalkPhotos = false
    @Published private(set) var detailsFallback = "none"
    @Published private(set) var limitedView = false
    @Published private(set) var avatarsLoaded = 0
    @Published private(set) var avatarsNonBlack = 0

    private let session: MapSession?
    private var observing: Task<Void, Never>?
    private var avatarPlace = ""
    private var seenAvatars: Set<String> = []
    private var coloredAvatars: Set<String> = []

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

    /// A place link already names its place and often carries its own point and feature id.
    /// Opening it directly anchors the sheet there; the details fetch fills the rest.
    func openIncoming(name: String, latitude: Double, longitude: Double, featureID: String?) {
        session?.place.selectIncoming(
            name: name, lat: latitude, lng: longitude, featureId: featureID)
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

    func loadPhotoCategories() {
        session?.place.loadPhotoCategories()
    }

    /// The UIKit avatar path reports the decoded pixels, so the UI test checks the image itself.
    func reportAvatar(_ url: String, image: UIImage) {
        guard !seenAvatars.contains(url) else { return }
        seenAvatars.insert(url)
        if ImagePixels.hasNonBlackPixel(image) { coloredAvatars.insert(url) }
        avatarsLoaded = seenAvatars.count
        avatarsNonBlack = coloredAvatars.count
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
        let placeKey = state.selected?.featureId ?? state.selected?.id ?? ""
        if avatarPlace != placeKey {
            avatarPlace = placeKey
            seenAvatars = []
            coloredAvatars = []
            avatarsLoaded = 0
            avatarsNonBlack = 0
        }
        loadingDetails = state.loadingDetails
        reviewsLoading = state.reviewsLoading
        reviewsFound = Int(state.reviewsFound)
        reviewsLimited = state.reviewsLimited
        reviewsFrom = state.reviewsFrom
        reviewsMoreLoading = state.reviewsMoreLoading
        canLoadMoreReviews = (state.reviewsNextToken != nil || state.reviewsCanScrapeMore) && !state.reviewsMoreLoading
        photosLoading = state.photosLoading
        canLoadMorePhotos = state.photosNextToken != nil && !state.photosLoading
        canWalkPhotos = state.photosCanWalk && !state.photosLoading
        detailsFallback = state.detailsFallback ?? "none"
        limitedView = state.limitedView
        reviews = state.reviews.enumerated().map { index, r in
            ReviewRow(id: index, author: r.author, avatar: r.authorPhoto, stars: Int(r.rating), age: r.relativeTime, text: r.text, photos: r.photos)
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
            photoDates: p.photoDates.map { $0 as? String },
            photoCategories: p.photoCategories.map { $0 as? String },
            streetViewThumbnail: streetViewThumbnail(p),
            busyDays: busyDays(p.popularTimes),
            latitude: p.location.lat,
            longitude: p.location.lng)
    }

    private static func busyDays(_ times: PopularTimes?) -> [BusyDay] {
        times?.days.map {
            BusyDay(dayOfWeek: Int($0.dayOfWeek), hours: $0.hours.map { BusyHour(hour: Int($0.hour), occupancy: Int($0.occupancy)) })
        } ?? []
    }

    private static func streetViewThumbnail(_ place: Place) -> String? {
        guard let pano = place.svPanoId, !pano.isEmpty else { return nil }
        let yaw = place.svYawDeg?.doubleValue ?? 0
        return "https://streetviewpixels-pa.googleapis.com/v1/thumbnail?panoid=\(pano)&cb_client=maps_sv.tactile.gps&w=600&h=300&yaw=\(yaw)&pitch=0&thumbfov=100"
    }
}
