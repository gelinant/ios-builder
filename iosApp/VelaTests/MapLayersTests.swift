import XCTest
@testable import Vela

/// The layer overlays must stay source-local: a downloaded offline style has no remote URL, and an
/// overlay that added one would silently break that promise.
final class MapLayersTests: XCTestCase {
    func testEveryOverlaySourceIsLocal() {
        XCTAssertFalse(MapLayers.sourceIdentifiers.isEmpty)
        for id in MapLayers.sourceIdentifiers {
            XCTAssertFalse(id.contains("http"), "remote source \(id)")
            XCTAssertFalse(id.contains("://"), "remote source \(id)")
        }
    }

    func testFuelLabelShowsThePencePrice() {
        let model = LayersModel(session: nil)
        let text = model.fuelTextForTest(brand: "Shell", e10: 145.9, e5: 152.0, b7p: 170.0)
        XCTAssertEqual(text, "Shell 145.9p")
    }
}
