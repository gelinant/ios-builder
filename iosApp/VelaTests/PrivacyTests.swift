import WebKit
import XCTest
import VelaCore
@testable import Vela

/// The privacy rules with no network: the rotation schedule, the Google-host predicate the request
/// counter uses, the page-telemetry rule list, and the diagnostics redaction.
final class PrivacyTests: XCTestCase {
    override func tearDown() {
        PrivacyRequestCounter.clear()
        UserDefaults(suiteName: SettingsPersistence.settingsSuite)?
            .removeObject(forKey: PrivacyRequestCounter.defaultsKey)
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

    func testConsentGateBlocksGoogleBeforeTheAnswer() {
        XCTAssertFalse(PrivacyConsent.shared.googleAllowed(welcomeDone: false, noGoogle: false))
        XCTAssertFalse(PrivacyConsent.shared.googleAllowed(welcomeDone: false, noGoogle: true))
        XCTAssertTrue(PrivacyConsent.shared.googleAllowed(welcomeDone: true, noGoogle: false))
        XCTAssertFalse(PrivacyConsent.shared.googleAllowed(welcomeDone: true, noGoogle: true))
        XCTAssertTrue(PrivacyConsent.shared.needsConsent(welcomeDone: false))
        XCTAssertFalse(PrivacyConsent.shared.needsConsent(welcomeDone: true))
    }

    func testTheCounterCountsPerHostAndSurvivesRelaunch() {
        PrivacyRequestCounter.clear()
        PrivacyRequestCounter.noteSent(URL(string: "https://www.google.com/search?tbm=map&q=x")!)
        PrivacyRequestCounter.noteSent(URL(string: "https://maps.googleapis.com/maps/api/js")!)
        PrivacyRequestCounter.noteSent(URL(string: "https://photon.komoot.io/api?q=x")!)
        PrivacyRequestCounter.noteBlocked(URL(string: "https://play.google.com/log?format=json")!)
        PrivacyRequestCounter.noteBlocked(URL(string: "https://example.com/")!)
        XCTAssertEqual(PrivacyRequestCounter.sentToday, 2, "only Google hosts count")
        XCTAssertEqual(PrivacyRequestCounter.blockedToday, 1)
        let hosts = Dictionary(uniqueKeysWithValues: PrivacyRequestCounter.hostRows.map { ($0.label, $0.week) })
        XCTAssertEqual(hosts["www.google.com"], 1)
        XCTAssertEqual(hosts["maps.googleapis.com"], 1)
        XCTAssertNil(hosts["photon.komoot.io"])
        let purposes = Dictionary(uniqueKeysWithValues: PrivacyRequestCounter.purposeRows.map { ($0.label, $0.week) })
        XCTAssertEqual(purposes["search"], 1)
        XCTAssertEqual(purposes["session"], 1)

        // A relaunch: the saved string goes back into a cold shared counter.
        PrivacyRequestCounter.saveNow()
        VelaCore.GoogleRequestCounter.shared.clear()
        PrivacyRequestCounter.start()
        XCTAssertEqual(PrivacyRequestCounter.sentToday, 2)
        XCTAssertEqual(PrivacyRequestCounter.blockedToday, 1)

        // Clearing the count leaves every other store alone; the saved string goes with it.
        PrivacyRequestCounter.clear()
        XCTAssertEqual(PrivacyRequestCounter.sentToday, 0)
        XCTAssertEqual(PrivacyRequestCounter.purposeRows.count, 0)
        XCTAssertEqual(PrivacyRequestCounter.hostRows.count, 0)
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
