import SwiftUI
import VelaCore

/// The kinds the one search field answers for. The Kotlin side carries the same strings, so a row
/// that crosses the bridge keeps its action.
enum UnifiedKind: String, CaseIterable {
    case place
    case address
    case saved
    case list
    case stop
    case line
    case wiki
    case setting
    case coordinate = "coord"
    case query

    /// The small tag under the list header, so a row's source is legible, not guessed.
    var label: String {
        switch self {
        case .place: return "Place"
        case .address: return "Address"
        case .saved: return "Saved"
        case .list: return "List"
        case .stop: return "Transit stop"
        case .line: return "Transit line"
        case .wiki: return "Wikivoyage"
        case .setting: return "Setting"
        case .coordinate: return "Coordinate"
        case .query: return "Search"
        }
    }
}

/// One row of the unified list, copied out of the Kotlin `UnifiedHit`.
struct UnifiedRow: Identifiable, Equatable {
    let id: String
    let kind: UnifiedKind
    let title: String
    let subtitle: String?
    let icon: String
    let score: Int
    let online: Bool
    let index: Int
    let query: String?
    let placeId: String?
    let listId: String?
    let lat: Double?
    let lng: Double?
    let line: String?
    let stopName: String?
    let anchor: String?
    let url: String?
    let detail: String?

    init(_ hit: UnifiedHit) {
        id = hit.id
        kind = UnifiedKind(rawValue: hit.kind) ?? .place
        title = hit.title
        subtitle = hit.subtitle
        icon = hit.icon
        score = Int(hit.score)
        online = hit.online
        index = Int(hit.index)
        query = hit.query
        placeId = hit.placeId
        listId = hit.listId
        lat = hit.lat?.doubleValue
        lng = hit.lng?.doubleValue
        line = hit.line
        stopName = hit.stopName
        anchor = hit.anchor
        url = hit.url
        detail = hit.detail
    }

    var accessibilityLabel: String {
        guard let subtitle, !subtitle.isEmpty else { return title }
        return "\(title), \(subtitle)"
    }

    /// Rows that keep SRCH-CARDS' own identifiers and trailing fill arrow: the user's places and
    /// the online place and query rows. The other kinds use their own row identity.
    var isSuggestion: Bool {
        kind == .saved || kind == .place || kind == .address || kind == .query
    }
}

/// A modal the unified field opens from its own row: a saved list, a Settings row, an article.
enum UnifiedDestination: Identifiable {
    case list(id: String, name: String)
    case settings(anchor: String, label: String, section: String)
    case wiki(UnifiedRow)

    var id: String {
        switch self {
        case .list(let id, _): return "list:\(id)"
        case .settings(let anchor, _, _): return "settings:\(anchor)"
        case .wiki(let row): return "wiki:\(row.id)"
        }
    }
}

/// One row under the search field. A local row leads the list with a solid icon; an online row
/// waits behind it with a lighter one, exactly as the ranking orders them.
struct UnifiedSuggestionRow: View {
    let row: UnifiedRow
    let onPick: () -> Void
    /// The return arrow of SRCH-CARDS, only on rows that are a place or a query.
    let onFill: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onPick) {
                HStack(spacing: 12) {
                    Image(systemName: row.icon)
                        .font(.body)
                        .foregroundStyle(row.online ? Color.secondary : Color.primary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let subtitle = row.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if !row.online && !row.isSuggestion {
                        Text(row.kind.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, onFill == nil ? 56 : 0)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(row.isSuggestion ? "search-suggestion" : "unified-row")
            .accessibilityValue(row.isSuggestion ? (row.online ? "network" : "local") : row.kind.rawValue)
            .accessibilityLabel(row.accessibilityLabel)
            if let onFill {
                Button(action: onFill) {
                    Image(systemName: "arrow.up.left")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fill search box")
                .accessibilityIdentifier("search-suggestion-fill")
                .accessibilityValue(row.online ? "network" : "local")
                // Clear of the voice microphone overlay at the panel's top right corner.
                .padding(.trailing, 56)
            }
        }
    }
}

/// A source that finished with nothing to say. The line names the source, so the user knows
/// whether to change the words or to look elsewhere, instead of reading one vague "No results".
struct UnifiedEmptyRow: View {
    let kind: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityIdentifier("unified-empty-\(kind)")
    }

    private var text: String {
        switch kind {
        case "saved": return "Nothing saved matches"
        case "stop": return "No transit stop nearby"
        case "wiki": return "No wiki article matches"
        default: return "No match here"
        }
    }

    private var icon: String {
        switch kind {
        case "saved": return "bookmark"
        case "stop": return "bus"
        case "wiki": return "globe"
        default: return "info.circle"
        }
    }
}

/// Android's search page offers the plain place search under the user's own rows. The compact row
/// says what it will do and sends the same words to the existing Google/Photon path.
struct SearchEverywhereRow: View {
    let query: String
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass.circle")
                    .foregroundStyle(.secondary)
                Text(query.isEmpty ? "Search everywhere" : "Search everywhere for \"\(query)\"")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("unified-search-everywhere")
    }
}

/// A saved list opened from the field. It is the list's own places, through the same store the
/// Saved sheet reads; a place opens its saved sheet as it does there.
struct UnifiedListSheet: View {
    let listId: String
    let name: String
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SavedPlaceRow] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows, id: \.id) { row in
                    Button {
                        AppGraph.session.openSavedPlace(listId: listId, placeId: row.placeId)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).foregroundStyle(.primary)
                            if let address = row.address, !address.isEmpty {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("unified-list-row")
                }
                if rows.isEmpty {
                    Text("This list is empty")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("unified-list-empty")
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                        .accessibilityIdentifier("unified-list-close")
                }
            }
            .accessibilityIdentifier("unified-list-sheet")
        }
        .onAppear { rows = AppGraph.session.saved.state.value.listPlaces(listId: listId) }
    }
}

/// The Settings form, opened from a setting row. The row's anchor rides with the destination; the
/// form opens at the top and the banner names the section, because `SettingsScreen` owns its own
/// scroll position and this lot may not edit it.
struct UnifiedSettingsSheet: View {
    let anchor: String
    let label: String
    let section: String
    let onClose: () -> Void
    @StateObject private var settings = SettingsModel(store: AppGraph.session.settings)
    @StateObject private var offline = OfflineModel(store: AppGraph.session.offline)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.subheadline.weight(.semibold))
                    Text("Settings > \(section)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { onClose() }
                    .accessibilityIdentifier("unified-settings-close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            SettingsScreen(model: settings, offline: offline)
        }
        .onAppear {
            settings.start()
            offline.start()
        }
        .accessibilityIdentifier("unified-settings-sheet")
        .accessibilityValue(anchor)
    }
}

/// A Wikivoyage or Wikipedia article opened from the field: the lead the search already returned,
/// with the link to the full page. No HTML is rendered and no image is loaded, as W-1 decided.
struct UnifiedWikiSheet: View {
    let row: UnifiedRow
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(row.title)
                        .font(.title2.weight(.semibold))
                    if let detail = row.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.body)
                            .accessibilityIdentifier("unified-wiki-extract")
                    }
                    if let url = row.url.flatMap(URL.init(string:)) {
                        Link(destination: url) {
                            Label("Read the full article", systemImage: "safari")
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("unified-wiki-link")
                    }
                    Text("Wikivoyage and Wikipedia contributors, CC BY-SA 4.0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                        .accessibilityIdentifier("unified-wiki-close")
                }
            }
            .accessibilityIdentifier("unified-wiki-sheet")
        }
    }
}
