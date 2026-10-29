import CoreLocation
import XCTest

/// M2 end to end: the app searches "coffee" over the San Francisco start camera and shows the
/// results as a list and as pins. Needs the network.
final class SearchUITests: VelaUITestCase {
    func testCoffeeSearchShowsResultsAndPins() throws {
        let app = launch(camera: "sf")
        let field = app.textFields["search-field"]
        // Lets the first tiles land, for the screenshots.
        sleep(6)
        field.tap()
        field.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row: \(messageText(app))")
        // The later pages arrive with the first; wait for the list to settle.
        var count = rows.count
        let settle = Date().addingTimeInterval(10)
        while Date() < settle {
            sleep(1)
            let now = rows.count
            if now == count && now >= 5 { break }
            count = now
        }
        count = rows.count
        print("SEARCH_ROWS=\(count)")
        report("search_rows", count)
        sleep(3)
        shot("search-list")
        XCTAssertGreaterThanOrEqual(count, 5, "fewer than 5 results")

        let toggle = app.buttons["search-panel-toggle"]
        XCTAssertTrue(toggle.exists)
        toggle.tap()
        sleep(3)
        shot("search-map")

        toggle.tap()
        let first = rows.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        sleep(4)
        shot("search-centered")
    }

    func testSuggestionsAppearAndFreezeAfterSelection() {
        let app = launch(camera: "sf")
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coff")

        let suggestions = app.buttons.matching(identifier: "search-suggestion")
        XCTAssertTrue(suggestions.firstMatch.waitForExistence(timeout: 45), "no suggestions")
        report("suggestion_rows", suggestions.count)
        shot("suggest")
        suggestions.firstMatch.tap()

        XCTAssertTrue(waitUntil(10) { suggestions.count == 0 }, "suggestions stayed open")
        sleep(2)
        XCTAssertEqual(suggestions.count, 0, "a late answer changed the selection")
        let opened = app.staticTexts["place-name"].exists || app.buttons["search-result"].firstMatch.exists
        XCTAssertTrue(opened || waitUntil(45) {
            app.staticTexts["place-name"].exists || app.buttons["search-result"].firstMatch.exists
        }, "selection opened neither a place nor a search")
    }

    func testQuickCategoryRunsSearch() {
        let app = launch(camera: "sf")
        let coffee = app.buttons["category-coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 10), "no Coffee category")
        coffee.tap()
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "category returned no results")
        report("category_rows", rows.count)
        shot("category")
        XCTAssertEqual(app.textFields["search-field"].value as? String, "Coffee")
    }

