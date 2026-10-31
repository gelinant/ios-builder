import CoreGraphics
import XCTest

/// SET-ABOUT on the simulator: the About hub search reaches a Settings row, a help topic and a
/// license, the support block tells the truth about the installer, and the notices page lists the
/// bundled libraries and data sources.
final class SettingsAboutUITests: VelaUITestCase {
    func testHubSearchAboutNoticesSupport() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)

        let about = scrollTo("settings-about", in: app, swipes: 26)
        XCTAssertTrue(about.waitForExistence(timeout: 5), "the About row is missing")
        about.tap()
        XCTAssertTrue(app.descendants(matching: .any)["about-screen"].waitForExistence(timeout: 10),
                      "the About hub did not open")

        // A help topic whose answer depends on the real traffic plumbing.
        search("live traffic", in: app)
        dismissKeyboard(app)
        XCTAssertTrue(app.buttons["about-result-help-no-live-traffic"].waitForExistence(timeout: 5),
                      "the traffic help topic is not in the search results")
        shot("settings-about-search")
        app.buttons["about-result-help-no-live-traffic"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["help-detail-no-live-traffic"].waitForExistence(timeout: 5),
                      "the traffic help page did not open")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'downloaded region'")).firstMatch.exists,
                      "the traffic answer does not name downloaded regions")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.textFields["about-search"].waitForExistence(timeout: 5))

        // A Settings row: the hub closes and the Form lands on the real control.
        search("photo quality", in: app)
        dismissKeyboard(app)
        let qualityHit = app.buttons["about-result-setting-settings-photo-quality"]
        XCTAssertTrue(qualityHit.waitForExistence(timeout: 5), "the photo quality row is not in the search results")
        qualityHit.tap()
        let quality = app.descendants(matching: .any)["settings-photo-quality"]
        XCTAssertTrue(waitUntil(6) { quality.exists && quality.isHittable },
                      "the Settings form did not scroll to photo quality")
        // The hit opens the page that now owns the row; return to the list before reopening About.
        app.buttons["settings-data-done"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))

        // Reopen and reach a license from a search hit.
        let aboutAgain = scrollTo("settings-about", in: app, swipes: 26)
        XCTAssertTrue(aboutAgain.waitForExistence(timeout: 5))
        aboutAgain.tap()
        XCTAssertTrue(app.descendants(matching: .any)["about-screen"].waitForExistence(timeout: 10))
        search("maplibre", in: app)
        dismissKeyboard(app)
        let licenseHit = app.buttons["about-result-notice-maplibre"]
        XCTAssertTrue(licenseHit.waitForExistence(timeout: 5), "MapLibre is not in the search results")
        licenseHit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["notice-detail-maplibre"].waitForExistence(timeout: 5),
                      "the MapLibre notice did not open")
        XCTAssertTrue(app.staticTexts["BSD-2-Clause"].exists, "the MapLibre license is not shown")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The diagnostics entry is reachable from the same search, in Settings and in Support.
        search("diagnostics", in: app)
        dismissKeyboard(app)
        XCTAssertTrue(app.buttons["about-result-setting-settings-export-diagnostics"].waitForExistence(timeout: 5),
                      "the Settings diagnostics row is not in the search results")
        let supportHit = app.buttons["about-result-support-diagnostics"]
        XCTAssertTrue(supportHit.waitForExistence(timeout: 5), "the Support diagnostics entry is not in the search results")
        supportHit.tap()
        let versionLine = app.staticTexts["about-version-line"]
        XCTAssertTrue(versionLine.waitForExistence(timeout: 5), "the version line is missing")
        XCTAssertTrue(waitUntil(5) { versionLine.isHittable }, "Support did not scroll into view")
        let version = versionLine.label
        report("about_version", version.replacingOccurrences(of: " ", with: ","))
        XCTAssertTrue(version.hasPrefix("Vela "), version)
        XCTAssertTrue(version.contains("(build "), version)

        let installer = app.staticTexts["about-installer-name"]
        XCTAssertTrue(installer.waitForExistence(timeout: 5), "the installer row is missing")
        report("about_installer", installer.label.replacingOccurrences(of: " ", with: ","))
        XCTAssertEqual(installer.label, "Not available on iOS")
        XCTAssertTrue(app.staticTexts["about-installer"].label.contains("TestFlight"),
                      "the installer explanation does not name TestFlight")
        XCTAssertTrue(app.buttons["about-export-diagnostics"].exists, "the diagnostics export is missing")
        shot("settings-about-support")

        // The notices page: every section and the task's named dependencies. Support sits below
        // the search field, so return to the top before typing again.
        scrollAboutToTop(app)
        search("notices", in: app)
        dismissKeyboard(app)
        let notices = app.buttons["about-result-support-notices"]
        XCTAssertTrue(notices.waitForExistence(timeout: 5), "the notices entry is not in the search results")
        notices.tap()
        XCTAssertTrue(app.descendants(matching: .any)["notices-screen"].waitForExistence(timeout: 5),
                      "the notices page did not open")
        let wanted = ["vela", "maplibre", "swcompression", "sherpa-onnx", "osm",
                      "openfreemap", "openmaptiles", "esri", "google", "transitous",
                      "photon", "overpass", "piper-voices"]
        var seen = 0
        for id in wanted {
            let row = notice(id, in: app)
            if row.exists {
                seen += 1
            } else {
                XCTFail("notice \(id) is missing from the page")
            }
        }
        report("about_notices_seen", seen)
        XCTAssertEqual(seen, wanted.count)
        for _ in 0..<4 { app.swipeUp() }
        shot("settings-about-notices")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["about-screen"].waitForExistence(timeout: 5))
        app.buttons["about-done"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")
    }

    private func search(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["about-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the About search field is missing")
        field.tap()
        clearSearchField(field)
        field.typeText(text)
    }

    private func clearSearchField(_ field: XCUIElement) {
        let value = String(describing: field.value ?? "")
        if value.isEmpty || value == "Search settings, help and licenses" { return }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2))
    }

    private func scrollAboutToTop(_ app: XCUIApplication) {
        let field = app.textFields["about-search"]
        for _ in 0..<12 where !field.isHittable {
            app.swipeDown()
        }
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let ret = app.keyboards.buttons["return"]
        if ret.exists { ret.tap() } else { app.swipeDown() }
    }

    @discardableResult
    private func scrollTo(_ id: String, in app: XCUIApplication, swipes: Int) -> XCUIElement {
        let element = app.descendants(matching: .any)[id]
        // The map behind the sheet also owns a ScrollView; swipe the app so the presented Form
        // receives the gesture.
        for _ in 0..<swipes where !element.isHittable {
            app.swipeUp()
        }
        return element
    }

    private func notice(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)["notice-\(id)"]
        for _ in 0..<20 where !element.exists {
            app.swipeUp()
        }
        return element
    }

    private func resetAfterTest() {
        let clean = XCUIApplication()
        clean.launchArguments = [
            "-VelaResetSettings", "YES", "-VelaDeterministic", "YES", "-VelaResetNavigation", "YES",
        ]
        clean.launch()
        clean.terminate()
    }
}
