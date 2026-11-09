import OSLog
import UIKit
import VelaCore
import WebKit

/// One hidden Google Maps page for a scrape the keyless HTTP path cannot do: the shared lifecycle,
/// written once as on Android (`app.vela.web.HiddenWebView`), under the W-2 rules
/// (docs/ios/spike-webview-ios.md, section 6):
///
/// 1. The view sits in the key window, outside the screen, at the Android size. Never detached: a
///    detached page reads as hidden and its timers are throttled.
/// 2. Safari on macOS and the desktop content mode (the mobile page has no Reviews tab).
/// 3. The page's `VelaBridge` is emulated by a document-start script posting to a script message
///    handler; both names are random per process, as `JsNames` on Android.
/// 4. `BlockedHosts` as a `WKContentRuleList`. No interception, no proxy.
/// 5. A dead web content process ends the request with what it had streamed (`pageDied`).
///
/// A fetcher is its URL, its script and its parser: run the work in `session`, start a page with
/// `nextId` + `load`, inject from `pageFinished`, and answer the bridge calls in `bridgeCall`.
/// Main thread only.
class HiddenWebView: NSObject {
    static let bridgeName = randomName()
    static let handlerName = randomName()

    /// Hidden pages currently in a window, across every fetcher. The reviews panel exposes it in
    /// its debug line: no Google document may sit under a full-screen panel, because its DOM makes
    /// every UI query walk the page. Main thread only.
    static private(set) var livePageCount = 0

    /// The readable bridge names of the shared scripts, swapped for this process's.
    static func jsNames(_ js: String) -> String {
        js.replacingOccurrences(of: "VelaBridge", with: bridgeName)
            .replacingOccurrences(of: "VelaPanel", with: randomPanelName)
    }

    private static let randomPanelName = randomName()

    /// One in-memory store for every hidden page, like Android's one `CookieManager`: the pages of
    /// a launch share Google's cookies, a new launch starts a new session.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()
    private static var prepared = false
    private static var preparing: [() -> Void] = []
    private static var rules: WKContentRuleList?
    private static var telemetryRules: WKContentRuleList?

    let tag: String
    let size: CGSize
    private let reapIdle: TimeInterval
    private(set) var webView: WKWebView?
    /// The offscreen container of [webView]. It is the accessibility boundary: the window holds a
    /// plain view that hides its whole subtree, so XCUITest never reaches the Google document.
    private var hostView: UIView?
    private(set) var currentId = ""
    private var seq = 0
    private var busy = false
    private var waiting: [(@escaping () -> Void) -> Void] = []
    private var reap: DispatchWorkItem?

    init(tag: String, size: CGSize, reapIdle: TimeInterval = 120) {
        self.tag = tag
        self.size = size
        self.reapIdle = reapIdle
        super.init()
    }

    // MARK: Hooks

    /// Whether the main frame may go to `url` (http and https only, already checked).
    func allowNavigation(_ url: URL) -> Bool { true }

    /// A page finished loading for request `requestId`.
    func pageFinished(url: URL?, requestId: String) {}

    /// The page called `VelaBridge.<method>(requestId, argument)`.
    func bridgeCall(method: String, requestId: String, argument: String) {}

    /// The web content process died during request `requestId`; the view is gone.
    func pageDied(requestId: String) {}

    // MARK: For fetchers

    /// A new request id: a late call from an older page can never answer a newer request.
    func nextId() -> String {
        seq += 1
        return String(seq)
    }

    /// Runs `work` when no other fetch of this view runs; `work` calls `done` when it has its
    /// answer. The view is put to the reap timer after.
    func session(_ work: @escaping (_ done: @escaping () -> Void) -> Void) {
        if busy {
            waiting.append(work)
            return
        }
        busy = true
        reap?.cancel()
        reap = nil
        var finished = false
        work { [weak self] in
            guard let self, !finished else { return }
            finished = true
            self.busy = false
            self.scheduleReap()
            if !self.waiting.isEmpty {
                let next = self.waiting.removeFirst()
                self.session(next)
            }
        }
    }

    /// Loads `url` as the page of request `id`, building the view first when there is none.
    func load(_ url: String, id: String) {
        guard let u = URL(string: url) else { return }
        currentId = id
        Self.prepare { [weak self] in
            guard let self, self.currentId == id else { return }
            guard let view = self.ensureWebView() else {
                self.pageDied(requestId: id)
                return
            }
            view.load(URLRequest(url: u))
        }
    }

