import XCTest
@testable import Vela

/// The wording of the picker's two travel-hint rows and the navigation banner's closing line.
/// The stores' own lifecycle is proven on the JVM; here only the clock and the sentences are
/// fixed, so a midnight crossing and a 24-hour device stay readable.
final class FuelWireTests: XCTestCase {
    private let gb = Locale(identifier: "en_GB")

    func testClockFollowsTheDeviceFormat() {
        XCTAssertEqual(TravelHintText.clock(17 * 60 + 5, locale: gb), "17:05")
        XCTAssertEqual(TravelHintText.clock(0, locale: gb), "00:00")
        XCTAssertEqual(TravelHintText.clock(24 * 60, locale: gb), "00:00")
    }

    func testClosingSentenceNamesBothHours() {
        XCTAssertEqual(
            TravelHintText.closing(
                name: "Co-op", closesAtMinuteOfDay: 17 * 60, arrivesAtMinuteOfDay: 17 * 60 + 40,
                beforeArrival: false, locale: gb),
            "Co-op closes at 17:00 and you arrive around 17:40")
        XCTAssertEqual(
            TravelHintText.closing(
                name: "Diner", closesAtMinuteOfDay: 23 * 60 + 50, arrivesAtMinuteOfDay: 5,
                beforeArrival: true, locale: gb),
            "Diner closes at 23:50, before you arrive around 00:05")
        XCTAssertEqual(
            TravelHintText.closing(
                name: "", closesAtMinuteOfDay: 9 * 60, arrivesAtMinuteOfDay: 8 * 60 + 30,
                beforeArrival: false, locale: gb),
            "The destination closes at 09:00 and you arrive around 08:30")
    }

    func testFuelDetourSentenceCarriesBrandPriceAndDistance() {
        XCTAssertEqual(
            TravelHintText.fuelDetour(brand: "TESCO", price: "169.9p/E10 · 189.9p/B7", meters: 40),
            "Cheaper fuel on the route: TESCO, 169.9p/E10 · 189.9p/B7, 40 m off the route")
        XCTAssertEqual(
            TravelHintText.fuelDetour(brand: nil, price: "169.9p/E10", meters: 900),
            "Cheaper fuel on the route: 169.9p/E10, 0.9 km off the route")
    }
}
