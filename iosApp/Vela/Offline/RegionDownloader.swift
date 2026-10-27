import Darwin
import Foundation
import VelaCore

struct RegionTransfer: Codable, Equatable {
    var key: String
    var id: String
    var kind: String
    var url: String
    var targetPath: String
    var temporaryPath: String
    var receivedBytes: Int64 = 0
    var expectedBytes: Int64 = -1
    var httpStatus: Int? = nil
    var resumeData: Data? = nil
    var downloadFinished = false
    var error: String? = nil
}

/// Durable URLSession metadata. The file is replaced atomically after every progress bucket.
final class RegionTransferStore {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() -> [String: RegionTransfer] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([String: RegionTransfer].self, from: data) else {
            return [:]
        }
        return records
    }

    func save(_ records: [String: RegionTransfer]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
}

enum RegionRecoveryAction: Equatable {
    case attach, install, resume, fresh
}

/// A device background session survives suspension and is reattached by its stable identifier. The
/// simulator uses a foreground session, with the same durable journal and recovery code.
final class URLSessionRegionDownloader: NSObject, OfflineDownloadClient {
    static let sessionIdentifier = "app.vela.ios.offline.regions"
    static let shared = URLSessionRegionDownloader()

    private final class Job {
        let key: String
        var progress: (Int64, Int64) -> Void
        var completion: (String?) -> Void
        var task: URLSessionDownloadTask?
        var attaching = false
        var cancelRequested = false
        var debugSuspending = false
        var debugExitScheduled = false
        var resumeOffset: Int64 = 0
        var resumeWriteModeKnown = false
        var resumeAddsOffset = false

        init(key: String, progress: @escaping (Int64, Int64) -> Void,
             completion: @escaping (String?) -> Void) {
            self.key = key
            self.progress = progress
            self.completion = completion
        }
    }

    private final class Handle: NSObject, VelaCore.Cancellable {
        private let block: () -> Void
        init(_ block: @escaping () -> Void) { self.block = block }
        func cancel() { block() }
    }

    private let transfers: RegionTransferStore
    private let identifier: String
    private let forceForeground: Bool
    private let installer = RegionDownloadInstaller()
    private var records: [String: RegionTransfer]
    private var jobs: [String: Job] = [:]
    private var backgroundCompletionHandler: (() -> Void)?
    private var backgroundEventsFinished = false

