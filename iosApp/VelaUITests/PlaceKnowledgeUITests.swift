import XCTest

/// W-1: the place sheet's "Learn more" section reads live Wikidata and Wikivoyage data for a place
/// that names its Wikidata item, and the wiki layer draws the geolocated articles once it has a
/// viewport payload. The screenshots are `place-wikidata.png`, `place-wikivoyage.png` and
/// `wiki-layer.png`; the summary lines are `wiki_fields`, `wikivoyage_chars` and `wiki_image`.
final class PlaceKnowledgeUITests: VelaUITestCase {
    private let wikidataFields = [
        "wiki-field-population", "wiki-field-opened", "wiki-field-website", "wiki-field-id",
    ]

    func testWikidataAndWikivoyage() {
        // The fixture opens Paris by its Wikidata id and turns the wiki layer on. No search and no
        // Google request happen; the section and the layer use the two Wikimedia hosts only.
        let app = launch(arguments: ["-VelaPlaceWikiFixture", "Q90"])

        let sheet = app.descendants(matching: .any)["place-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "no place sheet")
        XCTAssertEqual(app.staticTexts["place-name"].label, "Paris",
                       "the W-1 fixture did not open its Wikidata place")
        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "no place scroll")

        let section = app.descendants(matching: .any)["place-knowledge"]
        reveal(section, in: scroll)
        let population = app.descendants(matching: .any)["wiki-field-population"]
        reveal(population, in: scroll)
        if !population.waitForExistence(timeout: 120) {
            let state = debugText("wiki-state-debug") ?? "none"
            let wiki = debugText("wiki-debug") ?? "none"
            print("WIKI_DEBUG state=\(state) wiki=\(wiki)")
            shot("place-knowledge-debug.png")
            XCTFail("Wikidata returned no population for Q90: state=\(state) wiki=\(wiki)")
        }

        let fields = wikidataFields.filter { app.descendants(matching: .any)[$0].exists }.count
        XCTAssertGreaterThanOrEqual(fields, 2, "the Learn more section has fewer than two fields")
        shot("place-wikidata.png")

        let extract = app.staticTexts["wiki-extract"]
        reveal(extract, in: scroll)
        XCTAssertTrue(extract.waitForExistence(timeout: 90),
                      "Wikivoyage returned no extract for Q90")
        let extractText = extract.label.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertGreaterThan(extractText.count, 120, "the extract is too short to be the lead")
        XCTAssertTrue(app.buttons["wiki-source-link"].exists, "no link to the source page")
        XCTAssertTrue(app.staticTexts["wiki-attribution"].exists, "no Wikivoyage attribution")
        let debug = debugText("wiki-debug") ?? ""
        XCTAssertTrue(debug.contains("wiki_image=none"), "an image reached the section: \(debug)")
        shot("place-wikivoyage.png")

        report("wiki_fields", fields)
        report("wikivoyage_chars", extractText.count)
        report("wiki_image", "none")

        closePlace(app)
        XCTAssertTrue(waitUntil(10) { !app.descendants(matching: .any)["place-sheet"].exists },
                      "the place sheet stayed open")

        XCTAssertTrue(enableWikiLayer(app), "the wiki layer could not be turned on")
        var found = layerRow(app)
        for _ in 0..<5 where found == nil {
            if app.buttons["layers-close"].exists { app.buttons["layers-close"].tap() }
            _ = waitUntil(5) { !app.buttons["layer-painted"].exists }
            pan(app)
            sleepSeconds(10)
            found = layerRow(app)
        }
        XCTAssertNotNil(found, "the wiki layer drew no geolocated article near San Francisco")
        shot("wiki-layer.png")
        report("wiki_rows", found == nil ? 0 : 1)
    }

    private func closePlace(_ app: XCUIApplication) {
        let close = app.buttons["place-close"]
        if close.exists {
            close.tap()
        }
    }

    /// Opens the layers sheet, scrolls to the wiki switch and turns it on.
    private func enableWikiLayer(_ app: XCUIApplication) -> Bool {
        let layers = app.buttons["layers-button"]
        XCTAssertTrue(layers.waitForExistence(timeout: 20), "no layers button")
        layers.tap()
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")
        let toggle = app.buttons["world-layer-wiki"]
        for _ in 0..<10 where !toggle.isHittable {
            app.swipeUp()
        }
        guard toggle.exists else { return false }
        if (toggle.value as? String) != "on" {
            toggle.tap()
        }
        guard waitUntil(5, { (toggle.value as? String) == "on" }) else { return false }
        app.buttons["layers-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.buttons["layer-painted"].exists }, "layers sheet stayed open")

        // The host refreshes on a camera move, never on a timer.
        pan(app)
        sleepSeconds(8)
        return true
    }

    /// Reopens the sheet and returns the first Wikivoyage row, scrolling to the World layers block.
    private func layerRow(_ app: XCUIApplication) -> XCUIElement? {
        let layers = app.buttons["layers-button"]
        guard layers.waitForExistence(timeout: 10) else { return nil }
        layers.tap()
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")
        let wiki = app.buttons["world-layer-wiki"]
        for _ in 0..<10 where !wiki.isHittable {
            app.swipeUp()
        }
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'world-row-wiki:'")
        let row = app.buttons.matching(predicate).firstMatch
        for _ in 0..<6 where !row.exists {
            app.swipeUp()
        }
        return row.exists ? row : nil
    }

    /// Finds a section SwiftUI only realizes when it scrolls into view: a few swipes one way,
    /// then back the other, checking at every step.
    @discardableResult
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement,
                        timeout: TimeInterval = 45) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        var up = true
        var steps = 0
        while Date() < end {
            if element.exists { return true }
            if up { scroll.swipeUp() } else { scroll.swipeDown() }
            steps += 1
            if steps % 5 == 0 { up.toggle() }
            sleepSeconds(0.4)
        }
        return element.exists
    }

    private func pan(_ app: XCUIApplication) {
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.30))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.30))
        start.press(forDuration: 0.2, thenDragTo: end)
    }
}

private func sleepSeconds(_ seconds: TimeInterval) {
    usleep(useconds_t(seconds * 1_000_000))
}
