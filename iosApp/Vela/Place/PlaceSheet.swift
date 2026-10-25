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
                    contact
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

    @ViewBuilder private var photos: some View {
        if !card.photos.isEmpty || model.photosLoading {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: card.photos.isEmpty ? "Photos" : "Photos (\(card.photos.count))")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(Array(card.photos.enumerated()), id: \.offset) { _, url in
                            RemoteImage(url: url, headers: headers)
                                .frame(width: 132, height: 132)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityIdentifier("place-photo")
                        }
                        if model.photosLoading {
                            ProgressView()
                                .frame(width: 60, height: 132)
                        } else if model.canLoadMorePhotos {
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
        if !card.busyToday.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "Popular times today")
                BusyChart(hours: card.busyToday)
                    .frame(height: 90)
            }
            .accessibilityIdentifier("place-popular")
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
                ReviewView(review: review, headers: headers)
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
            if model.canLoadMoreReviews {
                Button("More reviews") { model.loadMoreReviews() }
                    .accessibilityIdentifier("place-more-reviews")
            }
        }
        .onAppear { model.reviewsVisible() }
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
            "hours=\(card.hours.count)",
            "phone=\(card.phone == nil ? 0 : 1)",
        ]
        return parts.joined(separator: " ")
    }
    #endif

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

private struct ReviewView: View {
    let review: ReviewRow
    let headers: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let avatar = review.avatar {
                    RemoteImage(url: avatar, headers: headers)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    // The author's initial, as Android draws a review without a photo. The
                    // person symbol here drew as a black disc (I-3).
                    Text(review.author.prefix(1).uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .label))
                        .frame(width: 28, height: 28)
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
                    .lineLimit(8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today's popular times as bars, one per open hour, labeled every three hours.
private struct BusyChart: View {
    let hours: [BusyHour]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(hours) { h in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(height: max(2, CGFloat(h.occupancy) * 0.7))
                    Text(h.hour % 3 == 0 ? Self.label(h.hour) : " ")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private static func label(_ hour: Int) -> String {
        if AppGraph.uses24HourClock() { return String(hour) }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12)\(hour < 12 ? "a" : "p")"
    }
}
