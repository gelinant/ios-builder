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

    func testTransferJournalRestoresProgressAndResumeDecision() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-transfer-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent("transfers.json")
        let store = RegionTransferStore(url: journal)
        let resume = Data([1, 2, 3, 4])
        let record = RegionTransfer(
            key: "basemap\nmonaco\n/data/monaco.pmtiles", id: "monaco", kind: "basemap",
            url: "https://example.invalid/monaco", targetPath: "/data/monaco.pmtiles",
            temporaryPath: "/data/monaco.pmtiles.download", receivedBytes: 40,
            expectedBytes: 100, resumeData: resume)
        try store.save([record.key: record])

        let restored = try XCTUnwrap(RegionTransferStore(url: journal).load()[record.key])
        XCTAssertEqual(restored.receivedBytes, 40)
        XCTAssertEqual(restored.expectedBytes, 100)
        XCTAssertEqual(restored.resumeData, resume)
        XCTAssertEqual(URLSessionRegionDownloader.recoveryAction(for: restored, hasTask: true), .attach)
        XCTAssertEqual(URLSessionRegionDownloader.recoveryAction(for: restored, hasTask: false), .resume)
        XCTAssertEqual(URLSessionRegionDownloader.recoveryAction(
            for: RegionTransfer(
                key: record.key, id: record.id, kind: record.kind, url: record.url,
                targetPath: record.targetPath, temporaryPath: record.temporaryPath,
                downloadFinished: true), hasTask: false), .install)
        XCTAssertEqual(URLSessionRegionDownloader.recoveryAction(
            for: RegionTransfer(
                key: record.key, id: record.id, kind: record.kind, url: record.url,
                targetPath: record.targetPath, temporaryPath: record.temporaryPath),
            hasTask: false), .fresh)
    }

    func testCutOffArchiveNeverReplacesAnInstalledFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-install-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("monaco.pmtiles")
        let partial = root.appendingPathComponent("monaco.pmtiles.download")
        let installed = Data("installed archive".utf8)
        try installed.write(to: target)
        var body = Data("PMTiles".utf8)
        body.append(Data(repeating: 0, count: 121))
        try body.write(to: partial)

        let error = RegionDownloadInstaller().install(
            kind: "basemap", temporary: partial, target: target,
            expectedBytes: Int64(body.count + 10), httpStatus: 200)
        XCTAssertEqual(error, "length")
        XCTAssertEqual(RegionDownloadInstaller().install(
            kind: "basemap", temporary: partial, target: target,
            expectedBytes: Int64(body.count), httpStatus: 503), "http")
        XCTAssertEqual(try Data(contentsOf: target), installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path))
    }

    func testCompleteArchiveAtomicallyReplacesAnInstalledFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-install-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("monaco.pmtiles")
        let bodyURL = root.appendingPathComponent("monaco.pmtiles.download")
        try Data("old".utf8).write(to: target)
        var body = Data("PMTiles".utf8)
        body.append(contentsOf: [3])
        body.append(Data(repeating: 0, count: 120))
        try body.write(to: bodyURL)

        let error = RegionDownloadInstaller().install(
            kind: "basemap", temporary: bodyURL, target: target,
            expectedBytes: Int64(body.count), httpStatus: 200)
        XCTAssertNil(error)
        XCTAssertEqual(try Data(contentsOf: target), body)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bodyURL.path))
    }
}
