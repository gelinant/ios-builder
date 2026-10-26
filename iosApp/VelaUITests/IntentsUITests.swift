import XCTest

/// App Intents terminate at the same deep links as these launches. Siri itself needs a human device
/// test; the Spotlight scenario uses the real index through a Debug-only fixture command.
final class IntentsUITests: VelaUITestCase {
    func testDeepLinkOpensSearch() {
        let app = launch(arguments: ["-VelaOpenURL", "vela://search?q=coffee"])
        let results = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout: 60), "deep-link search returned no rows")
        XCTAssertEqual(app.textFields["search-field"].value as? String, "coffee")
        XCTAssertEqual(debugText("intents-debug"), "route=search error=0")
        shot("intents-search")
        report("intents_search_rows", results.count)
    }

    func testDeepLinkOpensSavedPlace() {
        var app = launch(camera: "sf")
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")
        let results = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout: 60), "no search result")
        results.firstMatch.tap()
        let placeName = app.staticTexts["place-name"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 15), "no place sheet")
        let expectedName = placeName.label
        let save = app.buttons["place-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no Save button")
        if save.label == "Saved" { save.tap() }
        save.tap()
        XCTAssertTrue(waitUntil(5) { save.label == "Saved" }, "place was not saved")

        app.terminate()
        app = launch(camera: "sf", arguments: ["-VelaOpenSavedLink", "YES"])
        let reopenedName = app.staticTexts["place-name"]
        XCTAssertTrue(reopenedName.waitForExistence(timeout: 15), "saved deep link did not open a place")
        XCTAssertEqual(reopenedName.label, expectedName)
        XCTAssertEqual(debugText("intents-debug"), "route=place error=0")
        shot("intents-place")
        report("intents_saved_place", "opened")

        let cleanup = app.buttons["place-save"]
        XCTAssertTrue(cleanup.waitForExistence(timeout: 5), "cleanup Save button missing")
        XCTAssertTrue(waitUntil(10) { cleanup.label == "Saved" }, "saved state missing during cleanup")
        cleanup.tap()
    }

    func testHomeUnsetErrorOpensSavedSetup() {
        let app = launch(arguments: [
            "-VelaIntentTestReset", "YES",
            "-VelaOpenURL", "vela://navigate/home",
        ])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "missing Home did not show an error")
        XCTAssertEqual(debugText("intents-debug"), "route=home error=1")
        shot("intents-home-error")
        app.buttons["Open Saved"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 10), "Saved setup did not open")
        report("intents_home_unset", "saved_setup")
    }

    func testParkingDeepLinkOpensPlaceAndCleansUp() {
        var app = launch(arguments: [
            "-VelaIntentTestFixture", "parking",
            "-VelaOpenURL", "vela://parking",
        ])
        let placeName = app.staticTexts["place-name"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 15), "parking deep link did not open a place")
        XCTAssertEqual(placeName.label, "Parked car")
        XCTAssertEqual(debugText("intents-debug"), "route=parking error=0")
        report("intents_parking", "opened")

        app.terminate()
        app = launch(arguments: ["-VelaIntentTestReset", "YES"])
        XCTAssertTrue(app.textFields["search-field"].exists)
    }

    func testSpotlightFixtureAddsAndDeletesThroughRealIndex() {
        var app = launch(arguments: ["-VelaSpotlightTest", "add"])
        XCTAssertTrue(waitUntil(15) {
            debugText("spotlight-debug")?.contains("records=1 indexed=1") == true
                && debugText("spotlight-debug")?.contains("errors=0") == true
        }, "Spotlight add did not complete: \(debugText("spotlight-debug") ?? "missing")")
        report("intents_spotlight_add", 1)

        app.terminate()
        app = launch(arguments: ["-VelaSpotlightTest", "delete"])
        XCTAssertTrue(waitUntil(15) {
            debugText("spotlight-debug")?.contains("records=0 indexed=0 deleted=1") == true
                && debugText("spotlight-debug")?.contains("errors=0") == true
        }, "Spotlight delete did not complete: \(debugText("spotlight-debug") ?? "missing")")
        report("intents_spotlight_delete", 1)
    }
}
