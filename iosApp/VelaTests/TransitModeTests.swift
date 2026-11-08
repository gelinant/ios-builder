import Foundation
import XCTest
import VelaCore
@testable import Vela

/// TRANSIT-MODES: every leg names its vehicle, and the whole itinerary, transfer included, stays
/// in travel order. The fixture is a real Transitous reply (Paris, Hôtel de Ville to La Défense):
/// walk, Metro 1, transfer walk, RER A, final walk. It is parsed by the production parser.
final class TransitModeTests: XCTestCase {
    private func parisTransfer() throws -> TransitItinerary {
        let bundle = Bundle(for: TransitModel.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "paris-transfer-plan", withExtension: "json")
                ?? bundle.url(forResource: "paris-transfer-plan", withExtension: "json", subdirectory: "Fixtures"),
            "the recorded plan is not in the app bundle")
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let trips = Transitous.shared.parsePlanForFixture(
            json: json,
            originLat: 48.8566, originLng: 2.3522,
            destinationLat: 48.8974, destinationLng: 2.2385)
        return try XCTUnwrap(trips.first, "the recorded reply parsed to no trip")
    }

    // MARK: Mode mapping

    func testModesComeFromThePlannerModeAndTheAgency() {
        XCTAssertEqual(TransitLegMode.of(kind: "WALK").name, "Walk")
        XCTAssertEqual(TransitLegMode.of(kind: "BUS").title(line: "38", agency: nil), "Bus 38")
        XCTAssertEqual(TransitLegMode.of(kind: "SUBWAY").title(line: "2", agency: nil), "M2")
        XCTAssertEqual(TransitLegMode.of(kind: "TRAM").title(line: "K", agency: nil), "Tram K")
        XCTAssertEqual(TransitLegMode.of(kind: "REGIONAL_RAIL").title(line: "B", agency: "RER"), "RER B")
        XCTAssertEqual(TransitLegMode.of(kind: "COACH").title(line: "15", agency: nil), "Coach 15")
        XCTAssertEqual(TransitLegMode.of(kind: "FERRY").title(line: "1", agency: nil), "Ferry 1")
        XCTAssertEqual(TransitLegMode.of(kind: "CABLE_CAR").name, "Cable car")
        XCTAssertEqual(TransitLegMode.of(kind: "FUNICULAR").name, "Funicular")
        XCTAssertEqual(TransitLegMode.of(kind: "HIGHSPEED_RAIL").name, "Rail")
        // A mode the planner leaves generic says Transit and never invents a vehicle.
        XCTAssertEqual(TransitLegMode.of(kind: nil).title(line: nil, agency: nil), "Transit")
        XCTAssertEqual(TransitLegMode.of(kind: "GENERIC").title(line: "42", agency: "Some Agency"), "Transit 42")
    }

    func testGlyphsAreDistinctPerVehicle() {
        let symbols = ["WALK", "BUS", "TRAM", "SUBWAY", "RAIL", "FERRY"]
            .map { TransitLegMode.of(kind: $0).symbol }
        XCTAssertEqual(Set(symbols).count, symbols.count, "two vehicles share one glyph")
    }

    // MARK: Whole itinerary

    func testTheWholeTwoLegTripIsInTravelOrder() throws {
        let trip = try parisTransfer()
        let detail = try XCTUnwrap(TransitDetail(trip))
        XCTAssertEqual(detail.legs.count, 5, "the transfer reply lost a leg")
        XCTAssertEqual(detail.rides.count, 2, "the reply has two rides")
        XCTAssertEqual(detail.transferCount, 1)
        XCTAssertEqual(
            detail.legs.map(\.title),
            ["Walk", "M1", "Walk", "RER A", "Walk"])
        XCTAssertEqual(
            detail.legs.map { $0.isWalk },
            [true, false, true, false, true])
        XCTAssertEqual(detail.modeSequence, "Walk · M1 · Walk · RER A · Walk")
        // Board and alight are the planner's stops, in order.
        XCTAssertEqual(detail.legs[1].board?.name, "Hôtel de Ville")
        XCTAssertEqual(detail.legs[1].alight?.name, "Charles de Gaulle - Étoile")
        XCTAssertEqual(detail.legs[3].board?.name, "Charles de Gaulle - Étoile")
        XCTAssertEqual(detail.legs[3].alight?.name, "La Défense")
    }

    func testTransferWaitComesFromTheFeedsClocks() throws {
        let trip = try parisTransfer()
        let detail = try XCTUnwrap(TransitDetail(trip))
        let metro = detail.legs[1]
        // 13:43 arrival at Étoile, 13:46 RER A departure: three minutes, never an estimate.
        XCTAssertEqual(detail.waitMinutes(after: metro), 3)
        // The final walk has no next ride, so it has no wait.
        XCTAssertNil(detail.waitMinutes(after: detail.legs[3]))
    }

    func testGenericModeNeverBecomesAVehicle() {
        let mode = TransitLegMode.of(kind: nil)
        XCTAssertEqual(mode.title(line: nil, agency: "Operator"), "Transit")
        XCTAssertEqual(mode.subtitle(line: nil, agency: "Operator"), "Transit · Operator")
    }
}
