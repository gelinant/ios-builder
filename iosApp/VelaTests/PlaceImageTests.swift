import UIKit
import XCTest
@testable import Vela

final class PlaceImageTests: XCTestCase {
    func testColorSrgbPngKeepsItsPixelsThroughUIImageView() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120), format: format)
        let source = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
            UIColor(red: 0.12, green: 0.58, blue: 0.86, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 112, height: 112)).fill()
            UIColor(red: 0.95, green: 0.72, blue: 0.16, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 38, y: 38, width: 44, height: 44)).fill()
        }
        let png = try XCTUnwrap(source.pngData())
        let decoded = try XCTUnwrap(UIImage(data: png))
        let stats = ImagePixels.stats(decoded)
        XCTAssertGreaterThan(stats.visible, 2_500)
        XCTAssertGreaterThan(stats.nonBlack, 2_500)
        XCTAssertGreaterThan(stats.colorful, 2_500)

        // This is the display path used by RemoteAvatarImage: original rendering, no template tint.
        let view = UIImageView(image: decoded.withRenderingMode(.alwaysOriginal))
        let displayed = try XCTUnwrap(view.image)
        XCTAssertTrue(ImagePixels.hasNonBlackPixel(displayed))
        XCTAssertGreaterThan(ImagePixels.stats(displayed).colorful, 2_500)
    }

    func testFullyBlackTransparentAvatarDoesNotCountAsVisibleColor() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120))
        let black = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }
        let decoded = try XCTUnwrap(UIImage(data: XCTUnwrap(black.pngData())))
        XCTAssertEqual(ImagePixels.stats(decoded).nonBlack, 0)
    }
}
