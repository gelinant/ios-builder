import Foundation

/// Reads a picked KML or KMZ inside its security scope. The whole file is read before the scope is
/// released, so the parser never depends on the document URL afterwards. KMZ is a binary ZIP, so
/// the reader returns bytes; the KML parser decodes the document itself.
enum SavedImportReader {
    static func readData(_ url: URL) throws -> Data {
        try readData(
            url,
            start: { url.startAccessingSecurityScopedResource() },
            stop: { url.stopAccessingSecurityScopedResource() })
    }

    /// The seams make scope balancing testable without claiming that a bundle file is scoped.
    static func readData(_ url: URL, start: () -> Bool, stop: () -> Void) throws -> Data {
        let accessing = start()
        defer { if accessing { stop() } }
        return try Data(contentsOf: url)
    }
}
