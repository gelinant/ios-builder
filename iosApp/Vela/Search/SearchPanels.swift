import SwiftUI

/// Live place and query rows under the search field, the user's own places first (Android's
/// order). Each row's trailing arrow fills the box and does not search.
struct SuggestionsPanel: View {
    let rows: [SuggestionRow]
    let onPick: (SuggestionRow) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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
                        .accessibilityLabel("Fill search box")
                        .accessibilityIdentifier("search-suggestion-fill")
                        .accessibilityValue(row.local ? "local" : "network")
                        // Clear of the voice microphone overlay at the panel's top right corner
                        // (MapScreen owns it; the first row's arrow sat underneath it).
                        .padding(.trailing, 56)
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
        .frame(maxHeight: 320)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("search-suggestions")
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

/// A pin or an OSM feature without a confident Google listing. No Google details are invented.
struct MapPoiSheet: View {
    let card: MapPoiCard
    let resolving: Bool
    let googleUnavailable: Bool
    let onDirections: () -> Void
    let onClose: () -> Void

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
                .accessibilityLabel("Close")
                .accessibilityIdentifier("map-poi-close")
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
            if resolving {
                HStack(spacing: 6) {
                    ProgressView()
                    Text(card.droppedPin ? "Finding address" : "Finding Google details")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("map-poi-resolving")
            } else if googleUnavailable {
                Label("Google details unavailable", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("map-poi-unavailable")
            }
            Button(action: onDirections) {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("map-poi-directions")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 4, y: -1)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("map-poi-sheet")
    }
}
