import XCTest

/// TRANSIT-POLISH: a segment time change anchors on the board's own departure for that line at
/// that stop, the detail sheet keeps Close reachable above a long itinerary, and the guidance
/// card wraps Trip, GO and End at AX3 without losing a 44 pt target.
final class TransitPolishUITests: VelaUITestCase {
    private func launchFixture(transfer: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
        ]
        if transfer { app.launchArguments.append("-VelaTransitTransfer") }
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 30), "no transit card")
        return app
    }

    private func openTrip(_ app: XCUIApplication) {
        let open = app.buttons["transit-trip-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "no trip-view button")
        XCTAssertTrue(open.isHittable, "the trip-view button is outside the guidance card")
        open.tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20), "no trip screen")
        XCTAssertTrue(waitUntil(10) { self.value(app, "segments") != nil }, "no trip segments")
    }

    func testSegmentAnchorAndPinnedClose() {
        // The recorded San Francisco fixture rides Tram K. Its board lists that same 9:28 AM run,
        // so a +15 change must anchor on the board's epoch, not on now plus fifteen minutes.
        let app = launchFixture()
        openTrip(app)
        let ride = app.buttons.matching(identifier: "transit-trip-segment")
            .matching(NSPredicate(format: "label CONTAINS 'Tram K'"))
        XCTAssertTrue(ride.firstMatch.waitForExistence(timeout: 10), "no K ride card")
        let scroll = app.scrollViews["transit-trip-scroll"]
        reveal(ride.firstMatch, in: scroll, app: app)
        ride.firstMatch.tap()

        let leaveLater = app.buttons["transit-trip-leave-later"]
        reveal(leaveLater, in: scroll, app: app)
        XCTAssertTrue(leaveLater.isHittable, "the segment actions never came on screen")
        leaveLater.tap()
        let later = app.buttons["transit-trip-later-15"]
        XCTAssertTrue(later.waitForExistence(timeout: 10), "no +15 choice")
        later.tap()
        XCTAssertTrue(waitUntil(15) { self.value(app, "anchor") == "board" },
                      "the segment did not anchor on the board's departure")
        XCTAssertTrue(waitUntil(15) { (self.intValue(app, "options") ?? 0) > 0 },
                      "no new option set from the anchored time")
        let anchor = value(app, "anchor") ?? "?"
        report("anchor_source", anchor == "board" ? "board" : anchor == "now" ? "now" : anchor)
        XCTAssertEqual(anchor, "board", "leave later did not use the board's own departure")
        shot("transit-anchor")
        app.terminate()

        // The five-leg Paris transfer fixture makes the detail sheet longer than its window. The
        // action row must stay pinned, so Close is reachable after the itinerary scrolls.
        let long = launchFixture(transfer: true)
        let openDetail = long.buttons["transit-detail-open"]
        XCTAssertTrue(openDetail.waitForExistence(timeout: 20), "no detail sheet control")
        openDetail.tap()
        let sheet = long.descendants(matching: .any)["steps-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "no transit detail sheet")
        let detailScroll = long.scrollViews["transit-detail-scroll"]
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 10), "no detail scroll view")
        for _ in 0..<8 { detailScroll.swipeUp() }
        let close = long.buttons["steps-close"]
        XCTAssertTrue(close.exists, "the detail sheet lost Close")
        XCTAssertTrue(close.isHittable, "Close sits under the window edge on a long itinerary")
        let window = long.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(close.frame.maxY, window.maxY, "Close is below the window")
        report("detail_close_hittable", close.isHittable ? 1 : 0)
        shot("transit-pinned-close")
        long.terminate()

        // AX3: the card wraps its three actions under the line summary and collapses them to icons.
        // Each one is still a button with a label and at least 44 pt in both directions.
        let ax3 = launchFixture(largeText: true)
        let wrapped = ax3.descendants(matching: .any)["transit-card-actions-wrapped"]
            .firstMatch
        XCTAssertTrue(wrapped.waitForExistence(timeout: 10), "the guidance card did not wrap at AX3")
        let buttons = ["transit-trip-open", "transit-go-open", "transit-end"]
        for identifier in buttons {
            let button = ax3.buttons[identifier]
            XCTAssertTrue(button.exists, "missing guidance action: \(identifier)")
            XCTAssertTrue(button.isHittable, "guidance action outside the card: \(identifier)")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44,
                                        "\(identifier) is below 44 pt at AX3")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44,
                                        "\(identifier) is too narrow at AX3")
            XCTAssertFalse(button.label.isEmpty, "\(identifier) has no VoiceOver label")
        }
        report("card_buttons_wrapped", wrapped.exists ? 1 : 0)
        shot("transit-ax3-card")
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement,
                        app: XCUIApplication, tries: Int = 8) {
        var attempt = 0
        while !element.isHittable && attempt < tries {
            if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
            attempt += 1
        }
    }

    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        let element = app.staticTexts["transit-trip-debug"]
        guard element.exists else { return nil }
        for part in element.label.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ app: XCUIApplication, _ key: String) -> Int? {
        value(app, key).flatMap(Int.init)
    }
}
