import Foundation
import VelaCore

/// The `VelaHttp` seam over `URLSession` (PORTAGE_IOS.md D4, SPEC "Platform seams"). An ephemeral
/// session with no cookie storage and no cache: cookies live in `cookies` only, pre-seeded with
/// Google's consent cookies, and go out on every request and redirect to the same host.
///
/// The callback runs exactly once, on a background queue: with the response (any status code), or
/// with an `IosHttpException` (`timeout`, `cancelled`, `network`).
final class URLSessionVelaHttp: NSObject, VelaHttp {
    /// The whole-call deadline when a request sets none: the shared Android client's 12 s.
    static let defaultDeadlineMillis: Int64 = 12_000

    let cookies: CookieJar
    private let session: URLSession

    /// `followsRedirects: false` hands a 3xx answer back to the caller, the way
    /// `ShortLinks.resolve` reads the shortener's `Location` without loading the target.
    init(cookies: CookieJar = .app, followsRedirects: Bool = true) {
        self.cookies = cookies
        let config = URLSessionConfiguration.ephemeral
        #if DEBUG
        NavAlertTestSupport.configure(session: config)
        MapLayersTestSupport.configure(session: config)
        PlaceFixtureLaunch.configure(session: config)
        #endif
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config,
                             delegate: RedirectCookies(cookies: cookies, followsRedirects: followsRedirects),
                             delegateQueue: nil)
        super.init()
    }

    func execute(request: HttpRequest, callback: @escaping (HttpResponse?, KotlinThrowable?) -> Void) -> any VelaCore.Cancellable {
        let call = HttpCall(callback: callback)
        guard let url = URL(string: request.url) else {
            call.finish(nil, IosHttpException(message: "Malformed URL", reason: "network"))
            return call
        }
        // The one funnel every main request crosses. A Google request is refused on the phone
        // before the first-run answer, and while "Use Vela without Google" is on, except the one
        // shortener hop the user explicitly allowed (SET-PRIVACY).
        if let host = url.host, PrivacyPolicy.shared.isGoogleHost(host: host),
           !request.tags.allowGoogleWhenOff, !PrivacySettings.googleAllowed {
            PrivacyRequestCounter.noteBlocked(url)
            call.finish(nil, IosHttpException(message: "Google is disabled", reason: "blocked"))
            return call
        }
        PrivacyRequestCounter.noteSent(url)
        #if DEBUG
        DebugRequestCounter.shared.record(url)
        #endif
        var req = URLRequest(url: url)
        req.httpMethod = request.method
        for header in request.headers {
            req.addValue(header.value, forHTTPHeaderField: header.name)
        }
        if let cookie = cookies.header(for: url) {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let contentType = request.contentType {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let body = IosBytes.shared.bodyOf(request: request) {
            req.httpBody = body
        } else if ["POST", "PUT", "PATCH"].contains(request.method.uppercased()) {
            req.httpBody = Data()
        }
        let deadlineMillis = request.timeoutMillis > 0 ? request.timeoutMillis : Self.defaultDeadlineMillis
        req.timeoutInterval = Double(deadlineMillis) / 1000

        let cookies = self.cookies
        let task = session.dataTask(with: req) { data, response, error in
            if let http = response as? HTTPURLResponse, error == nil {
                let answered = http.url ?? url
                cookies.store(from: http, url: answered)
                var headers: [HttpHeader] = []
                for (name, value) in http.allHeaderFields {
                    headers.append(HttpHeader(name: "\(name)", value: "\(value)"))
                }
                let reply = IosBytes.shared.response(
                    code: Int32(http.statusCode), headers: headers, body: data ?? Data(),
                    finalUrl: answered.absoluteString)
                call.finish(reply, nil)
                return
            }
            let ns = error as NSError?
            let reason: String
            switch ns?.code {
            case NSURLErrorTimedOut: reason = "timeout"
            case NSURLErrorCancelled: reason = "cancelled"
            default: reason = "network"
            }
            call.finish(nil, IosHttpException(message: ns?.localizedDescription ?? "No response", reason: reason))
        }
        call.start(task, deadlineMillis: deadlineMillis)
        return call
    }
}

/// One request in flight: the once-only callback, the task and its deadline.
private final class HttpCall: NSObject, VelaCore.Cancellable {
    private let lock = NSLock()
    private var callback: ((HttpResponse?, KotlinThrowable?) -> Void)?
    private var task: URLSessionTask?
    private var deadline: DispatchWorkItem?

    init(callback: @escaping (HttpResponse?, KotlinThrowable?) -> Void) {
        self.callback = callback
    }

    func start(_ task: URLSessionTask, deadlineMillis: Int64) {
        let deadline = DispatchWorkItem { [weak self] in
            self?.stop(IosHttpException(message: "Deadline of \(deadlineMillis) ms passed", reason: "timeout"))
        }
        lock.lock()
        let live = callback != nil
        if live {
            self.task = task
            self.deadline = deadline
        }
        lock.unlock()
        guard live else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(Int(deadlineMillis)), execute: deadline)
        task.resume()
    }

    func cancel() {
        stop(IosHttpException(message: "Cancelled", reason: "cancelled"))
    }

    private func stop(_ error: IosHttpException) {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(nil, error)
    }

    func finish(_ response: HttpResponse?, _ error: KotlinThrowable?) {
        lock.lock()
        let callback = self.callback
        self.callback = nil
        let deadline = self.deadline
        self.deadline = nil
        self.task = nil
        lock.unlock()
        deadline?.cancel()
        callback?(response, error)
    }
}

/// Keeps the cookie jar in step across redirects: the cookies a redirect sets, and the ones the
/// next host should get.
private final class RedirectCookies: NSObject, URLSessionTaskDelegate {
    private let cookies: CookieJar
    private let followsRedirects: Bool

    init(cookies: CookieJar, followsRedirects: Bool) {
        self.cookies = cookies
        self.followsRedirects = followsRedirects
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let from = response.url ?? task.currentRequest?.url {
            cookies.store(from: response, url: from)
        }
        guard followsRedirects else {
            completionHandler(nil)
            return
        }
        var next = request
        if let url = request.url {
            next.setValue(cookies.header(for: url), forHTTPHeaderField: "Cookie")
        }
        completionHandler(next)
    }
}
