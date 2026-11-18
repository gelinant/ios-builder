import CryptoKit
import UIKit
import WebKit

// W-2 spike: runs Vela's Android hidden-WebView scripts (GeneratedJS, byte-equivalent) in a
// WKWebView and reports what comes back. Throwaway code: see docs/ios/spike-webview-ios.md.

let safariMacUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

enum Placement: String {
    case visible    // in the window, scaled down to fit the screen (debug view)
    case offscreen  // in the window, outside the screen bounds (what a hidden fetcher would do)
    case detached   // never added to a window
}

struct Variant {
    let key: String
    let name: String
    let desktop: Bool
    let persistent: Bool
    let placement: Placement
    let scrapes: [String]
    var noWebGL = false
}

// Run 1 (2026-10-24) settled C (detached: timers throttled, 2 ticks in 50 s) and D (mobile UA:
// no tabs, no cards); they stay listed for a rerun by letter.
let allVariants: [Variant] = [
    Variant(key: "A", name: "A-desktop-ephemeral-offscreen", desktop: true, persistent: false, placement: .offscreen, scrapes: ["reviews", "popular", "photos"]),
    Variant(key: "B", name: "B-desktop-ephemeral-offscreen-warmed", desktop: true, persistent: false, placement: .offscreen, scrapes: ["popular", "reviews", "reviews"]),
    Variant(key: "V", name: "V-desktop-ephemeral-visible", desktop: true, persistent: false, placement: .visible, scrapes: ["reviews"]),
]
let otherVariants: [Variant] = [
    Variant(key: "C", name: "C-desktop-ephemeral-detached", desktop: true, persistent: false, placement: .detached, scrapes: ["reviews"]),
    Variant(key: "D", name: "D-mobile-ephemeral-visible", desktop: false, persistent: false, placement: .visible, scrapes: ["reviews", "popular"]),
    // Diagnostic (run 2): the simulator's GPU process crashes under the Maps WebGL canvas and the
    // page stalls. With WebGL refused, Maps draws without it and the scrape runs to its end.
    Variant(key: "W", name: "W-desktop-ephemeral-offscreen-nowebgl", desktop: true, persistent: false, placement: .offscreen,
            scrapes: ["reviews", "photos", "reviews"], noWebGL: true),
]

enum Log {
    static var lines: [String] = []
    static let docs: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    static func p(_ s: String) {
        let line = "SPIKE|" + s
        print(line)
        fflush(stdout)
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: docs.appendingPathComponent("spike-log.txt"), atomically: true, encoding: .utf8)
    }
}

/// Resumes a continuation at most once (a result and its timeout race).
final class Once<T>: @unchecked Sendable {
    private var c: CheckedContinuation<T, Never>?
    init(_ c: CheckedContinuation<T, Never>) { self.c = c }
    func resume(_ v: T) {
        c?.resume(returning: v)
        c = nil
    }
}

@MainActor
func after(_ seconds: Double, _ f: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        f()
    }
}

func randomName() -> String {
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    return "_" + String((0..<10).map { _ in letters[Int.random(in: 0..<letters.count)] })
}

func sha256Hex(_ d: Data) -> String {
    SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
}

func at(_ v: Any?, _ path: [Int]) -> Any? {
    var cur = v
    for i in path {
        guard let a = cur as? [Any], i >= 0, i < a.count else { return nil }
        cur = a[i]
    }
    return cur
}

/// The URL without the `/@lat,lng` camera part Google appends (as Android's diag line does).
func shortUrl(_ s: String) -> String {
    let head = s.components(separatedBy: "/@").first ?? s
    return String(head.prefix(120))
}

