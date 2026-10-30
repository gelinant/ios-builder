import UIKit
import VelaCore

/// Android's `WebPopularTimesFetcher`: warm google.com and Maps, then run the focused search as a
/// same-origin fetch. Kotlin builds the URL and parses the reply with `PopularTimesParser`.
/// Android has not moved this small script to core-common, so its Swift equivalent stays here.
/// Main thread only.
final class PopularTimesWebFetcher: HiddenWebView {
    static let shared = PopularTimesWebFetcher(tag: "popular", size: CGSize(width: 1200, height: 1000))

    private static let settle: TimeInterval = 1.2
    private static let maxWarm: TimeInterval = 9

    private final class Active {
        let id: String
        let request: WebDetailsRequest
        let sink: WebDetailsSink
        let done: () -> Void
        var fetchStarted = false
        var fetchByCap = false
        var heard = false

        init(id: String, request: WebDetailsRequest, sink: WebDetailsSink, done: @escaping () -> Void) {
            self.id = id
            self.request = request
            self.sink = sink
            self.done = done
        }
    }

    private var active: Active?
    private var warmed = false
    private var warmFinishes = 0

    func details(request: WebDetailsRequest, sink: WebDetailsSink) -> any VelaCore.Cancellable {
        let handle = WebFetchHandle()
        session { [weak self] done in
            guard let self, !handle.cancelled else {
                sink.onResult(payload: nil)
                done()
                return
            }
            let id = self.nextId()
            let active = Active(id: id, request: request, sink: sink, done: done)
            self.active = active
            handle.onCancel = { [weak self] in self?.giveUp(id) }
            self.ensureWarm(id)
        }
        return handle
    }

    override func allowNavigation(_ url: URL) -> Bool {
        let host = url.host ?? ""
        return host == "google.com" || host.hasSuffix(".google.com")
    }

    override func pageFinished(url: URL?, requestId: String) {
        guard let active, active.id == requestId else { return }
        if active.fetchStarted {
            // The warm deadline may have injected into a document that was then replaced (W-2).
            if active.fetchByCap && !active.heard {
                active.fetchByCap = false
                webLog.debug("popular: injecting again after the page finished")
                evaluate(Self.fetchScript(active.request, id: requestId))
            }
            return
        }
        guard !warmed else {
            startFetch(requestId)
            return
        }
        warmFinishes += 1
        if warmFinishes == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let active = self.active, active.id == requestId, !active.fetchStarted else { return }
                self.load(active.request.warmUrl, id: requestId)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in
                self?.startFetch(requestId)
            }
        }
    }

    override func bridgeCall(method: String, requestId: String, argument: String) {
        guard let active, active.id == requestId, method == "onResult" else { return }
        active.heard = true
        finish(requestId, argument)
    }

    override func pageDied(requestId: String) {
        warmed = false
        finish(requestId, nil)
    }

    override func reapNow() {
        warmed = false
        super.reapNow()
    }

    private func ensureWarm(_ id: String) {
        guard active?.id == id else { return }
        if warmed, webView != nil {
            startFetch(id)
            return
        }
        warmFinishes = 0
        load("https://www.google.com/?hl=en&gl=us", id: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxWarm) { [weak self] in
            self?.startFetch(id, byCap: true)
        }
    }

    private func startFetch(_ id: String, byCap: Bool = false) {
        guard let active, active.id == id, !active.fetchStarted else { return }
        active.fetchStarted = true
        active.fetchByCap = byCap
        warmed = true
        webLog.debug("popular: same-origin details fetch")
        evaluate(Self.fetchScript(active.request, id: id))
    }

    private func giveUp(_ id: String) {
        guard active?.id == id else { return }
        stop()
        finish(id, nil)
    }

    private func finish(_ id: String, _ payload: String?) {
        guard let active, active.id == id else { return }
        self.active = nil
        webLog.debug("popular: replied with \(payload?.utf8.count ?? -1) characters")
        // The answered page is Google's own heavy document. Keeping it for the idle timer put its
        // DOM in the app's accessibility tree and made later UI queries walk that page; the
        // reviews fetcher already destroys its page on the answer for the same reason.
        reapNow()
        active.sink.onResult(payload: payload)
        active.done()
    }

    private static func fetchScript(_ request: WebDetailsRequest, id: String) -> String {
        let url = quoted(request.url)
        let requestId = quoted(id)
        return #"""
        (function(){
          try {
            fetch(\#(url), {credentials:"include", headers:{"accept-language":"en-US,en;q=0.9"}})
              .then(function(r){ return r.text(); })
              .then(function(t){ VelaBridge.onResult(\#(requestId), t.slice(0, 2000000)); })
              .catch(function(e){ VelaBridge.onResult(\#(requestId), ""); });
          } catch(e){ VelaBridge.onResult(\#(requestId), ""); }
        })();
        """#
    }

    private static func quoted(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}
