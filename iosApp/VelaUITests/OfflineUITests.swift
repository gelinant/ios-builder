import XCTest

/// I-7 end to end on the smallest complete fixture: Monaco's pack, places and basemap are about
/// 1 MB together. The 62 MB shared glyph pack is downloaded once per simulator installation.
final class OfflineUITests: VelaUITestCase {
    func testMonacoDownloadOfflineMapAndSearch() throws {
        let app = launch(camera: "43.7391,7.4280,14", arguments: ["-VelaOfflineTest", "YES"])
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 5))
        app.buttons["offline-menu-item"].tap()

        let filter = app.textFields["offline-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 30), "region catalog did not load")
        filter.tap()
        filter.typeText("Monaco")
        if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
        let download = app.buttons["offline-download-monaco"]
        XCTAssertTrue(download.waitForExistence(timeout: 10), "Monaco is missing from the catalog")
        download.tap()
        XCTAssertTrue(app.progressIndicators["offline-progress"].waitForExistence(timeout: 20),
                      "download progress never appeared")
        XCTAssertTrue(waitUntil(120) {
            guard let line = app.staticTexts["offline-download-debug"].exists
                    ? app.staticTexts["offline-download-debug"].label : nil else { return false }
            return line.contains("downloading=monaco") && self.value(line, "pct") > 0
        }, "no piece reached a resumable partial body")
        let suspend = app.buttons["offline-test-suspend"]
        suspend.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        shot("offline-progress")
        XCTAssertTrue(waitUntil(15) { app.state == .notRunning }, "debug suspension did not exit")
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60))
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 5))
        app.buttons["offline-menu-item"].tap()
        XCTAssertTrue(app.progressIndicators["offline-progress"].waitForExistence(timeout: 20),
                       "persisted region plan did not reattach")
        if let line = app.staticTexts["offline-download-debug"].exists
                ? app.staticTexts["offline-download-debug"].label : nil {
            report("offline_resume_progress", value(line, "pct"))
        }
        shot("offline-resume")

        let installed = app.staticTexts["offline-installed-monaco"]
        XCTAssertTrue(installed.waitForExistence(timeout: 300), "region did not install")
        XCTAssertTrue(app.staticTexts["offline-ready"].waitForExistence(timeout: 60),
                      "region completion did not settle")
        XCTAssertTrue(waitUntil(30) { !app.progressIndicators["offline-progress"].exists })
        sleep(1)
        shot("offline-regions")

        let block = app.buttons["offline-test-block"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        for _ in 0..<4 where !block.isHittable {
            if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeDown()
            } else {
                app.swipeDown()
            }
        }
        block.tap()
        app.buttons["offline-done"].tap()

        XCTAssertTrue(waitUntil(60) {
            self.debugText("offline-map-debug")?.contains("archive=monaco.pmtiles remote=0") == true
        }, "offline map did not mount the local archive: \(self.debugText("offline-map-debug") ?? "none")")
        if let sizes = debugText("offline-debug") {
            for key in ["pack", "places", "map", "glyphs", "total"] {
                report("offline_\(key == "map" ? "basemap" : key)_bytes", value(sizes, key))
            }
            report("offline_installed", value(sizes, "installed"))
        }
        report("offline_remote_urls", 0)
        sleep(8)
        shot("offline-map")

        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("Casino de Monte Carlo\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "no offline search result")
        XCTAssertTrue(waitUntil(10) { self.debugText("search-debug")?.contains("offline=1") == true })
        report("offline_search_results", rows.count)
        shot("offline-search")
        XCTAssertGreaterThanOrEqual(rows.count, 1)
    }

    private func value(_ line: String, _ key: String) -> Int {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key, let number = Int(pair[1]) { return number }
        }
        return -1
    }
}
