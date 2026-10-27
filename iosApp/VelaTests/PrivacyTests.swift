import WebKit
import XCTest
import VelaCore
@testable import Vela

/// The privacy rules with no network: the rotation schedule, the Google-host predicate the request
/// counter uses, the page-telemetry rule list, and the diagnostics redaction.
final class PrivacyTests: XCTestCase {
    override func tearDown() {
        GoogleRequestCounter.reset()
        super.tearDown()
    }

    func testRotationModesAndPeriods() {
        XCTAssertEqual(PrivacyPolicy.shared.normalizeRotation(mode: "nonsense"), "week")
        XCTAssertEqual(PrivacyPolicy.shared.rotationPeriodMillis(mode: "day"), 86_400_000)
        XCTAssertEqual(PrivacyPolicy.shared.rotationPeriodMillis(mode: "week"), 604_800_000)
        XCTAssertEqual(PrivacyPolicy.shared.rotationPeriodMillis(mode: "launch"), 0)
        let started: Int64 = 1_000_000
        XCTAssertFalse(PrivacyPolicy.shared.isRotationDue(mode: "week", startedMs: started,
                                                          nowMs: started + 604_800_000 - 1))
        XCTAssertTrue(PrivacyPolicy.shared.isRotationDue(mode: "week", startedMs: started,
                                                         nowMs: started + 604_800_000))
        XCTAssertTrue(PrivacyPolicy.shared.isRotationDue(mode: "launch", startedMs: started, nowMs: started))
        XCTAssertFalse(PrivacyPolicy.shared.isRotationDue(mode: "week", startedMs: 0, nowMs: started))
    }

    func testTheCounterCountsGoogleHostsOnly() {
        GoogleRequestCounter.reset()
        GoogleRequestCounter.noteSent("www.google.com")
        GoogleRequestCounter.noteSent("maps.googleapis.com")
        GoogleRequestCounter.noteSent("photon.komoot.io")
        GoogleRequestCounter.noteBlocked("play.google.com")
        GoogleRequestCounter.noteBlocked("example.com")
        XCTAssertEqual(GoogleRequestCounter.sent, 2)
        XCTAssertEqual(GoogleRequestCounter.blocked, 1)
    }

    func testTelemetryRulesParseAndCompile() throws {
        let json = PrivacyPolicy.shared.telemetryRulesJson()
        let rules = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(rules.count, 3)
        for rule in rules {
            let action = try XCTUnwrap(rule["action"] as? [String: Any])
            XCTAssertEqual(action["type"] as? String, "block")
            let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
            XCTAssertNotNil(trigger["url-filter"] as? String)
        }
        let compiled = expectation(description: "compiled")
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "vela-google-telemetry-test", encodedContentRuleList: json
        ) { list, error in
            XCTAssertNil(error)
            XCTAssertNotNil(list)
            compiled.fulfill()
        }
        wait(for: [compiled], timeout: 20)
    }

    func testDiagnosticsNeverCarryACoordinateQueryOrName() {
        let report = PrivacyPolicy.shared.diagnosticsReport(
            appVersion: "0.1.1", buildNumber: "7", calibrationVersion: 27,
            flags: ["no_google=1"],
            logLines: ["open https://www.google.com/maps/place/x?pb=secret at 37.7749,-122.4194 \"Ferry Building\""])
        XCTAssertTrue(report.contains("calibration: 27"))
        XCTAssertTrue(report.contains("no_google=1"))
        XCTAssertFalse(report.contains("pb=secret"))
        XCTAssertFalse(report.contains("37.7749"))
        XCTAssertFalse(report.contains("Ferry Building"))
    }
}
