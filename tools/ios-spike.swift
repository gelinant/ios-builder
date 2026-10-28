#!/usr/bin/env swift
// Vela iOS scrape spike (W-1). Run on macOS:  swift tools/ios-spike.swift [identity ...]
// Replays Vela's keyless Google requests (the set GoogleHealthProbeTest checks) (calibration.json v27) over Apple's network stack
// (URLSession / CFNetwork, the same TLS stack an iOS app gets) and reports, per identity,
// whether Google answers with real data or with a consent wall, a /sorry page or a thin reply.
//
// Identities:
//   chrome-win   what Android Vela claims today (Chrome 156 desktop). Its TLS handshake will
//                NOT match the UA on Apple: there is no current Cronet build for iOS.
//   safari-mac   desktop Safari. UA and TLS come from the same vendor; no client hints.
//   safari-ios   mobile Safari, the identity a WKWebView has by default.
// With no argument the three run one after the other, each with a fresh cookie store.
import Foundation

// ---- endpoints and templates (byte-exact from calibration.json) ----
let WARM_URL      = "https://www.google.com/maps?hl=en&gl=us"
let SEARCH_EP     = "https://www.google.com/search?tbm=map&authuser=0&hl=en&gl=us"
let DIRECTIONS_EP = "https://www.google.com/maps/preview/directions?authuser=0&hl=en&gl=us"
let REVIEWS_EP    = "https://www.google.com/maps/preview/review/listentitiesreviews?authuser=0&hl=en&gl=us"
func batchUrl(_ rpc: String) -> String {
    "https://www.google.com/maps/_/MapsWizUi/data/batchexecute?rpcids=\(rpc)&source-path=%2Fmaps&hl=en&gl=us&_reqid=\(Int.random(in: 1000...99999))&rt=c"
}
// Calibration.DEFAULT_RPC_CONTEXT and DEFAULT_REVIEW_FEED_PROTO (not overridden in calibration.json v27).
let RPC_CONTEXT   = "CAE="
let REVIEW_FEED_PROTO = "[[[\"{FID}\"],null,null,null,null,[null,null,null,[[1],[3]]]],[10,\"{TOKEN}\"],null,null,[null,null,null,null,null,null,81],null,null,[null,1,1,null,1,null,1,null,null,null,null,[1,1,null,[[1]]]],null,null,[3,1,null,null,null,[2]],null,[1]]"
// GoogleHealthProbeTest's fixture business (Davis Food Co-op).
let FIXTURE_FID   = "0x8085299fd6f41a23:0x10d37b4cae550f0"

