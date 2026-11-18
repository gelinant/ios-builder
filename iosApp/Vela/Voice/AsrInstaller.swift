import CryptoKit
import Foundation
import SWCompression

/// Downloads one `vela-asr-<id>.tar.gz` from the `asr-models` release, checks its size and SHA-256,
/// extracts the gzipped tar and swaps the result into place atomically. Any failure removes the
/// partial work, so `AsrLayout` never offers a half-installed engine.
final class AsrInstaller {
    enum InstallError: LocalizedError {
        case badStatus(Int)
        case notGzip
        case wrongSize(Int64)
        case wrongChecksum
        case emptyArchive
        case incomplete(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "The download failed (HTTP \(code))."
            case .notGzip: return "The downloaded file is not a gzip archive."
            case .wrongSize(let bytes): return "The download was incomplete (\(bytes) bytes)."
            case .wrongChecksum: return "The download did not match its checksum."
            case .emptyArchive: return "The archive contained no model files."
            case .incomplete(let id): return "The \(id) model is incomplete."
            }
        }
    }

    private let downloader = AsrDownloader()

    func install(
        entry: AsrEntry,
        url: URL,
        root: URL = AsrLayout.storeRoot(),
        progress: @escaping (Double) -> Void,
        installing: @escaping () -> Void
    ) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".\(entry.id).staging", isDirectory: true)
        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-asr-\(entry.id)-\(UUID().uuidString).tar.gz")
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.removeItem(at: archive)
        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: staging)
        }

        let downloaded = try await downloader.download(url: url) { fraction in
            progress(fraction * 0.9)
        }
        try FileManager.default.moveItem(at: downloaded, to: archive)
        let size = AsrLayout.fileSize(archive.path)
        guard entry.expectedBytes == 0 || size == entry.expectedBytes else {
            throw InstallError.wrongSize(size)
        }
        let digest = SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        if !entry.sha256.isEmpty && digest != entry.sha256 { throw InstallError.wrongChecksum }

        installing()
        try await Task.detached(priority: .userInitiated) {
            let compressed = try Data(contentsOf: archive, options: .mappedIfSafe)
            guard compressed.count > 2, compressed[0] == 0x1f, compressed[1] == 0x8b else {
                throw InstallError.notGzip
            }
            let tar = try GzipArchive.unarchive(archive: compressed)
            guard !tar.isEmpty else { throw InstallError.emptyArchive }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try VoiceModelInstaller.extractTar(
                tar, id: entry.id, into: staging, requireModel: false)
        }.value

        let extracted = staging.appendingPathComponent(entry.id, isDirectory: true)
        guard Self.complete(entry, in: extracted) else {
            throw InstallError.incomplete(entry.id)
        }
        let destination = AsrLayout.directory(id: entry.id, root: root)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: extracted, to: destination)
        progress(1)
    }

    private static func complete(_ entry: AsrEntry, in directory: URL) -> Bool {
        entry.files.allSatisfy { AsrLayout.fileSize(directory.appendingPathComponent($0).path) > 0 }
    }
}

/// Progress-reporting download, the same shape as the Piper installer's.
private final class AsrDownloader: NSObject, URLSessionDownloadDelegate {
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
            finish(.failure(AsrInstaller.InstallError.badStatus(response.statusCode)))
            return
        }
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-asr-download-\(UUID().uuidString)")
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