/// One WKWebView with the emulated `VelaBridge` (HiddenWebView's view and bridge).
@MainActor
final class Page: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let tag: String
    let webView: WKWebView
    let handlerName: String
    let googleOnly: Bool
    let t0 = ProcessInfo.processInfo.systemUptime
    var onFinish: (@MainActor (Int, String) -> Void)?
    var env = ""
    var finishes = 0
    var firstFinishMs = -1
    var injected = false
    var injectedMs = -1
    var resultMs = -1
    var results: [String: String] = [:]
    private var waiters: [String: Once<String?>] = [:]
    var infos: [String] = []
    var progress: [Int] = []
    var partials = 0
    var lastPartial: String?
    var terminatedMs = -1
    var histogram: String?
    var dates: String?
    var events: [String] = []

    init(tag: String, variant: Variant, size: CGSize, store: WKWebsiteDataStore, rules: WKContentRuleList?,
         bridgeName: String, handlerName: String, googleOnly: Bool, host: UIView) {
        self.tag = tag
        self.handlerName = handlerName
        self.googleOnly = googleOnly
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store
        cfg.defaultWebpagePreferences.preferredContentMode = variant.desktop ? .desktop : .mobile
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = .all
        let ucc = WKUserContentController()
        let bridgeJS = """
        (function(){
          var h = window.webkit.messageHandlers.\(handlerName);
          function f(n){ return function(){ try { h.postMessage({m:n, a:Array.prototype.slice.call(arguments).map(function(x){ return String(x); })}); } catch(e){} }; }
          var b = {onResult:f('onResult'), onProgress:f('onProgress'), onInfo:f('onInfo'), onHistogram:f('onHistogram'), onPartial:f('onPartial'), onDates:f('onDates')};
          try { Object.defineProperty(window, '\(bridgeName)', {value:b, writable:false, enumerable:false, configurable:false}); } catch(e) { window['\(bridgeName)'] = b; }
        })();
        """
        ucc.addUserScript(WKUserScript(source: bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if variant.noWebGL {
            let noGL = "(function(){ var g=HTMLCanvasElement.prototype.getContext; HTMLCanvasElement.prototype.getContext=function(t){ if(/webgl/i.test(String(t))) return null; return g.apply(this, arguments); }; })();"
            ucc.addUserScript(WKUserScript(source: noGL, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        if let rules { ucc.add(rules) }
        cfg.userContentController = ucc
        let wv = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: cfg)
        if variant.desktop { wv.customUserAgent = safariMacUA }
        webView = wv
        super.init()
        ucc.add(self, name: handlerName)
        webView.navigationDelegate = self
        switch variant.placement {
        case .visible:
            let top: CGFloat = 100
            let s = min(host.bounds.width / size.width, (host.bounds.height - top) / size.height)
            webView.bounds = CGRect(origin: .zero, size: size)
            webView.transform = CGAffineTransform(scaleX: s, y: s)
            webView.center = CGPoint(x: host.bounds.midX, y: top + size.height * s / 2)
            host.addSubview(webView)
        case .offscreen:
            webView.frame = CGRect(x: host.bounds.width + 2000, y: 0, width: size.width, height: size.height)
            host.addSubview(webView)
        case .detached:
            break
        }
    }

    func ms() -> Int { Int((ProcessInfo.processInfo.systemUptime - t0) * 1000) }

    func event(_ s: String) {
        let e = "\(ms())ms \(s)"
        events.append(e)
        Log.p("\(tag)|\(e)")
    }

    func load(_ url: String) {
        guard let u = URL(string: url) else { return }
        event("load \(shortUrl(url))")
        webView.load(URLRequest(url: u))
    }

    /// Fire-and-forget evaluation, as Android's `evaluateJavascript(js, null)`.
    func run(_ js: String) {
        webView.evaluateJavaScript(js) { [weak self] _, error in
            if let error { self?.event("eval error: \(error.localizedDescription)") }
        }
    }

    func evalString(_ js: String) async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            let once = Once(c)
            webView.evaluateJavaScript(js) { v, e in
                if let e { once.resume("error: \(e.localizedDescription)") } else { once.resume(v.map { "\($0)" } ?? "nil") }
            }
            after(5) { once.resume("eval timeout") }
        }
    }

    func deliver(_ id: String, _ payload: String) {
        if results[id] != nil { return }
        results[id] = payload
        waiters.removeValue(forKey: id)?.resume(payload)
    }

    func waitResult(_ id: String, timeout: Double) async -> String? {
        if let r = results[id] { return r }
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let once = Once(c)
            waiters[id] = once
            after(timeout) { [weak self] in
                self?.waiters.removeValue(forKey: id)
                once.resume(nil)
            }
        }
    }

    func snapshot(_ name: String) async {
        let cfg = WKSnapshotConfiguration()
        let img: UIImage? = await withCheckedContinuation { (c: CheckedContinuation<UIImage?, Never>) in
            let once = Once(c)
            webView.takeSnapshot(with: cfg) { image, error in
                if let error { Log.p("snapshot|\(name)|error \(error.localizedDescription)") }
                once.resume(image)
            }
            after(8) { once.resume(nil) }
        }
        if let d = img?.jpegData(compressionQuality: 0.6) {
            try? d.write(to: Log.docs.appendingPathComponent("snap-\(name).jpg"))
            Log.p("snapshot|\(name)|\(d.count) bytes")
        } else {
            Log.p("snapshot|\(name)|none")
        }
    }

    func teardown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
        webView.removeFromSuperview()
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let m = body["m"] as? String,
              let a = body["a"] as? [String], a.count >= 2 else { return }
        let id = a[0]
        let p = a[1]
        switch m {
        case "onResult":
            if resultMs < 0 { resultMs = ms() }
            event("onResult id=\(id) \(p.utf8.count) bytes")
            deliver(id, p)
        case "onProgress":
            progress.append(Int(p) ?? -1)
            event("onProgress \(p)")
        case "onInfo":
            infos.append(String(p.prefix(600)))
            event("onInfo \(p.prefix(600))")
        case "onHistogram":
            histogram = p
            event("onHistogram \(p)")
        case "onPartial":
            partials += 1
            lastPartial = p
        case "onDates":
            dates = p
            event("onDates \(p.utf8.count) bytes")
        default:
            event("unknown bridge call \(m)")
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let u = navigationAction.request.url
        let isMain = navigationAction.targetFrame?.isMainFrame ?? false
        if isMain {
            let scheme = u?.scheme ?? ""
            if scheme != "https" && scheme != "http" {
                event("blocked nav (scheme) \(shortUrl(u?.absoluteString ?? ""))")
                decisionHandler(.cancel)
                return
            }
            let host = u?.host ?? ""
            if googleOnly && !(host == "google.com" || host.hasSuffix(".google.com")) {
                event("blocked nav (host) \(shortUrl(u?.absoluteString ?? ""))")
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishes += 1
        if firstFinishMs < 0 { firstFinishMs = ms() }
        let url = webView.url?.absoluteString ?? ""
        event("finish #\(finishes) \(shortUrl(url))")
        if url == "about:blank" { return }
        onFinish?(finishes, url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        event("didFail \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        event("didFailProvisional \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        event("web content process terminated")
        if terminatedMs < 0 { terminatedMs = ms() }
        // The page and its script are gone: nothing will answer.
        let w = waiters
        waiters.removeAll()
        for (_, once) in w { once.resume(nil) }
    }
}

@MainActor
final class SpikeRunner {
    let host: UIView
    let status: UILabel
    let bridgeName = randomName()
    let panelName = randomName()
    let handlerName = randomName()
    var seq = 0
    var report: [String: Any] = [:]
    var variantsOut: [[String: Any]] = []

    static let envJS = "JSON.stringify({ua:navigator.userAgent,pf:navigator.platform,mtp:navigator.maxTouchPoints,w:innerWidth,h:innerHeight,dpr:devicePixelRatio,vis:document.visibilityState,focus:document.hasFocus(),lang:navigator.language,wd:navigator.webdriver===true})"
    // WebReviewsFetcher.onPageFinished's diagnostics line.
    static let reviewsDiagJS = "location.host+location.pathname.split('/@')[0].slice(0,40)+' lang='+document.documentElement.lang+' nav='+navigator.language"

    init(host: UIView, status: UILabel) {
        self.host = host
        self.status = status
    }

    func nextId() -> String {
        seq += 1
        return String(seq)
    }

    func say(_ s: String) {
        status.text = s
        Log.p("status|\(s)")
    }

    /// The Android script for request [id], with the per-process bridge names (JsNames.of).
    func script(_ b64: String, _ id: String) -> String {
        let js = String(decoding: Data(base64Encoded: b64) ?? Data(), as: UTF8.self)
        return js.replacingOccurrences(of: "@@ID@@", with: id)
            .replacingOccurrences(of: "VelaBridge", with: bridgeName)
            .replacingOccurrences(of: "VelaPanel", with: panelName)
    }

    func cid(_ featureId: String) -> String {
        let low = featureId.components(separatedBy: ":").last ?? ""
        let hex = low.hasPrefix("0x") ? String(low.dropFirst(2)) : low
        return UInt64(hex, radix: 16).map { String($0) } ?? ""
    }

    func runAll(args: [String]) async {
        after(1500) { [weak self] in
            Log.p("global timeout")
            self?.writeReport(done: false)
            exit(2)
        }
        let wanted = Set(args.filter { $0.count == 1 })
        let variants = wanted.isEmpty ? allVariants : (allVariants + otherVariants).filter { wanted.contains($0.key) }
        var shas: [String: Any] = [:]
        for (name, b64, expected) in [("reviews", GeneratedJS.reviewsB64, GeneratedJS.reviewsSha256),
                                      ("photos", GeneratedJS.photosB64, GeneratedJS.photosSha256),
                                      ("popular", GeneratedJS.popularB64, GeneratedJS.popularSha256)] {
            let got = sha256Hex(Data(base64Encoded: b64) ?? Data())
            shas[name] = ["sha256": got, "matchesGenerator": got == expected]
        }
        report["scripts"] = shas
        report["ios"] = UIDevice.current.systemVersion
        report["model"] = UIDevice.current.model
        report["bridgeNameLength"] = bridgeName.count
        report["cid"] = cid(GeneratedJS.featureId)
        Log.p("start|ios \(UIDevice.current.systemVersion)|cid \(cid(GeneratedJS.featureId))|scripts \(shas)")
        let rules = await compileRules()
        report["contentRules"] = rules != nil
        for v in variants {
            let store: WKWebsiteDataStore = v.persistent ? .default() : .nonPersistent()
            await seedCookies(store.httpCookieStore)
            var out: [String: Any] = [
                "variant": v.name, "desktop": v.desktop, "persistentStore": v.persistent, "placement": v.placement.rawValue,
            ]
            for s in v.scrapes {
                say("\(v.name): \(s)")
                let key = out[s] == nil ? s : s + "#2"
                switch s {
                case "reviews": out[key] = await runReviews(v, store, rules)
                case "popular": out[key] = await runPopular(v, store, rules)
                case "photos": out[key] = await runPhotos(v, store, rules)
                default: break
                }
                variantsOut.removeAll { ($0["variant"] as? String) == v.name }
                variantsOut.append(out)
                writeReport(done: false)
            }
            let cookies = await store.httpCookieStore.allCookies()
            out["cookies"] = cookies.map { "\($0.name)@\($0.domain)" }.sorted()
            variantsOut.removeAll { ($0["variant"] as? String) == v.name }
            variantsOut.append(out)
            writeReport(done: false)
        }
        writeReport(done: true)
        say("done")
        try? "done\n".write(to: Log.docs.appendingPathComponent("spike-done"), atomically: true, encoding: .utf8)
        after(1) { exit(0) }
    }

    func writeReport(done: Bool) {
        var r = report
        r["variants"] = variantsOut
        r["done"] = done
        guard JSONSerialization.isValidJSONObject(r),
              let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) else {
            Log.p("report|invalid json")
            return
        }
        try? d.write(to: Log.docs.appendingPathComponent("spike-result.json"))
    }

    func seedCookies(_ store: WKHTTPCookieStore) async {
        for (n, v) in [("SOCS", "CAESHAgBEhIaAB"), ("CONSENT", "YES+")] {
            let props: [HTTPCookiePropertyKey: Any] = [
                .domain: ".google.com", .path: "/", .name: n, .value: v,
                .expires: Date().addingTimeInterval(400 * 86400),
            ]
            if let c = HTTPCookie(properties: props) { await store.setCookie(c) }
        }
    }

    /// BlockedHosts as a WKContentRuleList (Android answers these requests empty in
    /// shouldInterceptRequest).
    func compileRules() async -> WKContentRuleList? {
        let hosts = ["doubleclick.net", "googleadservices.com", "googlesyndication.com",
                     "google-analytics.com", "googletagmanager.com", "adservice.google", "csi.gstatic.com"]
        func esc(_ s: String) -> String { s.replacingOccurrences(of: ".", with: "\\.") }
        var filters = hosts.map { "^https?://([a-z0-9-]+\\.)*" + esc($0) }
        filters += ["/gen_204", "/log204", "/log\\?", "/domainreliability/", "^https?://play\\.google\\.com/log"]
        let rules: [[String: Any]] = filters.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
        guard let d = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: d, encoding: .utf8) else { return nil }
        let store: WKContentRuleListStore? = WKContentRuleListStore.default()
        guard let store else { Log.p("rules|no store"); return nil }
        do {
            let list: WKContentRuleList? = try await store.compileContentRuleList(forIdentifier: "vela-blocked-hosts", encodedContentRuleList: json)
            Log.p("rules|compiled \(filters.count) rules|\(list != nil)")
            return list
        } catch {
            Log.p("rules|error \(error.localizedDescription)")
            return nil
        }
    }

    func makePage(_ tag: String, _ v: Variant, _ size: CGSize, _ store: WKWebsiteDataStore, _ rules: WKContentRuleList?, googleOnly: Bool) -> Page {
        Page(tag: "\(v.key)/\(tag)", variant: v, size: size, store: store, rules: rules,
             bridgeName: bridgeName, handlerName: handlerName, googleOnly: googleOnly, host: host)
    }

    /// Inject a page scraper once (the page-finish settle and the load cap race, as on Android).
    func inject(_ page: Page, _ js: String, _ id: String) {
        guard !page.injected, page.results[id] == nil else { return }
        page.injected = true
        page.injectedMs = page.ms()
        page.event("inject")
        page.run(js)
    }

    func common(_ page: Page) -> [String: Any] {
        [
            "firstFinishMs": page.firstFinishMs, "injectedMs": page.injectedMs, "resultMs": page.resultMs,
            "finishes": page.finishes, "terminatedMs": page.terminatedMs, "infos": Array(page.infos.prefix(20)), "events": Array(page.events.prefix(60)),
        ]
    }

    // MARK: WebReviewsFetcher

    func runReviews(_ v: Variant, _ store: WKWebsiteDataStore, _ rules: WKContentRuleList?) async -> [String: Any] {
        let size = v.desktop ? CGSize(width: 1200, height: 1000) : CGSize(width: 402, height: 874)
        let page = makePage("reviews", v, size, store, rules, googleOnly: true)
        let id = nextId()
        let js = script(GeneratedJS.reviewsB64, id)
        page.onFinish = { [weak self, weak page] n, _ in
            guard let self, let page else { return }
            Task { @MainActor in
                let d = await page.evalString(SpikeRunner.reviewsDiagJS)
                page.event("page loaded: \(d)")
                if n == 1 {
                    page.env = await page.evalString(SpikeRunner.envJS)
                    page.event("env: \(page.env)")
                }
            }
            after(0.15) { self.inject(page, js, id) }
        }
        page.load("https://www.google.com/maps?cid=\(cid(GeneratedJS.featureId))&hl=en&gl=us")
        after(7) { [weak self, weak page] in
            guard let self, let page else { return }
            self.inject(page, js, id)
        }
        let raw = await page.waitResult(id, timeout: 60)
        await page.snapshot("\(v.key)-reviews")
        var out = common(page)
        out["timedOut"] = raw == nil
        out["withinAndroidTimeout45s"] = raw != nil && page.resultMs <= 45_000
        out["env"] = page.env
        out["progressMax"] = page.progress.max() ?? 0
        out["partials"] = page.partials
        out["histogram"] = page.histogram ?? ""
        out.merge(summarizeReviews(raw)) { _, b in b }
        out["lastPartial"] = summarizeReviews(page.lastPartial)
        page.teardown()
        Log.p("result|\(v.key)/reviews|count \(out["count"] ?? 0)|ms \(page.resultMs)")
        return out
    }

    /// The fields ReviewsWebParser keeps.
    func summarizeReviews(_ raw: String?) -> [String: Any] {
        guard let raw else { return ["count": 0, "rawBytes": -1] }
        guard let arr = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [[String: Any]] else {
            return ["count": 0, "rawBytes": raw.utf8.count, "parseError": true]
        }
        var n = 0, rated = 0, texts = 0, textChars = 0, dates = 0, avatars = 0, withPhotos = 0, photos = 0, rids = 0
        var stars = [Int](repeating: 0, count: 6)
        var sampleDates: [String] = []
        for o in arr {
            let a = ((o["a"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if a.isEmpty { continue }
            n += 1
            let r = min(max((o["r"] as? Int) ?? 0, 0), 5)
            stars[r] += 1
            if r > 0 { rated += 1 }
            if let t = o["t"] as? String, !t.isEmpty { texts += 1; textChars += t.count }
            if let d = o["d"] as? String, !d.isEmpty {
                dates += 1
                if sampleDates.count < 5 { sampleDates.append(d) }
            }
            if let av = o["av"] as? String, av.hasPrefix("http") { avatars += 1 }
            let ps = Set(((o["p"] as? [String]) ?? []).filter { $0.hasPrefix("http") })
            if !ps.isEmpty { withPhotos += 1; photos += ps.count }
            if let rid = o["rid"] as? String, !rid.isEmpty { rids += 1 }
        }
        return [
            "rawBytes": raw.utf8.count, "entries": arr.count, "count": n, "withRating": rated, "stars0to5": stars,
            "withText": texts, "textChars": textChars, "withDate": dates, "sampleDates": sampleDates,
            "withAvatar": avatars, "withPhotos": withPhotos, "photoUrls": photos, "withReviewId": rids,
        ]
    }

    // MARK: WebPopularTimesFetcher

    func runPopular(_ v: Variant, _ store: WKWebsiteDataStore, _ rules: WKContentRuleList?) async -> [String: Any] {
        let size = v.desktop ? CGSize(width: 1200, height: 1000) : CGSize(width: 402, height: 874)
        let page = makePage("popular", v, size, store, rules, googleOnly: false)
        page.onFinish = { [weak page] n, _ in
            guard let page else { return }
            if n == 1 {
                after(0.5) { page.load(GeneratedJS.sessionWarmUrl) }
            } else {
                after(1.2) { page.deliver("warm", "") }
            }
        }
        page.load("https://www.google.com/?hl=en&gl=us")
        _ = await page.waitResult("warm", timeout: 9)
        let warmMs = page.ms()
        page.onFinish = nil
        let env = await page.evalString(SpikeRunner.envJS)
        page.event("env: \(env)")
        let id = nextId()
        page.injected = true
        page.injectedMs = page.ms()
        page.event("fetch details")
        page.run(script(GeneratedJS.popularB64, id))
        let raw = await page.waitResult(id, timeout: 30)
        await page.snapshot("\(v.key)-popular")
        var out = common(page)
        out["warmMs"] = warmMs
        out["timedOut"] = raw == nil
        out["withinAndroidTimeout22s"] = raw != nil && page.resultMs <= 22_000
        out["env"] = env
        if let raw {
            try? raw.write(to: Log.docs.appendingPathComponent("popular-\(v.key).txt"), atomically: true, encoding: .utf8)
        }
        out.merge(summarizePopular(raw)) { _, b in b }
        page.teardown()
        Log.p("result|\(v.key)/popular|days \(out["popularDays"] ?? 0)|bytes \(out["rawBytes"] ?? 0)|ms \(page.resultMs)")
        return out
    }

    /// What PopularTimesParser reads: the focused node [0][1][0][14] and the results list [64].
    func summarizePopular(_ raw: String?) -> [String: Any] {
        guard let raw else { return ["rawBytes": -1] }
        var body = raw
        for g in [")]}'\n", ")]}',\n", ")]}'", ")]}", "while(1);", "for(;;);"] where body.hasPrefix(g) {
            body = String(body.dropFirst(g.count))
            break
        }
        body = String(body.drop(while: { $0 == "\n" || $0 == "\r" }))
        if body.hasSuffix("/*\"\"*/") { body = String(body.dropLast(6)) }
        guard let root = try? JSONSerialization.jsonObject(with: Data(body.utf8), options: [.fragmentsAllowed]) else {
            return ["rawBytes": raw.utf8.count, "json": false, "head": String(raw.prefix(80))]
        }
        let node = at(root, [0, 1, 0, 14])
        var o: [String: Any] = ["rawBytes": raw.utf8.count, "json": true, "focusedNode": node is [Any]]
        o["focusedFid"] = (at(node, [10]) as? String) ?? ""
        o["focusedFidMatches"] = ((at(node, [10]) as? String) ?? "") == GeneratedJS.featureId
        o["focusedName"] = (at(node, [11]) as? String) ?? ""
        o["rating"] = (at(node, [4, 7]) as? Double) ?? -1
        o["reviewCount"] = (at(node, [4, 8]) as? Int) ?? -1
        o["address"] = at(node, [39]) is String
        o["hours203"] = at(node, [203, 0]) is [Any]
        o["editorial"] = at(node, [32, 1, 1]) is String
        o["phone"] = at(node, [178, 0, 0]) is String
        let days = at(node, [84, 0]) as? [Any]
        o["popularDays"] = days?.count ?? 0
        var slots = 0
        for d in days ?? [] { slots += (at(d, [1]) as? [Any])?.count ?? 0 }
        o["popularHourSlots"] = slots
        let list = at(root, [64]) as? [Any]
        o["resultsList"] = list?.count ?? 0
        o["resultsWithPopular"] = (list ?? []).filter { at($0, [1, 84, 0]) is [Any] }.count
        return o
    }

    // MARK: WebPhotoFetcher

    func runPhotos(_ v: Variant, _ store: WKWebsiteDataStore, _ rules: WKContentRuleList?) async -> [String: Any] {
        let size = v.desktop ? CGSize(width: 1200, height: 3200) : CGSize(width: 402, height: 874)
        let page = makePage("photos", v, size, store, rules, googleOnly: true)
        let id = nextId()
        let js = script(GeneratedJS.photosB64, id)
        page.onFinish = { [weak self, weak page] _, _ in
            guard let self, let page else { return }
            after(1.2) { self.inject(page, js, id) }
        }
        page.load("https://www.google.com/maps?cid=\(cid(GeneratedJS.featureId))&hl=en&gl=us")
        after(7) { [weak self, weak page] in
            guard let self, let page else { return }
            self.inject(page, js, id)
        }
        let raw = await page.waitResult(id, timeout: 70)
        await page.snapshot("\(v.key)-photos")
        var out = common(page)
        out["timedOut"] = raw == nil
        out["withinAndroidTimeout55s"] = raw != nil && page.resultMs <= 55_000
        out["partials"] = page.partials
        out["histogram"] = page.histogram ?? ""
        let lines = (raw ?? "").split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var cats: [String: Int] = [:]
        for l in lines {
            let c = l.components(separatedBy: "\t").count > 1 ? (l.components(separatedBy: "\t").first ?? "") : ""
            cats[c.isEmpty ? "(all)" : c, default: 0] += 1
        }
        out["count"] = lines.count
        out["categories"] = cats
        if let dates = page.dates, let arr = (try? JSONSerialization.jsonObject(with: Data(dates.utf8))) as? [Any] {
            out["datedPhotos"] = arr.count
        } else {
            out["datedPhotos"] = 0
        }
        page.teardown()
        Log.p("result|\(v.key)/photos|count \(lines.count)|ms \(page.resultMs)")
        return out
    }
}
