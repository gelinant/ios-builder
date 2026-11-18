import XCTest

/// SRCH-FILTER on the simulator: the results header's filter sheet narrows the list to a rating
/// floor, then the distance sort reorders what is left. The screenshots show the sheet and the
/// filtered cards. Assertions read the cards' real accessibility labels, not debug-only values.
final class SearchFiltersUITests: VelaUITestCase {
    func testFiltersAndSort() throws {
        let app = launch(camera: "sf")
        sleep(6)
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row: \(messageText(app))")
        XCTAssertTrue(waitUntil(30) { rows.count >= 5 }, "fewer than 5 results to filter")
        let before = settledCount(rows)
        report("filter_baseline_rows", before)

        let filters = app.buttons["search-filters-open"]
        XCTAssertTrue(filters.waitForExistence(timeout: 10), "no filter button on the results header")
        filters.tap()

        let rating = app.buttons["search-filter-rating-40"]
        XCTAssertTrue(rating.waitForExistence(timeout: 10), "the filter sheet did not open")
        rating.tap()
        sleep(1)
        shot("search-filter-sheet")
        app.buttons["search-filters-done"].tap()
        XCTAssertTrue(waitUntil(15) { app.buttons["search-filters-open"].isHittable },
                      "the filter sheet stayed open")

        XCTAssertTrue(waitUntil(30) { rows.count > 0 }, "the 4.0 floor emptied the list")
        let filtered = settledCount(rows)
        report("filter_rows_after_rating", filtered)
        XCTAssertLessThanOrEqual(filtered, before, "the rating floor added rows")
        let ratings = rows.allElementsBoundByIndex.compactMap { Self.rating($0.label) }
        XCTAssertEqual(ratings.count, filtered, "a card carried no rating: "
            + rows.allElementsBoundByIndex.map { $0.label }.joined(separator: " / "))
        XCTAssertTrue(ratings.allSatisfy { $0 >= 3.99 }, "a card below the 4.0 floor stayed: \(ratings)")
        XCTAssertTrue(app.staticTexts["search-filter-summary"].exists, "the header did not say the filter")
        shot("search-filtered")

        filters.tap()
        let sort = app.segmentedControls["search-filter-sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10), "no sort control in the sheet")
        if sort.buttons["Distance"].exists {
            sort.buttons["Distance"].tap()
        } else {
            app.buttons["Distance"].tap()
        }
        app.buttons["search-filters-done"].tap()
        XCTAssertTrue(waitUntil(15) { app.buttons["search-filters-open"].isHittable },
                      "the filter sheet stayed open after choosing the sort")

        XCTAssertTrue(waitUntil(20) { rows.count > 0 }, "the distance sort emptied the list")
        sleep(1)
        let distances = rows.allElementsBoundByIndex.compactMap { Self.distanceMeters($0.label) }
        report("filter_sorted_rows", rows.count)
        report("filter_sorted_first_m", distances.first ?? -1)
        report("filter_sorted_last_m", distances.last ?? -1)
        XCTAssertGreaterThanOrEqual(distances.count, min(2, rows.count),
                                    "the cards carried no distance: "
            + rows.allElementsBoundByIndex.map { $0.label }.joined(separator: " / "))
        for pair in zip(distances, distances.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0, pair.1 + 1, "distance sort is out of order: \(distances)")
        }
    }

    /// The later pages land with the first; wait for the list to settle before counting.
    private func settledCount(_ rows: XCUIElementQuery) -> Int {
        var count = rows.count
        let until = Date().addingTimeInterval(8)
        while Date() < until {
            sleep(1)
            let now = rows.count
            if now == count && now > 0 { break }
            count = now
        }
        return rows.count
    }

    /// "Fixture Coffee, 4.5 stars, 120 reviews, ..." to the rating.
    private static func rating(_ label: String) -> Double? {
        guard let match = label.range(of: #"(\d\.\d) stars"#, options: .regularExpression) else { return nil }
        return Double(label[match].replacingOccurrences(of: " stars", with: ""))
    }

    /// The card's distance ("350 m", "1.2 km", "900 ft", "1.1 mi") in meters.
    private static func distanceMeters(_ label: String) -> Double? {
        guard let match = label.range(of: #"\d+(?:\.\d+)? (?:m|km|ft|mi)\b"#,
                                      options: .regularExpression) else { return nil }
        let parts = label[match].split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        switch parts[1] {
        case "km": return value * 1000
        case "ft": return value / 3.28084
        case "mi": return value * 1609.344
        default: return value
        }
    }

    private func messageText(_ app: XCUIApplication) -> String {
        let message = app.staticTexts["search-message"]
        return message.exists ? message.label : "no message"
    }
}
