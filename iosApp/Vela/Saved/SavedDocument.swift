import Foundation

/// Reads a picked document inside its security scope. The whole file is decoded before the scope
/// is released, so the Takeout lookup coroutine never depends on the document URL afterward.
enum SavedDocumentReader {
    static func read(_ url: URL) throws -> String {
        try read(
            url,
            start: { url.startAccessingSecurityScopedResource() },
            stop: { url.stopAccessingSecurityScopedResource() })
    }

    /// The seams make scope balancing testable without claiming that a bundle file is scoped.
    static func read(_ url: URL, start: () -> Bool, stop: () -> Void) throws -> String {
        let accessing = start()
        defer { if accessing { stop() } }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

struct SavedShareDocument: Identifiable {
    let id = UUID()
    let url: URL
}

enum SavedDocumentExport {
    static func json(_ body: String, listName: String) throws -> SavedShareDocument {
        let allowed = listName.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-" || scalar == "_"
                ? Character(String(scalar)) : "-"
        }
        let safe = String(String(allowed).trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            .replacingOccurrences(of: " ", with: "-")
        let name = "vela-list-\(safe.isEmpty ? "list" : safe)-\(UUID().uuidString).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return SavedShareDocument(url: url)
    }
}
