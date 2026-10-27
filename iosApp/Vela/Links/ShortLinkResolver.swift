import Foundation
import VelaCore

/// Reads where a Google Maps short link points. One cookieless request to the shortener only; the
/// target is parsed on the phone by `MapLinkParser` and nothing else is fetched. A direct link that
/// already carries its data is never sent anywhere.
enum VelaShortLinkResolver {
    static func resolve(_ url: URL) async -> URL? {
        guard ShortLinks.shared.isShortener(url: url.absoluteString) else { return nil }
        // The shortener only needs its code. Tracking parameters a sender attached are dropped
        // before the request, never forwarded to Google.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let short = components?.url ?? url
        let userAgent = AppGraph.session.webUserAgent()
        let http = URLSessionVelaHttp(followsRedirects: false)
        guard let target = try? await ShortLinks.shared.resolve(
            http: http, url: short.absoluteString, userAgent: userAgent, maxHops: 3),
            let targetURL = URL(string: target) else {
            return nil
        }
        return targetURL
    }
}
