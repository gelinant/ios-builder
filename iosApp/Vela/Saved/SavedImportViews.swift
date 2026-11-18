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
                        Text(VelaL10n.text("saved_shared_google_maps_list_link"))
                    } footer: {
                        Text(VelaL10n.text("saved_paste_the_link_from_google_maps")
                            + VelaL10n.text("saved_page_and_keeps_its_order_names")
                            + VelaL10n.text("saved_is_reported_not_filled_with_guessed"))
                    }
                } else {
                    Section {
                        Text(VelaL10n.text("saved_google_list_import_needs_google_use")
                            + VelaL10n.text("saved_will_not_open_the_list_page")
                            + VelaL10n.text("saved_path_works_entirely_on_the_phone"))
                            .font(.footnote)
                            .accessibilityIdentifier("saved-import-google-blocked")
                    }
                }
            }
            .navigationTitle(VelaL10n.text("saved_import_a_google_list"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(VelaL10n.text("settings_cancel")) { dismiss() }
                        .accessibilityIdentifier("saved-import-link-cancel")
                }
                if model.googleListAvailable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(VelaL10n.text("settings_import")) {
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
