import UIKit
import XCTest

/// SAV-MARK: saved places and lists on the map. Two lists and a drawing list are imported through
/// the real Saved importer, then the screenshots and the pixel counts prove the list colours, the
/// shrink between a neighbourhood zoom and a city zoom, and a drawn line's colour. A tap on a pin
/// opens the saved place, and the list screen edits the line's name.
final class SavedMapUITests: VelaUITestCase {
    /// List places carry their list's purple, one carries its own teal, and the drawing list is
    /// magenta so no basemap or chrome colour can be mistaken for it.
    private let fixture = """
    [{"id":"list:savmark:pins","name":"SAV Map Pins","icon":"star.fill","color":4287837414,\
    "places":[\
    {"id":"savmark:centre","name":"SAV Pins Centre","lat":37.7749,"lng":-122.4194,"address":"Market St"},\
    {"id":"savmark:emoji","name":"SAV Pins Emoji","lat":37.779,"lng":-122.414,"icon":"emoji:☕","color":4278225275}]},\
    {"id":"list:savmark:drawings","name":"SAV Map Drawings","icon":"bookmark","color":4294902015,\
    "shapes":[\
    {"name":"SAV Line","pts":[37.781,-122.434,37.769,-122.404],"closed":false,"color":4294902015,"width":8},\
    {"name":"SAV Area","pts":[37.779,-122.424,37.779,-122.414,37.772,-122.414,37.772,-122.424],"closed":true,\
    "color":4294902015,"width":4,"fill":1090453759}]},\
    {"id":"list:savmark:edit","name":"SAV Map Edit","icon":"bookmark","color":4279923688,\
    "shapes":[{"name":"SAV Editable","pts":[37.777,-122.42,37.773,-122.418],"closed":false,"color":4279923688,"width":3}]}]
    """

    private let purple = RGB(0x93, 0x34, 0xE6)
    private let teal = RGB(0x00, 0x89, 0x7B)
    private let magenta = RGB(0xFF, 0x00, 0xFF)

