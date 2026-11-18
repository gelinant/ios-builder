import SwiftUI
import UIKit

/// The in-drive "Add a stop" search. It is an overlay over the drive, not a sheet, so the
/// guidance camera, the banner and the Live Activity keep running behind it. The pick goes to the
/// live session as the last stop and the drive replans through it without ending.
struct NavStopOverlay: View {
    @ObservedObject var model: NavModel
    @ObservedObject var search: SearchModel
    let onClose: () -> Void
    @State private var text = ""

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityIdentifier("nav-stop-backdrop")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(VelaL10n.text("place_add_stop"))
                        .font(.title3.weight(.bold))
                        .accessibilityIdentifier("nav-stop-title")
                    Spacer()
                    Button(VelaL10n.text("mapscreen_dismiss")) { close() }
                        .accessibilityIdentifier("nav-stop-cancel")
                }
                HStack(spacing: 8) {
                    TextField(VelaL10n.text("route_search_for_a_place"), text: $text)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit(runSearch)
                        .accessibilityIdentifier("nav-stop-search")
                    Button(action: runSearch) {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(VelaL10n.text("settings_search"))
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
            .frame(maxHeight: 360)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .padding(.horizontal, 12)
            .padding(.top, 64)
        }
        // Without containment the container swallows the search field and the results, exactly the
        // bug the transit sheet and the sound choices had.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nav-stop-sheet")
        .onAppear { search.clear() }
        .onDisappear { search.clear() }
    }

    private func runSearch() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        search.search(query, viewport: nil)
    }

    private func close() {
        search.clear()
        onClose()
    }
}
