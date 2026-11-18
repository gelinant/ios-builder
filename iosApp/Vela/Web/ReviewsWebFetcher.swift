import OSLog
import UIKit
import VelaCore

/// The place's reviews read off its Google Maps page, as Android's `WebReviewsFetcher`: load the
/// place's `?cid=` page in the hidden view, inject the shared scraper (`ReviewScripts` in
/// :core-common, built by the Kotlin `PlaceStore`), and pass what its bridge reports to the
/// Kotlin sink. One fetch at a time; a new place's fetch waits for the previous one, which the
/// store cancels first. Main thread only.
final class ReviewsWebFetcher: HiddenWebView, PlaceWebFallback {
    /// Android's size (CSS px; a WKWebView point is a CSS px): the desktop layout, shorter than
    /// the feed so the pane scrolls and Google pages the next cards in.
    static let shared = ReviewsWebFetcher(tag: "reviews", size: CGSize(width: 1200, height: 1000))

    /// After the page's own finish, as Android (`SETTLE_MS`).
    private static let settle: TimeInterval = 0.15
    /// Inject anyway when the page has not finished by then (`MAX_LOAD_MS`).
    private static let maxLoad: TimeInterval = 7

    private final class Active {
        let id: String
        let request: WebReviewsRequest
        let sink: WebReviewsSink
        let done: () -> Void
        var injected = false
        var injectedByCap = false
        var heard = false
        var lastPartial: String?

        init(id: String, request: WebReviewsRequest, sink: WebReviewsSink, done: @escaping () -> Void) {
            self.id = id
            self.request = request
            self.sink = sink
            self.done = done
        }
    }

    private var active: Active?

    func reviews(request: WebReviewsRequest, sink: WebReviewsSink) -> any VelaCore.Cancellable {
        let handle = WebFetchHandle()
        session { [weak self] done in
            guard let self, !handle.cancelled else {
                sink.onResult(payload: nil)
                done()
                return
            }
            let id = self.nextId()
            let a = Active(id: id, request: request, sink: sink, done: done)
            self.active = a
            handle.onCancel = { [weak self] in self?.giveUp(id) }
            webLog.debug("reviews: page asked for \(request.featureId, privacy: .public)")
            // Blank the previous place's page first, so the load cap cannot inject into it and
            // answer this place with that one's reviews.
            self.evaluate("try{document.documentElement.innerHTML=''}catch(e){}")
            self.load(request.url, id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxLoad) { [weak self] in
                self?.inject(id, byCap: true)
            }
        }
        return handle
    }

    override func allowNavigation(_ url: URL) -> Bool {
        let host = url.host ?? ""
        return host == "google.com" || host.hasSuffix(".google.com")
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
        case "onResult":
            finish(requestId, argument)
        case "onProgress":
            a.sink.onProgress(count: Int32(argument) ?? 0)
        case "onPartial":
            a.lastPartial = argument
            a.sink.onPartial(payload: argument)
        case "onHistogram":
            a.sink.onHistogram(json: argument)
        case "onInfo":
            webLog.debug("reviews probe: \(argument.prefix(400), privacy: .public)")
        default:
            break
        }
    }

    override func pageDied(requestId: String) {
        // Rule 5 of W-2: what streamed in is better than nothing.
        finish(requestId, active?.lastPartial)
    }

    /// Injects the scraper for request `id` once: the page finish and the load cap race for it.
    /// A cap injection the page never answered may have gone into a document that was then
    /// replaced (W-2, section 7), so a later page finish injects again.
    private func inject(_ id: String, byCap: Bool) {
        guard let a = active, a.id == id else { return }
        if a.injected {
            guard !byCap, a.injectedByCap, !a.heard else { return }
            webLog.debug("reviews: injecting again after the page finished")
        }
        a.injected = true
        a.injectedByCap = byCap
        evaluate(a.request.script(requestId: id))
    }

    private func giveUp(_ id: String) {
        guard let a = active, a.id == id else { return }
        stop()
        finish(id, nil)
    }

    private func finish(_ id: String, _ payload: String?) {
        guard let a = active, a.id == id else { return }
        active = nil
        webLog.debug("reviews: \(payload == nil ? "given up" : "answered", privacy: .public)")
        // The Google Maps page weighs hundreds of megabytes of WebContent and carries a live map
        // and a whole reviews DOM. Once it has answered, nothing needs it: keeping it costs memory
        // and puts that DOM in the app's accessibility tree, which made every later UI query walk
        // the page. The next fetch builds a fresh view over the same cookie store.
        reapNow()
        a.sink.onResult(payload: payload)
        a.done()
    }
}

extension ReviewsWebFetcher {
    /// The other place fetchers have their own page and serial session, as on Android. The single
    /// Kotlin fallback object forwards to them so `AppGraph` still installs one facade.
    func photos(request: WebPhotosRequest, sink: WebPhotosSink) -> any VelaCore.Cancellable {
        PhotosWebFetcher.shared.photos(request: request, sink: sink)
    }

    func details(request: WebDetailsRequest, sink: WebDetailsSink) -> any VelaCore.Cancellable {
        PopularTimesWebFetcher.shared.details(request: request, sink: sink)
    }
}
