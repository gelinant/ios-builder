import SwiftUI
import WebKit

/// The events the bundled terrain document reports to Swift. The JavaScript side owns the map,
/// the DEM and the sky; Swift only shows what it reports and never drives the camera.
enum TerrainScreenEvent: Equatable {
    /// The bundled document executed its script, before the map is created.
    case document
    /// The MapLibre GL JS style finished loading.
    case loaded
    /// The elevation source delivered tiles and terrain is drawing.
    case dem
    /// A tile or style failure the page could not recover from.
    case failure(String)
    /// Terrain cannot be drawn: no network, blocked elevation host, or a WebGL failure.
    case unavailable(String)
}

/// The one WKWebView of the terrain screen. It loads `terrain/index.html` from the app bundle,
/// with the pinned MapLibre GL JS and its stylesheet inlined. No remote document, no CDN, no
/// timer.
struct TerrainWebView: UIViewRepresentable {
    let onEvent: (TerrainScreenEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(context.coordinator, name: Coordinator.handlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.accessibilityIdentifier = "terrain-map"
        // VoiceOver reaches the close button and the status line; the map itself is a direct
        // touch surface, as on the native map.
        webView.isAccessibilityElement = false
        context.coordinator.webView = webView
        context.coordinator.demHandler.webView = webView

        Self.loadDocument(in: webView, onEvent: onEvent)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    /// The page is assembled from the three bundled files and loaded with the OpenFreeMap origin,
    /// so the style, tiles and glyphs are same-origin fetches. A file document would run with an
    /// opaque origin and depend on the remote host's CORS policy for every request. If a bundled
    /// file is missing, the plain local document is loaded instead.
    private static func loadDocument(in webView: WKWebView, onEvent: (TerrainScreenEvent) -> Void) {
        guard let document = documentURL else {
            onEvent(.unavailable("missing-resource"))
            return
        }
        let directory = document.deletingLastPathComponent()
        let scriptTag = "<script src=\"maplibre-gl.js\"></script>"
        let styleTag = "<link rel=\"stylesheet\" href=\"maplibre-gl.css\" />"
        if let html = try? String(contentsOf: document, encoding: .utf8),
           let script = try? String(contentsOf: directory.appendingPathComponent("maplibre-gl.js"),
                                     encoding: .utf8),
           let stylesheet = try? String(contentsOf: directory.appendingPathComponent("maplibre-gl.css"),
                                        encoding: .utf8),
           html.contains(scriptTag), html.contains(styleTag) {
            let inlined = html
                .replacingOccurrences(of: styleTag, with: "<style>\(stylesheet)</style>")
                .replacingOccurrences(of: scriptTag, with: "<script>\(script)</script>")
            webView.loadHTMLString(inlined, baseURL: URL(string: "https://tiles.openfreemap.org/"))
        } else {
            webView.loadFileURL(document, allowingReadAccessTo: directory)
        }
    }

    /// Closing the sheet destroys the only WKWebView: its script handler goes, the load stops,
    /// queued elevation requests are cancelled and the web process is released with the view.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.demHandler.shutdown()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.handlerName)
        webView.configuration.userContentController.removeAllUserScripts()
        webView.loadHTMLString("", baseURL: nil)
        coordinator.webView = nil
    }

    /// Xcode flattens regular resources into the bundle root, so try the folder first and the
    /// root second. The JavaScript and the stylesheet sit next to it either way.
    static var documentURL: URL? {
        let bundle = Bundle.main
        return bundle.url(forResource: "index", withExtension: "html", subdirectory: "terrain")
            ?? bundle.url(forResource: "index", withExtension: "html", subdirectory: "Resources/terrain")
            ?? bundle.url(forResource: "index", withExtension: "html")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "terrain"

        private let onEvent: (TerrainScreenEvent) -> Void
        let demHandler = TerrainDEMHandler()
        weak var webView: WKWebView?

        init(onEvent: @escaping (TerrainScreenEvent) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == Self.handlerName,
                  let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            switch event {
            case "document":
                onEvent(.document)
            case "loaded":
                onEvent(.loaded)
            case "dem":
                onEvent(.dem)
            case "dem_request":
                guard let id = body["id"] as? String, let url = body["url"] as? String else { return }
                demHandler.fetch(id: id, tileURL: url)
            case "failure":
                onEvent(.failure(body["message"] as? String ?? "error"))
            case "unavailable":
                let reason = body["reason"] as? String ?? "unknown"
                onEvent(.unavailable(reason))
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onEvent(.unavailable("load"))
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            onEvent(.unavailable("load"))
        }
    }
}

/// Answers the page's `vela-dem` protocol. The AWS bucket sends no CORS header, so a browser
/// fetch cannot read its tiles; URLSession can. Each tile is fetched here and handed back to the
/// page as base64, which MapLibre decodes as its raster-dem image. Nothing runs once the screen
/// is closed: the session is invalidated and every pending task is cancelled.
final class TerrainDEMHandler: NSObject {
    private static let upstream = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium"

    private let session: URLSession
    private var running: [String: URLSessionDataTask] = [:]
    private var isClosed = false
    weak var webView: WKWebView?

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration)
        super.init()
    }

    deinit {
        session.invalidateAndCancel()
    }

    func fetch(id: String, tileURL: String) {
        guard !isClosed, let upstream = Self.upstreamURL(from: tileURL) else {
            reject(id)
            return
        }
        let task = session.dataTask(with: upstream) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, !self.isClosed else { return }
                self.running.removeValue(forKey: id)
                guard error == nil,
                      let data,
                      let http = response as? HTTPURLResponse,
                      http.statusCode == 200 else {
                    self.reject(id)
                    return
                }
                self.resolve(id: id, data: data)
            }
        }
        running[id] = task
        task.resume()
    }

    /// Called from `dismantleUIView`, before the web view goes away.
    func shutdown() {
        DispatchQueue.main.async {
            self.isClosed = true
            for task in self.running.values { task.cancel() }
            self.running.removeAll()
            self.webView = nil
            self.session.invalidateAndCancel()
        }
    }

    private func resolve(id: String, data: Data) {
        guard let webView else { return }
        let base64 = data.base64EncodedString()
        let script = "window.terrainDEM && window.terrainDEM.resolve(\(Self.literal(id)), \(Self.literal(base64)));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func reject(_ id: String) {
        guard let webView else { return }
        let script = "window.terrainDEM && window.terrainDEM.reject(\(Self.literal(id)), \"dem\");"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// A quoted JavaScript string literal, safe for an id or a base64 payload.
    private static func literal(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }

    /// `vela-dem://tile/{z}/{x}/{y}.png` to the pinned terrarium URL. `tile` is the URL host, so
    /// the three path components are the zoom, the column and the row.
    private static func upstreamURL(from tileURL: String) -> URL? {
        guard let url = URL(string: tileURL) else { return nil }
        var parts = url.pathComponents.filter { $0 != "/" }
        if url.host != "tile" {
            guard parts.first == "tile" else { return nil }
            parts.removeFirst()
        }
        guard parts.count == 3, parts[2].hasSuffix(".png") else { return nil }
        let y = parts[2].replacingOccurrences(of: ".png", with: "")
        guard parts[0].allSatisfy(\.isNumber), parts[1].allSatisfy(\.isNumber),
              y.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "\(upstream)/\(parts[0])/\(parts[1])/\(y).png")
    }
}
