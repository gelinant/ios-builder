import XCTest
@testable import Vela

final class SavedFinishingTests: XCTestCase {
    func testDocumentReaderBalancesSecurityScopeAfterRead() throws {
        let url = try fixture(Data("Title,Note,URL,Comment\n".utf8))
        var starts = 0
        var stops = 0
        let text = try SavedDocumentReader.read(
            url,
            start: { starts += 1; return true },
            stop: { stops += 1 })
        XCTAssertEqual(text, "Title,Note,URL,Comment\n")
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 1)
    }

    func testDocumentReaderDoesNotStopDeniedScope() throws {
        let url = try fixture(Data("pins".utf8))
        var stops = 0
        XCTAssertEqual(try SavedDocumentReader.read(url, start: { false }, stop: { stops += 1 }), "pins")
        XCTAssertEqual(stops, 0)
    }

    func testDocumentReaderReleasesScopeAfterDecodingFailure() throws {
        let url = try fixture(Data([0xFF, 0xFE, 0xFD]))
        var stops = 0
        XCTAssertThrowsError(try SavedDocumentReader.read(url, start: { true }, stop: { stops += 1 }))
        XCTAssertEqual(stops, 1)
    }

    func testListExportWritesReadableJsonDocument() throws {
        let document = try SavedDocumentExport.json("[{\"name\":\"Weekend\"}]", listName: "Weekend / Davis")
        defer { try? FileManager.default.removeItem(at: document.url) }
        XCTAssertEqual(document.url.pathExtension, "json")
        XCTAssertTrue(document.url.lastPathComponent.contains("Weekend"))
        let body = try String(contentsOf: document.url, encoding: .utf8)
        XCTAssertEqual(body, "[{\"name\":\"Weekend\"}]")
    }

    func testExportDocumentUsesTheReadableNameAndExtension() throws {
        let document = try SavedDocumentExport.document(
            "<gpx/>", baseName: "vela-list-UI Export List", extension: "gpx")
        defer { try? FileManager.default.removeItem(at: document.url.deletingLastPathComponent()) }
        XCTAssertEqual(document.url.lastPathComponent, "vela-list-UI-Export-List.gpx")
        XCTAssertEqual(try String(contentsOf: document.url, encoding: .utf8), "<gpx/>")
    }

    private func fixture(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("saved-reader-\(UUID().uuidString).csv")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
