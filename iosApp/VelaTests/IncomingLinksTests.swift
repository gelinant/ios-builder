import XCTest
@testable import Vela

/// The link shapes another app or a person hands to Vela. All fixtures are in Davis, Sacramento
/// and San Francisco; no personal location appears here.
final class IncomingLinksTests: XCTestCase {
    private let davisPlace = "https://www.google.com/maps/place/Davis+Food+Co-op/" +
        "@38.5449065,-121.7405167,17z/data=!3m1!4b1!4m6!3m5!1s" +
        "0x808529999495543f:0xed7bb8fb4c8510c0!8m2!3d38.5449065!4d-121.7405167"

    func testGooglePlaceLinkCarriesNamePointAndZoom() throws {
        let link = try incoming(davisPlace)
        XCTAssertEqual(link.kind, .place)
        XCTAssertEqual(link.target?.name, "Davis Food Co-op")
        XCTAssertEqual(link.target?.latitude ?? 0, 38.5449065, accuracy: 1e-6)
        XCTAssertEqual(link.target?.longitude ?? 0, -121.7405167, accuracy: 1e-6)
        XCTAssertEqual(link.zoom ?? 0, 17, accuracy: 1e-6)
        XCTAssertEqual(link.featureID, "0x808529999495543f:0xed7bb8fb4c8510c0")
        XCTAssertNil(link.origin)
        XCTAssertEqual(link.stopCount, 0)
    }

    func testGoogleSearchLinkListsResults() throws {
        let link = try incoming(
            "https://www.google.com/maps/search/coffee/@38.5449,-121.7405,12z")
        XCTAssertEqual(link.kind, .search)
        XCTAssertEqual(link.target?.name, "coffee")
        XCTAssertEqual(link.target?.latitude ?? 0, 38.5449, accuracy: 1e-6)
    }

    func testClassicMapsQueryIsASearch() throws {
        let link = try incoming("https://maps.google.com/?q=Davis+Food+Co-op")
        XCTAssertEqual(link.kind, .search)
        XCTAssertEqual(link.target?.name, "Davis Food Co-op")
        XCTAssertNil(link.target?.latitude)
    }

    func testMapsUrlsDirectionsPairAndMode() throws {
        let link = try incoming(
            "https://www.google.com/maps/dir/?api=1" +
                "&origin=38.5815719,-121.4943996" +
                "&destination=38.5449065,-121.7405167&travelmode=driving")
        XCTAssertEqual(link.kind, .directions)
        XCTAssertEqual(link.target?.latitude ?? 0, 38.5449065, accuracy: 1e-6)
        XCTAssertEqual(link.target?.longitude ?? 0, -121.7405167, accuracy: 1e-6)
        XCTAssertEqual(link.origin?.latitude ?? 0, 38.5815719, accuracy: 1e-6)
        XCTAssertEqual(link.origin?.longitude ?? 0, -121.4943996, accuracy: 1e-6)
        XCTAssertEqual(link.mode, "DRIVE")
        XCTAssertEqual(link.stopCount, 0)
    }

    func testPathDirectionsPairByNames() throws {
        let link = try incoming("https://www.google.com/maps/dir/Sacramento,+CA/Davis,+CA/")
        XCTAssertEqual(link.kind, .directions)
        XCTAssertEqual(link.target?.name, "Davis, CA")
        XCTAssertEqual(link.origin?.name, "Sacramento, CA")
        XCTAssertNil(link.target?.latitude)
    }

    func testGeoPointAndNamedPoint() throws {
        let point = try incoming("geo:38.5449,-121.7405")
        XCTAssertEqual(point.kind, .place)
        XCTAssertEqual(point.target?.latitude ?? 0, 38.5449, accuracy: 1e-6)
        XCTAssertEqual(point.target?.longitude ?? 0, -121.7405, accuracy: 1e-6)
        XCTAssertNil(point.target?.name)

        let named = try incoming("geo:38.5449,-121.7405?q=Davis%20Food%20Co-op")
        XCTAssertEqual(named.kind, .place)
        XCTAssertEqual(named.target?.name, "Davis Food Co-op")
        XCTAssertEqual(named.target?.latitude ?? 0, 38.5449, accuracy: 1e-6)
    }

    func testGeoQueryWithNoPointIsASearch() throws {
        let link = try incoming("geo:0,0?q=coffee")
        XCTAssertEqual(link.kind, .search)
        XCTAssertEqual(link.target?.name, "coffee")
        XCTAssertNil(link.target?.latitude)
    }

    func testGoogleNavigationIntentIsDirections() throws {
        let link = try incoming(
            "google.navigation:q=2000+Sutter+Pl,+Davis,+CA&mode=w")
        XCTAssertEqual(link.kind, .directions)
        XCTAssertEqual(link.target?.name, "2000 Sutter Pl, Davis, CA")
        XCTAssertEqual(link.mode, "WALK")
    }

