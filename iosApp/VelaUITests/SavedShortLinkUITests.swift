import XCTest

/// IMPORT-SHORTLINK on the simulator: the three reported `maps.app.goo.gl` share links, each
/// replayed from the real resolved page and getlist reply captured on 2026-10-28. The page id is
/// read from the captured page through the same function the live path uses, so a rotated page
/// shape fails here rather than silently importing an empty list.
final class SavedShortLinkUITests: VelaUITestCase {
    private struct Manifest: Decodable {
        let captured: String
        let links: [Entry]
    }

    private struct Entry: Decodable {
        let link: String
        let title: String
        let places: Int
        let first: String
    }

    func testShortLinksImportTheirRealLists() throws {
        let url = try XCTUnwrap(
            Bundle(for: SavedShortLinkUITests.self).url(forResource: "ShortLinkFixtures", withExtension: "json"),
            "the short-link manifest is not in the UI test bundle")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        XCTAssertEqual(3, manifest.links.count, "the three reported links must be captured")

        let app = launch(camera: "davis", arguments: [
            "-VelaIntentTestReset", "YES",
            "-VelaSavedShortLinkFixtures", url.path,
        ])
        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 10), "Saved sheet missing")
        resolveDuplicateIfPresent(app)

        for (index, entry) in manifest.links.enumerated() {
            runLinkImport(app, link: entry.link)
            if app.buttons["saved-import-replace"].waitForExistence(timeout: 3) {
                app.buttons["saved-import-replace"].tap()
            }
            let message = app.staticTexts["saved-import-message"]
            XCTAssertTrue(reveal(message, in: app), "short link \(index + 1) did not finish")
            XCTAssertTrue(
                message.label.contains("\(entry.places) places imported into \(entry.title)"),
                "short link \(index + 1): \(message.label)")

            let row = app.buttons["\(entry.title), \(entry.places) places"]
            XCTAssertTrue(reveal(row, in: app, up: false), "short link \(index + 1) list is missing")
            row.tap()
            XCTAssertTrue(app.navigationBars[entry.title].waitForExistence(timeout: 5),
                          "short link \(index + 1) list did not open")
            let first = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", entry.first)).firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 5),
                          "short link \(index + 1) first place is \(entry.first)")
            report("shortlink_places", entry.places)
            app.navigationBars[entry.title].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5),
                          "back to Saved failed")
        }
        report("shortlink_list", 1)
        report("shortlink_source", "fixture")
        shot("saved-shortlink")

        for entry in manifest.links { deleteList(app, named: entry.title) }
    }

    private func openGoogleLinkSheet(_ app: XCUIApplication) {
        app.buttons["saved-import"].tap()
        let item = app.buttons["saved-import-google"]
        if item.waitForExistence(timeout: 5) {
            item.tap()
        } else {
            app.menuItems["Google Maps list link"].tap()
        }
        XCTAssertTrue(app.textFields["saved-import-link"].waitForExistence(timeout: 5),
                      "the link sheet did not open")
    }

    private func runLinkImport(_ app: XCUIApplication, link: String) {
        openGoogleLinkSheet(app)
        let field = app.textFields["saved-import-link"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no link field")
        field.tap()
        field.typeText(link)
        app.buttons["saved-import-link-run"].tap()
        XCTAssertTrue(waitUntil(5) { !field.exists }, "the link sheet did not close")
    }

    private func resolveDuplicateIfPresent(_ app: XCUIApplication) {
        let merge = app.buttons.matching(identifier: "saved-import-merge").firstMatch
        guard merge.waitForExistence(timeout: 3) else { return }
        merge.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            if up { app.swipeUp() } else { app.swipeDown() }
            usleep(300_000)
        }
        return element.exists
    }

    private func deleteList(_ app: XCUIApplication, named name: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name),")).firstMatch
        guard row.exists || reveal(row, in: app, up: false) else { return }
        row.swipeLeft()
        if app.buttons["Delete"].waitForExistence(timeout: 3) { app.buttons["Delete"].tap() }
    }
}
