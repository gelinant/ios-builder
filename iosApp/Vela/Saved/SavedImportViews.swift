import SwiftUI

/// Pasting a public Google Maps list link. On iOS a Google Maps link cannot open Vela directly, so
/// this is the entry point the app owns; the KML/KMZ document path stays beside it and never needs
/// a Google request.
struct SavedLinkImportSheet: View {
    @ObservedObject var model: SavedModel
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

    var body: some View {
        NavigationStack {
            Form {
                if model.googleListAvailable {
                    Section {
                        TextField("https://maps.app.goo.gl/...", text: $link)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .accessibilityIdentifier("saved-import-link")
                    } header: {
                        Text("Shared Google Maps list link")
                    } footer: {
                        Text("Paste the link from Google Maps, Share list. Vela reads the public list "
                            + "page and keeps its order, names and notes. A private or changed page "
                            + "is reported, not filled with guessed places.")
                    }
                } else {
                    Section {
                        Text("Google list import needs Google. Use Vela without Google is on, so Vela "
                            + "will not open the list page. Import a KML or KMZ file instead: that "
                            + "path works entirely on the phone.")
                            .font(.footnote)
                            .accessibilityIdentifier("saved-import-google-blocked")
                    }
                }
            }
            .navigationTitle("Import a Google list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("saved-import-link-cancel")
                }
                if model.googleListAvailable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            model.requestGoogleLinkImport(link: trimmed)
                            dismiss()
                        }
                        .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saved-import-link-run")
                    }
                }
            }
            .onAppear {
                if !model.googleListAvailable { model.noteGoogleListUnavailable() }
            }
        }
    }
}
