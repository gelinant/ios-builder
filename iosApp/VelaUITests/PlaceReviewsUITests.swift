import XCTest

/// PLC-REVIEW on the Davis fixture: Google's star histogram in the native reviews panel, More
/// reviews appending another page, and the full-screen gallery viewer with its caption and source.
/// Google may withhold the histogram or the next page on the runner's address; the scenarios
/// report that and keep the screenshots rather than inventing data.
final class PlaceReviewsUITests: VelaUITestCase {

    func testReviewsHistogramAndControls() throws {
        let scroll = openFixturePlace()

        let allReviews = app.buttons.matching(identifier: "place-all-reviews").firstMatch
        XCTAssertTrue(reveal(allReviews, in: scroll), "no reviews panel entry")
        allReviews.tap()
        XCTAssertTrue(app.buttons["place-reviews-close"].waitForExistence(timeout: 10), "reviews panel did not open")
        XCTAssertTrue(waitUntil(150) { self.intValue("initialLoading", debugID: "place-reviews-debug") == 0 },
                      "reviews load did not finish")

        // The histogram arrives with the gallery walk or the reviews page, never invented here.
        // When the feed's limited view carried no breakdown, More reviews is the user action that
        // asks the page for another batch, and that same scrape reads Google's histogram.
        let fiveStars = app.descendants(matching: .any)["place-histogram-row-5"]
        if !waitUntil(10, { fiveStars.exists }) {
            let more = app.buttons["place-panel-more-reviews"]
            let panel = app.scrollViews["place-reviews-scroll"]
            for _ in 0..<12 where !more.isHittable {
                panel.swipeUp()
                sleep(1)
            }
            if more.exists && more.isHittable {
                more.tap()
                for _ in 0..<12 where !app.staticTexts["place-reviews-debug"].exists {
                    panel.swipeDown()
                    sleep(1)
                }
                _ = waitUntil(150) { self.intValue("loading", debugID: "place-reviews-debug") == 0 }
            }
        }
        let histogramSeen = waitUntil(20) { fiveStars.exists }
        shot("reviews-histogram")
        report("reviews_histogram", histogramSeen ? intValue("histogram", debugID: "place-reviews-debug") : "google-omitted")
        if histogramSeen {
            XCTAssertTrue(app.descendants(matching: .any)["place-histogram-row-1"].exists,
                          "no one-star row in the histogram")
        }

        // Sort and search are Android's controls for the reviews already loaded.
        let reviews = intValue("count", debugID: "place-reviews-debug")
        if reviews >= 3 {
            XCTAssertTrue(app.buttons["place-review-sort-0"].exists, "no relevant sort")
            XCTAssertTrue(app.buttons["place-review-sort-1"].exists, "no highest sort")
            XCTAssertTrue(app.buttons["place-review-sort-2"].exists, "no lowest sort")
            XCTAssertTrue(app.buttons["place-review-search-toggle"].exists, "no search toggle")
            app.buttons["place-review-sort-1"].tap()
            report("reviews_sort", value("sort", debugID: "place-reviews-debug") ?? "?")
            shot("reviews-sorted")
        }
        report("reviews_translated", value("translated", debugID: "place-reviews-debug") ?? "0")
        app.buttons["place-reviews-close"].tap()
    }

