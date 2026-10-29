import Foundation
import UIKit
import VelaCore

/// What the hidden page found: the raw getlist body and the shared id that produced it, or the
/// single place a link pointed at. A failure reason travels in the body as `#vela:<reason>`.
struct SavedGoogleFetchResult {
    let payload: String?
    /// The shared list id, read from the resolved URL or the page: the stable import identity.
    let listId: String?
    let place: SavedSharedPlace?
}

/// The shared Google Maps page, read in the hidden WebView (IMP-GOOGLE). A short link
/// (`maps.app.goo.gl/...`) redirects there; the page script reads the shared id from the URL it
/// landed on (or from the page), moves to the canonical `www.google.com` page carrying that id,
/// then lifts the `/maps/preview/entitylist/getlist` reply. The body goes to
/// `SavedStore.finishGoogleListImport`, which parses it with `EntityListParser`: a page whose shape
/// changed produces no list rather than invented places.
///
/// One fetch at a time, like the place scrapers. Cancelling stops the page and answers nothing.
final class SavedGoogleListFetcher: HiddenWebView {
    static let shared = SavedGoogleListFetcher(tag: "saved-list", size: CGSize(width: 1200, height: 1000))

    /// After the page's own finish, and the cap when a consent wall never finishes.
    private static let settle: TimeInterval = 0.2
    private static let maxLoad: TimeInterval = 15

    private final class Active {
        let id: String
        let link: String
        let onProgress: (Int) -> Void
        let onResult: (SavedGoogleFetchResult?) -> Void
        let done: () -> Void
        var injected = false
        var injectedByCap = false
        var heard = false
        var place: SavedSharedPlace?

        init(id: String, link: String, onProgress: @escaping (Int) -> Void,
             onResult: @escaping (SavedGoogleFetchResult?) -> Void, done: @escaping () -> Void) {
            self.id = id
            self.link = link
            self.onProgress = onProgress
            self.onResult = onResult
            self.done = done
        }
    }

    private var active: Active?

    func fetch(link: String, onProgress: @escaping (Int) -> Void,
               onResult: @escaping (SavedGoogleFetchResult?) -> Void) -> WebFetchHandle {
        let handle = WebFetchHandle()
        #if DEBUG
        // The UI scenario cannot drive Google's live page (nor should it depend on it): the real
        // captured resolved page and getlist reply are replayed down the same progress and parse
        // path.
        if let fixture = Self.shortLinkFixture(link: link) {
            onProgress(1)
            onProgress(2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard !handle.cancelled else {
                    onResult(nil)
                    return
                }
                onProgress(3)
                onResult(SavedGoogleFetchResult(payload: fixture.reply, listId: fixture.id, place: nil))
            }
            return handle
        }
        if let payload = Self.fixturePayload() {
            onProgress(1)
            onProgress(2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard !handle.cancelled else {
                    onResult(nil)
                    return
                }
                onProgress(3)
                let id = SavedListImport.shared.listId(link: link)
                onResult(SavedGoogleFetchResult(
                    payload: payload, listId: id.isEmpty ? nil : id, place: nil))
            }
            return handle
        }
        #endif
        session { [weak self] done in
            guard let self, !handle.cancelled else {
                onResult(nil)
                done()
                return
            }
            let id = self.nextId()
            let a = Active(id: id, link: link, onProgress: onProgress, onResult: onResult, done: done)
            self.active = a
            handle.onCancel = { [weak self] in self?.giveUp(id) }
            onProgress(1)
            webLog.debug("saved-list: page asked for \(link.prefix(80), privacy: .public)")
            // Blank the previous list first, so a late injection cannot answer this link with it.
            self.evaluate("try{document.documentElement.innerHTML=''}catch(e){}")
            self.load(link, id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxLoad) { [weak self] in
                self?.inject(id, byCap: true)
            }
        }
        return handle
    }

    /// Google redirects a short link to a country host (`www.google.fr`, `consent.google.fr`),
    /// so every Google host family is allowed; anything else is refused before it loads.
    override func allowNavigation(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return SavedListImport.shared.isGoogleLink(link: url.absoluteString)
            || host == "goo.gl" || host.hasSuffix(".goo.gl")
            || host == "g.co" || host.hasSuffix(".g.co")
            || host == "google.com" || host.hasSuffix(".google.com")
            || host.hasPrefix("maps.google.") || host.hasPrefix("consent.google.")
    }

