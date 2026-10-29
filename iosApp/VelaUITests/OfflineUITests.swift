import XCTest

/// I-7 end to end on the smallest complete fixture: Monaco's pack, places and basemap are about
/// 1 MB together. The 62 MB shared glyph pack is downloaded once per simulator installation.
final class OfflineUITests: VelaUITestCase {
    func testMonacoDownloadOfflineMapAndSearch() throws {
        let app = launch(camera: "43.7391,7.4280,14", arguments: ["-VelaOfflineTest", "YES"])
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 5))
        app.buttons["offline-menu-item"].tap()

        // This scenario must not inherit a region or a pending plan from the fixture scenarios
        // that run before it in the same simulator.
        let reset = app.buttons["offline-test-reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10), "no debug reset button")
        reset.tap()

        let filter = app.textFields["offline-filter"]
        _ = revealInSheet(filter, in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 30), "region catalog did not load")
        filter.tap()
        filter.typeText("Monaco")
        if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
        let download = app.buttons["offline-download-monaco"]
        XCTAssertTrue(download.waitForExistence(timeout: 10), "Monaco is missing from the catalog")
        download.tap()
        XCTAssertTrue(app.progressIndicators["offline-progress"].waitForExistence(timeout: 20),
                      "download progress never appeared")
        shot("offline-progress")
        app.terminate()
        XCTAssertTrue(waitUntil(15) { app.state == .notRunning }, "partial download did not stop")
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60))
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 5))
        app.buttons["offline-menu-item"].tap()
        XCTAssertTrue(waitUntil(25) {
            app.progressIndicators["offline-progress"].exists ||
            app.staticTexts["offline-installed-monaco"].exists ||
            app.staticTexts["offline-ready"].exists
        }, "persisted region plan did not reattach or finish")
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

    func testMonacoDeltaUpdateStorageAndWorldFallback() throws {
        let fixture = ["-VelaOfflineTest", "YES", "-VelaOfflineFixture", "YES"]
        let app = launch(camera: "43.7391,7.4280,14", arguments: fixture)
        openOfflineSheet(app)
        downloadMonacoFixture(app)

        XCTAssertTrue(app.staticTexts["offline-installed-monaco"].waitForExistence(timeout: 120),
                      "fixture region did not install")
        XCTAssertTrue(app.staticTexts["offline-ready"].waitForExistence(timeout: 60))
        XCTAssertTrue(waitUntil(30) { !app.progressIndicators["offline-progress"].exists })
        let world = app.descendants(matching: .any)["offline-world-state"]
        report("offline_fixture_world",
               world.exists && world.label.lowercased().contains("installed") ? 1 : 0)

        let manifest = app.buttons["offline-test-update-manifest"]
        XCTAssertTrue(manifest.waitForExistence(timeout: 5))
        manifest.tap()
        let update = app.buttons["offline-update-monaco"]
        reveal(app, update)
        XCTAssertTrue(update.waitForExistence(timeout: 10), "update was not offered after rev 2")
        update.tap()
        for _ in 0..<3 { app.swipeDown() }
        let updated = app.staticTexts["offline-updated"]
        XCTAssertTrue(updated.waitForExistence(timeout: 120), "delta update did not finish")
        let line = updated.label
        let deltaCount = app.staticTexts["offline-updated-debug"].exists
            ? value(app.staticTexts["offline-updated-debug"].label, "delta") : -1
        let fullCount = app.staticTexts["offline-updated-debug"].exists
            ? value(app.staticTexts["offline-updated-debug"].label, "full") : -1
        report("offline_update_deltas", deltaCount)
        report("offline_update_full", fullCount)
        XCTAssertGreaterThanOrEqual(deltaCount, 1, "no piece took its delta: \(line)")
        shot("offline-update")

        let deletePlaces = app.buttons["offline-delete-places-monaco"]
        reveal(app, deletePlaces)
        XCTAssertTrue(deletePlaces.waitForExistence(timeout: 5))
        deletePlaces.tap()
        XCTAssertTrue(waitUntil(20) { !app.buttons["offline-delete-places-monaco"].exists },
                      "places category did not go away")
        XCTAssertTrue(app.staticTexts["offline-installed-monaco"].exists,
                      "deleting one category uninstalled the region")
        reveal(app, app.descendants(matching: .any)["offline-size-places"])
        shot("offline-storage")
        app.buttons["offline-done"].tap()

        app.terminate()
        XCTAssertTrue(waitUntil(15) { app.state == .notRunning })
        // The relaunch proves the installed region, the world archive and their markers survive a
        // process death. It must not pass the fixture argument: that resets the store at launch.
        app.launchArguments = ["-VelaOfflineTest", "YES", "-VelaStartCamera", "48.8566,2.3522,10"]
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60))
        openOfflineSheet(app)
        let block = app.buttons["offline-test-block"]
        XCTAssertTrue(block.waitForExistence(timeout: 10))
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
            self.debugText("offline-map-debug")?.contains("archive=world.pmtiles remote=0") == true
        }, "world basemap was not the offline fallback: \(self.debugText("offline-map-debug") ?? "none")")
        report("offline_world_fallback", 1)
        report("offline_world_remote_urls", 0)
        sleep(6)
        shot("offline-world")
    }

    private func openOfflineSheet(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 5))
        app.buttons["offline-menu-item"].tap()
    }

    private func downloadMonacoFixture(_ app: XCUIApplication) {
        let filter = app.textFields["offline-filter"]
        // The area entry added at the top pushed the region section below the first screen.
        _ = revealInSheet(filter, in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 30), "region catalog did not load")
        filter.tap()
        filter.typeText("Monaco")
        if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
        let download = app.buttons["offline-download-monaco"]
        reveal(app, download)
        XCTAssertTrue(download.waitForExistence(timeout: 10), "Monaco is missing from the catalog")
        download.tap()
    }

    /// Swipes the sheet until [element] is on screen; a SwiftUI List does not expose offscreen rows.
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, swipes: Int = 8) {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return }
            _ = element.waitForExistence(timeout: 1)
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func value(_ line: String, _ key: String) -> Int {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key, let number = Int(pair[1]) { return number }
        }
        return -1
    }
}
