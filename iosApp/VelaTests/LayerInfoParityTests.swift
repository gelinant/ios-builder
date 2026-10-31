import XCTest
@testable import Vela

/// LAYER-INFO: the map symbol and the info card read one field list per layer. These tests compare
/// the two lists, the rendered terms and the units, so a field added on one side only fails here
/// instead of drifting in the app. One test per layer named by the lot, plus the legend contract.
final class LayerInfoParityTests: XCTestCase {
    private func assertParity(_ id: LayerInfoID) {
        let contract = LayerInfoCatalog.contract(id)
        XCTAssertEqual(contract.mapFieldIDs, contract.infoFieldIDs,
                       "\(id.rawValue): map and info fields differ")
        XCTAssertEqual(Set(contract.fields.map(\.id)).count, contract.fields.count,
                       "\(id.rawValue): duplicate field id")
        XCTAssertFalse(contract.fields.contains(where: { $0.id.isEmpty }),
                       "\(id.rawValue): empty field id")

        let values = contract.fields.map {
            LayerInfoValue(id: $0.id, text: "v-\($0.id)", unit: $0.unit)
        }
        let label = contract.mapLabel(values)
        let lines = contract.infoLines(values)
        XCTAssertEqual(lines.count, contract.fields.count,
                       "\(id.rawValue): info surface misses a field")
        for line in lines {
            XCTAssertTrue(label.contains(line.text),
                          "\(id.rawValue): map label misses \(line.id)")
        }

        let units = Set(contract.fields.map(\.unit))
        for unit in units where !unit.isEmpty {
            XCTAssertTrue(label.contains(unit), "\(id.rawValue): map misses unit \(unit)")
            XCTAssertTrue(lines.contains(where: { $0.text.contains(unit) }),
                          "\(id.rawValue): info misses unit \(unit)")
        }
    }

    func testAviationParity() { assertParity(.aviation) }
    func testMaritimeParity() { assertParity(.maritime) }
    func testEnergyParity() { assertParity(.energy) }
    func testRadarParity() { assertParity(.radar) }
    func testSatelliteParity() { assertParity(.satellite) }
    func testWikiParity() { assertParity(.wiki) }
    func testCamerasParity() { assertParity(.cameras) }
    func testTransitParity() { assertParity(.transit) }
    func testTrafficParity() { assertParity(.traffic) }

    func testEveryLegendLayerIsParityClean() {
        XCTAssertTrue(LayerInfoParity.failures().isEmpty,
                      LayerInfoParity.failures().joined(separator: "; "))
        XCTAssertTrue(LayerInfoParity.renderFailures().isEmpty,
                      LayerInfoParity.renderFailures().joined(separator: "; "))
    }

    func testAgeRuleUsesRelativeLiveAbsoluteScheduleAndNoData() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(LayerAge.text(updatedAt: nil, freshness: .live, now: now),
                       VelaL10n.text("layer_no_data", language: "en"))
        XCTAssertEqual(
            LayerAge.text(updatedAt: now.addingTimeInterval(-125), freshness: .live, now: now),
            VelaL10n.text("layer_age_minutes", language: "en", 2))
        let scheduled = now.addingTimeInterval(-3_600)
        let absolute = LayerAge.text(updatedAt: scheduled, freshness: .schedule, now: now)
        XCTAssertTrue(absolute.contains(":"), "a schedule must show an absolute clock: \(absolute)")
    }
}