let SEARCH_PB     = "!1s{QUERY}!4m8!1m3!1d25229.167291701906!2d{LNG}!3d{LAT}!3m2!1i1024!2i768!4f13.1!7i20!10b1!12m52!1m5!18b1!30b1!31m1!1b1!34e1!2m4!5m1!6e2!20e3!39b1!6m25!32i1!49b1!63m0!66b1!85b1!114b1!149b1!206b1!209b1!212b1!216b1!222b1!223b1!232b1!234b1!235b1!244b1!246b1!250b1!253b1!260b1!266b1!273b1!281b1!291m0!10b1!12b1!13b1!14b1!16b1!17m1!3e1!20m3!5e2!6b1!14b1!46m1!1b0!96b1!99b1!19m4!2m3!1i360!2i120!4i8!20m57!2m2!1i203!2i100!3m2!2i4!5b1!6m6!1m2!1i86!2i86!1m2!1i408!2i240!7m33!1m3!1e1!2b0!3e3!1m3!1e2!2b1!3e2!1m3!1e2!2b0!3e3!1m3!1e8!2b0!3e3!1m3!1e10!2b0!3e3!1m3!1e10!2b1!3e2!1m3!1e10!2b0!3e4!1m3!1e9!2b1!3e2!2b1!9b0!15m8!1m7!1m2!1m1!1e2!2m2!1i195!2i195!3i20!15i9937!24m107!1m25!13m9!2b1!3b1!4b1!6i1!8b1!9b1!14b1!20b1!25b1!18m14!3b1!4b1!5b1!6b1!13b1!14b1!17b1!21b1!22b1!32b1!33m1!1b1!34b1!36e2!10m1!8e3!11m1!3e1!17b1!20m2!1e3!1e6!24b1!25b1!26b1!27b1!29b1!30m1!2b1!36b1!37b1!39m3!2m2!2i1!3i1!43b1!52b1!54m1!1b1!55b1!56m1!1b1!61m2!1m1!1e1!65m5!3m4!1m3!1m2!1i224!2i298!72m22!1m8!2b1!5b1!7b1!12m4!1b1!2b1!4m1!1e1!4b1!8m10!1m6!4m1!1e1!4m1!1e3!4m1!1e4!3sother_user_google_review_posts__and__hotel_and_vr_partner_review_posts!6m1!1e1!9b1!89b1!90m2!1m1!1e2!98m3!1b1!2b1!3b1!103b1!113b1!114m3!1b1!2m1!1b1!117b1!122m1!1b1!126b1!127b1!128m1!1b0!26m4!2m3!1i80!2i92!4i8!30m28!1m6!1m2!1i0!2i0!2m2!1i530!2i768!1m6!1m2!1i974!2i0!2m2!1i1024!2i768!1m6!1m2!1i0!2i0!2m2!1i1024!2i20!1m6!1m2!1i0!2i748!2m2!1i1024!2i768!34m19!2b1!3b1!4b1!6b1!8m6!1b1!3b1!4b1!5b1!6b1!7b1!9b1!12b1!14b1!20b1!23b1!25b1!26b1!31b1!37m1!1e81!42b1!49m10!3b1!6m2!1b1!2b1!7m2!1e3!2b1!8b1!9b1!10e2!50m3!2e2!3m1!3b1!61b1!67m5!7b1!10b1!14b1!15m1!1b0!69i782!77b1"
let DIRECTIONS_PB = "!1m4!3m2!3d{OLAT}!4d{OLNG}!6e2!1m4!3m2!3d{DLAT}!4d{DLNG}!6e2!3m12!1m3!1d24960.741896132306!2d-121.7527808!3d38.554674999999996!2m3!1f0.0!2f0.0!3f0.0!3m2!1i1024!2i768!4f13.1!6m56!1m5!18b1!30b1!31m1!1b1!34e1!2m4!5m1!6e2!20e3!39b1!6m27!32i1!49b1!63m0!66b1!85b1!114b1!149b1!206b1!209b1!212b1!216b1!222b1!223b1!232b1!234b1!235b1!244b1!246b1!250b1!253b1!260b1!266b1!270b1!273b1!279b1!281b1!291m0!10b1!12b1!13b1!14b1!16b1!17m1!3e1!20m5!1e{MODE}!2e3!5e2!6b1!14b1!46m1!1b0!96b1!99b1!15i10142!20m28!1m6!1m2!1i0!2i0!2m2!1i530!2i768!1m6!1m2!1i974!2i0!2m2!1i1024!2i768!1m6!1m2!1i0!2i0!2m2!1i1024!2i20!1m6!1m2!1i0!2i748!2m2!1i1024!2i768!27b1!40i783!47m2!8b1!10e2"
let REVIEWS_PB    = "!1m2!1y{HIGH}!2y{LOW}!2m2!2i0!3i20!3e1!5m2!1svela!7e81"
let PHOTOS_PROTO  = "[2,null,[\"{FID}\",null,null,null,null,null,null,null,0],null,[null,[1200,1000],[null,{COUNT},null,null,1],null,null,null,[[[1,0,3],[2,1,2],[2,0,3],[8,0,3],[10,0,3],[10,1,2],[10,0,4],[9,1,2]],1],null,0],null,null,null,null,null,null,null,null,null,null,[null,1,null,1]]"

// ---- identities ----
struct Identity {
    let name: String
    let ua: String
    let acceptDoc: String
    let clientHints: [String: String]   // empty for Safari: it sends none
}
let IDENTITIES: [Identity] = [
    Identity(
        name: "chrome-win",
        ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36",
        acceptDoc: "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        clientHints: [
            "Sec-CH-UA": "\"Not:A-Brand\";v=\"8\", \"Chromium\";v=\"156\", \"Google Chrome\";v=\"156\"",
            "Sec-CH-UA-Mobile": "?0",
            "Sec-CH-UA-Platform": "\"Windows\"",
        ]),
    Identity(
        name: "safari-mac",
        ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
        acceptDoc: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        clientHints: [:]),
    Identity(
        name: "safari-ios",
        ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
        acceptDoc: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        clientHints: [:]),
]

