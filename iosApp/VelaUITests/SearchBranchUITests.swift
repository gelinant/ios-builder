import XCTest

/// SRCH-BRANCH: the other Google listings at one address, their count chip, and the quick-search
/// editor behind the More chip. The branch group comes from a debug fixture so the scenario never
/// depends on Google sending siblings; the production path reads the search reply it already has.
final class SearchBranchUITests: VelaUITestCase {
    func testBranchChipAndShortcutEditor() {
        let app = launch(arguments: ["-VelaPlaceBranchesFixture", "YES"])

        let chip = app.buttons["place-branch-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 30), "no branch count chip: \(debugText(app, "place-debug"))")
        XCTAssertEqual(String(describing: chip.value ?? ""), "3", "the chip hid a branch")
        report("branch_chip", chip.label)
        shot("place-branch-chip")

        chip.tap()
        let rows = app.buttons.matching(identifier: "place-branch-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the chip opened no branch list")
        XCTAssertEqual(rows.count, 3, "the list did not name every other listing at the address")
        report("branch_rows", rows.count)
        shot("place-branch-list")

        let opened = rows.firstMatch.label
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(10) {
            app.staticTexts["place-name"].label != "Market Hall"
        }, "the branch did not replace the sheet: \(app.staticTexts["place-name"].label)")
        XCTAssertEqual(String(describing: chip.value ?? ""), "3", "the original listing left the group")
        XCTAssertFalse(opened.isEmpty)
        shot("place-branch-opened")

        app.buttons["place-close"].tap()
        XCTAssertTrue(waitUntil(10) { app.buttons["category-restaurants"].exists },
                      "closing the place did not bring the quick-search row back")
        let more = app.buttons["category-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "the row lost its More chip")
        shot("search-more-chip")

        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")

        let entry = app.buttons["settings-quick-chips"]
        for _ in 0..<10 where !entry.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(entry.isHittable, "the quick-search row stayed off screen")
        entry.tap()

        let editor = app.descendants(matching: .any)["quick-chips-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "no quick-search editor")
        let coffee = app.switches["quick-chip-toggle-coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 10), "the editor did not list the saved chips")
        XCTAssertEqual(String(describing: coffee.value ?? ""), "1")
        shot("quick-chips-editor")

        coffee.tap()
        XCTAssertTrue(waitUntil(5) { String(describing: coffee.value ?? "") == "0" },
                      "switching a chip off did not persist in the editor")

        let up = app.buttons["quick-chip-up-coffee"]
        XCTAssertTrue(up.isHittable, "no reorder control on the chip")
        up.tap()
        XCTAssertTrue(waitUntil(5) { !up.isEnabled }, "the move did not reach the top of the order")
        shot("quick-chips-reordered")

        app.buttons["quick-chips-done"].tap()
        entry.tap()
        XCTAssertTrue(coffee.waitForExistence(timeout: 10))
        XCTAssertEqual(String(describing: coffee.value ?? ""), "0", "the switch was not saved")
        XCTAssertFalse(app.buttons["quick-chip-up-coffee"].isEnabled, "the order was not saved")
        app.buttons["quick-chips-done"].tap()
        app.buttons["settings-done"].tap()
        report("quick_chip_hidden", "Coffee")
    }

    private func debugText(_ app: XCUIApplication, _ id: String) -> String {
        let element = app.staticTexts[id]
        return element.exists ? element.label : "none"
    }
}