    func testMoreReviewsAppendsAPage() throws {
        let scroll = openFixturePlace()

        let allReviews = app.buttons.matching(identifier: "place-all-reviews").firstMatch
        XCTAssertTrue(reveal(allReviews, in: scroll), "no reviews panel entry")
        allReviews.tap()
        XCTAssertTrue(app.buttons["place-reviews-close"].waitForExistence(timeout: 10), "reviews panel did not open")
        XCTAssertTrue(waitUntil(150) { self.intValue("initialLoading", debugID: "place-reviews-debug") == 0 },
                      "reviews load did not finish")

        let before = intValue("count", debugID: "place-reviews-debug")
        let more = app.buttons["place-panel-more-reviews"]
        let panel = app.scrollViews["place-reviews-scroll"]
        for _ in 0..<12 where !more.isHittable {
            panel.swipeUp()
            sleep(1)
        }
        var paging = "no-cursor"
        if more.exists && more.isHittable {
            more.tap()
            paging = "requested"
            // The debug line lives at the top of the lazy list; scroll back so its value can be
            // read after the page request completes.
            for _ in 0..<14 where !app.staticTexts["place-reviews-debug"].exists {
                panel.swipeDown()
                sleep(1)
            }
            XCTAssertTrue(waitUntil(150) { self.intValue("loading", debugID: "place-reviews-debug") == 0 },
                          "More reviews did not finish")
        }
        let after = intValue("count", debugID: "place-reviews-debug")
        if paging == "requested" && after > before {
            paging = "added-\(after - before)"
        } else if paging == "requested" {
            paging = "limited"
        }
        shot("reviews-more")
        report("reviews_initial", before)
        report("reviews_paging", paging)
        report("reviews_after_more", after)
        XCTAssertGreaterThan(after, 0, "no reviews at all")
        app.buttons["place-reviews-close"].tap()
    }

    func testGalleryViewerSwipesWithCaptionAndSource() throws {
        let scroll = openFixturePlace()
        XCTAssertTrue(waitUntil(45) { self.intValue("photos") > 0 }, "no photos loaded")

        let allPhotos = app.buttons.matching(identifier: "place-all-photos").firstMatch
        XCTAssertTrue(reveal(allPhotos, in: scroll), "no gallery entry")
        allPhotos.tap()
        XCTAssertTrue(app.buttons["place-gallery-close"].waitForExistence(timeout: 20), "gallery did not open")

        let categoryMenu = app.buttons["place-photo-category-menu"]
        report("gallery_menu_fallback", categoryMenu.exists ? 1 : 0)
        report("gallery_categories", intValue("categories", debugID: "place-gallery-debug"))
        report("gallery_photos", intValue("count", debugID: "place-gallery-debug"))

        let firstPhoto = app.buttons["place-grid-photo-0"]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 20), "no photo cell")
        firstPhoto.tap()
        XCTAssertTrue(app.buttons["place-viewer-close"].waitForExistence(timeout: 10), "viewer did not open")
        sleep(3)
        shot("gallery-viewer")
        XCTAssertTrue(app.staticTexts["place-viewer-source"].exists, "no photo source")
        XCTAssertTrue(app.descendants(matching: .any)["place-photo-attribution"].exists || app.staticTexts["place-photo-attribution"].exists,
                      "no photo caption")

        let count = intValue("count", debugID: "place-gallery-debug")
        if count > 1 {
            let counter = app.staticTexts["place-gallery-counter"]
            let before = counter.label
            app.descendants(matching: .any)["place-photo-viewer"].swipeLeft()
            XCTAssertTrue(waitUntil(10) { counter.label != before }, "viewer did not swipe to the next photo")
            shot("gallery-viewer-next")
            report("gallery_viewer_page", counter.label.replacingOccurrences(of: " ", with: ""))
        }
        app.buttons["place-viewer-close"].tap()
        app.buttons["place-gallery-close"].tap()
    }

    // MARK: Fixture

    /// Davis Food Co-op from the search field, with the sheet's scroll view in hand.
    private func openFixturePlace() -> XCUIElement {
        let app = launch(camera: "davis")
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("Davis Food Co-op\n")

        let rows = app.buttons.matching(identifier: "search-result")
        if !rows.firstMatch.waitForExistence(timeout: 45) {
            searchField.tap()
            searchField.typeText("\n")
        }
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 45), "no result row")
        sleep(3)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 15), "no place sheet")
        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "no sheet scroll view")
        return scroll
    }

    /// Finds a lazy section without jumping past it: a few swipes one way, then back the other.
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement) -> Bool {
        for _ in 0..<4 {
            if element.isHittable { return true }
            scroll.swipeUp()
            sleep(1)
        }
        for _ in 0..<8 {
            if element.isHittable { return true }
            scroll.swipeDown()
            sleep(1)
        }
        return element.isHittable
    }

    private func value(_ key: String, debugID: String = "place-debug") -> String? {
        guard let line = debugText(debugID) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ key: String, debugID: String = "place-debug") -> Int {
        Int(value(key, debugID: debugID) ?? "") ?? -1
    }
}
