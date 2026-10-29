import XCTest

/// OFF-AREA end to end on the offline fixtures: frame an area over Monaco, read the estimate and
/// the free space, switch off the two network extras, download, and prove the progress card and
/// the installed region survive closing the sheet. The fixture serves every map piece, so the run
/// never touches the real network; the slow hook keeps a progress frame on screen for the capture.
final class OfflineAreaUITests: VelaUITestCase {
    func testFrameAreaAndPreferences() throws {
        let fixture = ["-VelaOfflineTest", "YES", "-VelaOfflineFixture", "YES", "-VelaOfflineAreaSlow", "YES"]
        let app = launch(camera: "43.7391,7.4280,14", arguments: fixture)
        openOfflineSheet(app)

        let start = app.buttons["offline-area-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "the area entry is missing from the offline sheet")
        let note = app.staticTexts["offline-area-note"]
        XCTAssertTrue(waitUntil(10) {
            note.exists && note.label.contains("include offline routing")
        }, "the sheet does not say routing is excluded: \(note.label)")
        start.tap()

        XCTAssertTrue(app.descendants(matching: .any)["offline-area-frame"].waitForExistence(timeout: 10),
                      "the picker frame never appeared")
        let estimate = app.staticTexts["area-estimate"]
        XCTAssertTrue(waitUntil(20) { estimate.exists && estimate.label.contains("Estimated download") },
                      "no estimate for the framed area: \(estimate.exists ? estimate.label : "missing")")
        let routeNote = app.staticTexts["area-routing-note"]
        XCTAssertTrue(waitUntil(10) {
            routeNote.exists && routeNote.label.contains("include offline routing")
        }, "the picker does not say routing is excluded: \(routeNote.label)")
        shot("offline-area-frame")

        let free = app.staticTexts["area-free-space"]
        // The picker's form is built lazily; the preferences and the free space sit below the frame.
        _ = revealInSheet(free, in: app)
        XCTAssertTrue(free.waitForExistence(timeout: 10), "the picker does not show the free space")
        _ = revealInSheet(app.switches["area-include-addresses"], in: app)
        let cameraToggle = app.switches["area-include-cameras"]
        let addressToggle = app.switches["area-include-addresses"]
        XCTAssertTrue(cameraToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(addressToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(5) { (cameraToggle.value as? String) == "1" },
                      "cameras should be included by default")
        // Tap the switch itself, not the middle of the whole row: the label is multiline and the
        // switch sits at the trailing edge.
        cameraToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitUntil(5) { (cameraToggle.value as? String) == "0" },
                      "the camera switch did not turn off")
        addressToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitUntil(5) { (addressToggle.value as? String) == "0" },
                      "the address switch did not turn off")

        report("area_estimate_mb", number(estimate.label, key: "Estimated download"))
        report("area_free_bytes", free.label.replacingOccurrences(of: "Free space: ", with: ""))
        report("area_pref_cameras", cameraToggle.value as? String ?? "?")
        report("area_pref_addresses", addressToggle.value as? String ?? "?")
        if app.staticTexts["area-debug"].exists {
            report("area_prefs", value(app.staticTexts["area-debug"].label, "prefs"))
        }
        shot("offline-area-estimate")

        let download = app.buttons["area-download"]
        XCTAssertTrue(waitUntil(20) { download.exists && download.isEnabled },
                      "Download stayed disabled: \(estimate.label)")
        download.tap()

        let progress = app.progressIndicators["area-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10),
                      "the progress state did not survive the confirmation")
        XCTAssertTrue(app.staticTexts["area-progress-stage"].exists)
        report("area_progress_seen", 1)
        shot("offline-area-progress")

        let stage = app.staticTexts["area-progress-stage"]
        XCTAssertTrue(waitUntil(180) { stage.exists && stage.label.contains("Offline routing is not included") },
                      "the area download did not finish: \(stage.exists ? stage.label : "missing")")
        let progressDebug = app.staticTexts["area-progress-debug"]
        if progressDebug.exists {
            for key in ["stage", "pct", "pieces", "cameras", "addresses"] {
                report("area_\(key)", value(progressDebug.label, key))
            }
        }
        app.buttons["area-hide"].tap()

        openOfflineSheet(app)
        XCTAssertTrue(app.staticTexts["offline-installed-monaco"].waitForExistence(timeout: 30),
                      "the area download did not install its region")
        let ready = app.staticTexts["area-sheet-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "the sheet lost the area download state")
        if let sizes = debugText("offline-debug") {
            for key in ["pack", "places", "map", "glyphs", "total"] {
                report("area_\(key == "map" ? "basemap" : key)_bytes", value(sizes, key))
            }
        }
        shot("offline-area-sheet")
        app.buttons["offline-done"].tap()

        // The camera and address switches persist: a second picker reads them back off.
        XCTAssertTrue(waitUntil(60) {
            self.debugText("offline-map-debug")?.contains("remote=0") == true
        }, "the downloaded area did not mount a remote-free style: \(self.debugText("offline-map-debug") ?? "none")")
        report("area_remote_urls", 0)
        openOfflineSheet(app)
        let secondStart = app.buttons["offline-area-start"]
        XCTAssertTrue(secondStart.waitForExistence(timeout: 15), "the offline sheet did not reopen")
        secondStart.tap()
        XCTAssertTrue(app.switches["area-include-cameras"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(5) {
            (app.switches["area-include-cameras"].value as? String) == "0"
        }, "the camera preference did not persist")
        XCTAssertTrue(waitUntil(5) {
            (app.switches["area-include-addresses"].value as? String) == "0"
        }, "the address preference did not persist")
        shot("offline-area-preferences")
        let close = app.buttons["area-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
    }

    private func openOfflineSheet(_ app: XCUIApplication) {
        let overflow = app.buttons["map-overflow"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 30), "no map chrome")
        for _ in 0..<4 {
            overflow.tap()
            if app.buttons["offline-menu-item"].waitForExistence(timeout: 3) {
                app.buttons["offline-menu-item"].tap()
                return
            }
            sleep(1)
        }
        XCTFail("the map menu never offered the offline sheet")
    }

    private func number(_ label: String, key: String) -> Int {
        guard let part = label.split(separator: ":").last else { return -1 }
        return Int(part.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") ?? -1
    }

    private func value(_ line: String, _ key: String) -> String {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key { return String(pair[1]) }
        }
        return "-"
    }
}
