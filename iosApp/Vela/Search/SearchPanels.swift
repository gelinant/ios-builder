import SwiftUI

/// Live rows under the search field, the user's own places first (Android's order). From
/// UNIFIED-SEARCH the panel shows the one field's whole answer: saved places and lists, settings,
/// stops, lines, wiki articles, coordinates and, behind them, the online place rows. Each place
/// row keeps its trailing arrow, which fills the box and does not search.
struct SuggestionsPanel: View {
    let rows: [SuggestionRow]
    let onPick: (SuggestionRow) -> Void

    private var model: SearchModel? { SearchActions.model }
    private var unified: [UnifiedRow] { model?.unifiedRows ?? [] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if unified.isEmpty && (model?.unifiedEmpty.isEmpty ?? true) {
                    legacyRows
                } else {
                    unifiedRows
                }
            }
        }
        .frame(maxHeight: 320)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("search-suggestions")
    }

    @ViewBuilder private var unifiedRows: some View {
        ForEach(unified) { row in
            UnifiedSuggestionRow(
                row: row,
                onPick: { pick(row) },
                onFill: row.isSuggestion ? { fill(row) } : nil)
            Divider().padding(.leading, 16)
        }
        ForEach(model?.unifiedEmpty ?? [], id: \.self) { kind in
            UnifiedEmptyRow(kind: kind)
        }
        if (model?.unifiedLoading ?? 0) > 0 {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(VelaL10n.text("search_searching_transit_and_wiki"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .accessibilityIdentifier("unified-loading")
        }
        if let query = model?.query, !query.isEmpty {
            Divider().padding(.leading, 16)
            SearchEverywhereRow(query: query) { SearchActions.searchEverywhere() }
        }
        #if DEBUG
        if let line = model?.unifiedDebug, !line.isEmpty {
            Text(line)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .accessibilityIdentifier("unified-debug")
        }
        #endif
    }

    @ViewBuilder private var legacyRows: some View {
        ForEach(rows) { row in
            HStack(spacing: 4) {
                Button { onPick(row) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: row))
                            .foregroundStyle(row.local ? .primary : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).foregroundStyle(.primary).lineLimit(1)
                            if let address = row.address {
                                Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-suggestion")
                .accessibilityValue(row.local ? "local" : "network")
                Button { SearchActions.fill(row) } label: {
                    Image(systemName: "arrow.up.left")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VelaL10n.text("search_fill_search_box"))
                .accessibilityIdentifier("search-suggestion-fill")
                .accessibilityValue(row.local ? "local" : "network")
                // Clear of the voice microphone overlay at the panel's top right corner
                // (MapScreen owns it; the first row's arrow sat underneath it).
                .padding(.trailing, 56)
            }
            Divider().padding(.leading, 16)
        }
    }

    /// A place or query row keeps MapScreen's own path, camera framing included. A local row runs
    /// its own action: the saved sheet, the list, the board, the article, Settings or a pin.
    private func pick(_ row: UnifiedRow) {
        switch row.kind {
        case .place, .address, .query:
            onPick(suggestionRow(row))
        default:
            SearchActions.pickUnified(row)
        }
    }

    /// The return arrow: the row's text lands in the box, no search runs (SRCH-CARDS).
    private func fill(_ row: UnifiedRow) {
        SearchActions.fill(suggestionRow(row))
    }

    private func suggestionRow(_ row: UnifiedRow) -> SuggestionRow {
        SuggestionRow(
            id: row.id, index: row.index, name: row.title, address: row.subtitle,
            query: row.query, latitude: row.lat, longitude: row.lng, local: !row.online)
    }

    private func icon(for row: SuggestionRow) -> String {
        if row.query != nil { return "magnifyingglass" }
        return row.local ? "clock.arrow.circlepath" : "mappin.circle"
    }
}

/// The quick-search row under the search field: the user's chips in their order, then a More chip
/// that opens every saved shortcut, the switched-off ones included (Android's row).
struct QuickCategoriesView: View {
    let onPick: (QuickCategory) -> Void
    @StateObject private var chips = QuickChipsModel.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips.visible) { category in
                    Button { onPick(category) } label: {
                        Label(category.label, systemImage: category.icon)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 13)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(.regularMaterial, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.label)
                    .accessibilityIdentifier("category-\(category.id)")
                }
                moreChip
            }
            .padding(.horizontal, 12)
        }
        .onAppear { chips.start() }
        .accessibilityIdentifier("quick-categories")
    }

    /// Every chip, hidden ones included, in the user's order. A pick runs that search.
    private var moreChip: some View {
        Menu {
            ForEach(chips.arranged) { category in
                Button {
                    onPick(category)
                } label: {
                    Label(category.label, systemImage: category.icon)
                }
                .accessibilityIdentifier("category-menu-\(category.id)")
            }
        } label: {
            Label(VelaL10n.text("cat_more"), systemImage: "ellipsis")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 13)
                .frame(minWidth: 44, minHeight: 44)
                .background(.regularMaterial, in: Capsule())
                .contentShape(Capsule())
        }
        .accessibilityLabel(VelaL10n.text("cat_more"))
        .accessibilityIdentifier("category-more")
    }
}