    override func pageFinished(url: URL?, requestId: String) {
        guard let a = active, a.id == requestId else { return }
        // A new document: the previous injection (or a cap injection) belongs to the page that
        // just went away. The script may have navigated to the canonical page carrying the id.
        a.injected = false
        a.injectedByCap = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in
            self?.inject(requestId, byCap: false)
        }
    }

    override func bridgeCall(method: String, requestId: String, argument: String) {
        guard let a = active, a.id == requestId else { return }
        a.heard = true
        switch method {
        case "onProgress":
            a.onProgress(Int(argument) ?? 0)
        case "onInfo":
            if argument.hasPrefix("place|") {
                let fields = argument.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
                if fields.count == 4, let lat = Double(fields[2]), let lng = Double(fields[3]) {
                    a.place = SavedSharedPlace(name: String(fields[1]), lat: lat, lng: lng)
                }
            }
        case "onResult":
            finish(requestId, argument.isEmpty ? nil : argument)
        default:
            break
        }
    }

    override func pageDied(requestId: String) {
        // A dead page has no list to offer; the store reports the failure rather than a blank one.
        finish(requestId, nil)
    }

    /// Injects once per page. The finish and the load cap race; a cap injection into a document
    /// that was then replaced is followed by the finish's own injection.
    private func inject(_ id: String, byCap: Bool) {
        guard let a = active, a.id == id else { return }
        if a.injected {
            guard !byCap, a.injectedByCap, !a.heard else { return }
            webLog.debug("saved-list: injecting again after the page finished")
        }
        a.injected = true
        a.injectedByCap = byCap
        let listId = SavedListImport.shared.listId(link: a.link)
        evaluate(SavedListImport.shared.googleScript(requestId: id, listId: listId))
    }

    private func giveUp(_ id: String) {
        guard let a = active, a.id == id else { return }
        stop()
        finish(id, nil)
    }

    private func finish(_ id: String, _ payload: String?) {
        guard let a = active, a.id == id else { return }
        active = nil
        webLog.debug("saved-list: \(payload == nil ? "given up" : "answered", privacy: .public)")
        a.onResult(payload.map {
            SavedGoogleFetchResult(payload: $0, listId: a.place == nil ? resolvedListId(a, $0) : nil, place: a.place)
        })
        a.done()
    }

    /// The id the script actually used: a direct link carries it; a short link's id is read from
    /// the page URL the request ended on, or from the failure reason's page.
    private func resolvedListId(_ a: Active, _ payload: String?) -> String? {
        let direct = SavedListImport.shared.listId(link: a.link)
        if !direct.isEmpty { return direct }
        let page = webView?.url?.absoluteString ?? ""
        let found = SavedListImport.shared.listIdFromPage(pageUrl: page, html: nil)
        return found.isEmpty ? nil : found
    }

    #if DEBUG
    private struct ShortLinkFixture: Decodable {
        let link: String
        let id: String
        let page: String
        let reply: String
    }

    private struct ShortLinkManifest: Decodable {
        let links: [ShortLinkFixture]
    }

    private struct LoadedFixture {
        let id: String
        let reply: String
    }

    /// A captured resolved page and getlist reply for [link], when the UI scenario supplied the
    /// manifest. The id is read from the real captured page through the same function the live
    /// path uses, so a rotated page shape fails the scenario.
    private static func shortLinkFixture(link: String) -> LoadedFixture? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaSavedShortLinkFixtures"),
              index + 1 < arguments.count else { return nil }
        let manifestURL = URL(fileURLWithPath: arguments[index + 1])
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ShortLinkManifest.self, from: data),
              let entry = manifest.links.first(where: {
                  $0.link.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ==
                      link.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
              }) else { return nil }
        let dir = manifestURL.deletingLastPathComponent()
        guard let html = try? String(contentsOf: dir.appendingPathComponent(entry.page), encoding: .utf8),
              let reply = try? String(contentsOf: dir.appendingPathComponent(entry.reply), encoding: .utf8)
        else { return nil }
        let resolved = SavedListImport.shared.listIdFromPage(pageUrl: nil, html: html)
        guard !resolved.isEmpty else { return nil }
        return LoadedFixture(id: resolved, reply: reply)
    }

    /// The captured list reply supplied by the UI test, if any. Debug only: a release build never
    /// reads a file in place of the page.
    private static func fixturePayload() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaSavedGoogleFixture"), index + 1 < arguments.count else {
            return nil
        }
        return try? String(contentsOfFile: arguments[index + 1], encoding: .utf8)
    }
    #endif
}
