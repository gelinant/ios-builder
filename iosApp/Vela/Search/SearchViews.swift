import SwiftUI

/// The search field over the map. Return submits.
struct SearchBar: View {
    @Binding var text: String
    let searching: Bool
    let onSubmit: () -> Void
    let onClear: () -> Void
    let onOffline: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search here", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit {
                    focused = false
                    onSubmit()
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
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("search-clear")
            }
            Menu {
                Button("Offline maps", action: onOffline)
                    .accessibilityIdentifier("offline-menu-item")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("More options")
            .accessibilityIdentifier("map-overflow")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }
}

/// The results list at the bottom of the map. Its header folds it to leave the map in view.
struct ResultsPanel: View {
    let rows: [SearchRow]
    let message: String?
    let searching: Bool
    @Binding var expanded: Bool
    let onPick: (SearchRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
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
            if expanded {
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
                                Button {
                                    onPick(row)
                                } label: {
                                    ResultRow(row: row)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("search-result")
                                Divider()
                                    .padding(.leading, 16)
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
    }

    private var title: String {
        if searching { return "Searching" }
        if rows.isEmpty { return "Search" }
        return rows.count == 1 ? "1 result" : "\(rows.count) results"
    }
}

struct ResultRow: View {
    let row: SearchRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if let rating = row.rating {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", rating))
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if let count = row.reviewCount {
                        Text("(\(count))")
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
                .font(.subheadline)
            }
            if let address = row.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
