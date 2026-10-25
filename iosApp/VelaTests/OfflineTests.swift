import XCTest
@testable import Vela

final class OfflineTests: XCTestCase {
    func testOfflineStyleHasOnlyLocalResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-offline-style-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("monaco.pmtiles")
        try Data(repeating: 0, count: 128).write(to: archive)
        let style = try OfflineStyleFactory.makeStyle(
            archivePath: archive.path,
            glyphsPath: root.appendingPathComponent("glyphs").path,
            spritesPath: root.appendingPathComponent("sprites").path)

        XCTAssertEqual(OfflineStyleFactory.remoteURLCount(in: style), 0)
        let rootObject = try JSONSerialization.jsonObject(with: Data(contentsOf: style)) as! [String: Any]
        let sources = rootObject["sources"] as? [String: Any]
        XCTAssertNil(sources?["openmaptiles"])
        XCTAssertNil(sources?["ne2_shaded"])
        let layers = rootObject["layers"] as? [[String: Any]] ?? []
        XCTAssertFalse(layers.isEmpty)
        XCTAssertFalse(layers.contains { $0["source"] as? String == "ne2_shaded" })
        XCTAssertFalse(layers.contains { $0["source"] as? String == "openmaptiles" })
        XCTAssertTrue(layers.contains { $0["source"] as? String == OfflineStyleFactory.sourceId })
        XCTAssertTrue((rootObject["glyphs"] as? String)?.hasPrefix("file://") == true)
        XCTAssertTrue((rootObject["sprite"] as? String)?.hasPrefix("file://") == true)
        let fonts = layers.compactMap { ($0["layout"] as? [String: Any])?["text-font"] as? [String] }.flatMap { $0 }
        XCTAssertFalse(fonts.isEmpty)
        XCTAssertFalse(fonts.contains { $0.hasPrefix("Roboto") })
    }

    func testZipReaderRejectsATruncatedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("short.zip")
        try Data("not a zip".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ZipArchive(url: url))
    }
}
