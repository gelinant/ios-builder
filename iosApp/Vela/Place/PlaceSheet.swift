import SwiftUI
import UIKit

// Dynamic catalog labels use their Android keys. Place names, addresses and reviews remain data.

/// The place sheet over the bottom of the map: what Android's `PlaceSheet` shows first (name,
/// rating, category, status and hours, the actions, address, phone, website, photos, popular
/// times, reviews). Its content is lazy, so the reviews start loading when their section comes on
/// screen, as on Android.
struct PlaceSheet: View {
    @ObservedObject var model: PlaceModel
    @ObservedObject var saved: SavedModel
    let card: PlaceCard
    let onClose: () -> Void
    let onDirections: () -> Void

    @State private var hoursOpen = false
    @State private var showsSaveSheet = false
    @State private var showsShareSheet = false
    @State private var showsPhotoGrid = false
    @State private var showsReviewsPanel = false
    @State private var gallery: GalleryRequest?

    private var headers: [String: String] { model.photoHeaders() }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
            HStack(alignment: .top) {
                Text(card.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .accessibilityIdentifier("place-name")
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("place-close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            #if DEBUG
            debugLine
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            #endif
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    summary
                    actions
                    featureActions
                    contact
                    streetView
                    photos
                    popularTimes
                    reviews
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .accessibilityIdentifier("place-scroll")
        }
        .frame(maxWidth: .infinity)
        // Opaque, like the results panel (a material made secondary text vanish on iOS 26).
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .sheet(isPresented: $showsSaveSheet) {
            SavePlaceSheet(model: saved)
        }
        .sheet(isPresented: $showsShareSheet) {
            ActivityView(items: [saved.shareSelectedUrl() ?? card.name])
        }
        .fullScreenCover(isPresented: $showsPhotoGrid) {
            PhotoGridView(model: model, onClose: { showsPhotoGrid = false })
        }
        .fullScreenCover(isPresented: $showsReviewsPanel) {
            ReviewsPanel(model: model, onClose: { showsReviewsPanel = false })
        }
        .fullScreenCover(item: $gallery) { request in
            PhotoViewer(request: request, headers: model.photoHeaders(), onClose: { gallery = nil })
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-sheet")
    }

    // MARK: Sections

    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let rating = card.rating {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", rating))
                    Stars(value: rating)
                    if let count = card.reviewCount {
                        Text("(\(count))")
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
                .font(.subheadline)
                .accessibilityIdentifier("place-rating")
            }
            let kind = [card.category, card.priceText].compactMap { $0 }.joined(separator: " · ")
            if !kind.isEmpty {
                Text(kind)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            if let status = card.statusText ?? card.openNow.map({ $0 ? "Open" : "Closed" }) {
                Button {
                    if card.hours.count > 1 { hoursOpen.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(status)
                            .foregroundStyle(statusColor)
                        if card.hours.count > 1 {
                            Image(systemName: hoursOpen ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("place-status")
            }
            if hoursOpen {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(card.hours.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.footnote)
                    }
                }
                .accessibilityIdentifier("place-hours")
            }
            if let summary = card.summary {
                Text(summary)
                    .font(.subheadline)
            }
            if model.loadingDetails {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Loading details")
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
        }
    }

    private var statusColor: Color {
        switch card.openNow {
        case true?: return Color(uiColor: .systemGreen)
        case false?: return Color(uiColor: .systemRed)
        default: return Color(uiColor: .label)
        }
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: onDirections) {
                    Label(VelaL10n.text("place_directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("place-directions")
                Button(action: saved.toggleSelected) {
                    Label(saved.selectedSaved ? "Saved" : "Save", systemImage: saved.selectedSaved ? "star.fill" : "star")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("place-save")
                Button {
                    showsSaveSheet = true
                } label: {
                    Label("Lists", systemImage: "bookmark")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("place-lists")
                Button {
                    showsShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("place-share")
                if let url = phoneURL {
                    Link(destination: url) {
                        Label(VelaL10n.text("place_call"), systemImage: "phone.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("place-call")
                }
                if let url = websiteURL {
                    Link(destination: url) {
                        Label(VelaL10n.text("place_website"), systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("place-website")
                }
            }
        }
    }

    @ViewBuilder private var featureActions: some View {
        if !card.photos.isEmpty || card.rating != nil || card.reviewCount != nil || !model.reviews.isEmpty {
            HStack(spacing: 8) {
                if !card.photos.isEmpty {
                    Button { showsPhotoGrid = true } label: {
                        Label("All photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("place-all-photos")
                }
                if card.rating != nil || card.reviewCount != nil || !model.reviews.isEmpty {
                    Button { showsReviewsPanel = true } label: {
                        Label("All reviews", systemImage: "text.bubble")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("place-all-reviews")
                }
            }
        }
    }

    @ViewBuilder private var contact: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let address = card.address {
                InfoRow(icon: "mappin.and.ellipse", text: address)
                    .accessibilityIdentifier("place-address")
            }
            if let phone = card.phone {
                if let url = phoneURL {
                    Link(destination: url) { InfoRow(icon: "phone", text: phone, tint: true) }
                        .accessibilityIdentifier("place-phone")
                } else {
                    InfoRow(icon: "phone", text: phone)
                }
            }
            if let website = card.website, let url = websiteURL {
                Link(destination: url) { InfoRow(icon: "globe", text: Self.shortHost(website), tint: true) }
                    .accessibilityIdentifier("place-site")
            }
        }
    }

    @ViewBuilder private var streetView: some View {
        if let url = card.streetViewThumbnail {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "Street View")
                RemoteImage(url: url, headers: headers)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityIdentifier("place-street-view")
        }
    }

    @ViewBuilder private var photos: some View {
        if !card.photos.isEmpty || model.photosLoading {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: card.photos.isEmpty ? "Photos" : "Photos (\(card.photos.count))")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(Array(card.photos.enumerated()), id: \.offset) { index, url in
                            Button {
                                openGallery(card.photos, index: index, captions: photoCaptions(card))
                            } label: {
                                RemoteImage(url: url, headers: headers)
                                    .frame(width: 132, height: 132)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .allowsHitTesting(false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("place-photo")
                        }
                        if model.photosLoading {
                            ProgressView()
                                .frame(width: 60, height: 132)
                        } else if model.canLoadMorePhotos || model.canWalkPhotos {
                            Button("More") { model.loadMorePhotos() }
                                .frame(width: 80, height: 132)
                                .accessibilityIdentifier("place-more-photos")
                        }
                    }
                }
                .frame(height: 132)
            }
            .accessibilityIdentifier("place-photos")
        }
    }

    @ViewBuilder private var popularTimes: some View {
        if !card.busyDays.isEmpty {
            PopularTimesView(days: card.busyDays)
                .accessibilityIdentifier("place-popular")
        } else if model.limitedView {
            Text("Google is showing a limited view right now, so popular times and more reviews may be missing here.")
                .font(.footnote)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .accessibilityIdentifier("place-limited-view")
        }
    }

    @ViewBuilder private var reviews: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Reviews")
                .accessibilityIdentifier("place-reviews-title")
            if model.reviewsLoading {
                HStack(spacing: 6) {
                    ProgressView()
                    Text(model.reviewsFound > 0 ? "Collecting reviews (\(model.reviewsFound))" : "Loading reviews")
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            ForEach(model.reviews) { review in
                reviewView(review)
                    .accessibilityIdentifier("place-review")
                Divider()
            }
            if !model.reviewsLoading && model.reviews.isEmpty {
                Text("No reviews to show")
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            if model.reviewsLimited {
                Text("Google is showing a limited view: only a few reviews for now.")
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            if model.canLoadMoreReviews || model.reviewsMoreLoading {
                Button(action: model.loadMoreReviews) {
                    if model.reviewsMoreLoading { ProgressView() } else { Text("More reviews") }
                }
                .disabled(model.reviewsMoreLoading)
                .accessibilityIdentifier("place-more-reviews")
            }
        }
        .onAppear { model.reviewsVisible() }
    }

    private func reviewView(_ review: ReviewRow) -> some View {
        ReviewView(
            review: review,
            headers: headers,
            onAvatar: { image in
            if let avatar = review.avatar { model.reportAvatar(avatar, image: image) }
            },
            onPhoto: { index in
                let caption = [review.author, review.age].compactMap { $0 }.joined(separator: " · ")
                let captions: [String?] = review.photos.map { _ in caption }
                openGallery(review.photos, index: index, captions: captions)
            })
    }

    #if DEBUG
    /// Read by PlaceUITests: what the sheet holds, without guessing it from a screenshot.
    private var debugLine: some View {
        Text(debugText)
            .font(.caption2.monospaced())
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .accessibilityIdentifier("place-debug")
    }

    private var debugText: String {
        let parts = [
            "photos=\(card.photos.count)",
            "reviews=\(model.reviews.count)",
            "from=\(model.reviewsFrom ?? "none")",
            "details=\(model.loadingDetails ? "loading" : "done")",
            "reviewsLoading=\(model.reviewsLoading ? 1 : 0)",
            "popular=\(card.busyToday.count)",
            "fallback=\(model.detailsFallback)",
            "walk=\(model.canWalkPhotos ? 1 : 0)",
            "moreReviews=\(model.canLoadMoreReviews ? 1 : 0)",
            "avatarLoaded=\(model.avatarsLoaded)",
            "avatarColor=\(model.avatarsNonBlack)",
            "hours=\(card.hours.count)",
            "phone=\(card.phone == nil ? 0 : 1)",
        ]
        return parts.joined(separator: " ")
    }
    #endif

    private func openGallery(_ urls: [String], index: Int, captions: [String?]) {
        guard !urls.isEmpty else { return }
        gallery = GalleryRequest(urls: urls, captions: captions, start: index)
    }

    private func photoCaptions(_ card: PlaceCard) -> [String?] {
        card.photos.indices.map { index in
            let date = index < card.photoDates.count ? card.photoDates[index] : nil
            let category = index < card.photoCategories.count ? card.photoCategories[index] : nil
            let parts = [category, date].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    // MARK: Links

    private var phoneURL: URL? {
        guard let phone = card.phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    private var websiteURL: URL? {
        guard let site = card.website, let url = URL(string: site), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    static func shortHost(_ site: String) -> String {
        guard let host = URL(string: site)?.host else { return site }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String
    var tint = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(tint ? Color.accentColor : Color(uiColor: .label))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}

/// Five stars filled to `value`, by halves.
private struct Stars: View {
    let value: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: Self.symbol(value - Double(i)))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityHidden(true)
    }

    private static func symbol(_ left: Double) -> String {
        if left >= 0.75 { return "star.fill" }
        if left >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct ReviewView: View {
    let review: ReviewRow
    let headers: [String: String]
    let onAvatar: (UIImage) -> Void
    let onPhoto: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let avatar = review.avatar {
                    RemoteAvatarImage(url: avatar, headers: headers, onImage: onAvatar)
                        .frame(width: 32, height: 32)
                        .accessibilityIdentifier("place-avatar")
                } else {
                    Text(review.author.prefix(1).uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .label))
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .systemGray5), in: Circle())
                }
                Text(review.author)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if review.stars > 0 {
                    Stars(value: Double(review.stars))
                }
                if let age = review.age {
                    Text(age)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            if let text = review.text {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !review.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(Array(review.photos.enumerated()), id: \.offset) { index, url in
                            Button { onPhoto(index) } label: {
                                RemoteImage(url: url, headers: headers)
                                    .frame(width: 104, height: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .allowsHitTesting(false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("place-review-photo")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
