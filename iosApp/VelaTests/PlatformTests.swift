import XCTest
@testable import Vela

final class PlatformTests: XCTestCase {
    func testCookieJarStartsWithGoogleConsent() throws {
        let jar = CookieJar()
        let header = try XCTUnwrap(jar.header(for: URL(string: "https://www.google.com/maps")!))
        XCTAssertEqual(header, "CONSENT=YES+; SOCS=CAESHAgBEhIaAB")
        XCTAssertNil(jar.header(for: URL(string: "https://tiles.openfreemap.org/styles/liberty")!))
    }

    func testCookieJarSharesAParentDomainCookieWithItsHosts() {
        let jar = CookieJar(seedGoogleConsent: false)
        let url = URL(string: "https://www.google.com/maps?hl=en&gl=us")!
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": "NID=abc; Domain=.google.com; Path=/; Secure"])!
        jar.store(from: response, url: url)
        XCTAssertEqual(jar.header(for: URL(string: "https://google.com/")!), "NID=abc")
        XCTAssertEqual(jar.header(for: URL(string: "https://www.google.com/search")!), "NID=abc")
        XCTAssertNil(jar.header(for: URL(string: "https://example.com/")!))
    }

    func testLegacyLanguageCodesMatchAndroid() {
        XCTAssertEqual(DevicePlatformLocale.legacyLanguage(of: "he-IL"), "iw")
        XCTAssertEqual(DevicePlatformLocale.legacyLanguage(of: "id"), "in")
        XCTAssertEqual(DevicePlatformLocale.legacyLanguage(of: "yi"), "ji")
        XCTAssertEqual(DevicePlatformLocale.legacyLanguage(of: "zh-Hant-TW"), "zh")
        XCTAssertEqual(DevicePlatformLocale.legacyLanguage(of: "fr_FR"), "fr")
    }
}
