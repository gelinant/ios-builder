import SwiftUI

/// Live place and query rows under the search field.
struct SuggestionsPanel: View {
    let rows: [SuggestionRow]
    let onPick: (SuggestionRow) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    Button { onPick(row) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: row.query == nil ? "mappin.circle" : "magnifyingglass")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).foregroundStyle(.primary).lineLimit(1)
                                if let address = row.address {
                                    Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search-suggestion")
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
}

struct QuickCategory: Identifiable {
    let id: String
    let label: String
    let query: String
    let icon: String

    /// Android's stable English queries. CategoryQuery is Android-only, so the US fuel term is used.
    static let all = [
        QuickCategory(id: "coffee", label: "Coffee", query: "Coffee", icon: "cup.and.saucer.fill"),
        QuickCategory(id: "restaurants", label: "Restaurants", query: "Restaurants", icon: "fork.knife"),
        QuickCategory(id: "gas", label: "Gas", query: "Gas station", icon: "fuelpump.fill"),
        QuickCategory(id: "parking", label: "Parking", query: "Parking", icon: "parkingsign.circle.fill"),
        QuickCategory(id: "groceries", label: "Groceries", query: "Groceries", icon: "cart.fill"),
        QuickCategory(id: "transit", label: "Transit stops", query: "Transit stops", icon: "tram.fill"),
    ]
}

struct QuickCategoriesView: View {
    let onPick: (QuickCategory) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickCategory.all) { category in
                    Button { onPick(category) } label: {
                        Label(category.label, systemImage: category.icon)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 13)
                            .frame(height: 38)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.label)
                    .accessibilityIdentifier("category-\(category.id)")
                }
            }
            .padding(.horizontal, 12)
        }
        .accessibilityIdentifier("quick-categories")
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
