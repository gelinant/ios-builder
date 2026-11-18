import Foundation
import VelaCore

/// Answers the page's data requests (webmap.js `swiftRequest`). Three kinds:
/// - `vela-file://<path>`: a local file (offline glyphs, sprites, styles);
/// - `vela-pmtiles://<archive>/<z>/<x>/<y>`: one tile of a registered PMTiles archive,
///   decompressed, read with the shared Kotlin reader;
/// - `vela-nets://` and `vela-net://`: an HTTPS or HTTP URL fetched with URLSession, for hosts that
///   send no CORS header (the elevation tiles, Google and Esri rasters). Google requests get the
///   calibrated browser headers through `MapTileNetwork`.
///
/// Results are base64, the form `evaluateJavaScript` carries; a missing PMTiles tile is an empty
/// tile, every other miss is a failure the page treats as a missing tile.
final class WebMapResources {
    static let shared = WebMapResources()

    enum Result {
        case data(String)
        case failure(Int)
    }

    final class Request {
        private let lock = NSLock()
        private var cancelled = false
        fileprivate var task: URLSessionTask?

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }

    struct ArchiveInfo {
        let key: String
        let minZoom: Int
        let maxZoom: Int
    }

    private final class ArchiveHandle {
        let path: String
        let queue: DispatchQueue
        var archive: PmtilesReader.Archive?

        init(path: String, key: String) {
            self.path = path
            queue = DispatchQueue(label: "app.vela.webmap.pmtiles.\(key)", qos: .userInitiated)
        }
    }

    private let lock = NSLock()
    private var archives: [String: ArchiveHandle] = [:]
    private var infoByPath: [String: ArchiveInfo] = [:]
    private let fileQueue = DispatchQueue(
        label: "app.vela.webmap.files", qos: .userInitiated, attributes: .concurrent)
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 6
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        configuration.urlCache = URLCache(
            memoryCapacity: 24 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024,
            directory: caches?.appendingPathComponent("VelaWebMapTiles", isDirectory: true))
        configuration.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: configuration)
    }

    /// Registers a local archive once per path and returns its key and zoom range, or nil when
    /// the file is not a PMTiles v3 archive.
    func registerArchive(path: String) -> ArchiveInfo? {
        lock.lock()
        if let known = infoByPath[path] {
            lock.unlock()
            return known
        }
        lock.unlock()
        guard let header = PmtilesReader.shared.header(file: path) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let key = "a\(infoByPath.count + 1)"
        let info = ArchiveInfo(key: key, minZoom: Int(header.minZoom), maxZoom: Int(header.maxZoom))
        infoByPath[path] = info
        archives[key] = ArchiveHandle(path: path, key: key)
        return info
    }

    @discardableResult
    func load(_ url: String, completion: @escaping (Result) -> Void) -> Request {
        let request = Request()
        if url.hasPrefix("vela-file://") {
            loadFile(String(url.dropFirst("vela-file://".count)), request: request, completion: completion)
        } else if url.hasPrefix("vela-pmtiles://") {
            loadTile(String(url.dropFirst("vela-pmtiles://".count)), request: request, completion: completion)
        } else if url.hasPrefix("vela-nets://") {
            loadRemote("https://" + url.dropFirst("vela-nets://".count), request: request, completion: completion)
        } else if url.hasPrefix("vela-net://") {
            loadRemote("http://" + url.dropFirst("vela-net://".count), request: request, completion: completion)
        } else {
            completion(.failure(400))
        }
        return request
    }

    private func loadFile(_ rawPath: String, request: Request, completion: @escaping (Result) -> Void) {
        fileQueue.async {
            guard !request.isCancelled else { return }
            let path = (rawPath.components(separatedBy: "?").first ?? rawPath)
            let decoded = path.removingPercentEncoding ?? path
            guard let data = FileManager.default.contents(atPath: decoded) else {
                completion(.failure(404))
                return
            }
            completion(.data(data.base64EncodedString()))
        }
    }

    private func loadTile(_ rest: String, request: Request, completion: @escaping (Result) -> Void) {
        let parts = rest.split(separator: "/").map(String.init)
        guard parts.count >= 4,
              let z = Int32(parts[1]), let x = Int32(parts[2]),
              let y = Int32(parts[3].components(separatedBy: ".").first ?? parts[3]) else {
            completion(.failure(400))
            return
        }
        lock.lock()
        let handle = archives[parts[0]]
        lock.unlock()
        guard let handle else {
            completion(.failure(404))
            return
        }
        handle.queue.async {
            guard !request.isCancelled else { return }
            if handle.archive == nil {
                let attributes = try? FileManager.default.attributesOfItem(atPath: handle.path)
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                handle.archive = PmtilesReader.Archive.companion.file(
                    file: handle.path, size: size, lastModifiedMillis: Int64(modified * 1000))
            }
            guard let bytes = handle.archive?.tile(z: z, x: x, y: y) else {
                completion(.data(""))
                return
            }
            let data = IosBytes.shared.toData(bytes: bytes)
            completion(.data(data.base64EncodedString()))
        }
    }

    private func loadRemote(_ string: String, request: Request, completion: @escaping (Result) -> Void) {
        guard let url = URL(string: string) else {
            completion(.failure(400))
            return
        }
        var urlRequest = URLRequest(url: url)
        MapTileNetwork.shared.prepare(&urlRequest)
        let task = session.dataTask(with: urlRequest) { data, response, error in
            guard !request.isCancelled else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, let data, (200..<300).contains(status), !data.isEmpty else {
                completion(.failure(status))
                return
            }
            completion(.data(data.base64EncodedString()))
        }
        request.task = task
        if request.isCancelled { return }
        task.resume()
    }
}