// ---- Java URLEncoder.encode equivalent (space -> +, keep .-*_ alnum) ----
func javaURLEncode(_ s: String) -> String {
    var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    allowed.insert(charactersIn: "-._*")
    let pct = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    return pct.replacingOccurrences(of: "%20", with: "+")
}

func jsonString(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
    let arr = String(data: data, encoding: .utf8)!
    return String(arr.dropFirst().dropLast())
}

struct Reply { let code: Int; let bytes: Int; let ms: Int; let finalURL: String; let text: String }

final class Client {
    let id: Identity
    let session: URLSession
    // Own jar, keyed by host, like the health probe's: a bare HTTPCookieStorage() instance does not
    // store anything, so URLSession's automatic handling is off and the headers are set by hand.
    var jar: [String: [String: String]] = [:]

    init(_ id: Identity) {
        self.id = id
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 30
        session = URLSession(configuration: cfg)
        // Pre-seeded like CoreModule.InMemoryCookieJar.
        for h in ["www.google.com", "google.com", "consent.google.com"] {
            jar[h] = ["SOCS": "CAESHAgBEhIaAB", "CONSENT": "YES+"]
        }
    }

    func call(_ method: String, _ url: String, body: String? = nil, xhr: Bool, extra: [String: String] = [:]) -> Reply {
        let u = URL(string: url)!
        var req = URLRequest(url: u)
        if let cookies = jar[u.host ?? ""], !cookies.isEmpty {
            req.setValue(cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        for (k, v) in extra { req.setValue(v, forHTTPHeaderField: k) }
        req.httpMethod = method
        req.setValue(id.ua, forHTTPHeaderField: "User-Agent")
        req.setValue(xhr ? "*/*" : id.acceptDoc, forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        for (k, v) in id.clientHints { req.setValue(v, forHTTPHeaderField: k) }
        if xhr {
            req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
            req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
            req.setValue("https://www.google.com/maps", forHTTPHeaderField: "Referer")
            if !id.clientHints.isEmpty {
                req.setValue("10", forHTTPHeaderField: "Downlink")
                req.setValue("50", forHTTPHeaderField: "RTT")
            }
        } else {
            req.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
            req.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
            req.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        }
        if let b = body {
            req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = b.data(using: .utf8)
        }
        let sem = DispatchSemaphore(value: 0)
        var out = Reply(code: 0, bytes: 0, ms: 0, finalURL: "", text: "")
        let t0 = Date()
        session.dataTask(with: req) { data, resp, err in
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let r = resp as? HTTPURLResponse
            if let r = r, let host = u.host {
                let fields = r.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
                for c in HTTPCookie.cookies(withResponseHeaderFields: fields, for: u) {
                    let target = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                    for h in Set([host, target, "www." + target].filter { $0.hasSuffix("google.com") }) {
                        self.jar[h, default: [:]][c.name] = c.value
                    }
                }
            }
            let d = data ?? Data()
            let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? ""
            out = Reply(code: r?.statusCode ?? -1, bytes: d.count, ms: ms,
                        finalURL: r?.url?.absoluteString ?? (err.map { "error: \($0.localizedDescription)" } ?? ""), text: text)
            sem.signal()
        }.resume()
        sem.wait()
        // Spread requests the way core/util/Jitter does, roughly.
        Thread.sleep(forTimeInterval: Double.random(in: 1.0...2.5))
        return out
    }
}

func verdict(_ r: Reply, expectAtLeast: Int) -> String {
    let low = r.text.lowercased()
    var sig: [String] = []
    if r.finalURL.contains("consent.google") { sig.append("CONSENT-WALL") }
    if r.finalURL.contains("/sorry") || low.contains("/sorry/index") { sig.append("SORRY") }
    if low.contains("recaptcha") || low.contains("captcha") { sig.append("CAPTCHA?") }
    if r.code != 200 { sig.append("HTTP-\(r.code)") }
    if r.code == 200 && r.bytes < expectAtLeast { sig.append("THIN(<\(expectAtLeast)B)") }
    return sig.isEmpty ? "OK" : sig.joined(separator: ",")
}

func row(_ label: String, _ r: Reply, expectAtLeast: Int) {
    let head = String(r.text.prefix(100)).replacingOccurrences(of: "\n", with: " ")
    let v = verdict(r, expectAtLeast: expectAtLeast)
    print("  \(label.padding(toLength: 11, withPad: " ", startingAt: 0)) HTTP \(r.code)  \(String(r.bytes).padding(toLength: 8, withPad: " ", startingAt: 0))B  \(String(r.ms).padding(toLength: 6, withPad: " ", startingAt: 0))ms  \(v)")
    print("              \(head)")
}

func firstFeatureId(_ s: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: "0x[0-9a-f]{8,16}:0x[0-9a-f]{8,16}") else { return nil }
    let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    return m.flatMap { Range($0.range, in: s).map { String(s[$0]) } }
}

// Fixtures from CLAUDE.md "Location hygiene": Davis, California.
let query = "coffee"
let lat = "38.55", lng = "-121.74"

func run(_ id: Identity) {
    print("=== identity \(id.name) ===")
    let c = Client(id)

    row("warm-up", c.call("GET", WARM_URL, xhr: false), expectAtLeast: 50_000)

    let pb = SEARCH_PB
        .replacingOccurrences(of: "{QUERY}", with: query)
        .replacingOccurrences(of: "{LAT}", with: lat)
        .replacingOccurrences(of: "{LNG}", with: lng)
    let search = c.call("GET", SEARCH_EP + "&q=" + javaURLEncode(query) + "&pb=" + javaURLEncode(pb), xhr: true)
    row("search", search, expectAtLeast: 20_000)

    let found = firstFeatureId(search.text)
    print("              feature id found in search: \(found != nil ? "yes" : "no")")
    let fid = FIXTURE_FID
    let rpcHeaders = ["X-Same-Domain": "1", "x-maps-diversion-context-bin": RPC_CONTEXT]
    func rpc(_ id: String, _ inner: String) -> Reply {
        let freq = "[[[\"\(id)\",\(jsonString(inner)),null,\"generic\"]]]"
        return c.call("POST", batchUrl(id), body: "f.req=" + javaURLEncode(freq) + "&", xhr: true, extra: rpcHeaders)
    }

    let parts = fid.split(separator: ":").map { String($0.dropFirst(2)) }
    if parts.count == 2, let hi = UInt64(parts[0], radix: 16), let lo = UInt64(parts[1], radix: 16) {
        let rpb = REVIEWS_PB.replacingOccurrences(of: "{HIGH}", with: String(hi)).replacingOccurrences(of: "{LOW}", with: String(lo))
        row("reviews-old", c.call("GET", REVIEWS_EP + "&pb=" + javaURLEncode(rpb), xhr: true), expectAtLeast: 2_000)
    }
    let feed = rpc("qv9Egd", REVIEW_FEED_PROTO.replacingOccurrences(of: "{FID}", with: fid).replacingOccurrences(of: "{TOKEN}", with: ""))
    row("review-feed", feed, expectAtLeast: 5_000)
    let photos = rpc("hspqX", PHOTOS_PROTO.replacingOccurrences(of: "{FID}", with: fid).replacingOccurrences(of: "{COUNT}", with: "40")
        .replacingOccurrences(of: "[1200,1000]", with: "[1920,945]"))
    row("photos", photos, expectAtLeast: 5_000)
    print("              photo URLs in reply: \(photos.text.components(separatedBy: "googleusercontent.com").count - 1)")

    let dpb = DIRECTIONS_PB
        .replacingOccurrences(of: "{OLAT}", with: "38.5500").replacingOccurrences(of: "{OLNG}", with: "-121.7400")
        .replacingOccurrences(of: "{DLAT}", with: "38.5582").replacingOccurrences(of: "{DLNG}", with: "-121.7864")
        .replacingOccurrences(of: "{MODE}", with: "0")
    row("directions", c.call("GET", DIRECTIONS_EP + "&pb=" + javaURLEncode(dpb), xhr: true), expectAtLeast: 5_000)

    let names = Set(c.jar.values.flatMap { $0.keys })
    print("  cookies after session: \(names.sorted().joined(separator: " "))\n")
}

let wanted = CommandLine.arguments.dropFirst()
for id in IDENTITIES where wanted.isEmpty || wanted.contains(id.name) { run(id) }
print("Read: OK on search + reviews + photos for an identity = that identity passes from Apple's stack.")
print("Paste the full output into the W-1 report (docs/ios/spike-scraping-ios.md, section 6).")
