import XCTest

/// AO-1 and AO-2: the place sheet's two link-only rows open Atlas Obscura and Gastro Obscura in
/// the app's Safari sheet. The fixtures open a place without a search or Google request, and the
/// DEBUG accessibility value carries the address because the Safari sheet is a remote process.
final class PlaceObscuraUITests: VelaUITestCase {
    override func setUp() {
        super.setUp()
        // A remote Safari sheet must never hang the runner job: bound the scenario so the script
        // still publishes its log and STATUS.
        executionTimeAllowance = 900
    }

    func testAtlasObscuraLinkOpensWebSheet() throws {
        // A gas station has coordinates and is not food, so only the Atlas row appears.
        let app = launch(camera: "sf", arguments: ["-VelaPlaceFuelFixture", "fuel"])
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 30),
                      "no fixture place sheet")

        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "no place sheet scroll view")
        let atlas = app.buttons["place-obscura-atlas"]
        XCTAssertTrue(reveal(atlas, in: scroll), "no Atlas Obscura row")
        XCTAssertTrue(atlas.label.contains("Atlas Obscura, link only"), "no link-only mention: \(atlas.label)")
        XCTAssertFalse(app.buttons["place-obscura-gastro"].exists,
                       "the Gastro row appeared for a gas station")

        let url = (atlas.value as? String) ?? ""
        XCTAssertTrue(url.hasPrefix("https://www.atlasobscura.com/search?"), "wrong host: \(url)")
        XCTAssertTrue(url.contains("nearby=true"), "no nearby flag: \(url)")
        XCTAssertTrue(url.contains("lat=51.507400&lng=-0.127800"), "wrong point: \(url)")
        XCTAssertFalse(url.contains("/foods/"), "an article path entered the link: \(url)")
        report("obscura_action", "atlas_nearby")
        report("obscura_host", "www.atlasobscura.com")

        sleep(1)
        atlas.tap()
        // iOS 26 runs the Safari sheet in SafariViewService and its default dismiss control is
        // the Close (xmark) style; earlier systems label the same control Done. Either one proves
        // the sheet opened, and the DEBUG value above already proved which address was opened.
        let done = safariDismissButton(app, timeout: 90)
        shot("place-atlas-obscura")
        XCTAssertNotNil(done, "the Safari sheet did not open")
        report("obscura_sheet", done?.label ?? "?")
        dismissSafari(done)
        XCTAssertTrue(waitUntil(10) { atlas.exists }, "the place sheet did not return")
    }

    func testGastroObscuraLinkOpensWebSheet() throws {
        // The branch fixture is a cafe with coordinates, so both rows appear.
        let app = launch(camera: "sf", arguments: ["-VelaPlaceBranchesFixture", "YES"])
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 30),
                      "no fixture place sheet")

        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "no place sheet scroll view")
        let atlas = app.buttons["place-obscura-atlas"]
        let gastro = app.buttons["place-obscura-gastro"]
        XCTAssertTrue(reveal(atlas, in: scroll), "no Atlas Obscura row")
        XCTAssertTrue(reveal(gastro, in: scroll), "no Gastro Obscura row on a cafe")
        XCTAssertTrue(gastro.label.contains("Gastro Obscura, link only"),
                      "no link-only mention: \(gastro.label)")

        let url = (gastro.value as? String) ?? ""
        XCTAssertEqual(url, "https://www.atlasobscura.com/gastro/places", "wrong Gastro link: \(url)")
        XCTAssertFalse(url.contains("lat="), "Gastro was sent a coordinate: \(url)")
        XCTAssertFalse(url.contains("lng="), "Gastro was sent a coordinate: \(url)")
        XCTAssertFalse(url.contains("/foods/"), "an article path entered the link: \(url)")
        report("obscura_action", "gastro_places")

        sleep(1)
        gastro.tap()
        let done = safariDismissButton(app, timeout: 90)
        shot("place-gastro-obscura")
        XCTAssertNotNil(done, "the Safari sheet did not open")
        report("obscura_sheet", done?.label ?? "?")
        dismissSafari(done)
        XCTAssertTrue(waitUntil(10) { gastro.exists }, "the place sheet did not return")
    }

    /// The Safari sheet's dismiss control: Close on iOS 26's xmark default, Done on earlier
    /// systems. It may live in SafariViewService, the host navigation bar, or the app's tree.
    private func safariDismissButton(_ app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let service = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            for label in ["Close", "Done"] {
                let remote = service.buttons[label]
                if remote.exists { return remote }
                let navigation = app.navigationBars.buttons[label]
                if navigation.exists { return navigation }
                let bar = app.otherElements["TopBrowserBar"].buttons[label]
                if bar.exists { return bar }
                // The place sheet behind has its own Close button; never mistake it for Safari's.
                let host = app.buttons.matching(
                    NSPredicate(format: "label == %@ AND identifier != 'place-close'", label)).firstMatch
                if host.exists { return host }
            }
            usleep(500_000)
        }
        return nil
    }

    /// A Done button inside the Safari sheet often refuses a direct tap, so the screen coordinate
    /// of its centre is used, as the framework documents for this out-of-process chrome.
    private func dismissSafari(_ done: XCUIElement?) {
        guard let done else { return }
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if !waitUntil(5, { !done.exists }) {
            app.swipeDown()
        }
    }

    /// Swipes the sheet until the row exists and can be tapped, the way the place sheets reveal a
    /// lazily built section below the action pills.
    @discardableResult
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement) -> Bool {
        for _ in 0..<12 where !(element.exists && element.isHittable) {
            scroll.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
