import Foundation
import UIKit
import VelaCore

/// The shared Google Maps list page, read in the hidden WebView (IMP-GOOGLE). The page itself is
/// loaded so Google's consent and session cookies apply, and the shared script then reads the list
/// id from the URL or lifts Google's own getlist request from the page. The body goes to
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
        let onResult: (String?) -> Void
        let done: () -> Void
        var injected = false
        var injectedByCap = false
        var heard = false

        init(id: String, link: String, onProgress: @escaping (Int) -> Void,
             onResult: @escaping (String?) -> Void, done: @escaping () -> Void) {
            self.id = id
            self.link = link
            self.onProgress = onProgress
            self.onResult = onResult
            self.done = done
        }
    }

    private var active: Active?

    func fetch(link: String, onProgress: @escaping (Int) -> Void,
               onResult: @escaping (String?) -> Void) -> WebFetchHandle {
        let handle = WebFetchHandle()
        #if DEBUG
        // The UI scenario cannot drive Google's live page (nor should it depend on it): a captured
        // reply is replayed down the same progress and parse path.
        if let fixture = Self.fixturePayload() {
            onProgress(1)
            onProgress(2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard !handle.cancelled else {
                    onResult(nil)
                    return
                }
                onProgress(3)
                onResult(fixture)
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

    override func allowNavigation(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host == "google.com" || host.hasSuffix(".google.com")
            || host == "goo.gl" || host.hasSuffix(".goo.gl")
    }

    override func pageFinished(url: URL?, requestId: String) {
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
        a.onResult(payload)
        a.done()
    }

    #if DEBUG
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
