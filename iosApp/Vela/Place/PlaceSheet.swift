import SwiftUI
import UIKit

// Dynamic catalog labels use their Android keys. Place names, addresses and reviews remain data.

/// The place sheet over the bottom of the map: Google's own tabs (Overview, Reviews, About,
/// Photos, and Menu or Updates when Google supplies them). Overview keeps what Android shows
/// first (name, rating, status, hours, actions, contact, popular times and related places).
/// Sections only ever show data Google actually returned, with an explicit empty state otherwise.
struct PlaceSheet: View {
    @ObservedObject var model: PlaceModel
    @ObservedObject var saved: SavedModel
    let card: PlaceCard
    let onClose: () -> Void
    let onDirections: () -> Void
    let onOpenStreetView: (PlaceCard) -> Void

    @State private var hoursOpen = false
    @State private var selectedTab: PlaceTab = .overview
    @State private var showsSaveSheet = false
    @State private var showsShareSheet = false
    @State private var showsPhotoGrid = false
    @State private var showsReviewsPanel = false
    @State private var showsBranchList = false
    @State private var gallery: GalleryRequest?
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var headers: [String: String] { model.photoHeaders() }
    /// The place share: canonical Google link when Google is on, else the open link or the pin.
    private var sharePayload: VelaSharePayload {
        PlaceShare.payload(
            name: card.name, address: card.address, latitude: card.latitude,
            longitude: card.longitude, featureId: card.featureId, sourceId: card.sourceId)
    }

    /// DEBUG builds expose the payload on the share button: the activity sheet is a remote
    /// process, so the UI scenario reads what Vela handed it, then checks the sheet opened.
    private var shareDebugValue: String {
        #if DEBUG
        sharePayload.debugText
        #else
        ""
        #endif
    }
    private var needsUnifiedScroll: Bool {
        sizeCategory.isAccessibilityCategory || verticalSizeClass == .compact
    }

    private var menuIndices: [Int] { card.menuPhotoIndices }

    /// Tabs Android can show for this reply. About always exists so a place without attributes
    /// says so instead of hiding the section without explanation.
    private var tabs: [PlaceTab] {
        var out: [PlaceTab] = [.overview]
        if card.isListing || !model.reviews.isEmpty { out.append(.reviews) }
        out.append(.about)
        if card.isListing || !card.photos.isEmpty { out.append(.photos) }
        if !menuIndices.isEmpty { out.append(.menu) }
        if card.updates.count > 1 { out.append(.updates) }
        return out
    }

