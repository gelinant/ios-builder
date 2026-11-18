import XCTest
@testable import Vela

/// The JavaScript and signature seams (SPEC "Platform seams", PORTAGE_IOS.md D6). Each test prints
/// a `SEAM_TEST` line that scripts/ios/ci-ipa.sh copies to the summary.
final class SeamTests: XCTestCase {
    func testJsEngineRunsATransform() {
        let js = JavaScriptCoreJsEngine()
        let source = "function transformPlaces(s) { var a = JSON.parse(s); a.push({name: 'b'}); return JSON.stringify(a); }"
        XCTAssertEqual(js.call(source: source, function: "transformPlaces", argument: "[{\"name\":\"a\"}]", timeLimitMillis: 2000),
                       "[{\"name\":\"a\"},{\"name\":\"b\"}]")
        print("SEAM_TEST js transform: ok")
    }

    func testJsEngineKillsAnEndlessLoopAndStillWorksAfterward() {
        let js = JavaScriptCoreJsEngine()
        let started = Date()
        XCTAssertNil(js.call(source: "function f(s) { while (true) {} }", function: "f", argument: "", timeLimitMillis: 500))
        let killed = Date().timeIntervalSince(started)
        XCTAssertLessThan(killed, 3, "the loop ran \(killed) s")
        // An endless loop at the top level, not only in the call.
        XCTAssertNil(js.call(source: "while (true) {}", function: "f", argument: "", timeLimitMillis: 300))
        XCTAssertEqual(js.call(source: "function f(s) { return s + '!'; }", function: "f", argument: "next", timeLimitMillis: 2000), "next!")
        print("SEAM_TEST js while(true) killed after \(String(format: "%.2f", killed)) s, next call ok")
    }

    func testJsEngineReturnsNilOnErrorsAndOddResults() {
        let js = JavaScriptCoreJsEngine()
        XCTAssertNil(js.call(source: "function f(s) {", function: "f", argument: "x", timeLimitMillis: 1000), "syntax error")
        XCTAssertNil(js.call(source: "function f(s) { throw new Error('x'); }", function: "f", argument: "x", timeLimitMillis: 1000), "throw")
        XCTAssertNil(js.call(source: "var f = 3;", function: "f", argument: "x", timeLimitMillis: 1000), "not a function")
        XCTAssertNil(js.call(source: "", function: "g", argument: "x", timeLimitMillis: 1000), "no such function")
        XCTAssertNil(js.call(source: "function f(s) { return 42; }", function: "f", argument: "x", timeLimitMillis: 1000), "not a string")
        XCTAssertNil(js.call(source: "function f(s) { return '  '; }", function: "f", argument: "x", timeLimitMillis: 1000), "blank")
        // No host objects and no state carried from one call to the next.
        XCTAssertEqual(js.call(source: "function f(s) { return typeof setTimeout + typeof window + typeof XMLHttpRequest; }",
                               function: "f", argument: "", timeLimitMillis: 1000), "undefinedundefinedundefined")
        _ = js.call(source: "var leaked = 'yes'; function f(s) { return s; }", function: "f", argument: "x", timeLimitMillis: 1000)
        XCTAssertEqual(js.call(source: "function f(s) { return typeof leaked; }", function: "f", argument: "", timeLimitMillis: 1000), "undefined")
    }

    func testSignatureVerifiesTheRealCalibrationAndRefusesATamperedByte() throws {
        let bundle = Bundle(for: SeamTests.self)
        let body = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "calibration", withExtension: "json")))
        let sig = try String(contentsOf: XCTUnwrap(bundle.url(forResource: "calibration.json", withExtension: "sig")), encoding: .utf8)
        let key = SecKeySignatureVerifier.pinnedCalibrationKey
        XCTAssertTrue(SecKeySignatureVerifier.verify(body, signatureBase64: sig, publicKeyBase64: key))

        var tampered = body
        tampered[tampered.count / 2] ^= 0x01
        XCTAssertFalse(SecKeySignatureVerifier.verify(tampered, signatureBase64: sig, publicKeyBase64: key))

        var badSig = try XCTUnwrap(Data(base64Encoded: sig.trimmingCharacters(in: .whitespacesAndNewlines)))
        badSig[badSig.count - 1] ^= 0x01
        XCTAssertFalse(SecKeySignatureVerifier.verify(body, signatureBase64: badSig.base64EncodedString(), publicKeyBase64: key))
        XCTAssertFalse(SecKeySignatureVerifier.verify(body, signatureBase64: "not base64", publicKeyBase64: key))
        XCTAssertFalse(SecKeySignatureVerifier.verify(body, signatureBase64: sig, publicKeyBase64: String(key.dropFirst(4))))
        print("SEAM_TEST signature: real calibration.json verified, tampered byte refused")
    }

    func testLaunchOptionsReadTheCamera() {
        XCTAssertEqual(LaunchOptions(arguments: ["Vela", "-VelaStartCamera", "davis"]).camera,
                       LaunchOptions.fixtures["davis"])
        XCTAssertEqual(LaunchOptions(arguments: ["Vela", "-VelaStartCamera", "38.5816,-121.4944,14"]).camera,
                       LaunchOptions.Camera(latitude: 38.5816, longitude: -121.4944, zoom: 14))
        XCTAssertEqual(LaunchOptions(arguments: ["Vela", "-VelaStartCamera", "95,0"]).camera, LaunchOptions.fixtures["sf"])
        XCTAssertEqual(LaunchOptions(arguments: ["Vela"]).camera, LaunchOptions.fixtures["sf"])
        XCTAssertTrue(LaunchOptions(arguments: ["Vela", "-VelaDeterministic", "YES"]).deterministic)
        XCTAssertFalse(LaunchOptions(arguments: ["Vela"]).deterministic)
    }
}