    private lazy var session: URLSession = {
        #if targetEnvironment(simulator)
        let config = URLSessionConfiguration.default
        #else
        let config = forceForeground
            ? URLSessionConfiguration.default
            : URLSessionConfiguration.background(withIdentifier: identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        #endif
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    init(storageURL: URL? = nil, identifier: String = URLSessionRegionDownloader.sessionIdentifier,
         forceForeground: Bool = false) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let journal = storageURL ?? support.appendingPathComponent("NoBackup/offline/transfers.json")
        self.transfers = RegionTransferStore(url: journal)
        self.identifier = identifier
        self.forceForeground = forceForeground
        self.records = transfers.load()
        super.init()
    }

    static func handleEvents(forBackgroundURLSession identifier: String,
                             completionHandler: @escaping () -> Void) {
        guard identifier == sessionIdentifier else {
            completionHandler()
            return
        }
        shared.registerBackgroundCompletion(completionHandler)
    }

    private func registerBackgroundCompletion(_ handler: @escaping () -> Void) {
        _ = session
        backgroundCompletionHandler = handler
        if backgroundEventsFinished {
            backgroundCompletionHandler = nil
            DispatchQueue.main.async(execute: handler)
        }
    }

    func start(id: String, kind: String, url: String, targetPath: String,
               onProgress: @escaping (KotlinLong, KotlinLong) -> Void,
               onComplete: @escaping (String?) -> Void) -> any VelaCore.Cancellable {
        let suffix = kind == "glyphs" ? ".download.zip" : ".download"
        let key = Self.key(id: id, kind: kind, targetPath: targetPath)
        let progress = { (received: Int64, total: Int64) in
            onProgress(KotlinLong(value: received), KotlinLong(value: total))
        }
        let job = jobs[key] ?? Job(key: key, progress: progress, completion: onComplete)
        job.progress = progress
        job.completion = onComplete
        job.cancelRequested = false
        jobs[key] = job

        guard let remote = URL(string: url), remote.scheme == "https" || remote.scheme == "http" else {
            jobs.removeValue(forKey: key)
            DispatchQueue.main.async { onComplete("url") }
            return Handle {}
        }
        let temporaryPath = targetPath + suffix
        if let old = records[key], old.url != url || old.temporaryPath != temporaryPath {
            try? FileManager.default.removeItem(atPath: old.temporaryPath)
            records.removeValue(forKey: key)
        }
        if records[key] == nil {
            records[key] = RegionTransfer(
                key: key, id: id, kind: kind, url: url,
                targetPath: targetPath, temporaryPath: temporaryPath)
        }
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: temporaryPath).deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try transfers.save(records)
        } catch {
            jobs.removeValue(forKey: key)
            records.removeValue(forKey: key)
            DispatchQueue.main.async { onComplete("files") }
            return Handle {}
        }
        if let record = records[key] {
            if job.resumeOffset == 0 { job.resumeOffset = record.receivedBytes }
            job.resumeWriteModeKnown = false
            job.progress(record.receivedBytes, record.expectedBytes)
        }
        recoverIfNeeded(job)
        return Handle { [weak self] in
            DispatchQueue.main.async { self?.cancel(key) }
        }
    }

    private static func key(id: String, kind: String, targetPath: String) -> String {
        kind + "\n" + id + "\n" + targetPath
    }

    static func recoveryAction(for record: RegionTransfer, hasTask: Bool) -> RegionRecoveryAction {
        if hasTask { return .attach }
        if record.error == nil && record.downloadFinished { return .install }
        if record.resumeData != nil { return .resume }
        return .fresh
    }

    private func recoverIfNeeded(_ job: Job) {
        guard !job.attaching, job.task == nil, !job.cancelRequested else { return }
        job.attaching = true
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self, let current = self.jobs[job.key], current === job else { return }
                job.attaching = false
                if job.cancelRequested {
                    self.finish(job, error: "cancelled", cleanupBody: true)
                    return
                }
                let existing = tasks.compactMap { $0 as? URLSessionDownloadTask }.first {
                    $0.taskDescription == job.key
                }
                guard var record = self.records[job.key] else { return }
                let action = Self.recoveryAction(for: record, hasTask: existing != nil)
                record.error = nil
                self.records[job.key] = record
                switch action {
                case .attach:
                    job.task = existing
                    if existing?.state == .suspended { existing?.resume() }
                case .install:
                    self.installDownloadedBody(job)
                case .resume:
                    guard let data = record.resumeData else {
                        self.startFresh(job, remote: URL(string: record.url)!)
                        return
                    }
                    let task = self.session.downloadTask(withResumeData: data)
                    task.taskDescription = job.key
                    job.task = task
                    self.persist()
                    #if DEBUG
                    if LaunchOptions.current.offlineTest {
                        // Leave enough time for the UI scenario to reopen the sheet and capture the
                        // restored progress before a fast runner finishes the remaining bytes.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { task.resume() }
                    } else {
                        task.resume()
                    }
                    #else
                    task.resume()
                    #endif
                case .fresh:
                    self.startFresh(job, remote: URL(string: record.url)!)
                }
            }
        }
    }

    private func startFresh(_ job: Job, remote: URL) {
        guard var record = records[job.key] else { return }
        job.resumeOffset = 0
        job.resumeWriteModeKnown = false
        job.resumeAddsOffset = false
        #if DEBUG
        let delayForTest = record.receivedBytes > 0
        #endif
        try? FileManager.default.removeItem(atPath: record.temporaryPath)
        record.receivedBytes = 0
        record.expectedBytes = -1
        record.httpStatus = nil
        record.resumeData = nil
        record.downloadFinished = false
        record.error = nil
        records[job.key] = record
        let task = session.downloadTask(with: remote)
        task.taskDescription = job.key
        job.task = task
        persist()
        #if DEBUG
        if LaunchOptions.current.offlineTest && delayForTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { task.resume() }
        } else {
            task.resume()
        }
        #else
        task.resume()
        #endif
    }

    private func cancel(_ key: String) {
        guard let job = jobs[key] else { return }
        job.cancelRequested = true
        if let task = job.task {
            task.cancel()
        } else {
            finish(job, error: "cancelled", cleanupBody: true)
        }
    }

    /// A cancellation not requested by the user is an interrupted OS transfer, not a canceled plan.
    private func restartAfterSystemCancellation(_ job: Job) {
        guard jobs[job.key] === job, !job.cancelRequested,
              let record = records[job.key] else { return }
        if let data = record.resumeData {
            let task = session.downloadTask(withResumeData: data)
            task.taskDescription = job.key
            job.task = task
            persist()
            task.resume()
        } else if let remote = URL(string: record.url) {
            startFresh(job, remote: remote)
        }
    }

    private func job(for task: URLSessionTask) -> Job? {
        guard let key = task.taskDescription, var record = records[key] else { return nil }
        if let job = jobs[key] { return job }
        // Background events can arrive before Kotlin rebuilds its plan. Install them from the journal.
        record.httpStatus = (task.response as? HTTPURLResponse)?.statusCode ?? record.httpStatus
        records[key] = record
        let job = Job(key: key, progress: { _, _ in }, completion: { _ in })
        job.task = task as? URLSessionDownloadTask
        jobs[key] = job
        return job
    }

    private func installDownloadedBody(_ job: Job) {
        guard let record = records[job.key] else { return }
        let failure = installer.install(
            kind: record.kind,
            temporary: URL(fileURLWithPath: record.temporaryPath),
            target: URL(fileURLWithPath: record.targetPath, isDirectory: record.kind == "glyphs"),
            expectedBytes: record.expectedBytes,
            httpStatus: record.httpStatus)
        finish(job, error: failure, cleanupBody: failure != nil)
    }

    private func finish(_ job: Job, error: String?, cleanupBody: Bool) {
        guard var record = records[job.key], jobs[job.key] === job else { return }
        jobs.removeValue(forKey: job.key)
        if cleanupBody {
            try? FileManager.default.removeItem(atPath: record.temporaryPath)
            if record.kind == "glyphs" {
                try? FileManager.default.removeItem(atPath: record.targetPath + ".new")
            }
            record.resumeData = nil
        }
        record.error = error
        if error == nil || error == "cancelled" {
            records.removeValue(forKey: job.key)
        } else {
            records[job.key] = record
        }
        persist()
        job.completion(error)
    }

    private func persist() {
        try? transfers.save(records)
    }

    #if DEBUG
    /// Saves OS resume data, then exits before Kotlin sees a failure. The next launch reattaches the
    /// same persisted region plan and resumes this task. Used only by OfflineUITests.
    func suspendActiveDownloadForTest(retries: Int = 10) {
        guard let job = jobs.values.first(where: { $0.task != nil }), let task = job.task else {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.suspendActiveDownloadForTest(retries: retries - 1)
                }
            }
            return
        }
        job.debugSuspending = true
        task.cancel(byProducingResumeData: { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveDebugResume(data, for: job)
                self.scheduleDebugExit(job)
            }
        })
    }

    private func saveDebugResume(_ data: Data?, for job: Job) {
        guard var record = records[job.key] else { return }
        if let data { record.resumeData = data }
        record.receivedBytes = max(record.receivedBytes, job.task?.countOfBytesReceived ?? 0)
        record.downloadFinished = false
        record.error = nil
        records[job.key] = record
        persist()
    }

    private func scheduleDebugExit(_ job: Job) {
        guard !job.debugExitScheduled else { return }
        job.debugExitScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Darwin.exit(0)
        }
    }
    #endif
}