    func testPinsShowTheirListColoursShrinkFarOutAndOpenThePlace() {
        let close = launch(camera: "37.7749,-122.4194,15", arguments: ["-VelaSavedFixtureText", fixture])
        importFixture(close)
        let closeShot = waitForPixels(purple, minimum: 400)
        XCTAssertNotNil(closeShot, "the saved pins never drew in their list colour")
        sleep(2)
        shot("saved-map-pins")
        let closePurple = pixels(XCUIScreen.main.screenshot(), of: purple)
        let closeTeal = pixels(XCUIScreen.main.screenshot(), of: teal)
        XCTAssertGreaterThan(closeTeal, 0, "the place's own colour did not win over its list's")
        report("saved_map_pins_close", closePurple)
        report("saved_map_pin_own_colour", closeTeal)

        // The pin at the camera centre is "SAV Pins Centre"; picking it opens its saved place.
        close.otherElements["map"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(close.staticTexts["place-name"].waitForExistence(timeout: 20), "a saved pin opened no place")
        XCTAssertEqual(close.staticTexts["place-name"].label, "SAV Pins Centre")
        report("saved_map_pin_tap", "place-opened")
        shot("saved-map-place")
        close.buttons["place-close"].tap()

        // Same camera centre and lists, one city zoom out: the pin is less than half its size.
        close.terminate()
        launch(camera: "37.7749,-122.4194,11")
        let farShot = waitForPixels(purple, minimum: 20)
        XCTAssertNotNil(farShot, "the pins did not survive the far zoom")
        sleep(2)
        shot("saved-map-pins-far")
        let farPurple = pixels(XCUIScreen.main.screenshot(), of: purple)
        report("saved_map_pins_far", farPurple)
        XCTAssertGreaterThan(farPurple, 20, "no pin colour at the far zoom")
        XCTAssertGreaterThan(closePurple, farPurple * 2, "the pins did not shrink far out")
    }

    func testDrawnShapesDrawAndTheirListEditorRenamesOne() {
        let app = launch(camera: "37.775,-122.419,15", arguments: ["-VelaSavedFixtureText", fixture])
        importFixture(app)
        let shapeShot = waitForPixels(magenta, minimum: 400)
        XCTAssertNotNil(shapeShot, "the drawn line never reached the map")
        sleep(2)
        shot("saved-map-shape")
        let close = pixels(XCUIScreen.main.screenshot(), of: magenta)
        report("saved_map_shape", close)
        XCTAssertGreaterThan(close, 400)

        // The line keeps drawing at a far zoom, where its name is not shown (label zoom 12).
        app.terminate()
        launch(camera: "37.775,-122.419,11")
        XCTAssertNotNil(waitForPixels(magenta, minimum: 100), "the line vanished at the far zoom")
        shot("saved-map-shape-far")

        // The list screen lists the shape and renames it; deleting the throwaway list at the end
        // makes the next run import the same fixture again.
        openMapAction("saved-open", in: app)
        let pins = app.buttons["SAV Map Pins, 2 places"]
        XCTAssertTrue(reveal(pins, in: app), "the imported lists are missing")
        let edit = app.buttons["SAV Map Edit, 0 places"]
        XCTAssertTrue(reveal(edit, in: app), "the drawing list is missing")
        edit.tap()
        XCTAssertTrue(app.staticTexts["Lines and areas"].waitForExistence(timeout: 5), "no shapes section")
        XCTAssertTrue(app.staticTexts["SAV Editable"].exists, "the list does not show its line")
        shot("saved-map-shape-editor")
        app.buttons["saved-shape-actions"].firstMatch.tap()
        let rename = app.buttons["Rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "no shape actions")
        rename.tap()
        let field = app.textFields["saved-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no rename sheet")
        replaceText(in: field, with: "SAV Edited")
        app.buttons["saved-name-save"].tap()
        XCTAssertTrue(waitUntil(5) { app.staticTexts["SAV Edited"].exists }, "the shape kept its old name")
        report("saved_map_shape_edit", "renamed")

        app.navigationBars.buttons.firstMatch.tap()
        let row = app.buttons.matching(identifier: "saved-list")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "SAV Map Edit")).firstMatch
        XCTAssertTrue(reveal(row, in: app), "no throwaway list to clean up")
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "no delete action")
        delete.tap()
        app.buttons["saved-close"].tap()
    }

    /// The fixture arrives through SavedTestSupport when the sheet first appears, exactly as the
    /// Takeout and export fixtures do.
    private func importFixture(_ app: XCUIApplication) {
        openMapAction("saved-open", in: app)
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 10), "Saved did not open")
        XCTAssertTrue(reveal(app.buttons["SAV Map Pins, 2 places"], in: app),
                      "the saved fixture never imported")
        app.buttons["saved-close"].tap()
    }

    private struct RGB: Equatable {
        let r: Int
        let g: Int
        let b: Int

        init(_ r: Int, _ g: Int, _ b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    /// Screenshots until at least [minimum] pixels carry [color], so the map has drawn the pins.
    private func waitForPixels(_ color: RGB, minimum: Int, timeout: TimeInterval = 60) -> XCUIScreenshot? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            let shot = XCUIScreen.main.screenshot()
            if pixels(shot, of: color) >= minimum { return shot }
            usleep(1_000_000)
        } while Date() < end
        return nil
    }

    /// Counts the screenshot's pixels within a small tolerance of [color]. The map's own palette,
    /// the chrome and the pins' white ring all stay outside that tolerance.
    private func pixels(_ shot: XCUIScreenshot, of color: RGB, tolerance: Int = 8) -> Int {
        guard let image = shot.image.cgImage else { return 0 }
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        var index = 0
        while index + 2 < data.count {
            if abs(Int(data[index]) - color.r) <= tolerance,
               abs(Int(data[index + 1]) - color.g) <= tolerance,
               abs(Int(data[index + 2]) - color.b) <= tolerance {
                count += 1
            }
            index += 4
        }
        return count
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            if up { app.swipeUp() } else { app.swipeDown() }
            usleep(300_000)
        }
        return element.exists
    }
}
