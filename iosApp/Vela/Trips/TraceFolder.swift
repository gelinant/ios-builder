import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VelaCore

/// The folder the user picked for redacted full-trace copies.
///
/// iOS gives an app no path and no standing access: it gives a security-scoped URL while the
/// picker is open, and a bookmark that can be resolved later. The bookmark, not a path, is what
/// survives a relaunch. It goes stale when the folder is moved or deleted, or when an iCloud
/// provider signs out; resolving then fails and Vela asks for the folder again.
final class TraceFolderStore: ObservableObject {
    static let shared = TraceFolderStore()

    @Published private(set) var folderName: String?
    @Published private(set) var lastSavedFile: String?
    @Published private(set) var lastError: String?

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "vela_trace_folder_bookmark"
    private let nameKey = "vela_trace_folder_name"
    private var installed = false

    init() {
        folderName = defaults.string(forKey: nameKey)
    }

    var hasFolder: Bool { defaults.data(forKey: bookmarkKey) != nil }

    /// One listener for the process: a finished drive is copied without the trips screen open.
    func install(store: TripsStore) {
        guard !installed else { return }
        installed = true
        store.setFinishedListener { summary in
            let id = summary.id
            let startedAt = summary.startedAt
            Task { @MainActor in
                TraceFolderStore.shared.autosave(tripID: id, startedAt: startedAt, store: store)
            }
        }
    }

    /// Picks and remembers a folder. The bookmark is made inside the security scope, so it carries
    /// the user's grant; the raw path is never stored.
    func remember(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data: Data
            do {
                data = try url.bookmarkData(
                    options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch {
                data = try url.bookmarkData(
                    options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            defaults.set(data, forKey: bookmarkKey)
            defaults.set(url.lastPathComponent, forKey: nameKey)
            folderName = url.lastPathComponent
            lastError = nil
            return true
        } catch {
            lastError = "iOS did not let Vela keep this folder. Choose it again."
            return false
        }
    }

    func forget() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: nameKey)
        folderName = nil
        lastSavedFile = nil
        lastError = nil
    }

    private func autosave(tripID: String, startedAt: Int64, store: TripsStore) {
        guard hasFolder else { return }
        _ = save(store: store, tripID: tripID, startedAt: startedAt)
    }

    /// Writes the trip's redacted full trace into the remembered folder. The copy keeps every fix
    /// but carries no trip label, destination, street name or wall clock (see
    /// `TripsStore.exportFullRedactedCsv`).
    func save(store: TripsStore, tripID: String, startedAt: Int64) -> Bool {
        guard let text = store.exportFullRedactedCsv(id: tripID) else {
            lastError = "Could not read this trace."
            return false
        }
        guard let folder = resolveFolder() else {
            lastError = "The folder is no longer available. Choose it again."
            return false
        }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let name = "\(TripsModel.fileStem(startedAt))-full.csv"
        do {
            try text.write(
                to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            lastSavedFile = name
            lastError = nil
            return true
        } catch {
            lastError = "The trace could not be written to that folder. Choose it again."
            return false
        }
    }

    private func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
            bookmarkDataIsStale: &stale) else {
            forget()
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(
            options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: bookmarkKey)
        }
        return url
    }
}

/// The system folder picker. It grants access to one folder at a time and returns a security-scoped
/// URL; it never exposes a writable path of the app's choosing.
struct TraceFolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