extension URLSessionRegionDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        guard let job = job(for: downloadTask), var record = records[job.key] else { return }
        job.resumeOffset = fileOffset
        job.resumeWriteModeKnown = false
        job.resumeAddsOffset = false
        record.receivedBytes = fileOffset
        if expectedTotalBytes > 0 { record.expectedBytes = expectedTotalBytes }
        records[job.key] = record
        job.progress(fileOffset, record.expectedBytes)
        persist()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let job = job(for: downloadTask), var record = records[job.key] else { return }
        if !job.resumeWriteModeKnown {
            job.resumeAddsOffset = job.resumeOffset > 0 && totalBytesWritten == bytesWritten
            job.resumeWriteModeKnown = true
        }
        let received = totalBytesWritten + (job.resumeAddsOffset ? job.resumeOffset : 0)
        let previousBucket = record.expectedBytes > 0
            ? record.receivedBytes * 100 / record.expectedBytes
            : record.receivedBytes / (8 * 1024 * 1024)
        record.receivedBytes = received
        if totalBytesExpectedToWrite > 0 { record.expectedBytes = totalBytesExpectedToWrite }
        records[job.key] = record
        job.progress(received, record.expectedBytes)
        let bucket = record.expectedBytes > 0
            ? record.receivedBytes * 100 / record.expectedBytes
            : record.receivedBytes / (8 * 1024 * 1024)
        if bucket != previousBucket { persist() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let job = job(for: downloadTask), var record = records[job.key] else { return }
        do {
            try? FileManager.default.removeItem(atPath: record.temporaryPath)
            try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: record.temporaryPath))
            if let http = downloadTask.response as? HTTPURLResponse {
                record.httpStatus = http.statusCode
                if record.expectedBytes <= 0 { record.expectedBytes = http.expectedContentLength }
            }
            record.downloadFinished = true
            records[job.key] = record
            persist()
        } catch {
            finish(job, error: "files", cleanupBody: true)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let job = job(for: task), var record = records[job.key] else { return }
        #if DEBUG
        if job.debugSuspending {
            let data = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            saveDebugResume(data, for: job)
            scheduleDebugExit(job)
            return
        }
        #endif
        if let error {
            let nsError = error as NSError
            if !job.cancelRequested,
               let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                record.resumeData = data
                records[job.key] = record
            }
            if nsError.code == NSURLErrorCancelled && !job.cancelRequested {
                record.error = nil
                record.downloadFinished = false
                records[job.key] = record
                job.task = nil
                job.attaching = false
                persist()
                DispatchQueue.main.async { [weak self, weak job] in
                    guard let job else { return }
                    self?.restartAfterSystemCancellation(job)
                }
                return
            }
            finish(job, error: job.cancelRequested ? "cancelled" : "network",
                   cleanupBody: job.cancelRequested)
            return
        }
        guard record.downloadFinished else {
            finish(job, error: "task", cleanupBody: true)
            return
        }
        installDownloadedBody(job)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundEventsFinished = true
        guard let handler = backgroundCompletionHandler else { return }
        backgroundCompletionHandler = nil
        // Give Kotlin one main-queue turn to start the next piece, then queue behind its reattachment
        // query so the OS does not suspend the process between two pieces of one region plan.
        DispatchQueue.main.async {
            session.getAllTasks { _ in
                DispatchQueue.main.async(execute: handler)
            }
        }
    }
}
