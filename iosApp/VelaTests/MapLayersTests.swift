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
        let fuel = MapFuelPoint(
            lat: 51.5, lng: -0.1, brand: "Shell",
            e10Pence: 145.9, e5Pence: 152.0, b7sPence: 160.0, b7pPence: 170.0)
        let model = LayersModel(session: nil)
        let text = model.fuelTextForTest(fuel)
        XCTAssertEqual(text, "Shell 145.9p")
    }
}
