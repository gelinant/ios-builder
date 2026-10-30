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
    @Environment(\.sheetDetent) private var sheetDetent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabUnderline

    /// The photo header belongs to the compact detent. Expanded and full keep only a title bar so
    /// the long content gets the height.
    private var headerCollapsed: Bool {
        sheetDetent == .expanded || sheetDetent == .full
    }

    private var headerShowsPhoto: Bool {
        !card.photos.isEmpty
    }

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
            placeHeader
            #if DEBUG
            debugLine
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Design.Padding.page)
            Text(shareDebugValue)
                .font(.caption2.monospaced())
                .lineLimit(2)
                .accessibilityLabel(shareDebugValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Design.Padding.page)
                .accessibilityIdentifier("place-share-debug")
            #endif
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.l) {
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
                .padding(.horizontal, Design.Padding.page)
                .padding(.top, needsUnifiedScroll ? Design.Spacing.m : Design.Spacing.xs)
                .padding(.bottom, Design.Padding.sheetBottom)
            }
            .accessibilityIdentifier("place-scroll")
        }
        .frame(maxWidth: .infinity)
        .animation(Design.Motion.animation(Design.Motion.sheetSpring, reduceMotion: reduceMotion),
                   value: headerCollapsed)
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

    // MARK: Header

    /// The photo header at the compact detent, the small title bar at expanded and full.
    @ViewBuilder private var placeHeader: some View {
        if headerCollapsed {
            compactHeader
        } else {
            photoHeader
        }
    }

    private var photoHeaderHeight: CGFloat {
        headerShowsPhoto ? Design.Size.photoHeader : 120
    }

    private var photoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo = card.photos.first {
                RemoteImage(url: photo, headers: headers)
                    .frame(maxWidth: .infinity)
                    .frame(height: photoHeaderHeight)
            } else {
                CategoryHeaderBackground(category: card.category)
                    .frame(height: photoHeaderHeight)
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.68)],
                startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text(card.name)
                    .font(Design.Typography.sheetTitle)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("place-name")
                ratingLine(.white)
            }
            .padding(.horizontal, Design.Padding.page)
            .padding(.bottom, Design.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: photoHeaderHeight)
        .clipped()
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.75))
                .frame(width: Design.Chrome.grabberWidth, height: Design.Chrome.grabberHeight)
                .padding(.top, Design.Padding.sheetTop)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            headerControls(onPhoto: true)
                .padding(.top, Design.Spacing.s)
                .padding(.trailing, Design.Padding.page)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-header")
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: Design.Spacing.s) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(card.name)
                    .font(Design.Typography.nav)
                    .foregroundStyle(Design.Colors.label)
                    .lineLimit(sizeCategory.isAccessibilityCategory ? 2 : 1)
                    .accessibilityIdentifier("place-name")
                ratingLine(Design.Colors.secondaryLabel)
            }
            Spacer(minLength: Design.Spacing.s)
            headerControls(onPhoto: false)
        }
        .padding(.horizontal, Design.Padding.page)
        .padding(.top, Design.Spacing.l)
        .padding(.bottom, Design.Spacing.s)
        .frame(minHeight: Design.Size.hitTarget)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: Design.Chrome.grabberWidth, height: Design.Chrome.grabberHeight)
                .padding(.top, Design.Padding.sheetTop)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-header")
    }

    @ViewBuilder private func ratingLine(_ foreground: Color) -> some View {
        if let rating = card.rating {
            HStack(spacing: Design.Spacing.s) {
                Text(String(format: "%.1f", rating))
                    .font(Design.Typography.rating)
                Stars(value: rating)
                if let count = card.reviewCount {
                    Text("(\(count))")
                        .font(Design.Typography.caption)
                        .foregroundStyle(foreground.opacity(0.85))
                }
            }
            .foregroundStyle(foreground)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("place-rating")
        } else if let count = card.reviewCount {
            Text(VelaL10n.text("place_reviews", String(describing: (count))))
                .font(Design.Typography.caption)
                .foregroundStyle(foreground.opacity(0.85))
                .accessibilityIdentifier("place-rating")
        }
    }

    private func headerControls(onPhoto: Bool) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            Button(action: saved.toggleSelected) {
                Image(systemName: saved.selectedSaved ? "star.fill" : "star")
                    .font(Design.Typography.button)
                    .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                    .background(
                        onPhoto ? Color.black.opacity(0.38) : Design.Colors.surfaceRaised,
                        in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(onPhoto ? Color.white : Design.Colors.label)
            .accessibilityLabel(saved.selectedSaved
                ? VelaL10n.text("place_saved") : VelaL10n.text("place_save"))
            .accessibilityIdentifier("place-header-save")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(Design.Typography.button)
                    .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                    .background(
                        onPhoto ? Color.black.opacity(0.38) : Design.Colors.surfaceRaised,
                        in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(onPhoto ? Color.white : Design.Colors.label)
            .accessibilityLabel(VelaL10n.text("place_close"))
            .accessibilityIdentifier("place-close")
        }
    }

    // MARK: Header sections

    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
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

    /// One primary action and secondary pills. The secondary row scrolls instead of sharing the
    /// width between every action, so seven buttons never become seven equal controls.
    @ViewBuilder private var actions: some View {
        if sizeCategory.isAccessibilityCategory {
            VStack(alignment: .leading, spacing: Design.Spacing.s) { actionButtons }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.s) { actionButtons }
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button(action: onDirections) {
            pillLabel(primary: true) {
                Label(VelaL10n.text("place_directions"),
                      systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-directions")
        Button(action: saved.toggleSelected) {
            pillLabel(primary: false) {
                Label(saved.selectedSaved ? VelaL10n.text("place_saved") : VelaL10n.text("place_save"),
                      systemImage: saved.selectedSaved ? "star.fill" : "star")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-save")
        Button {
            showsSaveSheet = true
        } label: {
            pillLabel(primary: false) {
                Label(VelaL10n.text("saved_lists"), systemImage: "bookmark")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-lists")
        Button {
            showsShareSheet = true
        } label: {
            pillLabel(primary: false) {
                Label(VelaL10n.text("settings_trip_share"), systemImage: "square.and.arrow.up")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-share")
        .accessibilityValue(shareDebugValue)
        if let url = phoneURL {
            Link(destination: url) {
                pillLabel(primary: false) {
                    Label(VelaL10n.text("place_call"), systemImage: "phone.fill")
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-call")
        }
        if let url = websiteURL {
            Link(destination: url) {
                pillLabel(primary: false) {
                    Label(VelaL10n.text("place_website"), systemImage: "globe")
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-website")
        }
        if let label = card.actionLabel, let url = actionURL {
            Link(destination: url) {
                pillLabel(primary: false) {
                    Label(label, systemImage: "arrow.up.right.square")
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-action-link")
        }
    }

    private func pillLabel<Content: View>(primary: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(Design.Typography.button)
            .foregroundStyle(primary ? Design.Colors.onAccent : Design.Colors.label)
            .padding(.horizontal, Design.Padding.buttonH)
            .frame(minHeight: Design.Size.hitTarget)
            .background(
                primary ? Design.Colors.accentFill : Design.Colors.surfaceRaised,
                in: Capsule())
            .overlay {
                if !primary {
                    Capsule().strokeBorder(Design.Colors.separator, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
    }

    @ViewBuilder private var featureActions: some View {
        if !card.photos.isEmpty || card.isListing || !model.reviews.isEmpty {
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
                pillLabel(primary: false) {
                    Label(VelaL10n.text("place_all_photos"), systemImage: "photo.on.rectangle")
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-all-photos")
        }
        if card.isListing || !model.reviews.isEmpty {
            Button { showsReviewsPanel = true } label: {
                pillLabel(primary: false) {
                    Label(VelaL10n.text("place_all_reviews_short"), systemImage: "text.bubble")
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-all-reviews")
        }
    }

    // MARK: Tabs

    /// Text tabs with a 3 pt underline that slides between them. The row scrolls and keeps the
    /// selected tab in view, which matters once Dynamic Type widens the labels.
    private var tabRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.xs) {
                    ForEach(tabs) { tab in
                        Button {
                            withAnimation(Design.Motion.animation(
                                Design.Motion.snap, reduceMotion: reduceMotion)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.label(menuName: card.menuCategoryName))
                                .font(Design.Typography.tab)
                                .foregroundStyle(shownTab == tab
                                    ? Design.Colors.accent : Design.Colors.secondaryLabel)
                                .padding(.horizontal, Design.Spacing.m)
                                .frame(minHeight: Design.Size.hitTarget)
                                .overlay(alignment: .bottom) {
                                    if shownTab == tab {
                                        Rectangle()
                                            .fill(Design.Colors.accent)
                                            .frame(height: 3)
                                            .matchedGeometryEffect(id: "place-tab-underline",
                                                                   in: tabUnderline)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(tab.rawValue)
                        .accessibilityAddTraits(shownTab == tab ? .isSelected : [])
                        .accessibilityIdentifier("place-tab-\(tab.rawValue)")
                    }
                }
            }
            .onAppear {
                proxy.scrollTo(shownTab.rawValue, anchor: .center)
            }
            .onChange(of: shownTab) { _, tab in
                withAnimation(Design.Motion.animation(
                    Design.Motion.move, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(tab.rawValue, anchor: .center)
                }
            }
            .onChange(of: sizeCategory) { _, _ in
                proxy.scrollTo(shownTab.rawValue, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
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
            "headerStyle=\(headerShowsPhoto ? "photo" : "category")",
            "tabsStyle=underlined",
            "headerCollapsed=\(headerCollapsed ? 1 : 0)",
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
        case .overview: return VelaL10n.text("place_tab_overview")
        case .reviews: return VelaL10n.text("place_tab_reviews")
        case .about: return VelaL10n.text("place_tab_about")
        case .photos: return VelaL10n.text("place_tab_photos")
        case .menu: return menuName ?? VelaL10n.text("place_tab_menu")
        case .updates: return VelaL10n.text("place_updates")
        }
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Design.Typography.section)
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

/// A colored header for a place Google returned no photo for. The hue comes from the category, so
/// the block reads as that kind of place and never as an empty band.
private struct CategoryHeaderBackground: View {
    let category: String?

    private var hue: Double {
        let sum = (category ?? "place").unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) % 3600
        }
        return Double(sum) / 3600
    }

    private var base: Color {
        Color(hue: hue, saturation: 0.48, brightness: 0.36)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [base, base.opacity(0.82)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: Self.icon(category))
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.22))
                .padding(.trailing, Design.Spacing.xxl)
                .accessibilityHidden(true)
        }
    }

    private static func icon(_ category: String?) -> String {
        let lower = (category ?? "").lowercased()
        let words: [(String, String)] = [
            ("restaurant", "fork.knife"), ("cafe", "cup.and.saucer.fill"),
            ("coffee", "cup.and.saucer.fill"), ("bar", "wineglass.fill"),
            ("bakery", "birthday.cake.fill"), ("hotel", "bed.double.fill"),
            ("museum", "building.columns.fill"), ("park", "leaf.fill"),
            ("store", "bag.fill"), ("shop", "bag.fill"), ("market", "cart.fill"),
            ("fuel", "fuelpump.fill"), ("hospital", "cross.case.fill"),
            ("school", "graduationcap.fill"),
        ]
        return words.first { lower.contains($0.0) }?.1 ?? "mappin.and.ellipse"
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
                    .foregroundStyle(Design.Colors.star)
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
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            HStack(spacing: Design.Spacing.s) {
                if let avatar = review.avatar {
                    RemoteAvatarImage(url: avatar, headers: headers, onImage: onAvatar)
                        .frame(width: Design.Size.avatar, height: Design.Size.avatar)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("place-avatar")
                } else {
                    Text(review.author.prefix(1).uppercased())
                        .font(Design.Typography.rowTitle)
                        .foregroundStyle(Design.Colors.label)
                        .frame(width: Design.Size.avatar, height: Design.Size.avatar)
                        .background(Design.Colors.surfaceSunken, in: Circle())
                        .accessibilityHidden(true)
                }
                Text(review.author)
                    .font(Design.Typography.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Design.Spacing.xs) {
                if review.stars > 0 {
                    Stars(value: Double(review.stars))
                }
                if let age = review.age {
                    Text(age)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                }
            }
            if let text = review.text {
                Text(text)
                    .font(Design.Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !review.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Design.Spacing.s) {
                        ForEach(Array(review.photos.enumerated()), id: \.offset) { index, url in
                            Button { onPhoto(index) } label: {
                                RemoteImage(url: url, headers: headers)
                                    .frame(width: Design.Size.reviewThumb,
                                           height: Design.Size.reviewThumb)
                                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.s))
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
