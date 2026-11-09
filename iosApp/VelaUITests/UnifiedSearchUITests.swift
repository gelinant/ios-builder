import XCTest

/// UNIFIED-SEARCH end to end: one field finds a saved place, a list, a transit stop and line, a
/// wiki article, a setting, a typed coordinate and, finally, a place. The transit board and the
/// saved list come from the real fixtures (Debug), so only the wiki and place rows need the network.
final class UnifiedSearchUITests: VelaUITestCase {
    /// A list is the format the Saved importer accepts; its places are saved places for the field.
    private let fixture = """
    [{"id":"list:srch:unified","name":"SRCH Unified List","icon":"bookmark","color":4287837414,\
    "places":[{"id":"srch:unified:cafe","name":"SRCH Unified Cafe","lat":37.7749,\
    "lng":-122.4194,"address":"1 Market St"}]}]
    """

    func testFindSavedTransitWikiSettingAndPlace() throws {
        let app = launch(
            camera: "sf",
            arguments: ["-VelaSavedFixtureText", fixture, "-VelaTransitBoardOfflineTest"])

        // The Debug transit fixture opens the Ferry Building board at launch; closing it remembers
        // the stop and its lines for the field, exactly as a user's own visit would.
        let boardClose = app.buttons["transit-board-close"]
        XCTAssertTrue(boardClose.waitForExistence(timeout: 20), "the transit board fixture never opened")
        // Wait for the fixture's lines before closing: the field remembers the board it saw, and a
        // close while the first frame was still loading would leave nothing to remember.
        let boardLine = app.descendants(matching: .any)["transit-board-line"].firstMatch
        XCTAssertTrue(boardLine.waitForExistence(timeout: 20), "the transit board fixture never loaded")
        boardClose.tap()

        // The saved fixture imports through the real Saved sheet, as the user's own list would.
        openMapAction("saved-open", in: app)
        let list = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "SRCH Unified List")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 20), "the saved fixture never imported")
        app.buttons["saved-close"].tap()

        // Saved place.
        var field = app.textFields["search-field"]
        field.tap()
        field.typeText("SRCH Unified Cafe")
        let saved = app.buttons.matching(NSPredicate(
            format: "identifier == 'search-suggestion' AND value == 'local' AND label CONTAINS %@",
            "SRCH Unified Cafe")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 20), "no saved row: \(messageText(app))")
        report("unified_kind", "saved")
        shot("unified-saved")
        assertLocalBudget(app)
        saved.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 20),
                      "the saved row opened no place sheet")
        shot("unified-saved-place")
        app.buttons["place-close"].tap()

        // The list itself, then its places.
        clear(app)
        field = app.textFields["search-field"]
        field.tap()
        field.typeText("SRCH Unified List")
        let listRow = row(app, kind: "list")
        XCTAssertTrue(listRow.waitForExistence(timeout: 20), "no list row: \(messageText(app))")
        shot("unified-list")
        listRow.tap()
        XCTAssertTrue(app.buttons["unified-list-close"].waitForExistence(timeout: 15),
                      "the list did not open")
        XCTAssertTrue(app.buttons["unified-list-row"].firstMatch.waitForExistence(timeout: 10),
                      "the opened list has no place")
        report("unified_kind", "list")
        shot("unified-list-opened")
        app.buttons["unified-list-close"].tap()

        // Transit line, from the remembered fixture board. Before the stop step, so the live
        // board it opens cannot replace the labels this test knows.
        clear(app)
        field = app.textFields["search-field"]
        field.tap()
        field.typeText("14")
        let line = row(app, kind: "line")
        XCTAssertTrue(line.waitForExistence(timeout: 20), "no transit line row: \(messageText(app))")
        shot("unified-line")
        report("unified_kind", "line")
        line.tap()
        XCTAssertTrue(app.buttons["transit-board-close"].waitForExistence(timeout: 15),
                      "the line did not open its departures")
        app.buttons["transit-board-close"].tap()

        // Transit stop, remembered from the fixture board.
        clear(app)
        field = app.textFields["search-field"]
        field.tap()
        field.typeText("Ferry")
        let stop = row(app, kind: "stop")
        XCTAssertTrue(stop.waitForExistence(timeout: 20), "no transit stop row: \(messageText(app))")
        shot("unified-stop")
        report("unified_kind", "stop")
        stop.tap()
        XCTAssertTrue(app.buttons["transit-board-close"].waitForExistence(timeout: 15),
                      "the stop did not open its board")
        app.buttons["transit-board-close"].tap()

        // Wiki article, the only online row in this test besides places.
        clear(app)
        field = app.textFields["search-field"]
        field.tap()
        field.typeText("paris")
        let wiki = row(app, kind: "wiki")
        XCTAssertTrue(wiki.waitForExistence(timeout: 45), "no wiki row: \(messageText(app))")
        shot("unified-wiki")
        report("unified_kind", "wiki")
        wiki.tap()
        XCTAssertTrue(app.buttons["unified-wiki-close"].waitForExistence(timeout: 15),
                      "the article did not open")
        shot("unified-wiki-article")
        app.buttons["unified-wiki-close"].tap()

        // A Settings row, through SettingsIndex. Units sits in the first section, so the form
        // opens on the real control.
        clear(app)
        field = app.textFields["search-field"]
        field.tap()
        field.typeText("units")
        let setting = row(app, kind: "setting")
        XCTAssertTrue(setting.waitForExistence(timeout: 20), "no setting row: \(messageText(app))")
        shot("unified-setting")
        report("unified_kind", "setting")
        setting.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-units"].waitForExistence(timeout: 15),
                      "the setting did not open its Settings row")
        shot("unified-setting-row")
        // The sheet must be an accessibility container, not one element that swallows the form.
        XCTAssertTrue(app.descendants(matching: .any)["unified-settings-sheet"].exists,
                      "the settings sheet is not an accessibility container")
        let close = app.buttons["unified-settings-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10),
                      "the settings sheet swallowed its Close button")
        XCTAssertTrue(close.isHittable, "Close is behind the sheet container")
        close.tap()

        // A typed coordinate: a dropped pin with Directions.
        clear(app)
        field = app.textFields["search-field"]
        field.tap()
        field.typeText("37.7749, -122.4194")
        let coord = row(app, kind: "coord")
        XCTAssertTrue(coord.waitForExistence(timeout: 20), "no coordinate row: \(messageText(app))")
        shot("unified-coord")
        report("unified_kind", "coord")
        coord.tap()
        XCTAssertTrue(app.staticTexts["map-poi-coordinates"].waitForExistence(timeout: 15),
                      "the coordinate dropped no pin")
        shot("unified-coord-pin")
        app.buttons["map-poi-close"].tap()

        // A place, still through the existing Google/Photon path.
        clear(app)
        field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee")
        let place = app.buttons.matching(
            NSPredicate(format: "identifier == 'search-suggestion' AND value == 'network'")
        ).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 90), "no place row: \(messageText(app))")
        report("unified_kind", "place")
        shot("unified-place")

        let clearButton = app.buttons["search-clear"]
        if clearButton.exists { clearButton.tap() }
    }

    private func row(_ app: XCUIApplication, kind: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier == 'unified-row' AND value == %@", kind)).firstMatch
    }

    private func messageText(_ app: XCUIApplication) -> String {
        let message = app.staticTexts["search-message"]
        if message.exists { return message.label }
        let debug = app.staticTexts["search-debug"]
        return debug.exists ? debug.label : "no message"
    }

    private func clear(_ app: XCUIApplication) {
        let button = app.buttons["search-clear"]
        if button.waitForExistence(timeout: 5) { button.tap() }
    }

    /// The local rows are ranked synchronously; the debug line carries the measured milliseconds.
    private func assertLocalBudget(_ app: XCUIApplication) {
        let debug = app.staticTexts["search-debug"]
        guard debug.exists else { return }
        let label = debug.label
        guard let range = label.range(of: "ulocal=") else {
            XCTFail("the debug line has no local timing: \(label)")
            return
        }
        let tail = label[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        guard let millis = Int(digits) else {
            XCTFail("the local timing is unreadable: \(label)")
            return
        }
        report("unified_local_ms", millis)
        XCTAssertLessThan(millis, 120, "the local rows took \(millis)ms")
    }
}
