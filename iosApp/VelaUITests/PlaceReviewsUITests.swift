import XCTest

/// PLC-REVIEW on the recorded Davis place fixture: Google's star histogram in the native reviews
/// panel, More reviews appending another page, and the full-screen gallery viewer with its caption
/// and source. The place, its photos, its reviews and its histogram come from `-VelaPlaceFixture`,
/// so the same counts appear on every runner; nothing here reads a live Google reply.
final class PlaceReviewsUITests: VelaUITestCase {

    func testReviewsHistogramAndControls() throws {
        let scroll = openFixturePlace()
        _ = waitUntil(45) { self.intValue("photos") > 0 }
        let photos = intValue("photos")

        // The entry appears as soon as the listing does; the panel then asks the fixture for the
        // reviews, and its first answer carries the histogram.
        let allReviews = app.buttons.matching(identifier: "place-all-reviews").firstMatch
        XCTAssertTrue(allReviews.waitForExistence(timeout: 90), "no reviews panel entry")
        XCTAssertTrue(reveal(allReviews, in: scroll), "the reviews panel entry is not reachable")
        allReviews.tap()
        XCTAssertTrue(app.buttons["place-reviews-close"].waitForExistence(timeout: 10), "reviews panel did not open")
        XCTAssertTrue(waitUntil(150) { self.intValue("initialLoading", debugID: "place-reviews-debug") == 0 },
                      "reviews load did not finish")

        // The panel opens at the top with the five amber bars Google itself draws. The rows are
        // drawn from Google's counts but are not separate accessibility elements, so the panel's
        // own debug line (histogram=<bars>) and the summary element carry the proof.
        shot("reviews-histogram")
        XCTAssertTrue(waitUntil(20) {
            self.intValue("histogram", debugID: "place-reviews-debug") == 5
        }, "the panel does not carry Google's five-bar histogram")
        for _ in 0..<8 {
            app.swipeDown()
            sleep(1)
        }
        shot("reviews-histogram")
        report("reviews_histogram", intValue("histogram", debugID: "place-reviews-debug"))
        report("history", intValue("histogram", debugID: "place-reviews-debug"))
        report("reviews", intValue("count", debugID: "place-reviews-debug"))
        report("photos", photos)

        // Sort and search are Android's controls for the reviews already loaded.
        let reviews = intValue("count", debugID: "place-reviews-debug")
        if reviews >= 3 {
            XCTAssertTrue(app.buttons["place-review-sort-0"].exists, "no relevant sort")
            XCTAssertTrue(app.buttons["place-review-sort-1"].exists, "no highest sort")
            XCTAssertTrue(app.buttons["place-review-sort-2"].exists, "no lowest sort")
            XCTAssertTrue(app.buttons["place-review-search-toggle"].exists, "no search toggle")
            app.buttons["place-review-sort-1"].tap()
            sleep(1)
            report("reviews_sort", value("sort", debugID: "place-reviews-debug") ?? "?")
            shot("reviews-sorted")
        }
        report("reviews_translated", value("translated", debugID: "place-reviews-debug") ?? "0")
        app.buttons["place-reviews-close"].tap()
    }

    func testMoreReviewsAppendsAPage() throws {
        let scroll = openFixturePlace()

        // The entry appears once the place's reviews have loaded, and the details scrape is now
        // deferred while a full-screen panel is open, so it can take longer than a scroll cycle.
        let allReviews = app.buttons.matching(identifier: "place-all-reviews").firstMatch
        XCTAssertTrue(allReviews.waitForExistence(timeout: 90), "no reviews panel entry")
        XCTAssertTrue(reveal(allReviews, in: scroll), "the reviews panel entry is not reachable")
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
        XCTAssertTrue(more.exists && more.isHittable, "no More reviews button on the fixture page")
        more.tap()
        // The debug line lives at the top of the lazy list; scroll back so its value can be read
        // after the page request completes.
        for _ in 0..<14 where !app.staticTexts["place-reviews-debug"].exists {
            app.swipeDown()
            sleep(1)
        }
        XCTAssertTrue(waitUntil(150) { self.intValue("loading", debugID: "place-reviews-debug") == 0 },
                      "More reviews did not finish")
        let after = intValue("count", debugID: "place-reviews-debug")
        let paging = after > before ? "added-\(after - before)" : "limited"
        shot("reviews-more")
        report("reviews", after)
        report("reviews_initial", before)
        report("reviews_paging", paging)
        report("reviews_after_more", after)
        XCTAssertEqual(before, 12, "the fixture's first page changed")
        XCTAssertEqual(after, 18, "the fixture's second page changed")
        XCTAssertEqual(paging, "added-6", "More reviews did not add the fixture page")
        app.buttons["place-reviews-close"].tap()
    }

