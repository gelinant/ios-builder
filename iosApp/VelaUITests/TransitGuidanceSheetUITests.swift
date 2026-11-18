import XCTest

/// TRANSIT-FICHE: a running trip lives in one bottom sheet with three detents. The K fixture starts
/// the ride; the scenario walks the sheet from the full card details to the permanent bar to the GO
/// guidance and back, keeping the identifiers the trip scenarios already rely on. The GO capture is
/// taken on the ride so the rail, the per-stop times and the line pill are the proof, and the debug
/// line carries the feed's line color.
final class TransitGuidanceSheetUITests: VelaUITestCase {
    func testGuidanceSheetCyclesThroughItsThreeDetents() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
        ]
        app.launch()

        // Expanded detent: the full guidance card, its details and the three actions.
        let card = app.descendants(matching: .any)["transit-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "no guidance card")
        XCTAssertTrue(app.buttons["transit-go-open"].exists, "no GO on the card")
        XCTAssertTrue(app.buttons["transit-trip-open"].exists, "no Trip on the card")
        XCTAssertTrue(app.buttons["transit-end"].exists, "no End on the card")
        let grabber = app.buttons["sheet-grabber"].firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 5), "no sheet grabber")
        report("sheet_detent", "expanded")
        shot("transit-sheet-expanded")

        // Tap the grabber: the sheet wraps to the shortest detent, the permanent bar. The card
        // details collapse, GO and End stay, and the map keeps its search field.
        app.buttons["sheet-grabber"].firstMatch.tap()
        XCTAssertTrue(waitUntil(10) { !card.exists }, "the card details did not collapse to the bar")
        let bar = app.descendants(matching: .any)["transit-card-actions-inline"]
        XCTAssertTrue(waitUntil(10) { bar.exists }, "no permanent bar")
        XCTAssertTrue(app.buttons["transit-go-open"].exists, "the bar lost GO")
        XCTAssertTrue(app.buttons["transit-end"].exists, "the bar lost End")
        XCTAssertTrue(app.textFields["search-field"].exists, "the map kept no browse chrome")
        report("sheet_detent", "peek")
        shot("transit-sheet-peek")

        // Tap the grabber again: the medium detent holds the GO guidance. Wait for the action to
        // render before capturing, so the shot shows the guidance and not the preparing state.
        let go = app.descendants(matching: .any)["transit-go-screen"]
        app.buttons["sheet-grabber"].firstMatch.tap()
        XCTAssertTrue(go.waitForExistence(timeout: 15), "GO did not appear in the medium detent")
        XCTAssertTrue(waitUntil(15) { app.staticTexts["transit-go-action"].exists },
                      "the GO guidance did not render its action")
        XCTAssertTrue(app.staticTexts["transit-go-countdown"].exists, "GO shows no countdown")

        // Advance the walk to the ride: the rail with the per-stop times and the line pill render,
        // and the debug line proves the plan carries the feed's line color, not an accent fallback.
        for _ in 0..<2 {
            let next = app.buttons["transit-go-next"]
            if next.exists && next.isEnabled { next.tap() }
        }
        XCTAssertTrue(waitUntil(15) { self.value(app, "go_step") == "ride" },
                      "GO did not reach the ride")
        let color = value(app, "go_color") ?? "?"
        XCTAssertNotEqual(color, "none", "the GO plan lost the line color")
        XCTAssertNotEqual(color, "?", "the GO debug line has no color field")
        report("go_color", color)
        report("sheet_detent", "go")
        shot("transit-sheet-go")

        // Close (the GO bar's own control) returns to the full card details.
        app.buttons["transit-go-close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 15), "the sheet did not return to the card")
        report("sheet_detent", "expanded")

        // End from the card removes the sheet and restores the map.
        app.buttons["transit-end"].tap()
        XCTAssertTrue(waitUntil(15) { !card.exists }, "End did not remove the guidance sheet")
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5), "browse did not return")
        report("sheet_end", "restored")
    }

    /// A field of the `transit-go-debug` line, like `go_step=ride` or `go_color=#437c93`.
    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        let element = app.staticTexts["transit-go-debug"]
        guard element.exists else { return nil }
        for field in element.label.split(separator: " ") {
            let parts = field.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == Substring(key) {
                return String(parts[1])
            }
        }
        return nil
    }
}