import Foundation
import VelaCore

/// Foreground URLSession downloads for I-7. A later version can move this delegate to a background
/// session without changing OfflineStore. Partial bytes stay beside the target and are never mounted.
final class URLSessionRegionDownloader: NSObject, OfflineDownloadClient {
    private final class Job {
        let id: String
        let kind: String
        let target: URL
        let temporary: URL
        let progress: (Int64, Int64) -> Void
        let completion: (String?) -> Void
        var expectedBytes: Int64 = -1

        init(id: String, kind: String, target: URL, temporary: URL,
             progress: @escaping (Int64, Int64) -> Void, completion: @escaping (String?) -> Void) {
            self.id = id
            self.kind = kind
            self.target = target
            self.temporary = temporary
            self.progress = progress
            self.completion = completion
        }
    }

    private final class Handle: NSObject, VelaCore.Cancellable {
        private let block: () -> Void
        init(_ block: @escaping () -> Void) { self.block = block }
        func cancel() { block() }
    }

    private var jobs: [Int: Job] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    func start(id: String, kind: String, url: String, targetPath: String,
               onProgress: @escaping (KotlinLong, KotlinLong) -> Void,
               onComplete: @escaping (String?) -> Void) -> any VelaCore.Cancellable {
        let target = URL(fileURLWithPath: targetPath, isDirectory: kind == "glyphs")
        let suffix = kind == "glyphs" ? ".download.zip" : ".download"
        let temporary = URL(fileURLWithPath: targetPath + suffix)
        let job = Job(id: id, kind: kind, target: target, temporary: temporary,
                      progress: { received, total in
                          onProgress(KotlinLong(value: received), KotlinLong(value: total))
                      }, completion: onComplete)
        guard let remote = URL(string: url), remote.scheme == "https" || remote.scheme == "http" else {
            DispatchQueue.main.async { onComplete("url") }
            return Handle {}
        }
        do {
            try FileManager.default.createDirectory(
                at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: temporary)
        } catch {
            DispatchQueue.main.async { onComplete("files") }
            return Handle {}
        }
        let task = session.downloadTask(with: remote)
        jobs[task.taskIdentifier] = job
        task.resume()
        return Handle { [weak self, weak task] in
            guard let self, let task else { return }
            DispatchQueue.main.async {
                task.cancel()
                // A canceled temporary body is removed even if the session has already been invalidated.
                if self.jobs[task.taskIdentifier] == nil {
                    try? FileManager.default.removeItem(at: job.temporary)
                }
            }
        }
    }

    private func finish(_ task: URLSessionTask, error: String?) {
        guard let job = jobs.removeValue(forKey: task.taskIdentifier) else { return }
        if error != nil {
            try? FileManager.default.removeItem(at: job.temporary)
            if job.kind == "glyphs" {
                try? FileManager.default.removeItem(atPath: job.target.path + ".new")
            }
        }
        job.completion(error)
    }

    private func install(_ job: Job, task: URLSessionTask) -> String? {
        let fm = FileManager.default
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return "http"
        }
        let expected = job.expectedBytes > 0 ? job.expectedBytes : task.response?.expectedContentLength ?? -1
        let bytes = (try? fm.attributesOfItem(atPath: job.temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        if expected > 0 && bytes != expected { return "length" }
        do {
            switch job.kind {
            case "pack":
                let archive = try ZipArchive(url: job.temporary)
                let unpacked = URL(fileURLWithPath: job.target.path + ".install")
                try? fm.removeItem(at: unpacked)
                try archive.extract(try archive.firstDatabase(), to: unpacked)
                guard try validMagic(unpacked, count: 16, text: "SQLite format 3") else { return "format" }
                try replace(unpacked, with: job.target)
                try? fm.removeItem(at: job.temporary)
            case "places", "basemap":
                guard bytes > 127, try validMagic(job.temporary, count: 7, text: "PMTiles") else {
                    return "format"
                }
                try replace(job.temporary, with: job.target)
            case "glyphs":
                try installGlyphs(job)
            default:
                return "kind"
            }
            return nil
        } catch {
            return "format"
        }
    }

    private func installGlyphs(_ job: Job) throws {
        let fm = FileManager.default
        let archive = try ZipArchive(url: job.temporary)
        let staging = URL(fileURLWithPath: job.target.path + ".new", isDirectory: true)
        let old = URL(fileURLWithPath: job.target.path + ".old", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for entry in archive.entries where entry.name.hasSuffix(".pbf") {
            let parts = entry.name.split(separator: "/").filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let stack = String(parts[parts.count - 2])
            let range = String(parts[parts.count - 1])
            guard stack != ".", stack != "..", range != ".", range != ".." else { continue }
            let output = staging.appendingPathComponent(stack, isDirectory: true)
                .appendingPathComponent(range)
            try archive.extract(entry, to: output)
        }
        let required = staging.appendingPathComponent("Noto Sans Regular/0-255.pbf")
        guard fm.fileExists(atPath: required.path) else { throw ZipArchive.ZipError.corrupt }
        try? fm.removeItem(at: old)
        if fm.fileExists(atPath: job.target.path) {
            try fm.moveItem(at: job.target, to: old)
        }
        do {
            try fm.moveItem(at: staging, to: job.target)
            try? fm.removeItem(at: old)
            try? fm.removeItem(at: job.temporary)
        } catch {
            if fm.fileExists(atPath: old.path) {
                try? fm.moveItem(at: old, to: job.target)
            }
            throw error
        }
    }

    private func validMagic(_ url: URL, count: Int, text: String) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: count) ?? Data()
        return data.count >= count && String(data: data.prefix(text.utf8.count), encoding: .utf8) == text
    }

    /// rename(2) replaces the destination on APFS. The completed temporary file is on the same volume.
    private func replace(_ source: URL, with target: URL) throws {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if Darwin.rename(source.path, target.path) != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

extension URLSessionRegionDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let job = jobs[downloadTask.taskIdentifier] else { return }
        if totalBytesExpectedToWrite > 0 { job.expectedBytes = totalBytesExpectedToWrite }
        job.progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let job = jobs[downloadTask.taskIdentifier] else { return }
        do {
            try? FileManager.default.removeItem(at: job.temporary)
            try FileManager.default.moveItem(at: location, to: job.temporary)
        } catch {
            finish(downloadTask, error: "files")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard jobs[task.taskIdentifier] != nil else { return }
        if let error {
            let code = (error as NSError).code == NSURLErrorCancelled ? "cancelled" : "network"
            finish(task, error: code)
            return
        }
        guard let job = jobs[task.taskIdentifier], let download = task as? URLSessionDownloadTask else {
            finish(task, error: "task")
            return
        }
        let failure = install(job, task: download)
        finish(task, error: failure)
    }
}
