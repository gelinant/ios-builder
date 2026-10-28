import SwiftUI

/// The in-drive "Add a stop" sheet. It reuses the map's search model, so the result comes from
/// the same source as the browser's search; the pick goes to the live session as the last stop and
/// the drive replans through it without ending.
struct NavStopSheet: View {
    @ObservedObject var model: NavModel
    @ObservedObject var search: SearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(VelaL10n.text("place_add_stop"))
                    .font(.title3.weight(.bold))
                    .accessibilityIdentifier("nav-stop-title")
                Spacer()
                Button(VelaL10n.text("mapscreen_dismiss")) {
                    close()
                }
                .accessibilityIdentifier("nav-stop-cancel")
            }
            HStack(spacing: 8) {
                TextField("Search for a place", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit(runSearch)
                    .accessibilityIdentifier("nav-stop-search")
                Button(action: runSearch) {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Search")
                .accessibilityIdentifier("nav-stop-search-go")
            }
            if search.searching {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(search.rows.prefix(12))) { row in
                        Button {
                            model.addStop(name: row.name, latitude: row.latitude, longitude: row.longitude)
                            close()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let address = row.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nav-stop-result")
                        Divider()
                    }
                    if let message = search.message, search.rows.isEmpty, !search.searching {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("nav-stop-sheet")
        .onAppear {
            search.clear()
            focused = true
        }
        .onDisappear { search.clear() }
    }

    private func runSearch() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        search.search(query, viewport: nil)
    }

    private func close() {
        search.clear()
        dismiss()
    }
}
