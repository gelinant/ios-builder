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

    private var model: SearchModel? { SearchActions.model }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(VelaL10n.text("exp_chooser_more"))
            .accessibilityIdentifier("map-overflow")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        .onChange(of: focused) { _, value in onFocusChange(value) }
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

/// Recent queries and places offered while the search field is empty.
struct RecentsPanel: View {
    let rows: [RecentItem]
    let onPick: (RecentItem) -> Void
    let onRemove: (RecentItem) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(VelaL10n.text("search_recents")).font(.headline)
                Spacer()
                Button(VelaL10n.text("settings_clear_history_action"), action: onClear)
                    .font(.subheadline)
                    .accessibilityIdentifier("search-recents-clear")
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button { onPick(row) } label: {
                            HStack {
                                Image(systemName: row.kind == "search" ? "magnifyingglass" : "clock")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text(row.title).foregroundStyle(.primary)
                                    if let subtitle = row.subtitle {
                                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Button {
                                    onRemove(row)
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .accessibilityLabel(VelaL10n.text("search_remove_recent"))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search-recent")
                        .accessibilityLabel(row.title)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("search-recents")
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
    @Binding var expanded: Bool
    let onPick: (SearchRow) -> Void

    /// The model carries the pagination, photo identity and filters: MapScreen's call site stays
    /// as it is (BACKLOG section 3 serializes that file), so the panel reads the live model.
    private var model: SearchModel? { SearchActions.model }
    private var headers: [String: String] { model?.photoHeaders() ?? [:] }
    @State private var showFilters = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack {
                        Text(title)
                            .font(.headline)
                        Spacer()
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-panel-toggle")
                if !rows.isEmpty {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title3)
                            .foregroundStyle(filterSummary == nil ? Color.secondary : Color.accentColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(VelaL10n.text("search_filters"))
                    .accessibilityIdentifier("search-filters-open")
                    .padding(.trailing, 4)
                }
            }
            // Android's floating button above the results, shown only once the map has been
            // panned past its threshold. It stays visible while the panel is collapsed so the
            // refreshed list is one tap away and the map stays readable.
            if model?.searchAreaAvailable == true {
                Divider()
                SearchAreaButton(available: true)
            }
            if expanded {
                if let summary = filterSummary {
                    Divider()
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("search-filter-summary")
                }
                if let message {
                    Divider()
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .accessibilityIdentifier("search-message")
                }
                if !rows.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                ResultRow(row: row, headers: headers, onPick: { onPick(row) })
                                Divider()
                                    .padding(.leading, 16)
                            }
                            if model?.moreAvailable == true {
                                if model?.loadingMore == true {
                                    ProgressView()
                                        .padding(.vertical, 12)
                                        .accessibilityIdentifier("search-more-loading")
                                } else {
                                    Button(VelaL10n.text("mapscreen_more_results")) { SearchActions.loadMore() }
                                        .font(.subheadline.weight(.semibold))
                                        .frame(minHeight: 44)
                                        .padding(.vertical, 4)
                                        .accessibilityIdentifier("search-more")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                }
            }
        }
        // Opaque, not a material: secondary text and dividers drawn over a material in a scroll
        // view came out invisible on iOS 26 (run v2-search-ios-20261024-225803-24241).
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .sheet(isPresented: $showFilters) {
            if let model {
                SearchFilterSheet(model: model)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var title: String {
        if searching { return "Searching" }
        if rows.isEmpty { return "Search" }
        return rows.count == 1 ? "1 result" : "\(rows.count) results"
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
        HStack(spacing: 8) {
            pill("Directions", icon: "arrow.triangle.turn.up.right.diamond.fill", id: "result-directions") {
                SearchActions.directions(row)
            }
            if row.phone != nil {
                pill("Call", icon: "phone.fill", id: "result-call") {
                    SearchActions.call(row)
                }
            }
            pill(row.isSaved ? "Saved" : "Save",
                 icon: row.isSaved ? "bookmark.fill" : "bookmark",
                 id: "result-save") {
                SearchActions.toggleSave(row)
            }
            Spacer(minLength: 0)
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
