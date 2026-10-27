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
#endif
