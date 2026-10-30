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

        // DESIGN-W1: the sheet's content rows keep the 44 pt target the tokens require. A toolbar
        // item reports only its 36 pt label frame, so the Done is reported, not asserted.
        let doneButton = app.buttons["offline-done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        report("design_offline_done_height", Int(doneButton.frame.height))
        let areaEntry = app.buttons["offline-area-start"]
        XCTAssertTrue(areaEntry.waitForExistence(timeout: 10))
        report("design_offline_area_height", Int(areaEntry.frame.height))
        XCTAssertGreaterThanOrEqual(areaEntry.frame.height, 44, "the area entry is under 44 pt")

        let filter = app.textFields["offline-filter"]
        _ = revealInSheet(filter, in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 30), "region catalog did not load")
        filter.tap()
        filter.typeText("Monaco")
        if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
        let download = app.buttons["offline-download-monaco"]
        XCTAssertTrue(download.waitForExistence(timeout: 10), "Monaco is missing from the catalog")
        download.tap()
        let progress = app.progressIndicators["offline-progress"]
        let earlyInstalled = app.staticTexts["offline-installed-monaco"]
        let started = {
            progress.exists || earlyInstalled.exists || app.staticTexts["offline-ready"].exists
        }
        XCTAssertTrue(waitUntil(20, started), "the download never started")
        shot(progress.exists ? "offline-progress" : "offline-ready")
        app.terminate()
        XCTAssertTrue(waitUntil(15) { app.state == .notRunning }, "partial download did not stop")
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60))
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 5))
        app.buttons["offline-menu-item"].tap()
        // The sheet publishes rows lazily. The resumed card can be one screen below the fold, so
        // the probe has to scroll the sheet itself; an unbuilt row is not a stalled download.
        let resumed = {
            app.progressIndicators["offline-progress"].exists ||
                app.staticTexts["offline-installed-monaco"].exists ||
                app.staticTexts["offline-ready"].exists
        }
        var reattached = resumed()
        if !reattached {
            _ = revealInSheet(app.staticTexts["offline-installed-monaco"], in: app)
            reattached = waitUntil(10, resumed)
        }
        XCTAssertTrue(reattached, "persisted region plan did not reattach or finish")
        if let line = app.staticTexts["offline-download-debug"].exists
                ? app.staticTexts["offline-download-debug"].label : nil {
            report("offline_resume_progress", value(line, "pct"))
        }
        shot("offline-resume")

        let installed = app.staticTexts["offline-installed-monaco"]
        XCTAssertTrue(installed.waitForExistence(timeout: 300), "region did not install")
        XCTAssertTrue(app.staticTexts["offline-ready"].waitForExistence(timeout: 60),
                      "region completion did not settle")
        XCTAssertTrue(waitUntil(60) { !app.progressIndicators["offline-progress"].exists },
                      "the progress card survived the ready card")
        let settled = sessionState(app)
        XCTAssertLessThanOrEqual(value(settled, "downloads"), 1,
                       "a second download started after completion: \(settled)")
        sleep(5)
        XCTAssertEqual(sessionState(app), settled, "the download restarted after it was ready")
        report("offline_resume_downloads", value(settled, "downloads"))
        sleep(1)
        shot("offline-regions")

        let block = app.buttons["offline-test-block"]
        reopenOfflineSheet(app)
        XCTAssertTrue(block.waitForExistence(timeout: 10), "the network switch is missing")
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
        reopenOfflineSheet(app)
        XCTAssertTrue(app.staticTexts["offline-ready"].waitForExistence(timeout: 60))
        XCTAssertTrue(waitUntil(60) { !app.progressIndicators["offline-progress"].exists },
                      "the progress card survived the ready card")
        // Regression: the fixture download is one run. Read the process line twice, five seconds
        // apart, so a plan that re-entered after completion would change either field.
        let settled = sessionState(app)
        XCTAssertEqual(value(settled, "downloads"), 1,
                       "the fixture region downloaded more than once: \(settled)")
        XCTAssertTrue(settled.contains("pieces=5/5"), "the fixture plan did not finish: \(settled)")
        sleep(5)
        XCTAssertEqual(sessionState(app), settled,
                       "the fixture download restarted after it was ready")
        report("offline_fixture_downloads", value(settled, "downloads"))
        report("offline_fixture_pieces", "5/5")
        let world = app.descendants(matching: .any)["offline-world-state"]
        report("offline_fixture_world",
               world.exists && world.label.lowercased().contains("installed") ? 1 : 0)

        // One category, one tap, from the reopened top card. No swipe passes over the trash
        // buttons first, which can fire more than the requested category.
        let deletePlaces = reveal("offline-delete-places-monaco", in: "offline-sheet", tries: 20)
        XCTAssertTrue(deletePlaces.exists, "the places delete is missing")
        XCTAssertTrue(deletePlaces.isHittable, "the places delete is not reachable")
        deletePlaces.tap()
        XCTAssertTrue(waitUntil(20) { !app.buttons["offline-delete-places-monaco"].exists },
                      "places category did not go away")
        XCTAssertTrue(app.staticTexts["offline-installed-monaco"].waitForExistence(timeout: 10),
                      "deleting one category uninstalled the region")
        shot("offline-storage")

        let manifest = app.buttons["offline-test-update-manifest"]
        XCTAssertTrue(manifest.waitForExistence(timeout: 10), "the update manifest button is missing")
        manifest.tap()
        let fixtureState = { self.debugState(app) }
        XCTAssertTrue(waitUntil(10) {
            fixtureState().contains("manifest=2") && fixtureState().contains("updatable=1")
        }, "the fixture manifest did not reach the store: \(fixtureState())")
        report("offline_fixture_manifest", fixtureState())
        let update = reveal("offline-update-monaco", in: "offline-sheet",
                            direction: .backward, tries: 20)
        XCTAssertTrue(update.exists,
                      "update was not offered after rev 2: \(fixtureState())")
        update.tap()
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
        XCTAssertTrue(block.waitForExistence(timeout: 10), "the network switch is not reachable")
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
        XCTAssertTrue(reveal(app, download), "Monaco is missing from the catalog")
        download.tap()
    }

    /// Drags the offline list itself until [element] or one of [any] is built and hittable.
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, swipes: Int = 10) -> Bool {
        let sheet = sheet(app)
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            if sheet.exists && sheet.frame.height > 1 { sheet.swipeUp() } else { app.swipeUp() }
        }
        return element.exists
    }

    /// Closes the sheet through Done and opens it again at the top. No drag passes over a control,
    /// so a scenario can reach the first cards without the risk of firing one.
    private func reopenOfflineSheet(_ app: XCUIApplication) {
        let done = app.buttons["offline-done"]
        if done.exists { done.tap() }
        XCTAssertTrue(waitUntil(10) { !done.exists }, "the offline sheet did not close")
        openOfflineSheet(app)
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the offline sheet did not reopen")
    }

    /// The process-wide download line, carried as the Done button value so it costs no row.
    private func sessionState(_ app: XCUIApplication) -> String {
        debugState(app)
    }

    private func debugState(_ app: XCUIApplication) -> String {
        let done = app.buttons["offline-done"]
        guard done.exists, let value = done.value as? String else { return "missing" }
        return value
    }

    private func sheet(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["offline-sheet"].firstMatch
    }

    private func value(_ line: String, _ key: String) -> Int {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key, let number = Int(pair[1]) { return number }
        }
        return -1
    }
}