    func testSwipeKeepsThePanelResponsive() throws {
        let scroll = openFixturePlace()

        // The entry appears once the place's reviews have loaded, and the details scrape is now
        // deferred while a full-screen panel is open, so it can take longer than a scroll cycle.
        let allReviews = app.buttons.matching(identifier: "place-all-reviews").firstMatch
        XCTAssertTrue(allReviews.waitForExistence(timeout: 90), "no reviews panel entry")
        XCTAssertTrue(reveal(allReviews, in: scroll), "the reviews panel entry is not reachable")
        allReviews.tap()
        XCTAssertTrue(app.buttons["place-reviews-close"].waitForExistence(timeout: 10), "reviews panel did not open")
        XCTAssertTrue(waitUntil(150) { self.intValue("initialLoading", debugID: "place-reviews-debug") == 0 },
                      "reviews load did not finish")

        let panel = app.scrollViews["place-reviews-scroll"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "no reviews scroll view")
        let before = intValue("stall", debugID: "place-reviews-debug")
        XCTAssertGreaterThanOrEqual(before, 0, "no main-loop reading before the swipe")

        // The regression: the first swipe used to leave the app answering no UI query for over a
        // minute (BUG-HUNT P1 item 5). One swipe, then one query that must come back in a second.
        panel.swipeUp()
        let asked = Date()
        let answered = waitUntil(1) { self.app.buttons["place-reviews-close"].exists }
        let answerMs = Int((Date().timeIntervalSince(asked) * 1000).rounded())
        shot("reviews-swipe")

        // The debug line lives at the top of the lazy list; a swipe back brings it on screen.
        for _ in 0..<4 where !app.staticTexts["place-reviews-debug"].exists {
            app.swipeDown()
            sleep(1)
        }
        let after = intValue("stall", debugID: "place-reviews-debug")
        let fps = intValue("fps", debugID: "place-reviews-debug")
        let pages = intValue("pages", debugID: "place-reviews-debug")
        XCTAssertGreaterThanOrEqual(after, 0, "no main-loop reading after the swipe")
        report("mainloop_stall_ms", max(after, 0))
        report("mainloop_stall_before_ms", max(before, 0))
        report("reviews_live_pages", max(pages, 0))
        report("reviews_swipe_answer_ms", answerMs)
        report("reviews_swipe_fps", fps)
        XCTAssertTrue(answered, "the panel did not answer a UI query after the swipe")
        XCTAssertLessThanOrEqual(answerMs, 1000, "the panel took \(answerMs) ms to answer the swipe")
        XCTAssertLessThan(after, 1000, "the main loop stalled \(after) ms after the swipe")
        XCTAssertEqual(pages, 0, "a hidden Google page stayed under the panel")
        app.buttons["place-reviews-close"].tap()
    }

    func testGalleryViewerSwipesWithCaptionAndSource() throws {
        let scroll = openFixturePlace()
        XCTAssertTrue(waitUntil(45) { self.intValue("photos") > 0 }, "no photos loaded")

        let allPhotos = app.buttons.matching(identifier: "place-all-photos").firstMatch
        XCTAssertTrue(allPhotos.waitForExistence(timeout: 60), "no gallery entry")
        XCTAssertTrue(reveal(allPhotos, in: scroll), "the gallery entry is not reachable")
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
        XCTAssertEqual(count, 8, "the fixture gallery changed")
        report("photos", count)
        let counter = app.staticTexts["place-gallery-counter"]
        XCTAssertEqual(counter.label.replacingOccurrences(of: " ", with: ""), "1/8",
                       "the viewer did not open on the first fixture photo")
        app.descendants(matching: .any)["place-photo-viewer"].swipeLeft()
        XCTAssertTrue(waitUntil(10) { counter.label.replacingOccurrences(of: " ", with: "") == "2/8" },
                      "viewer did not swipe to the next photo")
        shot("gallery-viewer-next")
        report("pager", counter.label.replacingOccurrences(of: " ", with: ""))
        app.buttons["place-viewer-close"].tap()
        app.buttons["place-gallery-close"].tap()
    }

    // MARK: Fixture

    /// The recorded Davis place, opened by `-VelaPlaceFixture` without a search or a Google
    /// request, with the sheet's scroll view in hand.
    private func openFixturePlace() -> XCUIElement {
        let app = launch(camera: "davis", arguments: [
            "-VelaPlaceFixture", "YES",
            "-VelaResetSettings", "YES",
        ])
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 60), "no place sheet")
        XCTAssertEqual(app.staticTexts["place-name"].label, "Market Hall",
                       "the place fixture did not open")
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