/// An OpenStreetMap place or a pin without a confident Google listing. The sheet is built from
/// what the tap carries: name, category, point and distance. No Google details are invented, and
/// the explicit Google lookup is the only request this sheet can send.
struct MapPoiSheet: View {
    let card: MapPoiCard
    let resolving: Bool
    let googleUnavailable: Bool
    let onDirections: () -> Void
    let onClose: () -> Void

    @StateObject private var actions = MapPoiActions(session: AppGraph.session)
    @State private var showsShareSheet = false

    private var sharePayload: VelaSharePayload { actions.share(card) }

    /// DEBUG builds expose the payload on the share button: the system sheet is a remote process.
    private var shareDebugValue: String {
        #if DEBUG
        sharePayload.debugText
        #else
        ""
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(card.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .accessibilityIdentifier("map-poi-name")
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(VelaL10n.text("place_close"))
                .accessibilityIdentifier("map-poi-close")
            }
            if !card.droppedPin {
                Label(VelaL10n.text("search_osm_place"), systemImage: "map")
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("map-poi-osm")
            }
            if let category = card.category {
                Text(category.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let address = card.address {
                Label(address, systemImage: "mappin")
                    .font(.subheadline)
            }
            Text(String(format: "%.5f, %.5f", card.latitude, card.longitude))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("map-poi-coordinates")
            if let distance = card.distanceMeters {
                Label(RouteFormat.distance(distance), systemImage: "location")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("map-poi-distance")
            }
            if resolving {
                HStack(spacing: 6) {
                    ProgressView()
                    Text(card.droppedPin ? VelaL10n.text("search_finding_address") : VelaL10n.text("search_finding_google_details"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("map-poi-resolving")
            } else if googleUnavailable {
                Label(VelaL10n.text("search_google_details_unavailable"), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("map-poi-unavailable")
            }
            if card.googleSearchFoundNothing {
                Text(VelaL10n.text("search_google_details_unavailable"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("map-poi-google-empty")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: onDirections) {
                        Label(VelaL10n.text("place_directions"),
                              systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("map-poi-directions")
                    Button { actions.toggleSave(card) } label: {
                        Label(actions.saved ? VelaL10n.text("place_saved") : VelaL10n.text("place_save"),
                              systemImage: actions.saved ? "star.fill" : "star")
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("map-poi-save")
                    Button { showsShareSheet = true } label: {
                        Label(VelaL10n.text("place_share"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("map-poi-share")
                    .accessibilityValue(shareDebugValue)
                    if card.googleSearchable {
                        Button { actions.searchGoogle() } label: {
                            Label(VelaL10n.text("search_google_for_place"), systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("map-poi-search-google")
                    }
                }
            }
            #if DEBUG
            Text("poi_match=\(card.match) source=osm"
                + (card.distanceMeters.map { " distance=\(Int($0.rounded()))" } ?? ""))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("map-poi-debug")
            #endif
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .onAppear { actions.refresh(card) }
        .sheet(isPresented: $showsShareSheet) {
            ActivityView(items: sharePayload.items, subject: sharePayload.subject)
        }
        .accessibilityIdentifier("map-poi-sheet")
    }
}
