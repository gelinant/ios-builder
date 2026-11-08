import WebKit
import XCTest
@testable import Vela

final class WebTests: XCTestCase {
    func testBlockedHostsCompileAsAContentRuleList() throws {
        let json = HiddenWebView.blockedHostsRules()
        let rules = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(rules.count, 12)
        let compiled = expectation(description: "compiled")
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "vela-blocked-hosts-test", encodedContentRuleList: json
        ) { list, error in
            XCTAssertNil(error)
            XCTAssertNotNil(list)
            compiled.fulfill()
        }
        wait(for: [compiled], timeout: 20)
    }

    func testBridgeNamesAreSwappedForRandomOnes() {
        let js = HiddenWebView.jsNames("VelaBridge.onResult(ID, x); VelaPanel.ready()")
        XCTAssertFalse(js.contains("VelaBridge"))
        XCTAssertFalse(js.contains("VelaPanel"))
        XCTAssertTrue(js.contains("\(HiddenWebView.bridgeName).onResult(ID, x)"))
        XCTAssertEqual(HiddenWebView.bridgeName.count, 11)
    }

    func testTheSheetShowsTheSiteHost() {
        XCTAssertEqual(PlaceSheet.shortHost("https://www.davisfood.coop/hours"), "davisfood.coop")
        XCTAssertEqual(PlaceSheet.shortHost("not a url"), "not a url")
    }
}