    /// SRCH-CARDS: a place just opened leads the suggestions as the user's own recent place, and
    /// its trailing arrow fills the box without running a search.
    func testSuggestionPriorityAndArrow() {
        let app = launch(camera: "sf")
        sleep(6)
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row: \(messageText(app))")
        let name = rows.firstMatch.label.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(name.isEmpty, "the first card had no name")
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 45),
                      "the card did not open its place")
        app.buttons["place-close"].tap()

        let clear = app.buttons["search-clear"]
        if clear.waitForExistence(timeout: 5) { clear.tap() }
        field.tap()
        let prefix = String(name.prefix(5))
        field.typeText(prefix)

        let suggestions = app.buttons.matching(identifier: "search-suggestion")
        XCTAssertTrue(suggestions.firstMatch.waitForExistence(timeout: 45),
                      "no suggestions for \(prefix): \(messageText(app))")
        XCTAssertTrue(waitUntil(20) {
            String(describing: suggestions.firstMatch.value ?? "") == "local"
        }, "the user's recent place did not lead: \(suggestions.firstMatch.label)")
        XCTAssertTrue(suggestions.firstMatch.label.localizedCaseInsensitiveContains(prefix),
                      "the leading row is not the place just opened: \(suggestions.firstMatch.label)")
        report("suggestion_priority", "local")
        report("suggestion_leading_row", suggestions.firstMatch.label)

        let arrow = app.buttons.matching(identifier: "search-suggestion-fill").firstMatch
        XCTAssertTrue(arrow.waitForExistence(timeout: 10), "no return arrow on the suggestion")
        arrow.tap()
        XCTAssertTrue(waitUntil(10) { (field.value as? String) == name },
                      "the arrow did not fill the box: \(String(describing: field.value))")
        XCTAssertEqual(rows.count, 0, "the arrow submitted a search")
        shot("search-suggestion-priority")
    }

    /// SRCH-CARDS: a Google card carries its photo, rating and count, open status and the actions
    /// the reply supports. The screenshot shows the photo and the coloured status together.
    func testResultCardFields() {
        let app = launch(camera: "sf")
        sleep(6)
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row: \(messageText(app))")
        XCTAssertTrue(waitUntil(30) { rows.count >= 3 }, "fewer than 3 cards")
        sleep(2)

        let elements = rows.allElementsBoundByIndex
        let withStatus = elements.first { element in
            let label = element.label.lowercased()
            return (label.contains("stars") || label.contains("review")) &&
                (label.contains("open") || label.contains("closed"))
        }
        XCTAssertNotNil(withStatus, "no card carried both a rating and an open status: "
            + elements.map { $0.label }.joined(separator: " / "))
        let label = withStatus?.label ?? ""
        report("card_status_label", label)
        XCTAssertNotNil(label.range(of: "\\d\\.\\d", options: .regularExpression),
                        "the card carried no rating")

        let photos = app.descendants(matching: .any).matching(identifier: "result-photo")
        XCTAssertGreaterThan(photos.count, 0, "no card loaded a photo thumbnail")
        report("card_photo_rows", photos.count)
        let directions = app.buttons.matching(identifier: "result-directions")
        XCTAssertGreaterThan(directions.count, 0, "no Directions action on the cards")
        let saves = app.buttons.matching(identifier: "result-save")
        XCTAssertGreaterThan(saves.count, 0, "no Save action on the cards")
        report("card_call_rows", app.buttons.matching(identifier: "result-call").count)
        shot("search-card-fields")
    }

    func testAddressSearchMergesWithoutDuplicateRows() {
        let app = launch(camera: "sf")
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("1 Ferry Building\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no address result: \(messageText(app))")
        XCTAssertTrue(waitUntil(30) {
            rows.allElementsBoundByIndex.contains {
                $0.label.localizedCaseInsensitiveContains("1 Ferry Building") ||
                    ($0.value as? String)?.localizedCaseInsensitiveContains("1 Ferry Building") == true
            }
        }, "Google and Photon did not return the typed house number")
        let elements = rows.allElementsBoundByIndex
        let addressHits = elements.filter {
            $0.label.localizedCaseInsensitiveContains("1 Ferry Building") ||
                ($0.value as? String)?.localizedCaseInsensitiveContains("1 Ferry Building") == true
        }.count
        report("address_rows", elements.count)
        report("address_hits", addressHits)
        shot("address-search")
        XCTAssertGreaterThanOrEqual(addressHits, 1)

        var duplicates = 0
        var stableIds = Set<String>()
        var featureIds = Set<String>()
        var locatedNames: [(name: String, point: CLLocation)] = []
        for element in elements {
            let parts = (element.value as? String ?? "").components(separatedBy: "|")
            if let stableId = parts.first, !stableId.isEmpty, !stableIds.insert(stableId).inserted {
                duplicates += 1
            }
            if parts.count >= 5 {
                let featureId = parts[1]
                if !featureId.isEmpty, !featureIds.insert(featureId).inserted { duplicates += 1 }
                if let latitude = Double(parts[parts.count - 2]), let longitude = Double(parts[parts.count - 1]) {
                    locatedNames.append((Self.normalizedName(element.label), CLLocation(latitude: latitude, longitude: longitude)))
                }
            }
        }
        for (index, first) in locatedNames.enumerated() where !first.name.isEmpty {
            for second in locatedNames.dropFirst(index + 1) where first.name == second.name {
                if first.point.distance(from: second.point) < 60 { duplicates += 1 }
            }
        }
        report("dedup_rows", elements.count)
        report("dedup_duplicate_rows", duplicates)
        XCTAssertEqual(duplicates, 0, "duplicate source rows reached the list and its pins")

        app.buttons["search-panel-toggle"].tap()
        sleep(2)
        shot("dedup-search")
    }

    func testPhotonAddressSearchShowsTheTypedHouseNumber() {
        let app = launch(camera: "sf")
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("1 Ferry Building\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no address result: \(messageText(app))")
        XCTAssertTrue(waitUntil(30) {
            rows.allElementsBoundByIndex.contains {
                $0.label.localizedCaseInsensitiveContains("1 Ferry Building") ||
                    ($0.value as? String)?.localizedCaseInsensitiveContains("1 Ferry Building") == true
            }
        }, "neither Google nor Photon returned the typed house number")
        let elements = rows.allElementsBoundByIndex
        let photonRows = elements.filter { ($0.value as? String)?.hasPrefix("photon:") == true }
        report("photon_address_rows", elements.count)
        report("photon_address_hits", photonRows.count)
        shot("search-photon")
        XCTAssertGreaterThanOrEqual(elements.count, 1)
    }

    func testNoGoogleSearchReturnsPhotonRows() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetSettings() }
        openSettings(app)
        setGoogleSwitch(true, in: app)
        app.buttons["settings-done"].tap()

        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Ferry Building\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60),
                      "NoGoogle search returned no Photon row: \(messageText(app))")
        XCTAssertTrue(waitUntil(30) {
            rows.allElementsBoundByIndex.contains { ($0.value as? String)?.hasPrefix("photon:") == true }
        }, "no result came from Photon with Google off")
        let elements = rows.allElementsBoundByIndex
        let photonRows = elements.filter { ($0.value as? String)?.hasPrefix("photon:") == true }
        report("nogoogle_photon_rows", elements.count)
        report("nogoogle_photon_hits", photonRows.count)
        report("nogoogle_search_debug", debugText("search-debug") ?? "none")
        shot("search-photon-nogoogle")
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")
    }

    /// The Privacy section is below the fold on an iPhone 17 at the default text size.
    private func setGoogleSwitch(_ on: Bool, in app: XCUIApplication) {
        let toggle = app.descendants(matching: .any)["settings-no-google"]
        for _ in 0..<5 where !toggle.isHittable {
            if app.scrollViews.firstMatch.exists { app.scrollViews.firstMatch.swipeUp() } else { app.swipeUp() }
        }
        let target = on ? "1" : "0"
        if String(describing: toggle.value ?? "") != target { toggle.tap() }
        if !waitUntil(2, { String(describing: toggle.value ?? "") == target }),
           String(describing: toggle.value ?? "") != target {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitUntil(10) { String(describing: toggle.value ?? "") == target },
                      "Google switch did not change: \(String(describing: toggle.value ?? "none"))")
    }

    private func resetSettings() {
        let clean = XCUIApplication()
        clean.launchArguments = ["-VelaResetSettings", "YES", "-VelaDeterministic", "YES"]
        clean.launch()
        clean.terminate()
    }

    private static func normalizedName(_ value: String) -> String {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func messageText(_ app: XCUIApplication) -> String {
        let message = app.staticTexts["search-message"]
        return message.exists ? message.label : "no message"
    }
}
