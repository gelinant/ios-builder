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
    /// Google showed this review translated into the page language.
    let translated: Bool
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

/// One "About" section from Google's attributes panel.
struct AboutSectionRow: Identifiable, Equatable {
    let id: Int
    let title: String
    let items: [String]
}

/// One "People also search for" entry. Google supplies a name, a point and a feature id.
struct RelatedPlaceRow: Identifiable, Equatable {
    let id: Int
    let name: String
    let rating: Double?
    let latitude: Double
    let longitude: Double
    let featureId: String?
}

/// One business post ("From the owner" updates).
struct UpdateRow: Identifiable, Equatable {
    let id: Int
    let text: String
    let posted: String?
    let url: String?
    let linkLabel: String?
    let imageUrl: String?
}

/// One "Also at this location" row: another Google listing at the open place's address.
struct BranchRow: Identifiable, Equatable {
    let id: Int
    let stableId: String
    let name: String
    let category: String?
    let address: String?
    let rating: Double?
    let reviewCount: Int?
    let openNow: Bool?
    let statusText: String?
    let permanentlyClosed: Bool

    var status: String? {
        if permanentlyClosed { return "Permanently closed" }
        if let text = statusText, !text.isEmpty { return text }
        switch openNow {
        case true: return "Open"
        case false: return "Closed"
        case nil: return nil
        }
    }

    var summary: String {
        var parts: [String] = []
        if let rating {
            parts.append(reviewCount.map { String(format: "%.1f★ (%d)", rating, $0) }
                ?? String(format: "%.1f★", rating))
        }
        if let category, !category.isEmpty { parts.append(category) }
        return parts.joined(separator: " · ")
    }
}

/// A cheaper forecourt within reach of the open place: the Fuel Finder comparison.
struct FuelNearbyRow: Equatable {
    let brand: String?
    let pence: Int
    let meters: Double
}

/// One in-store department with its own schedule.
struct DepartmentRow: Identifiable, Equatable {
    let id: Int
    let name: String
    let hours: [String]
    let statusText: String?
    let openNow: Bool?
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
    let ownerDescription: String?
    let about: [AboutSectionRow]
    let updates: [UpdateRow]
    let similarPlaces: [RelatedPlaceRow]
    let departments: [DepartmentRow]
    let actionLabel: String?
    let actionUrl: String?
    let permanentlyClosed: Bool
    let temporarilyClosed: Bool
    /// The pump line: Google's US price or a UK Fuel Finder price ("172.9p/E10 · 199.9p/B7").
    let fuelPrice: String?
    /// The matched UK forecourt's newest report, unix seconds; nil for Google's US price.
    let fuelPriceAt: Int64?
    /// The matched forecourt's brand and the grade the nearby comparison uses.
    let fuelBrand: String?
    let fuelGrade: String?
    /// A cheaper forecourt within 5 km, only when the file supports one by at least a penny.
    let fuelNearby: FuelNearbyRow?
    let featuredReview: String?
    let photos: [String]
    let photoDates: [String?]
    let photoCategories: [String?]
    let streetViewThumbnail: String?
    let streetViewPanoId: String?
    let streetViewYawDeg: Double?
    let busyDays: [BusyDay]
    var busyToday: [BusyHour] { busyDays.first { $0.dayOfWeek == BusyDay.today }?.hours ?? [] }
    /// Google's rating distribution as `[5-star ... 1-star]` counts, when the page scrape saw it.
    let ratingHistogram: [Int]?
    let latitude: Double
    let longitude: Double
    /// The Google feature id, for the canonical share link when Google is on.
    let featureId: String?
    /// The place's own id (Google feature id, `osm:...`, `photon:...` or a pin), used to find an
    /// OpenStreetMap object for a share when Google is off.
    let sourceId: String

    /// A business or landmark rather than a bare address, as on Android's `Place.isListing`.
    var isListing: Bool {
        !(category?.isEmpty ?? true) || rating != nil || reviewCount != nil || featuredReview != nil
    }

    /// The Wikidata item this place names on its own id, if any (`wikidata:Q90`, `wd:Q90`, `Q90`).
    /// Google and OSM ids name none, so the sheet asks Wikidata nothing for them.
    var wikidataId: String? {
        for raw in [sourceId, featureId ?? ""] {
            if let id = PlaceCard.parseWikidataId(raw) { return id }
        }
        return nil
    }