    private var shownTab: PlaceTab {
        tabs.contains(selectedTab) ? selectedTab : .overview
    }

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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(VelaL10n.text("place_close"))
                .accessibilityIdentifier("place-close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            #if DEBUG
            debugLine
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            Text(shareDebugValue)
                .font(.caption2.monospaced())
                .lineLimit(2)
                .accessibilityLabel(shareDebugValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("place-share-debug")
            #endif
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    actions
                    if card.fuelPrice != nil {
                        PlaceFuelSection(card: card)
                    }
                    if shownTab == .overview {
                        featureActions
                    }
                    tabRow
                    tabContent
                    if shownTab == .overview {
                        PlaceObscuraSection(card: card)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, needsUnifiedScroll ? 12 : 4)
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
            ActivityView(items: sharePayload.items, subject: sharePayload.subject)
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
        .onChange(of: card.key) { _, _ in
            selectedTab = .overview
            hoursOpen = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-sheet")
    }

    // MARK: Header sections

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
            if let status = statusLabel {
                Button {
                    if card.hours.count > 1 || !card.departments.isEmpty { hoursOpen.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(status)
                            .foregroundStyle(statusColor)
                        if card.hours.count > 1 || !card.departments.isEmpty {
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
            PlaceClosingLine(card: card)
            if !model.branches.isEmpty {
                PlaceBranchChip(
                    count: model.branches.count,
                    expanded: showsBranchList) {
                        showsBranchList.toggle()
                    }
                if showsBranchList {
                    PlaceBranchList(model: model)
                }
            }
            if hoursOpen {
                hoursExpanded
            }
            if model.loadingDetails {
                HStack(spacing: 6) {
                    ProgressView()
                    Text(VelaL10n.text("place_loading_details"))
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
        }
    }

    private var statusLabel: String? {
        if card.permanentlyClosed { return "Permanently closed" }
        if card.temporarilyClosed { return "Temporarily closed" }
        if let status = card.statusText { return status }
        return card.openNow.map { $0 ? "Open" : "Closed" }
    }

    private var statusColor: Color {
        if card.permanentlyClosed || card.temporarilyClosed { return Color(uiColor: .systemRed) }
        switch card.openNow {
        case true?: return Color(uiColor: .systemGreen)
        case false?: return Color(uiColor: .systemRed)
        default: return Color(uiColor: .label)
        }
    }

    /// The week's hours and every department schedule, all behind the status line as on Android.
    @ViewBuilder private var hoursExpanded: some View {
        VStack(alignment: .leading, spacing: 2) {
            if card.hours.isEmpty && card.departments.isEmpty {
                Text(VelaL10n.text("place_hours_not_listed"))
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityIdentifier("place-hours-empty")
            }
            ForEach(Array(card.hours.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
            }
            if !card.departments.isEmpty {
                ForEach(card.departments) { department in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(department.name)
                            .font(.footnote.weight(.semibold))
                            .padding(.top, 4)
                        if let status = department.statusText {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                        ForEach(Array(department.hours.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("place-hours")
    }

    @ViewBuilder private var actions: some View {
        if sizeCategory.isAccessibilityCategory {
            VStack(alignment: .leading, spacing: 8) { actionButtons }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { actionButtons }
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button(action: onDirections) {
            Label(VelaL10n.text("place_directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
        }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: 44)
        .accessibilityIdentifier("place-directions")
        Button(action: saved.toggleSelected) {
            Label(saved.selectedSaved ? VelaL10n.text("place_saved") : VelaL10n.text("place_save"), systemImage: saved.selectedSaved ? VelaL10n.text("saved_star_fill") : "star")
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .accessibilityIdentifier("place-save")
        Button {
            showsSaveSheet = true
        } label: {
            Label(VelaL10n.text("saved_lists"), systemImage: "bookmark")
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .accessibilityIdentifier("place-lists")
        Button {
            showsShareSheet = true
        } label: {
            Label(VelaL10n.text("settings_trip_share"), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .accessibilityIdentifier("place-share")
        .accessibilityValue(shareDebugValue)
        if let url = phoneURL {
            Link(destination: url) {
                Label(VelaL10n.text("place_call"), systemImage: "phone.fill")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("place-call")
        }
        if let url = websiteURL {
            Link(destination: url) {
                Label(VelaL10n.text("place_website"), systemImage: "globe")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("place-website")
        }
        if let label = card.actionLabel, let url = actionURL {
            Link(destination: url) {
                Label(label, systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .frame(minHeight: 44)
            .accessibilityIdentifier("place-action-link")
        }
    }

    @ViewBuilder private var featureActions: some View {
        if !card.photos.isEmpty || card.rating != nil || card.reviewCount != nil || !model.reviews.isEmpty {
            if sizeCategory.isAccessibilityCategory {
                VStack(alignment: .leading, spacing: 8) { featureButtons }
            } else {
                HStack(spacing: 8) { featureButtons }
            }
        }
    }

    @ViewBuilder private var featureButtons: some View {
        if !card.photos.isEmpty {
            Button { showsPhotoGrid = true } label: {
                Label(VelaL10n.text("place_all_photos"), systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("place-all-photos")
        }
        if card.rating != nil || card.reviewCount != nil || !model.reviews.isEmpty {
            Button { showsReviewsPanel = true } label: {
                Label(VelaL10n.text("place_all_reviews_short"), systemImage: "text.bubble")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("place-all-reviews")
        }
    }

    // MARK: Tabs

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.label(menuName: card.menuCategoryName))
                            .font(.subheadline.weight(shownTab == tab ? .semibold : .regular))
                            .foregroundStyle(shownTab == tab ? Color.accentColor : Color(uiColor: .secondaryLabel))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                shownTab == tab ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(shownTab == tab ? .isSelected : [])
                    .accessibilityIdentifier("place-tab-\(tab.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("place-tabs")
    }

    @ViewBuilder private var tabContent: some View {
        switch shownTab {
        case .overview: overview
        case .reviews: reviews
        case .about: about
        case .photos: photoGrid
        case .menu: menu
        case .updates: updates(card.updates)
        }
    }

    // MARK: Overview

    @ViewBuilder private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            contact
            streetView
            popularTimes
            reviewSummary
            relatedPlaces
            PlaceKnowledgeSection(place: card)
            if let newest = card.updates.first {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: "Updates")
                    updateView(newest)
                    if card.updates.count > 1 {
                        Button(VelaL10n.text("place_all_updates", String(describing: (card.updates.count)))) { selectedTab = .updates }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("place-all-updates")
                    }
                }
                .accessibilityIdentifier("place-update-preview")
            }
            if hasAbout {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: "About")
                    aboutView
                }
                .accessibilityIdentifier("place-about-preview")
            }
        }
    }

    private var hasAbout: Bool {
        !card.about.isEmpty || !isBlank(card.summary) || !isBlank(card.ownerDescription)
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
                Button {
                    onOpenStreetView(card)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        RemoteImage(url: url, headers: headers)
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Label(VelaL10n.text("place_look_around"), systemImage: "figure.walk")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(10)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel(VelaL10n.text("place_open_street_view"))
                .accessibilityHint(VelaL10n.text("place_opens_the_interactive_panorama_for_this"))
                .accessibilityIdentifier("place-street-view")
            }
        }
    }

    @ViewBuilder private var popularTimes: some View {
        if !card.busyDays.isEmpty {
            PopularTimesView(days: card.busyDays)
                .accessibilityIdentifier("place-popular")
        } else if model.limitedView {
            Text(VelaL10n.text("place_limited_view"))
                .font(.footnote)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .accessibilityIdentifier("place-limited-view")
        } else if card.isListing && model.detailsFallback != "none" && model.detailsFallback != "loading" {
            Text(VelaL10n.text("place_google_did_not_provide_popular_times"))
                .font(.footnote)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .accessibilityIdentifier("place-popular-empty")
        }
    }

    @ViewBuilder private var reviewSummary: some View {
        if card.isListing || !model.reviews.isEmpty {
            Button { selectedTab = .reviews } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(VelaL10n.text("google_usage_kind_reviews"))
                            .font(.headline)
                            .foregroundStyle(Color(uiColor: .label))
                        if let count = card.reviewCount {
                            Text(VelaL10n.text("place_reviews", String(describing: (count))))
                                .font(.footnote)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        } else if let featured = card.featuredReview {
                            Text(featured)
                                .font(.footnote)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityIdentifier("place-review-summary")
        }
    }

    @ViewBuilder private var relatedPlaces: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "People also search for")
            if card.similarPlaces.isEmpty {
                Text(VelaL10n.text("place_google_did_not_provide_related_places"))
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityIdentifier("place-related-empty")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(card.similarPlaces) { related in
                            Button { model.openRelated(related) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(related.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color(uiColor: .label))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if let rating = related.rating {
                                        Text(String(format: "%.1f★", rating))
                                            .font(.caption)
                                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                                    }
                                }
                                .frame(width: 140, alignment: .leading)
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("place-related")
                        }
                    }
                }
            }
        }
        // Without containment the section identifier hides the empty state and the row it wraps.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-related-section")
    }

    // MARK: Reviews

    @ViewBuilder private var reviews: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Reviews")
                    .accessibilityIdentifier("place-reviews-title")
                Spacer()
                if card.rating != nil || card.reviewCount != nil {
                    Button(VelaL10n.text("place_all_reviews_short")) { showsReviewsPanel = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("place-all-reviews")
                }
            }
            if model.reviewsLoading {
                HStack(spacing: 6) {
                    ProgressView()
                    Text(model.reviewsFound > 0 ? VelaL10n.text("place_collecting_reviews", String(describing: (model.reviewsFound))) : VelaL10n.text("place_loading_reviews"))
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
                Text(VelaL10n.text("place_no_reviews_to_show"))
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityIdentifier("place-reviews-empty")
            }
            if model.reviewsLimited {
                Text(VelaL10n.text("place_google_is_showing_a_limited_view"))
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            if model.canLoadMoreReviews || model.reviewsMoreLoading {
                Button(action: model.loadMoreReviews) {
                    if model.reviewsMoreLoading { ProgressView() } else { Text(VelaL10n.text("place_more_reviews")) }
                }
                .disabled(model.reviewsMoreLoading)
                .frame(minHeight: 44)
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

    // MARK: About

    @ViewBuilder private var about: some View {
        if hasAbout {
            aboutView
        } else {
            Text(VelaL10n.text("place_google_did_not_provide_a_description"))
                .font(.footnote)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .accessibilityIdentifier("place-about-empty")
        }
    }

    @ViewBuilder private var aboutView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = card.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
            }
            if let owner = card.ownerDescription, !owner.isEmpty {
                Text(VelaL10n.text("place_from_the_owner"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.top, 6)
                Text(owner)
                    .font(.subheadline)
            }
            ForEach(card.about) { section in
                Text(section.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.top, 6)
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                        Text(item)
                            .font(.subheadline)
                    }
                }
            }
        }
        .accessibilityIdentifier("place-about")
    }

    // MARK: Photos and menu

    @ViewBuilder private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "Photos")
                Spacer()
                if !card.photos.isEmpty {
                    Button(VelaL10n.text("place_full_screen")) { showsPhotoGrid = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("place-open-gallery")
                }
            }
            if card.photos.isEmpty {
                if model.photosLoading {
                    ProgressView()
                } else {
                    Text(VelaL10n.text("place_google_did_not_provide_photos_for"))
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityIdentifier("place-photos-empty")
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(Array(card.photos.enumerated()), id: \.offset) { index, url in
                        Button {
                            openGallery(card.photos, index: index, captions: photoCaptions(card))
                        } label: {
                            RemoteImage(url: url, headers: headers)
                                .frame(maxWidth: .infinity)
                                .frame(height: 104)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(VelaL10n.text("place_place_photo_of", String(describing: (index + 1)), String(describing: (card.photos.count))))
                        .accessibilityHint(VelaL10n.text("place_opens_the_photo_viewer"))
                        .accessibilityIdentifier("place-photo")
                    }
                }
                if model.photosLoading {
                    ProgressView()
                } else if model.canLoadMorePhotos {
                    Button(VelaL10n.text("place_more_photos")) { model.loadMorePhotos() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("place-more-photos")
                } else if model.canWalkPhotos {
                    Button(VelaL10n.text("place_load_categories")) { model.loadPhotoCategories() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("place-photo-categories")
                }
            }
        }
        .accessibilityIdentifier("place-photos")
    }

    @ViewBuilder private var menu: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: card.menuCategoryName ?? "Menu")
            if menuIndices.isEmpty {
                Text(VelaL10n.text("place_google_did_not_provide_menu_photos"))
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityIdentifier("place-menu-empty")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                    ForEach(menuIndices, id: \.self) { index in
                        Button {
                            openGallery(card.photos, index: index, captions: photoCaptions(card))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                RemoteImage(url: card.photos[index], headers: headers)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 150)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                if index < card.photoDates.count, let date = card.photoDates[index] {
                                    Text(date)
                                        .font(.caption2)
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(VelaL10n.text("place_menu_photo_of", String(describing: (index + 1)), String(describing: (card.photos.count))))
                        .accessibilityHint(VelaL10n.text("place_opens_the_photo_viewer"))
                        .accessibilityIdentifier("place-menu-photo")
                    }
                }
            }
        }
        .accessibilityIdentifier("place-menu")
    }

    // MARK: Updates

    @ViewBuilder private func updates(_ updates: [UpdateRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Updates")
            if updates.isEmpty {
                Text(VelaL10n.text("place_google_did_not_provide_updates_from"))
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityIdentifier("place-updates-empty")
            } else {
                ForEach(updates) { update in
                    updateView(update)
                    Divider()
                }
            }
        }
        .accessibilityIdentifier("place-updates")
    }

    private func updateView(_ update: UpdateRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let posted = update.posted {
                    Text(posted)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Text(update.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = update.url, let link = URL(string: url) {
                    Link(update.linkLabel ?? VelaL10n.text("place_open"), destination: link)
                        .font(.footnote)
                        .frame(minHeight: 44)
                }
            }
            if let image = update.imageUrl {
                RemoteImage(url: image, headers: headers)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-update")
    }

    #if DEBUG
    /// Read by PlaceUITests: what the sheet holds, without guessing it from a screenshot.
    private var debugLine: some View {
        Text(debugText)
            .font(.caption2.monospaced())
            .dynamicTypeSize(.xSmall)
            .lineLimit(1)
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
            "tabs=\(tabs.count)",
            "about=\(card.about.count)",
            "aboutText=\(hasAbout ? 1 : 0)",
            "related=\(card.similarPlaces.count)",
            "updates=\(card.updates.count)",
            "menu=\(menuIndices.count)",
            "departments=\(card.departments.count)",
            "closed=\(card.permanentlyClosed || card.temporarilyClosed ? 1 : 0)",
            "poi_match=\(model.poiMatch)",
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

    private func isBlank(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    // MARK: Links

    private var phoneURL: URL? {
        guard let phone = card.phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    private var websiteURL: URL? {
        guard !ContentSettingsKeys.hideExternalLinksValue else { return nil }
        guard let site = card.website, let url = URL(string: site), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    private var actionURL: URL? {
        guard let action = card.actionUrl, let url = URL(string: action),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    static func shortHost(_ site: String) -> String {
        guard let host = URL(string: site)?.host else { return site }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// The tabs of Google's place page, in the order the sheet shows them.
private enum PlaceTab: String, Identifiable, CaseIterable {
    case overview
    case reviews
    case about
    case photos
    case menu
    case updates

    var id: String { rawValue }

    func label(menuName: String?) -> String {
        switch self {
        case .overview: return "Overview"
        case .reviews: return "Reviews"
        case .about: return "About"
        case .photos: return "Photos"
        case .menu: return menuName ?? "Menu"
        case .updates: return "Updates"
        }
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
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("place-avatar")
                } else {
                    Text(review.author.prefix(1).uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .label))
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .systemGray5), in: Circle())
                        .accessibilityHidden(true)
                }
                Text(review.author)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
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
                            .accessibilityLabel(
                                VelaL10n.text("place_photo_of_from_the_review_by", String(describing: (index + 1)), String(describing: (review.photos.count)), String(describing: (review.author))))
                            .accessibilityHint(VelaL10n.text("place_opens_the_photo_viewer"))
                            .accessibilityIdentifier("place-review-photo")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
