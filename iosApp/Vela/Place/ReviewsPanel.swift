import SwiftUI
import UIKit

/// The full native reviews panel. Feed cursors and the hidden-page More reviews path append here;
/// sorting and search are local to the reviews Google has supplied, as on Android's inline tab.
struct ReviewsPanel: View {
    @ObservedObject var model: PlaceModel
    let onClose: () -> Void

    @State private var sort = 0
    @State private var query = ""
    @State private var viewer: GalleryRequest?

    private var shown: [ReviewRow] {
        let filtered = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? model.reviews
            : model.reviews.filter {
                $0.author.localizedCaseInsensitiveContains(query) || ($0.text?.localizedCaseInsensitiveContains(query) ?? false)
            }
        switch sort {
        case 1: return filtered.sorted { $0.stars > $1.stars }
        case 2: return filtered.sorted { $0.stars < $1.stars }
        default: return filtered
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    #if DEBUG
                    Text("count=\(model.reviews.count) more=\(model.canLoadMoreReviews ? 1 : 0) loading=\(model.reviewsMoreLoading ? 1 : 0) initialLoading=\(model.reviewsLoading ? 1 : 0) from=\(model.reviewsFrom ?? "none") avatarLoaded=\(model.avatarsLoaded) avatarColor=\(model.avatarsNonBlack)")
                        .font(.caption2.monospaced())
                        .accessibilityIdentifier("place-reviews-debug")
                    #endif
                    if model.reviewsLimited {
                        Text("Google is showing a limited view: only a few reviews for now.")
                            .font(.footnote)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    if model.reviewsLoading {
                        HStack {
                            ProgressView()
                            Text(model.reviewsFound > 0 ? "Collecting reviews (\(model.reviewsFound))" : "Loading reviews")
                        }
                    }
                    if model.reviews.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                sortButton(0, title: "Most relevant")
                                sortButton(1, title: "Highest rating")
                                sortButton(2, title: "Lowest rating")
                            }
                        }
                        TextField("Search loaded reviews", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("place-review-search")
                    }
                    ForEach(shown) { review in
                        reviewView(review)
                        Divider()
                    }
                    if shown.isEmpty && !model.reviewsLoading {
                        Text(model.reviews.isEmpty ? "No reviews to show" : "No loaded reviews match")
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    if model.canLoadMoreReviews || model.reviewsMoreLoading {
                        Button(action: model.loadMoreReviews) {
                            if model.reviewsMoreLoading {
                                ProgressView()
                            } else {
                                Text("More reviews")
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
            .navigationTitle("Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onClose)
                        .accessibilityIdentifier("place-reviews-close")
                }
            }
        }
        .fullScreenCover(item: $viewer) { request in
            PhotoViewer(request: request, headers: model.photoHeaders(), onClose: { viewer = nil })
        }
        .onAppear { model.reviewsVisible() }
        .onChange(of: model.card?.key ?? "") { _, _ in sort = 0; query = "" }
    }

    private func sortButton(_ value: Int, title: String) -> some View {
        Button(title) { sort = value }
            .buttonStyle(.bordered)
            .tint(sort == value ? .accentColor : .secondary)
            .accessibilityIdentifier("place-review-sort-\(value)")
    }

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
                viewer = GalleryRequest(urls: review.photos, captions: captions, start: index)
            })
        .accessibilityIdentifier("place-review")
    }
}