    func testShortLinkNeedsOneResolutionAndIsNotFetchedHere() {
        let short = URL(string: "https://maps.app.goo.gl/AbCdEf123")!
        guard case .resolve(let target) = VelaIncomingLinkParser.parse(short) else {
            XCTFail("a Maps short link must resolve before routing")
            return
        }
        XCTAssertEqual(target, short)
    }

    @MainActor
    func testShortLinkResolutionPublishesTheParsedTarget() async throws {
        let resolved = URL(string: davisPlace)!
        let center = VelaDeepLinkCenter(resolveShortLink: { _ in resolved })
        center.open(URL(string: "https://maps.app.goo.gl/AbCdEf123")!)
        let request = try await pending(in: center)
        guard case .success(.incoming(let link)) = request.outcome else {
            XCTFail("short link did not publish an incoming place")
            return
        }
        XCTAssertEqual(link.kind, .place)
        XCTAssertEqual(link.target?.name, "Davis Food Co-op")
    }

    @MainActor
    func testShortLinkTargetOutsideGoogleIsRefused() async throws {
        let center = VelaDeepLinkCenter(resolveShortLink: { _ in
            URL(string: "https://example.com/maps/place/Foo")!
        })
        center.open(URL(string: "https://maps.app.goo.gl/AbCdEf123")!)
        let request = try await pending(in: center)
        guard case .failure(let error) = request.outcome else {
            XCTFail("a foreign redirect target must be refused")
            return
        }
        XCTAssertEqual(error, .unreadableLink)
    }

    func testCidOnlyLinkIsParsedButHasNoTarget() throws {
        let url = URL(string: "https://maps.google.com/?cid=1234567890123456789")!
        XCTAssertEqual(VelaIncomingLinkParser.cid(in: url), "1234567890123456789")
        let link = try incoming(url.absoluteString)
        XCTAssertEqual(link.kind, .place)
        XCTAssertNil(link.target)
        XCTAssertEqual(link.cid, "1234567890123456789")
    }

    func testInvalidAndForeignLinksAreRejected() {
        let cases: [(String, VelaDeepLinkError)] = [
            ("https://example.com/maps/place/Davis", .unsupportedScheme),
            ("https://www.google.com/search?q=coffee", .unsupportedScheme),
            ("javascript:alert(1)", .unsupportedScheme),
            ("mailto:person@example.com", .unsupportedScheme),
            ("https://www.google.com/maps/placelists/list/AbC", .unreadableLink),
            ("https://www.google.com/maps/dir/Sacramento/Davis/Vacaville/", .unsupportedStops),
            ("vela://other", .unknownRoute),
        ]
        for (text, expected) in cases {
            guard let url = URL(string: text) else {
                XCTFail("bad fixture \(text)")
                continue
            }
            guard case .rejected(let error) = VelaIncomingLinkParser.parse(url) else {
                XCTFail("Unexpected route for \(text)")
                continue
            }
            XCTAssertEqual(error, expected, text)
        }
    }

    func testTrackingParametersDoNotChangeTheParsedPlace() throws {
        let link = try incoming(davisPlace + "?utm_source=mstt_1&utm_medium=share&g_ep=abc")
        XCTAssertEqual(link.target?.name, "Davis Food Co-op")
        XCTAssertEqual(link.target?.latitude ?? 0, 38.5449065, accuracy: 1e-6)
        XCTAssertEqual(link.kind, .place)
    }

    func testDirectLinkPublishesWithoutWaitingForAResolver() throws {
        let center = VelaDeepLinkCenter(resolveShortLink: { _ in nil })
        center.open(URL(string: davisPlace)!)
        let request = try XCTUnwrap(center.pending)
        guard case .success(.incoming(let link)) = request.outcome else {
            XCTFail("direct link did not publish")
            return
        }
        XCTAssertEqual(link.kind, .place)
    }

    private func incoming(_ text: String, file: StaticString = #filePath,
                          line: UInt = #line) throws -> VelaIncomingLink {
        let url = try XCTUnwrap(URL(string: text), file: file, line: line)
        switch VelaIncomingLinkParser.parse(url) {
        case .route(.incoming(let link)):
            return link
        case .route(let route):
            XCTFail("Unexpected Vela route \(route)", file: file, line: line)
        case .resolve:
            XCTFail("Unexpected short link \(text)", file: file, line: line)
        case .rejected(let error):
            XCTFail("Could not parse \(text): \(error)", file: file, line: line)
        }
        throw IncomingLinkTestError.unparsed
    }

    @MainActor
    private func pending(in center: VelaDeepLinkCenter,
                         file: StaticString = #filePath, line: UInt = #line) async throws
        -> VelaDeepLinkRequest {
        for _ in 0..<100 {
            if let request = center.pending { return request }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("no deep link request was published", file: file, line: line)
        throw IncomingLinkTestError.unparsed
    }
}

private enum IncomingLinkTestError: Error {
    case unparsed
}
