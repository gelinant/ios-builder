import CoreSpotlight
import XCTest
@testable import Vela

final class IntentsTests: XCTestCase {
    private let reference = VelaSavedReference(
        placeID: "coop", listID: nil, name: "Davis Food Co-op",
        address: "620 G St, Davis, CA 95616", latitude: 38.5449, longitude: -121.7405)

    func testRouterParsesAndRoundTripsEveryRoute() {
        let routes: [VelaDeepLink] = [
            .search(query: "Davis Food Co-op"),
            .place("coop"),
            .place("imp:38.54490,-121.74050", listID: "list:week end", directions: true),
            .place("folder/place"),
            .saved,
            .parking,
            .navigate(.home),
            .navigate(.work),
        ]
        for route in routes {
            assertRoute(route.url.absoluteString, route)
        }
        XCTAssertEqual(VelaDeepLink.search(query: "coffee").url.absoluteString, "vela://search?q=coffee")
        XCTAssertEqual(VelaDeepLink.place("coop").url.absoluteString, "vela://place/coop")
        XCTAssertEqual(VelaDeepLink.saved.url.absoluteString, "vela://saved")
        XCTAssertEqual(VelaDeepLink.parking.url.absoluteString, "vela://parking")
        XCTAssertEqual(VelaDeepLink.navigate(.home).url.absoluteString, "vela://navigate/home")
    }

    func testRouterRejectsMalformedOrForeignLinks() {
        let cases: [(String, VelaDeepLinkError)] = [
            ("https://example.com/search?q=coffee", .unsupportedScheme),
            ("vela://search?q=%20", .invalidQuery),
            ("vela://search?q=one&q=two", .invalidQuery),
            ("vela://place", .missingPlaceID),
            ("vela://place/coop?directions=yes", .invalidQuery),
            ("vela://place/coop?directions", .invalidQuery),
            ("vela://place/coop?list", .invalidQuery),
            ("vela://place/coop?list=one&list=two", .invalidQuery),
            ("vela://navigate/gym", .invalidShortcut),
            ("vela://other", .unknownRoute),
            ("vela://user@saved", .invalidURL),
        ]
        for (text, expected) in cases {
            switch VelaDeepLinkRouter.parse(text) {
            case .success(let route):
                XCTFail("Unexpected route \(route) for \(text)")
            case .failure(let error):
                XCTAssertEqual(error, expected, text)
            }
        }
    }

    func testDeepLinkCenterRepeatsURLsAndIgnoresStaleConsumption() {
        let center = VelaDeepLinkCenter()
        let url = VelaDeepLink.saved.url
        center.open(url)
        let first = center.pending
        center.open(url)
        let second = center.pending
        XCTAssertNotEqual(first?.id, second?.id)
        if let first { center.consume(first) }
        XCTAssertEqual(center.pending?.id, second?.id)
        if let second { center.consume(second) }
        XCTAssertNil(center.pending)
    }

    func testIntentValidationAndSetupErrors() throws {
        XCTAssertEqual(try VelaIntentPlanner.search("  coffee\n").get(), .search(query: "coffee"))
        XCTAssertEqual(try VelaIntentPlanner.search(" \n").getError(), .emptyQuery)

        let empty = VelaIntentSnapshot()
        XCTAssertEqual(try VelaIntentPlanner.navigate(.home, snapshot: empty).getError(), .missingShortcut(.home))
        XCTAssertEqual(try VelaIntentPlanner.navigate(.work, snapshot: empty).getError(), .missingShortcut(.work))
        XCTAssertEqual(try VelaIntentPlanner.parking(snapshot: empty).getError(), .missingParking)
        XCTAssertTrue(VelaIntentError.missingShortcut(.home).errorDescription?.contains("Saved") == true)

        let ready = VelaIntentSnapshot(home: reference, work: reference, hasParking: true)
        XCTAssertEqual(try VelaIntentPlanner.navigate(.home, snapshot: ready).get(), .navigate(.home))
        XCTAssertEqual(try VelaIntentPlanner.navigate(.work, snapshot: ready).get(), .navigate(.work))
        XCTAssertEqual(try VelaIntentPlanner.parking(snapshot: ready).get(), .parking)
    }

    func testSpotlightItemUsesDeepLinkAndSavedMetadata() {
        let link = VelaDeepLink.place("coop")
        let record = SpotlightRecord(
            route: link, domain: .savedPlaces, title: reference.name, subtitle: reference.address,
            latitude: reference.latitude, longitude: reference.longitude)
        let item = record.searchableItem
        XCTAssertEqual(item.uniqueIdentifier, link.url.absoluteString)
        XCTAssertEqual(item.domainIdentifier, SpotlightDomain.savedPlaces.rawValue)
        XCTAssertEqual(item.attributeSet.title, reference.name)
        XCTAssertEqual(item.attributeSet.contentDescription, reference.address)
        XCTAssertEqual(item.attributeSet.contentURL, link.url)
        XCTAssertEqual(item.attributeSet.latitude?.doubleValue, reference.latitude)
        XCTAssertEqual(item.attributeSet.longitude?.doubleValue, reference.longitude)
        XCTAssertEqual(item.attributeSet.supportsNavigation?.boolValue, true)
    }

    private func assertRoute(_ text: String, _ expected: VelaDeepLink,
                             file: StaticString = #filePath, line: UInt = #line) {
        switch VelaDeepLinkRouter.parse(text) {
        case .success(let route):
            XCTAssertEqual(route, expected, text, file: file, line: line)
        case .failure(let error):
            XCTFail("Could not parse \(text): \(error)", file: file, line: line)
        }
    }
}

private extension Result {
    func getError() throws -> Failure {
        switch self {
        case .success:
            throw TestResultError.expectedFailure
        case .failure(let error):
            return error
        }
    }
}

private enum TestResultError: Error {
    case expectedFailure
}