    /// Runs `js` in the current page, bridge names swapped; fire and forget, as Android's
    /// `evaluateJavascript(js, null)`.
    func evaluate(_ js: String) {
        webView?.evaluateJavaScript(Self.jsNames(js)) { [tag] _, error in
            if let error { webLog.debug("\(tag, privacy: .public): script error \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Stops the page of a request given up on: left alone it would go on loading and running.
    func stop() {
        currentId = ""
        webView?.stopLoading()
    }

    // MARK: The view

    private func ensureWebView() -> WKWebView? {
        if let webView { return webView }
        guard let window = Self.hostWindow() else {
            webLog.error("\(self.tag, privacy: .public): no window to host the page")
            return nil
        }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = Self.dataStore
        cfg.defaultWebpagePreferences.preferredContentMode = .desktop
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.mediaTypesRequiringUserActionForPlayback = .all
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #if targetEnvironment(simulator)
        // The simulator's GPU process dies under Google's WebGL map and freezes the page (W-2,
        // section 4). A phone keeps WebGL until its cost is measured there.
        ucc.addUserScript(WKUserScript(source: Self.noWebGLScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        #endif
        if let rules = Self.rules { ucc.add(rules) }
        // Page telemetry blocking is the user's separate switch. Compiling it only when on would
        // put a compile in the way of the first page, so both lists are prepared once; only the
        // selected one is added. A change reaches the next hidden page.
        if PrivacySettings.telemetryBlockedNow, let telemetry = Self.telemetryRules {
            ucc.add(telemetry)
        }
        ucc.add(WeakHandler(self), name: Self.handlerName)
        cfg.userContentController = ucc
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: size.width, height: size.height), configuration: cfg)
        view.customUserAgent = AppGraph.session.webUserAgent()
        view.navigationDelegate = self
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.isAccessibilityElement = false
        // The web document is never part of the app's accessibility surface. Without the empty
        // array, XCUITest still walked the Google DOM on every query, which is what made the
        // reviews panel look frozen when any hidden page was loading.
        view.accessibilityElements = []
        // The window's child is this inert container, not the WebView: hiding the subtree at the
        // container keeps XCUITest's snapshot out of the page even while the page is still loading.
        let host = UIView(frame: CGRect(x: window.bounds.width + 2000, y: 0, width: size.width, height: size.height))
        host.isUserInteractionEnabled = false
        host.isAccessibilityElement = false
        host.accessibilityElementsHidden = true
        host.accessibilityElements = []
        host.addSubview(view)
        window.addSubview(host)
        hostView = host
        webView = view
        Self.livePageCount += 1
        webLog.debug("\(self.tag, privacy: .public): view created")
        return view
    }

    private func scheduleReap() {
        reap?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reapNow() }
        reap = item
        DispatchQueue.main.asyncAfter(deadline: .now() + reapIdle, execute: item)
    }

    /// Destroys the view; the next fetch builds a new one.
    func reapNow() {
        guard let view = webView else { return }
        webView = nil
        Self.livePageCount = max(0, Self.livePageCount - 1)
        view.stopLoading()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
        view.removeFromSuperview()
        hostView?.removeFromSuperview()
        hostView = nil
        webLog.debug("\(self.tag, privacy: .public): view destroyed")
    }

    private static func hostWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    // MARK: Once per process

    /// Compiles the blocked hosts and the optional page-telemetry list, and seeds the consent
    /// cookies, once, before the first page.
    private static func prepare(_ then: @escaping () -> Void) {
        if prepared {
            then()
            return
        }
        preparing.append(then)
        if preparing.count > 1 { return }
        let group = DispatchGroup()
        if let store = WKContentRuleListStore.default() {
            group.enter()
            store.compileContentRuleList(
                forIdentifier: "vela-blocked-hosts", encodedContentRuleList: blockedHostsRules()
            ) { list, error in
                if let error { webLog.error("blocked hosts: \(error.localizedDescription, privacy: .public)") }
                HiddenWebView.rules = list
                group.leave()
            }
            group.enter()
            store.compileContentRuleList(
                forIdentifier: "vela-google-telemetry",
                encodedContentRuleList: PrivacyPolicy.shared.telemetryRulesJson()
            ) { list, error in
                if let error { webLog.error("telemetry rules: \(error.localizedDescription, privacy: .public)") }
                HiddenWebView.telemetryRules = list
                group.leave()
            }
        }
        seedConsent(group)
        group.notify(queue: .main) {
            HiddenWebView.prepared = true
            let all = HiddenWebView.preparing
            HiddenWebView.preparing = []
            all.forEach { $0() }
        }
    }

    /// Seeds a best-effort consent hint before the first page. Google no longer accepts a fixed
    /// value for every account, so the fetchers that can meet a consent wall drive its real form
    /// instead (see `SavedListImport.googleScript`); this pair only avoids the wall when it still
    /// works and is never the answer to one.
    private static func seedConsent(_ group: DispatchGroup) {
        for (name, value) in [("SOCS", "CAESHAgBEhIaAB"), ("CONSENT", "YES+")] {
            let props: [HTTPCookiePropertyKey: Any] = [
                .domain: ".google.com", .path: "/", .name: name, .value: value,
                .expires: Date().addingTimeInterval(400 * 86400),
            ]
            guard let cookie = HTTPCookie(properties: props) else { continue }
            group.enter()
            dataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
    }

    /// "Start a new session now": drops the hidden store's cookies, caches and site storage, then
    /// re-seeds only the consent pair. Saved places and offline regions are in other stores.
    static func startNewSession(completion: @escaping () -> Void = {}) {
        let group = DispatchGroup()
        group.enter()
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: .distantPast) { group.leave() }
        group.notify(queue: .main) {
            let reseed = DispatchGroup()
            seedConsent(reseed)
            reseed.notify(queue: .main) {
                webLog.notice("hidden WebView store cleared")
                completion()
            }
        }
    }

    /// Android's `BlockedHosts`: ads and telemetry hosts, and the logging paths.
    static func blockedHostsRules() -> String {
        let hosts = ["doubleclick.net", "googleadservices.com", "googlesyndication.com",
                     "google-analytics.com", "googletagmanager.com", "adservice.google", "csi.gstatic.com"]
        var filters = hosts.map { "^https?://([a-z0-9-]+\\.)*" + $0.replacingOccurrences(of: ".", with: "\\.") }
        filters += ["/gen_204", "/log204", "/log\\?", "/domainreliability/", "^https?://play\\.google\\.com/log"]
        let rules: [[String: Any]] = filters.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static var bridgeScript: String {
        """
        (function(){
          var h = window.webkit.messageHandlers.\(handlerName);
          function f(n){ return function(){ try { h.postMessage({m:n, a:Array.prototype.slice.call(arguments).map(function(x){ return String(x); })}); } catch(e){} }; }
          var b = {onResult:f('onResult'), onProgress:f('onProgress'), onInfo:f('onInfo'), onHistogram:f('onHistogram'), onPartial:f('onPartial'), onDates:f('onDates')};
          try { Object.defineProperty(window, '\(bridgeName)', {value:b, writable:false, enumerable:false, configurable:false}); } catch(e) { window['\(bridgeName)'] = b; }
        })();
        """
    }

    private static let noWebGLScript =
        "(function(){ var g=HTMLCanvasElement.prototype.getContext; HTMLCanvasElement.prototype.getContext=function(t){ if(/webgl/i.test(String(t))) return null; return g.apply(this, arguments); }; })();"

    private static func randomName() -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return "_" + String((0..<10).map { _ in letters[Int.random(in: 0..<letters.count)] })
    }

    fileprivate func received(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let method = body["m"] as? String,
              let args = body["a"] as? [String], args.count >= 2 else { return }
        bridgeCall(method: method, requestId: args[0], argument: args[1])
    }
}

/// In an extension so only these methods are main-actor isolated, not the class.
extension HiddenWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame ?? false else {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? "") else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(allowNavigation(url) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, webView.url?.absoluteString != "about:blank", !currentId.isEmpty else { return }
        pageFinished(url: webView.url, requestId: currentId)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        webLog.error("\(self.tag, privacy: .public): web content process terminated")
        let id = currentId
        reapNow()
        if !id.isEmpty { pageDied(requestId: id) }
    }
}

/// The message handler, held weakly: the user content controller keeps its handlers alive.
/// The conformance is in an extension so only its method is main-actor isolated, not the class.
private final class WeakHandler: NSObject {
    weak var owner: HiddenWebView?

    init(_ owner: HiddenWebView) {
        self.owner = owner
    }
}

extension WeakHandler: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.received(message)
    }
}

/// What the Kotlin store holds to cancel a fetch, queued or running.
final class WebFetchHandle: NSObject, VelaCore.Cancellable {
    private(set) var cancelled = false
    var onCancel: (() -> Void)?

    func cancel() {
        DispatchQueue.main.async { [self] in
            guard !cancelled else { return }
            cancelled = true
            onCancel?()
            onCancel = nil
        }
    }
}

let webLog = Logger(subsystem: "app.vela.ios", category: "Web")
