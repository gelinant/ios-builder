import SwiftUI

/// The search field over the map. Return submits.
struct SearchBar: View {
    @Binding var text: String
    let searching: Bool
    /// The committed field text. A command is read from exactly this string, before any search.
    let onSubmit: (String) -> Void
    let onClear: () -> Void
    let onOffline: () -> Void
    let onFocusChange: (Bool) -> Void
    /// Incremented when a suggestion, category or map feature takes over from the keyboard.
    let blurTick: Int
    let onSettings: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var model: SearchModel? { SearchActions.model }

    var body: some View {
        HStack(spacing: Design.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Design.Size.icon))
                .foregroundStyle(Design.Colors.secondaryLabel)
            TextField(VelaL10n.text("search_placeholder"), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit {
                    focused = false
                    // The field commits its last characters to the binding around the return key.
                    // Reading the text on the next main-queue turn means the command parser sees
                    // the whole phrase, never a prefix, and it still runs before any search.
                    DispatchQueue.main.async { onSubmit(text) }
                }
                .frame(maxWidth: .infinity, minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("search-field")
            if searching {
                ProgressView()
            }
            if !text.isEmpty {
                Button {
                    focused = false
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(VelaL10n.text("search_clear_cd"))
                .accessibilityIdentifier("search-clear")
            }
            Menu {
                Button(VelaL10n.text("settings_offline"), action: onOffline)
                    .accessibilityIdentifier("offline-menu-item")
                Button(VelaL10n.text("search_settings_cd"), action: onSettings)
                    .accessibilityIdentifier("settings-menu-item")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(VelaL10n.text("exp_chooser_more"))
            .accessibilityIdentifier("map-overflow")
        }
        .padding(.horizontal, Design.Padding.page)
        .frame(minHeight: Design.Chrome.searchHeight)
        .background {
            if reduceTransparency {
                Capsule().fill(Design.Colors.surface)
                Capsule().strokeBorder(Design.Colors.separator, lineWidth: 1)
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .shadow(color: Design.Elevation.level2.color, radius: Design.Elevation.level2.radius,
                y: Design.Elevation.level2.y)
        .onChange(of: focused) { _, value in
            SearchActions.homeFocusChanged(value)
            onFocusChange(value)
        }
        .onChange(of: blurTick) { _, _ in focused = false }
        // A unified row takes over the screen (its sheet, board or pin): drop focus and keyboard.
        .onChange(of: model?.unifiedBlurTick) { _, _ in focused = false }
        // The bar stays mounted while the panel does not, so a saved list, a Settings row or an
        // article opened from the field survives the rows being dismissed.
        .sheet(item: destinationBinding) { destination in
            switch destination {
            case .list(let id, let name):
                UnifiedListSheet(listId: id, name: name) { closeDestination() }
            case .settings(let anchor, let label, let section):
                UnifiedSettingsSheet(anchor: anchor, label: label, section: section) { closeDestination() }
            case .wiki(let row):
                UnifiedWikiSheet(row: row) { closeDestination() }
            }
        }
    }

    private var destinationBinding: Binding<UnifiedDestination?> {
        Binding(
            get: { SearchActions.model?.unifiedDestination },
            set: { SearchActions.model?.unifiedDestination = $0 })
    }

    private func closeDestination() {
        SearchActions.model?.unifiedDestination = nil
    }
}

/// The search home: what the sheet shows when the field is empty and focused. The quick category
/// chips, then Recent, Saved and Nearby transit. A section with no row says so in one calm line.
/// Typing replaces the whole sheet with the live results; clearing the field brings it back.
struct RecentsPanel: View {
    let rows: [RecentItem]
    let onPick: (RecentItem) -> Void
    let onRemove: (RecentItem) -> Void
    let onClear: () -> Void

    private var model: SearchModel? { SearchActions.model }
    private var homeSaved: [HomeSavedRow] { model?.homeSaved ?? [] }
    private var homeTransit: [HomeTransitRow] { model?.homeTransit ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            if model?.homeFocused == true {
                QuickCategoriesView(onPick: { SearchActions.homeCategory($0.query) })
                    .padding(.vertical, Design.Spacing.s)
                Divider()
            }
            ScrollView {
                VStack(spacing: 0) {
                    recentSection
                    Divider()
                    savedSection
                    Divider()
                    transitSection
                }
            }
            .frame(maxHeight: 420)
        }
        .background(Design.Colors.surface)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: Design.Sheet.cornerRadius,
            topTrailingRadius: Design.Sheet.cornerRadius))
        .shadow(color: Design.Elevation.level3.color, radius: Design.Elevation.level3.radius,
                y: -Design.Elevation.level3.y)
        // Without containment the sections swallow the rows the scenarios tap.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-home")
    }

    private var recentSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: Design.Spacing.s) {
                sectionTitle(VelaL10n.text("mapscreen_section_recent"), kind: "recent")
                Spacer()
                if !rows.isEmpty {
                    Button(VelaL10n.text("settings_clear_history_action"), action: onClear)
                        .font(Design.Typography.detail)
                        .frame(minHeight: Design.Size.hitTarget)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("search-recents-clear")
                }
            }
            .padding(.horizontal, Design.Padding.page)
            .padding(.top, Design.Spacing.m)
            if rows.isEmpty {
                emptyLine(VelaL10n.text("search_home_no_recents"), id: "home-empty-recent")
            } else {
                ForEach(rows) { row in
                    recentRow(row)
                    Divider().padding(.leading, Design.Padding.page)
                }
            }
        }
    }

    private var savedSection: some View {
        VStack(spacing: 0) {
            sectionTitle(VelaL10n.text("mapscreen_section_saved"), kind: "saved")
                .padding(.horizontal, Design.Padding.page)
                .padding(.top, Design.Spacing.m)
            if homeSaved.isEmpty {
                emptyLine(VelaL10n.text("settings_no_saved_places"), id: "home-empty-saved")
            } else {
                ForEach(homeSaved) { row in
                    savedRow(row)
                    Divider().padding(.leading, Design.Padding.page)
                }
            }
        }
    }

    private var transitSection: some View {
        VStack(spacing: 0) {
            sectionTitle(VelaL10n.text("search_home_nearby_transit"), kind: "transit")
                .padding(.horizontal, Design.Padding.page)
                .padding(.top, Design.Spacing.m)
            if homeTransit.isEmpty {
                emptyLine(VelaL10n.text("search_home_no_stops"), id: "home-empty-transit")
            } else {
                ForEach(homeTransit) { row in
                    transitRow(row)
                    Divider().padding(.leading, Design.Padding.page)
                }
            }
        }
        .padding(.bottom, Design.Spacing.m)
    }

    /// The header carries a stable identifier and the section name as its value, so a scenario
    /// counts the three sections without reading a translated title.
    private func sectionTitle(_ title: String, kind: String) -> some View {
        Text(title)
            .font(Design.Typography.section)
            .foregroundStyle(Design.Colors.label)
            .accessibilityIdentifier("home-section")
            .accessibilityValue(kind)
    }

    private func emptyLine(_ text: String, id: String) -> some View {
        Text(text)
            .font(Design.Typography.detail)
            .foregroundStyle(Design.Colors.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Padding.page)
            .padding(.vertical, Design.Spacing.m)
            .accessibilityIdentifier(id)
    }

    private func recentRow(_ row: RecentItem) -> some View {
        HStack(spacing: 0) {
            Button { onPick(row) } label: {
                HStack(spacing: Design.Spacing.m) {
                    Image(systemName: row.kind == "search" ? "magnifyingglass" : "clock")
                        .font(.system(size: Design.Size.icon))
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .frame(width: Design.Size.icon, alignment: .center)
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text(row.title)
                            .font(Design.Typography.rowTitle)
                            .foregroundStyle(Design.Colors.label)
                            .lineLimit(1)
                        if let subtitle = row.subtitle {
                            Text(subtitle)
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.secondaryLabel)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, Design.Padding.page)
                .frame(minHeight: Design.Size.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search-recent")
            .accessibilityLabel(row.title)
            Button { onRemove(row) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VelaL10n.text("search_remove_recent"))
            .padding(.trailing, Design.Spacing.xs)
        }
    }

    private func savedRow(_ row: HomeSavedRow) -> some View {
        Button { SearchActions.pickHomeSaved(row) } label: {
            HStack(spacing: Design.Spacing.m) {
                Image(systemName: row.kind == .list ? "list.bullet" : "bookmark.fill")
                    .font(.system(size: Design.Size.icon))
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .frame(width: Design.Size.icon, alignment: .center)
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    Text(row.title)
                        .font(Design.Typography.rowTitle)
                        .foregroundStyle(Design.Colors.label)
                        .lineLimit(1)
                    if let subtitle = row.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryLabel)
            }
            .padding(.horizontal, Design.Padding.page)
            .frame(minHeight: Design.Size.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(row.kind == .list ? "home-saved-list" : "home-saved-place")
        .accessibilityLabel(row.title)
    }

    private func transitRow(_ row: HomeTransitRow) -> some View {
        Button { SearchActions.pickHomeTransit(row) } label: {
            HStack(spacing: Design.Spacing.m) {
                Image(systemName: "tram.fill")
                    .font(.system(size: Design.Size.icon))
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .frame(width: Design.Size.icon, alignment: .center)
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    Text(row.name)
                        .font(Design.Typography.rowTitle)
                        .foregroundStyle(Design.Colors.label)
                        .lineLimit(1)
                    Text(SearchRow.distance(row.distanceMeters))
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryLabel)
            }
            .padding(.horizontal, Design.Padding.page)
            .frame(minHeight: Design.Size.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-transit-stop")
        .accessibilityLabel(row.name)
    }
}

/// Android's "Search this area" pill, offered once the map has been panned past its threshold.
/// `ResultsPanel` mounts it above the list today, so `MapScreen.swift` needs no change; the map
/// chrome can mount the same view instead when that file is free to edit, keeping the model.
struct SearchAreaButton: View {
    let available: Bool

    var body: some View {
        if available {
            Button {
                SearchActions.searchArea()
            } label: {
                Label(VelaL10n.text("mapscreen_search_this_area"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search-area")
        }
    }
}

/// The results list at the bottom of the map. Its header folds it to leave the map in view.
struct ResultsPanel: View {
    let rows: [SearchRow]
    let message: String?
    let searching: Bool
    /// The host's detent. Compact keeps the map visible, expanded shows the full list; both show
    /// the same rows in the same order (DESIGN.md 3.7).
    @Binding var detent: SheetDetent
    /// The measured surface height, so the map's bottom inset follows the real sheet.
    var onHeightChange: ((CGFloat) -> Void)?
    let onPick: (SearchRow) -> Void

    private var detents: [SheetDetent] { [.compact, .expanded] }

    /// The model carries the pagination, photo identity and filters: MapScreen's call site stays
    /// as it is (BACKLOG section 3 serializes that file), so the panel reads the live model.
    private var model: SearchModel? { SearchActions.model }
    private var headers: [String: String] { model?.photoHeaders() ?? [:] }
    @State private var showFilters = false

    var body: some View {
        SheetSurface(detent: $detent, detents: detents, elevation: .level2,
                     onHeightChange: onHeightChange) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        toggleDetent()
                    } label: {
                        HStack {
                            Text(title)
                                .font(Design.Typography.nav)
                            Spacer()
                            Image(systemName: detent == .expanded ? "chevron.down" : "chevron.up")
                                .foregroundStyle(Design.Colors.secondaryLabel)
                        }
                        .frame(minHeight: Design.Size.hitTarget)
                        .padding(.horizontal, Design.Padding.page)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(detent == .expanded
                        ? VelaL10n.text("settings_collapse") : VelaL10n.text("mapscreen_expand_list"))
                    .accessibilityValue(title)
                    .accessibilityIdentifier("search-panel-toggle")
                    if !rows.isEmpty {
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: Design.Size.icon))
                                .foregroundStyle(filterSummary == nil
                                    ? Design.Colors.secondaryLabel : Design.Colors.accent)
                                .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(VelaL10n.text("search_filters"))
                        .accessibilityIdentifier("search-filters-open")
                        .padding(.trailing, Design.Spacing.xs)
                    }
                }
                .frame(minHeight: 56)
                // Android's floating button above the results, shown only once the map has been
                // panned past its threshold. It stays visible at both detents so the refreshed
                // list is one tap away and the map stays readable.
                if model?.searchAreaAvailable == true {
                    Divider()
                    SearchAreaButton(available: true)
                }
                if let summary = filterSummary {
                    Divider()
                    Text(summary)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Design.Padding.page)
                        .padding(.vertical, Design.Spacing.xs)
                        .accessibilityIdentifier("search-filter-summary")
                }
                if let message {
                    Divider()
                    Text(message)
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.Padding.page)
                        .accessibilityIdentifier("search-message")
                }
                if !rows.isEmpty {
                    Divider()
                    ScrollView {
                        // Not lazy: every row stays in the accessibility tree, so the result
                        // scenarios can count and inspect rows that are below the fold.
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                ResultRow(row: row, headers: headers, onPick: { onPick(row) })
                                Divider()
                                    .padding(.leading, Design.Padding.page)
                            }
                            if model?.moreAvailable == true {
                                if model?.loadingMore == true {
                                    ProgressView()
                                        .padding(.vertical, Design.Spacing.m)
                                        .accessibilityIdentifier("search-more-loading")
                                } else {
                                    Button(VelaL10n.text("mapscreen_more_results")) { SearchActions.loadMore() }
                                        .font(Design.Typography.button)
                                        .frame(maxWidth: .infinity, minHeight: Design.Size.hitTarget)
                                        .contentShape(Rectangle())
                                        .accessibilityIdentifier("search-more")
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("search-results-scroll")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            if let model {
                SearchFilterSheet(model: model)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func toggleDetent() {
        withAnimation(Design.Motion.sheetSpring) {
            detent = detent == .expanded ? .compact : .expanded
        }
    }

    private var title: String {
        if searching { return VelaL10n.text("route_searching") }
        if rows.isEmpty { return VelaL10n.text("settings_search") }
        return VelaL10n.text("mapscreen_results_count", Int(rows.count))
    }

    /// The active filters and sort, so the header says why the list is short.
    private var filterSummary: String? {
        guard let filters = model?.filters else { return nil }
        var parts: [String] = []
        if filters.openNow { parts.append(VelaL10n.text("mapscreen_filter_open_now")) }
        if filters.minRating > 0 { parts.append(String(format: "%.1f+ ★", filters.minRating)) }
        if filters.priceMax > 0 { parts.append(String(repeating: "$", count: filters.priceMax)) }
        if filters.accessibleOnly { parts.append(VelaL10n.text("mapscreen_filter_accessible")) }
        switch filters.sort {
        case .rating: parts.append(VelaL10n.text("mapscreen_sort_rating"))
        case .distance: parts.append(VelaL10n.text("mapscreen_sort_distance"))
        case .relevance: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Android's results-header controls, gathered in one sheet: sort, Open now, rating floor, price
/// ceiling and wheelchair accessibility. Controls the source cannot honour are absent, with a line
/// that says why rather than a list emptied by filters that mean nothing to Photon.
struct SearchFilterSheet: View {
    @ObservedObject var model: SearchModel
    @Environment(\.dismiss) private var dismiss

    private var support: SearchFilterSupportView { model.filterSupport }

    var body: some View {
        NavigationStack {
            Form {
                if support.openNow {
                    Section {
                        Toggle(isOn: Binding(get: { model.filters.openNow },
                                             set: { model.setOpenNow($0) })) {
                            Text(VelaL10n.text("mapscreen_filter_open_now"))
                        }
                        .accessibilityIdentifier("search-filter-open-now")
                    }
                }
                Section(header: Text(VelaL10n.text("mapscreen_sort"))) {
                    Picker(selection: Binding(get: { model.filters.sort.rawValue },
                                              set: { model.setSort(SearchSortChoice(rawValue: $0) ?? .relevance) })) {
                        ForEach(sortChoices) { choice in
                            Text(title(choice)).tag(choice.rawValue)
                        }
                    } label: {
                        Text(VelaL10n.text("mapscreen_sort"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("search-filter-sort")
                }
                if support.minRating {
                    Section(header: Text(VelaL10n.text("mapscreen_filter_rating"))) {
                        HStack(spacing: 8) {
                            ratingButton(VelaL10n.text("mapscreen_filter_any_rating"), value: 0, id: "any")
                            ratingButton("3.5+ ★", value: 3.5, id: "35")
                            ratingButton("4.0+ ★", value: 4.0, id: "40")
                            ratingButton("4.5+ ★", value: 4.5, id: "45")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if support.price {
                    Section(header: Text(VelaL10n.text("mapscreen_filter_price"))) {
                        HStack(spacing: 8) {
                            priceButton(VelaL10n.text("mapscreen_filter_any_price"), value: 0, id: "any")
                            ForEach(1...4, id: \.self) { level in
                                priceButton(String(repeating: "$", count: level), value: level, id: "\(level)")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if support.accessible {
                    Section {
                        Toggle(isOn: Binding(get: { model.filters.accessibleOnly },
                                             set: { model.setAccessibleOnly($0) })) {
                            Text(VelaL10n.text("mapscreen_filter_accessible"))
                        }
                        .accessibilityIdentifier("search-filter-accessible")
                    }
                }
                if !support.anyFilter || !support.sortRating || !support.sortDistance {
                    Section {
                        Text(VelaL10n.text("search_without_google_search_uses_photon_and")
                             + VelaL10n.text("search_carry_ratings_price_levels_live_opening")
                             + VelaL10n.text("search_so_those_filters_are_hidden_rather")
                             + VelaL10n.text("search_relevance_or_distance_still_works"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("search-filter-note")
                    }
                }
            }
            .navigationTitle(VelaL10n.text("search_filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .accessibilityIdentifier("search-filters-done")
                }
            }
            .accessibilityIdentifier("search-filter-sheet")
        }
    }

    private var sortChoices: [SearchSortChoice] {
        var out: [SearchSortChoice] = [.relevance]
        if support.sortRating { out.append(.rating) }
        if support.sortDistance { out.append(.distance) }
        return out
    }

    private func title(_ choice: SearchSortChoice) -> String {
        switch choice {
        case .relevance: return VelaL10n.text("mapscreen_sort_relevance")
        case .rating: return VelaL10n.text("mapscreen_sort_rating_item")
        case .distance: return VelaL10n.text("mapscreen_sort_distance_item")
        }
    }

    private func ratingButton(_ title: String, value: Double, id: String) -> some View {
        Button(title) { model.setMinRating(value) }
            .tint(model.filters.minRating == value ? Color.accentColor : Color(uiColor: .secondaryLabel))
            .accessibilityIdentifier("search-filter-rating-\(id)")
    }

    private func priceButton(_ title: String, value: Int, id: String) -> some View {
        Button(title) { model.setPriceMax(value) }
            .tint(model.filters.priceMax == value ? Color.accentColor : Color(uiColor: .secondaryLabel))
            .accessibilityIdentifier("search-filter-price-\(id)")
    }
}

/// Android's result card: photo, name, rating and count, price and kind, open status, address,
/// then the quick actions the Google data supports. Tapping the text or the photo opens the place.
struct ResultRow: View {
    let row: SearchRow
    let headers: [String: String]
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let photo = row.photoURL {
                    RemoteImage(url: photo, headers: headers)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture(perform: onPick)
                        .accessibilityElement()
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(VelaL10n.text("search_photo_of", String(describing: (row.name))))
                        .accessibilityIdentifier("result-photo")
                }
                Button(action: onPick) {
                    details
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-result")
                .accessibilityLabel(row.accessibilityLabel)
                #if DEBUG
                .accessibilityValue(row.debugAccessibilityValue)
                #else
                .accessibilityValue(row.address ?? "")
                #endif
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let rating = row.rating {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", rating))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if !row.summary.isEmpty {
                        Text(row.summary)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
            } else if !row.summary.isEmpty {
                Text(row.summary)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
            }
            if let status = row.status {
                Text(status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(row.statusIsPositive ? Color(uiColor: .systemGreen) : Color(uiColor: .systemRed))
                    .lineLimit(1)
                    .accessibilityIdentifier("result-status")
            }
            if let address = row.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(VelaL10n.text("place_directions"),
                     icon: "arrow.triangle.turn.up.right.diamond.fill", id: "result-directions") {
                    SearchActions.directions(row)
                }
                if row.phone != nil {
                    pill(VelaL10n.text("place_call"), icon: "phone.fill", id: "result-call") {
                        SearchActions.call(row)
                    }
                }
                pill(row.isSaved ? VelaL10n.text("place_saved") : VelaL10n.text("place_save"),
                     icon: row.isSaved ? "bookmark.fill" : "bookmark",
                     id: "result-save") {
                    SearchActions.toggleSave(row)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func pill(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
