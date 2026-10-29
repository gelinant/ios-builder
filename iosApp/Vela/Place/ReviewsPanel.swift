import SwiftUI
import UIKit

/// The full native reviews panel. The header carries Google's rating, review count and star
/// histogram, the bars Google itself draws. The chips sort and filter the reviews already loaded,
/// the hidden-page feed appends pages behind More reviews, and a review Google translated says so.
struct ReviewsPanel: View {
    @ObservedObject var model: PlaceModel
    let onClose: () -> Void

    @State private var sort = 0
    @State private var searchOpen = false
    @State private var query = ""
    @State private var viewer: GalleryRequest?

    private var card: PlaceCard? { model.card }

    private var shown: [ReviewRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = needle.isEmpty
            ? model.reviews
            : model.reviews.filter {
                $0.author.localizedCaseInsensitiveContains(needle) || ($0.text?.localizedCaseInsensitiveContains(needle) ?? false)
            }
        switch sort {
        case 1: return filtered.sorted { $0.stars > $1.stars }
        case 2: return filtered.sorted { $0.stars < $1.stars }
        default: return filtered
        }
    }

    /// Android offers the controls once the place has more than one review, or three loaded.
    private var sortable: Bool {
        (card?.reviewCount ?? 0) > 1 || model.reviews.count >= 3
    }

