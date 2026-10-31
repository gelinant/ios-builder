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
        try document(body, baseName: "vela-list-\(safeName(listName, fallback: "list"))", extension: "json")
    }

    /// Writes [body] under a readable file name. A fresh directory keeps two exports of the same
    /// list from overwriting each other while the share sheet still shows the plain name.
    static func document(_ body: String, baseName: String, extension ext: String) throws -> SavedShareDocument {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(safeName(baseName, fallback: "vela")).\(ext)")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return SavedShareDocument(url: url)
    }

    static func safeName(_ value: String, fallback: String) -> String {
        let allowed = value.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-" || scalar == "_"
                ? Character(String(scalar)) : "-"
        }
        let safe = String(String(allowed).trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            .replacingOccurrences(of: " ", with: "-")
        return safe.isEmpty ? fallback : safe
    }
}