    static func parseWikidataId(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["wikidata:", "wd:"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        guard text.count > 1, text.first?.lowercased() == "q",
              text.dropFirst().allSatisfy({ $0.isNumber }) else { return nil }
        return text.uppercased()
    }

    /// Whether the hidden gallery walk labelled any photo as a menu.
    var menuPhotoIndices: [Int] {
        photoCategories.indices.filter { index in
            guard let category = photoCategories[index] else { return false }
            let lower = category.lowercased()
            return PlaceCard.menuWords.contains { lower.contains($0) }
        }
    }

    var menuCategoryName: String? {
        menuPhotoIndices.first.flatMap { photoCategories[$0] }
    }

    /// Google localizes the gallery tab name, so the detection uses the same word set as Android.
    static let menuWords = ["menu", "menú", "menù", "speisekarte", "cardápio", "menukaart", "меню", "meny"]
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
    /// The other listings at the open place's address, read from the search reply already held.
    /// Empty when Google sent no sibling; nothing is drawn then.
    @Published private(set) var branches: [BranchRow] = []

    private let session: MapSession?
    private var observing: Task<Void, Never>?
    private var avatarPlace = ""
    private var seenAvatars: Set<String> = []
    private var coloredAvatars: Set<String> = []
    private var fixtureOpened = false
    /// The Kotlin branch places behind [branches], so a row opens the real listing.
    private var branchPlaces: [Place] = []
    /// Debug scenario only: a fixed group stands in for the search reply.
    private var branchFixture: [Place]?
    /// Debug scenario only: the W-1 place and its Wikidata id, opened without a search.
    private var wikiFixture = false

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    init(session: MapSession?) {
        self.session = session
    }

    var isOpen: Bool { card != nil }

    func start() {
        openWikiFixtureIfAsked()
        guard let store = session?.place, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
        openFuelFixtureIfAsked(store)
        openBranchFixtureIfAsked()
    }

    /// The W-1 scenario opens a fixed place that names a Wikidata item and turns the wiki layer on,
    /// so the section can fetch live without a search or a Google request. Production launches
    /// carry no such argument.
    private func openWikiFixtureIfAsked() {
        #if DEBUG
        guard !wikiFixture, card == nil else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaPlaceWikiFixture"),
              index + 1 < arguments.count else { return }
        let raw = arguments[index + 1].trimmingCharacters(in: .whitespaces)
        let candidate = raw.caseInsensitiveCompare("YES") == .orderedSame ? "Q90" : raw
        guard let id = PlaceCard.parseWikidataId(candidate) else { return }
        wikiFixture = true
        WorldLayersHub.shared.setEnabled("wiki", true)
        card = PlaceCard.wikiFixture(wikidataId: id)
        loadingDetails = false
        #endif
    }

    /// The branch scenario opens a fixed shop and its three neighbors without a search or a Google
    /// request. Production launches carry no such argument and read the search reply instead.
    private func openBranchFixtureIfAsked() {
        #if DEBUG
        guard branchFixture == nil else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaPlaceBranchesFixture"),
              index + 1 < arguments.count,
              arguments[index + 1].caseInsensitiveCompare("YES") == .orderedSame else { return }
        let group = PlaceBranches.shared.fixture()
        guard let first = group.first else { return }
        branchFixture = group
        showBranchFixture(first)
        #endif
    }

    /// Opens another listing at the same address without closing the group: the chip and the list
    /// recompute for the new place, so the original stays one tap away.
    func openBranch(_ row: BranchRow) {
        guard let place = branchPlaces.first(where: { $0.id == row.stableId }) else { return }
        if branchFixture != nil {
            showBranchFixture(place)
            return
        }
        session?.place.select(p: place)
    }

    private func showBranchFixture(_ selected: Place) {
        guard let group = branchFixture else { return }
        card = Self.makeCard(selected, fuel: nil)
        loadingDetails = false
        applyBranches(PlaceBranches.shared.companions(selected: selected, candidates: group))
    }

    /// The fuel scenarios open a fixed place without a search or a Google request. The value is
    /// the fixture kind ("fuel" or "closing"); production launches carry no such argument.
    private func openFuelFixtureIfAsked(_ store: PlaceStore) {
        guard !fixtureOpened else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaPlaceFuelFixture"),
              index + 1 < arguments.count else { return }
        let kind = arguments[index + 1].trimmingCharacters(in: .whitespaces)
        guard !kind.isEmpty else { return }
        fixtureOpened = true
        store.openFuelFixture(kind: kind)
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

    /// Opens one of the sheet's related places. It reuses the sheet's own load path, so the
    /// details, gallery and reviews start for the new place without another search request.
    func openRelated(_ row: RelatedPlaceRow) {
        session?.place.selectRelated(
            name: row.name, lat: row.latitude, lng: row.longitude, featureId: row.featureId)
    }

    func close() {
        // The debug branch scenario owns the sheet's card, so clear it here too: the store's
        // empty state alone would otherwise leave the fixture sheet on screen.
        branchFixture = nil
        branchPlaces = []
        branches = []
        wikiFixture = false
        card = nil
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
        // The debug branch scenario owns the sheet; a store emission must not replace it.
        if branchFixture != nil || wikiFixture { return }
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
            let key = Self.reviewKey(author: r.author, text: r.text)
            return ReviewRow(
                id: index, author: r.author, avatar: r.authorPhoto, stars: Int(r.rating),
                age: r.relativeTime, text: r.text, photos: r.photos,
                translated: state.reviewsTranslated.contains(key))
        }
        card = state.selected.map { Self.makeCard($0, fuel: state.fuel) }
        if branchFixture == nil {
            let siblings = state.selected.map {
                PlaceBranches.shared.companions(
                    selected: $0, candidates: session?.search.state.value.results ?? [])
            } ?? []
            applyBranches(siblings)
        }
    }

    /// Copies the Kotlin siblings into rows and remembers the places behind them.
    private func applyBranches(_ places: [Place]) {
        branchPlaces = places
        branches = places.enumerated().map { index, place in
            BranchRow(
                id: index,
                stableId: place.id,
                name: place.name,
                category: place.category,
                address: place.address,
                rating: place.rating?.doubleValue,
                reviewCount: place.reviewCount.map { Int($0.int32Value) },
                openNow: place.openNow?.boolValue,
                statusText: place.statusText,
                permanentlyClosed: place.permanentlyClosed)
        }
    }

    private static func makeCard(_ p: Place, fuel: FuelPriceInfo?) -> PlaceCard {
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
            ownerDescription: p.ownerDescription,
            about: p.about.enumerated().map { index, section in
                AboutSectionRow(id: index, title: section.title, items: section.items)
            },
            updates: p.updates.enumerated().map { index, update in
                UpdateRow(
                    id: index,
                    text: update.text,
                    posted: update.postedEpochSec.flatMap { Self.postedLabel($0.int64Value) },
                    url: update.url,
                    linkLabel: update.linkLabel,
                    imageUrl: update.imageUrl)
            },
            similarPlaces: p.similarPlaces.enumerated().map { index, related in
                RelatedPlaceRow(
                    id: index,
                    name: related.name,
                    rating: related.rating?.doubleValue,
                    latitude: related.location.lat,
                    longitude: related.location.lng,
                    featureId: related.featureId)
            },
            departments: p.departments.enumerated().map { index, department in
                DepartmentRow(
                    id: index,
                    name: department.name,
                    hours: department.hours,
                    statusText: department.statusText,
                    openNow: department.openNow?.boolValue)
            },
            actionLabel: p.actionLabel,
            actionUrl: p.actionUrl,
            permanentlyClosed: p.permanentlyClosed,
            temporarilyClosed: p.temporarilyClosed,
            fuelPrice: p.fuelPrice,
            fuelPriceAt: p.fuelPriceAt?.int64Value,
            fuelBrand: fuel?.brand,
            fuelGrade: fuel?.grade,
            fuelNearby: fuel?.nearby.map {
                FuelNearbyRow(brand: $0.brand, pence: Int($0.pence), meters: $0.meters)
            },
            featuredReview: p.featuredReview,
            photos: p.photoUrls,
            photoDates: p.photoDates.map { $0 as? String },
            photoCategories: p.photoCategories.map { $0 as? String },
            streetViewThumbnail: Self.streetViewThumbnail(p),
            streetViewPanoId: p.svPanoId,
            streetViewYawDeg: p.svYawDeg?.doubleValue,
            busyDays: Self.busyDays(p.popularTimes),
            ratingHistogram: p.ratingHistogram?.map { Int($0.int32Value) },
            latitude: p.location.lat,
            longitude: p.location.lng,
            featureId: p.featureId,
            sourceId: p.id)
    }

    /// The key the Kotlin store uses for a review (`PlaceReviews.reviewKey`): author and body,
    /// separated by a NUL character.
    private static func reviewKey(author: String, text: String?) -> String {
        author.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{0}" + (text ?? "")
    }

    private static func postedLabel(_ epochSeconds: Int64) -> String? {
        guard epochSeconds > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        return relative.localizedString(for: date, relativeTo: Date())
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
