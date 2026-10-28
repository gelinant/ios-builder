#if DEBUG
import Foundation
import VelaCore

/// The offline UI scenario enables this only after its downloads. HTTP(S) URLSession work then fails
/// immediately; file URLs are untouched. MapLibre also gets a generated style with zero remote URLs.
final class OfflineBlockURLProtocol: URLProtocol {
    fileprivate(set) static var enabled = false
    private(set) static var blockedRequests = 0

    override class func canInit(with request: URLRequest) -> Bool {
        guard enabled, let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.blockedRequests += 1
        client?.urlProtocol(self, didFailWithError: NSError(
            domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
    }

    override func stopLoading() {}
}

enum OfflineTestSupport {
    static func block(store: OfflineStore) {
        OfflineBlockURLProtocol.enabled = true
        _ = URLProtocol.registerClass(OfflineBlockURLProtocol.self)
        store.setOfflineTestMode(enabled: true)
    }
}

/// Debug-only offline download fixtures: two manifest revisions for Monaco, a place-pack delta,
/// an archive patch and a world archive. The scenario opts in with `-VelaOfflineFixture YES`; no
/// fixture URL, coordinate or asset reaches a production build.
enum OfflineFixtureSupport {
    static let host = "offline.fixture.invalid"

    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaOfflineFixture"),
              index + 1 < arguments.count else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }

    /// Called once from OfflineModel before OfflineStore starts.
    static func install(store: OfflineStore) {
        guard isEnabled else { return }
        OfflineFixtureURLProtocol.enabled = true
        _ = URLProtocol.registerClass(OfflineFixtureURLProtocol.self)
        store.resetForFixture()
        apply(store: store, update: false)
    }

    static func activateUpdate(store: OfflineStore) {
        guard isEnabled else { return }
        apply(store: store, update: true)
    }

    /// A custom URLSession does not reliably pick up a protocol registered after its creation.
    static func configure(session configuration: URLSessionConfiguration) {
        guard isEnabled else { return }
        configuration.protocolClasses = [OfflineFixtureURLProtocol.self] + (configuration.protocolClasses ?? [])
    }

    static func url(_ name: String) -> String { "https://\(host)/\(name)" }

    private static func apply(store: OfflineStore, update: Bool) {
        let rev = update ? 2 : 1
        let routing = """
        {"regions":[{"id":"monaco","name":"Monaco (fixture)",\
        "url":"\(url("obf"))","sizeMb":1,"bbox":[43.72,7.40,43.76,7.44]}]}
        """
        let counts = update
            ? "{\"poi\":3,\"streetname\":1,\"addr\":1,\"streetpt\":2}"
            : "{\"poi\":1,\"streetname\":1,\"addr\":1,\"streetpt\":1}"
        let packDelta = update
            ? ",\"delta\":{\"url\":\"\(url("pack-delta.zip"))\",\"fromRev\":1,\"sizeMb\":1}" : ""
        let packs = """
        {"regions":[{"id":"monaco","name":"Monaco (fixture)",\
        "url":"\(url("pack-v\(rev).zip"))","sizeMb":1,"installedMb":1,\
        "bbox":[43.72,7.40,43.76,7.44],"rev":\(rev),"counts":\(counts)\(packDelta)}]}
        """
        let places = archiveManifest(rev: rev, prefix: "places", deltaSuffix: "vpatch")
        let maps = archiveManifest(rev: rev, prefix: "basemap", deltaSuffix: "vpatch")
        store.useFixtureCatalogs(
            routingJson: routing, packsJson: packs, placesJson: places, mapsJson: maps,
            worldUrl: url("world.pmtiles"), glyphUrl: url("map-fonts.zip"))
    }

    private static func archiveManifest(rev: Int, prefix: String, deltaSuffix: String) -> String {
        let delta = rev > 1
            ? ",\"delta\":{\"url\":\"\(url("\(prefix)-v1-to-v2.\(deltaSuffix)"))\",\"fromRev\":1,\"sizeMb\":1}"
            : ""
        return """
        {"regions":[{"id":"monaco","name":"Monaco (fixture)",\
        "url":"\(url("\(prefix)-v\(rev).pmtiles"))","sizeMb":1,\
        "bbox":[43.72,7.40,43.76,7.44],"rev":\(rev)\(delta)}]}
        """
    }
}

/// Serves the fixture assets from the app bundle. Download bodies and manifests are tiny synthetic
/// files built by `scripts/ios/offline_fixture.py`, never real map data.
final class OfflineFixtureURLProtocol: URLProtocol {
    fileprivate(set) static var enabled = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard enabled, let host = request.url?.host else { return false }
        return host == OfflineFixtureSupport.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let name = url.lastPathComponent
        guard let file = Bundle.main.url(forResource: name, withExtension: nil),
              let body = try? Data(contentsOf: file) else {
            let response = HTTPURLResponse(
                url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Length": "\(body.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
