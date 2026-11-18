import XCTest

/// SRCH-AREA on the simulator: a real finger pan over the results offers "Search this area",
/// the tap re-runs the query from the panned center, and "More results" appends without
/// repeating a place or reordering what is already shown. Needs the network.
final class SearchAreaUITests: VelaUITestCase {
    func testSearchThisAreaAndMoreResults() throws {
        let app = launch(camera: "sf")
        sleep(6)
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row: \(messageText())")
        XCTAssertTrue(waitUntil(45) { self.settle(rows, timeout: 2) >= 5 }, "fewer than 5 results")
        sleep(3)
        // The first answer is not a pan: the button must not be there yet.
        XCTAssertFalse(app.buttons["search-area"].exists,
                       "Search this area appeared without a pan: \(debugText("search-debug") ?? "none")")
        let before = identities(rows)
        let searchesBefore = debugNumber("searches")
        report("search_area_rows_before", before.count)
        report("search_area_searches_before", searchesBefore)

        // A real drag across the map, clear of the search bar and of the results panel.
        drag(horizontal: true)
        if !app.buttons["search-area"].waitForExistence(timeout: 8) {
            // A second, vertical drag for a first one the map may have swallowed while framing.
            drag(horizontal: false)
        }
        let button = app.buttons["search-area"]
        XCTAssertTrue(button.waitForExistence(timeout: 20),
                      "no Search this area after the pan: \(debugText("search-debug") ?? "none")")
        XCTAssertEqual(debugNumber("area"), 1, "the debug line disagrees with the visible button")
        report("search_area_label", button.label)
        shot("search-area-button")

        button.tap()
        XCTAssertTrue(waitUntil(30) { self.debugNumber("area") == 0 }, "the offer survived its own search")
        XCTAssertTrue(waitUntil(60) { self.debugNumber("searches") == searchesBefore + 1 },
                      "the tap did not run a new search")
        XCTAssertTrue(waitUntil(60) { rows.count > 0 && self.settle(rows, timeout: 3) > 0 },
                      "the refreshed search returned no rows: \(messageText())")
        sleep(3)

        let refreshed = identities(rows)
        XCTAssertFalse(refreshed.isEmpty, "the refreshed list is empty")
        XCTAssertEqual(Set(refreshed).count, refreshed.count,
                       "the refreshed list repeats a place: \(refreshed)")
        report("search_area_rows_after", refreshed.count)
        report("search_area_dropped", debugNumber("dropped"))
        report("search_area_debug", debugText("search-debug") ?? "none")
        shot("search-area-refreshed")

        // "More results" must append behind the refreshed list, never repeat or reshuffle it.
        let more = app.buttons["search-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 20),
                      "no More results row after the refresh: \(debugText("search-debug") ?? "none")")
        let list = app.scrollViews.containing(.button, identifier: "search-result").firstMatch
        var scrolls = 0
        // The button closes a list of dozens of tall cards: swipe until it is on screen.
        while !more.isHittable && scrolls < 140 {
            if list.exists { list.swipeUp(velocity: .fast) } else { app.swipeUp() }
            scrolls += 1
        }
        report("search_more_scrolls", scrolls)
        XCTAssertTrue(more.isHittable, "More results never became hittable after \(scrolls) swipes")
        let beforeMore = identities(rows)
        more.tap()
        XCTAssertTrue(waitUntil(60) {
            !app.buttons["search-more-loading"].exists && self.settle(rows, timeout: 2) >= beforeMore.count
        }, "More results did not settle")
        sleep(2)
        let afterMore = identities(rows)
        XCTAssertEqual(Set(afterMore).count, afterMore.count,
                       "More results added a place already on screen")
        XCTAssertEqual(Array(afterMore.prefix(beforeMore.count)), beforeMore,
                       "More results reordered the rows that were already shown")
        report("search_more_rows_before", beforeMore.count)
        report("search_more_rows_after", afterMore.count)
        report("search_more_dropped", debugNumber("dropped"))
    }

    /// A finger drag over the map: horizontal from the right half to the left, or vertical in
    /// the middle. Both stay above the results panel and below the search bar.
    private func drag(horizontal: Bool) {
        let from: CGVector
        let to: CGVector
        if horizontal {
            from = CGVector(dx: 0.78, dy: 0.38)
            to = CGVector(dx: 0.22, dy: 0.38)
        } else {
            from = CGVector(dx: 0.50, dy: 0.44)
            to = CGVector(dx: 0.50, dy: 0.24)
        }
        app.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.15, thenDragTo: app.coordinate(withNormalizedOffset: to))
    }

    /// Polls the card count until it is non-zero and unchanged for two seconds.
    @discardableResult
    private func settle(_ rows: XCUIElementQuery, timeout: TimeInterval) -> Int {
        var last = -1
        var stable = 0
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let now = rows.count
            if now > 0 && now == last {
                stable += 1
                if stable >= 2 { return now }
            } else {
                stable = 0
            }
            last = now
            sleep(1)
        }
        return rows.count
    }

    /// Debug builds expose stable id, feature id, address and point on each card.
    private func identities(_ rows: XCUIElementQuery) -> [String] {
        rows.allElementsBoundByIndex.map { String(describing: $0.value ?? "") }
    }

    /// A number from `search-debug` (`area=1 dropped=0 searches=2`), or -1.
    private func debugNumber(_ key: String) -> Int {
        guard let text = debugText("search-debug") else { return -1 }
        for part in text.split(separator: " ") where part.hasPrefix("\(key)=") {
            return Int(part.dropFirst(key.count + 1)) ?? -1
        }
        return -1
    }

    private func messageText() -> String {
        let message = app.staticTexts["search-message"]
        return message.exists ? message.label : "no message"
    }
}