    private var histogram: [Int]? {
        guard let counts = card?.ratingHistogram, counts.count == 5, counts.reduce(0, +) > 0 else { return nil }
        return counts
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    #if DEBUG
                    Text(debugLine)
                        .font(.caption2.monospaced())
                        .dynamicTypeSize(.xSmall)
                        .lineLimit(1)
                        .accessibilityIdentifier("place-reviews-debug")
                    #endif
                    if model.reviewsLimited {
                        Text(VelaL10n.text("place_google_is_showing_a_limited_view"))
                            .font(.footnote)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    summary
                    if model.reviewsLoading {
                        HStack {
                            ProgressView()
                            Text(model.reviewsFound > 0 ? VelaL10n.text("place_collecting_reviews", String(describing: (model.reviewsFound))) : VelaL10n.text("place_loading_reviews"))
                        }
                    }
                    if sortable {
                        controls
                    }
                    if searchOpen {
                        TextField(VelaL10n.text("place_search_loaded_reviews"), text: $query)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("place-review-search")
                    }
                    ForEach(shown) { review in
                        reviewView(review)
                        if review.translated {
                            Text(VelaL10n.text("place_translated_by_google"))
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                .accessibilityIdentifier("place-review-translated")
                        }
                        Divider()
                    }
                    if shown.isEmpty && !model.reviewsLoading {
                        Text(model.reviews.isEmpty ? VelaL10n.text("place_no_reviews_to_show") : VelaL10n.text("place_no_loaded_reviews_match"))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .accessibilityIdentifier("place-reviews-empty")
                    }
                    if queryIsEmpty && (model.canLoadMoreReviews || model.reviewsMoreLoading) {
                        Button(action: model.loadMoreReviews) {
                            if model.reviewsMoreLoading {
                                ProgressView()
                            } else {
                                Text(VelaL10n.text("place_more_reviews"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.reviewsMoreLoading)
                        .accessibilityIdentifier("place-panel-more-reviews")
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("place-reviews-scroll")
            .navigationTitle(VelaL10n.text("google_usage_kind_reviews"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(VelaL10n.text("place_close"), action: onClose)
                        .accessibilityIdentifier("place-reviews-close")
                }
            }
        }
        .navigationDestination(item: $viewer) { request in
            PhotoViewer(request: request, headers: model.photoHeaders(), onClose: { viewer = nil })
                .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { model.reviewsVisible() }
        .onChange(of: model.card?.key ?? "") { _, _ in
            sort = 0
            searchOpen = false
            query = ""
        }
    }

    private var queryIsEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Header

    @ViewBuilder private var summary: some View {
        if let card, card.rating != nil || card.reviewCount != nil || histogram != nil {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    if let rating = card.rating {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 40, weight: .bold))
                    }
                    StarsRow(value: card.rating ?? 0)
                    if let count = card.reviewCount {
                        Text(VelaL10n.text("place_reviews", String(describing: (count))))
                            .font(.footnote)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
                .frame(minWidth: 92, alignment: .leading)
                if let histogram {
                    RatingHistogram(counts: histogram)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            .accessibilityIdentifier("place-reviews-summary")
        }
    }

    // MARK: Sort and search

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    searchOpen.toggle()
                    if !searchOpen { query = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .tint(searchOpen ? .accentColor : .secondary)
                .accessibilityLabel(VelaL10n.text("place_search_loaded_reviews"))
                .accessibilityIdentifier("place-review-search-toggle")
                Divider().frame(height: 24)
                sortButton(0, title: "Most relevant")
                sortButton(1, title: "Highest rating")
                sortButton(2, title: "Lowest rating")
            }
        }
    }

    private func sortButton(_ value: Int, title: String) -> some View {
        Button(title) { sort = value }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .tint(sort == value ? .accentColor : .secondary)
            .accessibilityAddTraits(sort == value ? .isSelected : [])
            .accessibilityIdentifier("place-review-sort-\(value)")
    }

    // MARK: One review

    private func reviewView(_ review: ReviewRow) -> some View {
        ReviewView(
            review: review,
            headers: model.photoHeaders(),
            onAvatar: { image in
                if let avatar = review.avatar { model.reportAvatar(avatar, image: image) }
            },
            onPhoto: { index in
                let caption = [review.author, review.age].compactMap { $0 }.joined(separator: " · ")
                let captions: [String?] = review.photos.map { _ in caption }
                viewer = GalleryRequest(
                    urls: review.photos, captions: captions, start: index,
                    source: "Photo from the review by \(review.author)")
            })
        .accessibilityIdentifier("place-review")
    }

    #if DEBUG
    private var debugLine: String {
        let translated = model.reviews.filter { $0.translated }.count
        return "count=\(model.reviews.count) more=\(model.canLoadMoreReviews ? 1 : 0) loading=\(model.reviewsMoreLoading ? 1 : 0) initialLoading=\(model.reviewsLoading ? 1 : 0) from=\(model.reviewsFrom ?? "none") avatarLoaded=\(model.avatarsLoaded) avatarColor=\(model.avatarsNonBlack) histogram=\(histogram?.count ?? 0) translated=\(translated) sort=\(sort) search=\(queryIsEmpty ? 0 : 1)"
    }
    #endif
}

/// The amber star bars of Google's own summary, counts ordered [5-star ... 1-star].
private struct RatingHistogram: View {
    let counts: [Int]

    private var peak: Int { Swift.max(counts.max() ?? 0, 1) }

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                let stars = 5 - index
                let count = index < counts.count ? counts[index] : 0
                HStack(spacing: 6) {
                    Text("\(stars)")
                        .font(.caption2)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: 12, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(uiColor: .secondaryLabel).opacity(0.22))
                            Capsule()
                                .fill(Color(red: 0.976, green: 0.671, blue: 0))
                                .frame(width: geometry.size.width * CGFloat(count) / CGFloat(peak))
                        }
                    }
                    .frame(height: 7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VelaL10n.text("place_stars_reviews", String(describing: (stars)), String(describing: (count))))
                .accessibilityIdentifier("place-histogram-row-\(stars)")
            }
        }
        .accessibilityIdentifier("place-histogram")
    }
}

/// The five star glyphs of a rating. It stays visual: the row's own label carries the number.
private struct StarsRow: View {
    let value: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(value - Double(index)))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityHidden(true)
    }

    private func symbol(_ left: Double) -> String {
        if left >= 0.75 { return "star.fill" }
        if left >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}
