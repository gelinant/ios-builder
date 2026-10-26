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

    private static func normalizedName(_ value: String) -> String {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func messageText(_ app: XCUIApplication) -> String {
        let message = app.staticTexts["search-message"]
        return message.exists ? message.label : "no message"
    }
}
