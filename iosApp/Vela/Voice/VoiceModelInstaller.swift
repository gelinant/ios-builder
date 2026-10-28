import Foundation
import SWCompression

/// Downloads a `vits-piper-<id>.tar.bz2` from the sherpa-onnx release, extracts it into a staging
/// directory and swaps it in atomically. Any failure removes the partial work, so the filesystem
/// registry in `VoiceLayout` never sees a half-installed voice.
final class VoiceModelInstaller {
    enum InstallError: LocalizedError {
        case badStatus(Int)
        case notBZip2
        case emptyModel
        case incomplete(String)
        case unsafeEntry(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "HTTP \(code)"
            case .notBZip2: return "not a bzip2 archive"
            case .emptyModel: return "model file missing or too small"
            case .incomplete(let id): return "incomplete voice \(id)"
            case .unsafeEntry(let name): return "unsafe archive entry \(name)"
            }
        }
    }

    private let downloader = VoiceDownloader()

    func install(
        id: String,
        url: URL,
        progress: @escaping (Double) -> Void,
        installing: @escaping () -> Void
    ) async throws {
        let root = VoiceLayout.storeRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".\(id).staging", isDirectory: true)
        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-voice-\(id).tar.bz2")
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.removeItem(at: archive)
        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: staging)
        }

        let downloaded = try await downloader.download(url: url) { fraction in
            progress(fraction * 0.85)
        }
        try FileManager.default.moveItem(at: downloaded, to: archive)
        let attributes = try? FileManager.default.attributesOfItem(atPath: archive.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 1_000_000 else { throw InstallError.notBZip2 }
        let header = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard Data(header.prefix(3)) == Data([0x42, 0x5A, 0x68]) else { throw InstallError.notBZip2 }

        installing()
        try await Task.detached(priority: .userInitiated) {
            let compressed = try Data(contentsOf: archive, options: .mappedIfSafe)
            let tar = try BZip2.decompress(data: compressed)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try Self.extractTar(tar, id: id, into: staging)
        }.value

        guard VoiceLayout.isComplete(id: id, root: staging) else {
            throw InstallError.incomplete(id)
        }
        let destination = VoiceLayout.directory(id: id)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(
            at: staging.appendingPathComponent(id, isDirectory: true), to: destination)
        progress(1)
    }

    /// Extract the entries of a tar archive under `<dest>/<id>/`, stripping the archive's single
    /// top-level folder. Exposed to tests with a synthetic archive. [requireModel] is false for a
    /// speech model, whose files are not named `<id>.onnx`.
    static func extractTar(_ data: Data, id: String, into dest: URL, requireModel: Bool = true) throws {
        let entries = try TarContainer.open(container: data)
        let names = entries.map { $0.info.name.replacingOccurrences(of: "\\", with: "/") }
        let firstParts = Set(names.compactMap { $0.split(separator: "/").first.map(String.init) })
        let stripPrefix = firstParts.count == 1 ? firstParts.first : nil
        let voiceDir = dest.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: voiceDir, withIntermediateDirectories: true)

        for (entry, rawName) in zip(entries, names) {
            var parts = rawName.split(separator: "/").map(String.init)
            if let stripPrefix, parts.first == stripPrefix { parts.removeFirst() }
            guard !parts.isEmpty else { continue }
            guard !parts.contains(".."), !rawName.hasPrefix("/") else {
                throw InstallError.unsafeEntry(rawName)
            }
            let target = parts.reduce(voiceDir) { $0.appendingPathComponent($1) }
            switch entry.info.type {
            case .directory:
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            case .regular:
                guard let body = entry.data else { continue }
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try body.write(to: target, options: .atomic)
            default:
                continue // symlinks and device nodes never ship in a voice archive
            }
        }
        guard requireModel else { return }
        let model = voiceDir.appendingPathComponent("\(id).onnx")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: model.path),
              (attrs[.size] as? NSNumber)?.int64Value ?? 0 > 1_000_000 else {
            throw InstallError.emptyModel
        }
    }
}

/// URLSession download with byte progress, returning a temporary file owned by the caller.
private final class VoiceDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: ((Double) -> Void)?
    private var session: URLSession?

    func download(url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        self.progress = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let report = progress
        DispatchQueue.main.async { report?(min(max(fraction, 0), 1)) }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            finish(.failure(VoiceModelInstaller.InstallError.badStatus(response.statusCode)))
            return
        }
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-voice-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        progress = nil
        continuation.resume(with: result)
    }
}
