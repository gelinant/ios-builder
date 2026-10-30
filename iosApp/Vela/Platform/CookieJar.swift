import Foundation

/// The cookies of one `URLSessionVelaHttp`, kept in memory per host as the W-1 spike did
/// (tools/ios-spike.swift) and as Android's `InMemoryCookieJar` does: Google's consent cookies
/// are there from the start, so an EU device never meets the consent wall.
final class CookieJar {
    static let consentSeed = ["SOCS": "CAESHAgBEhIaAB", "CONSENT": "YES+"]
    static let consentHosts = ["www.google.com", "google.com", "consent.google.com"]

    /// The app's one HTTP jar: "Start a new session now" empties it, and only it.
    static let app = CookieJar()

    private let lock = NSLock()
    private var byHost: [String: [String: String]] = [:]
    private let seedGoogleConsent: Bool

    init(seedGoogleConsent: Bool = true) {
        self.seedGoogleConsent = seedGoogleConsent
        if seedGoogleConsent {
            for host in Self.consentHosts {
                byHost[host] = Self.consentSeed
            }
        }
    }

    /// Throws away every cookie, then re-seeds only Google's consent pair: those carry no
    /// identity and keep the EU consent wall from blocking the new session.
    func reset() {
        lock.lock()
        byHost.removeAll()
        if seedGoogleConsent {
            for host in Self.consentHosts {
                byHost[host] = Self.consentSeed
            }
        }
        lock.unlock()
    }

    /// The `Cookie` header for a request to `url`, or nil when there is none.
    func header(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let cookies = byHost[host], !cookies.isEmpty else { return nil }
        return cookies.keys.sorted().map { "\($0)=\(cookies[$0]!)" }.joined(separator: "; ")
    }

    /// Takes the `Set-Cookie` lines of `response`, which answered a request to `url`. A cookie
    /// for a parent domain (`.google.com`) is shared with that domain and its `www.` host, never
    /// with an unrelated one.
    func store(from response: HTTPURLResponse, url: URL) {
        guard let host = url.host?.lowercased() else { return }
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            fields["\(key)"] = "\(value)"
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !cookies.isEmpty else { return }
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        for cookie in cookies {
            var domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") { domain.removeFirst() }
            var targets: Set<String> = [host]
            if !domain.isEmpty, domain == host || host.hasSuffix("." + domain) {
                targets.insert(domain)
                targets.insert("www." + domain)
            }
            let expired = cookie.expiresDate.map { $0 < now } ?? false
            for target in targets {
                if expired {
                    byHost[target]?[cookie.name] = nil
                } else {
                    byHost[target, default: [:]][cookie.name] = cookie.value
                }
            }
        }
    }
}
