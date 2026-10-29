import Darwin
import Foundation

/// The four moments TRIP-DIAG measures: process launch, the first map frame, the first location
/// fix and the first offline region load. Each is recorded once, with both its elapsed time since
/// the process started and its wall-clock timestamp, and stays in memory for this launch only.
///
/// Nothing here is ever sent anywhere: there is no network call, no OSLog write, and no file. The
/// rows are read by the diagnostics screen, and a crash report deliberately keeps only the
/// process uptime, never a wall clock.
final class DiagnosticsMeasurements {
    static let shared = DiagnosticsMeasurements()
    static let changedNotification = Notification.Name("VelaDiagnosticsMeasurement")

    enum Mark: String, CaseIterable {
        case launch = "launch"
        case firstMapFrame = "first map frame"
        case firstFix = "first fix"
        case offlineRegionLoad = "offline region load"
    }

    struct Entry {
        let elapsed: TimeInterval
        let at: Date
    }

    private let lock = NSLock()
    private var entries: [Mark: Entry] = [:]
    private let processStart: Date?

    private init() {
        processStart = Self.processStartDate()
    }

    /// Records [mark] the first time it happens. Later calls are no-ops, so a style reload or a
    /// second fix never rewrites the interesting moment.
    func mark(_ mark: Mark) {
        lock.lock()
        defer { lock.unlock() }
        guard entries[mark] == nil else { return }
        let now = Date()
        let elapsed = processStart.map { max(0, now.timeIntervalSince($0)) } ?? 0
        entries[mark] = Entry(elapsed: elapsed, at: now)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        }
    }

    func entry(_ mark: Mark) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[mark]
    }

    /// One line per mark, in the enum's order, with the local time kept on screen only.
    func lines() -> [String] {
        Mark.allCases.map { mark in
            guard let entry = entry(mark) else { return "\(mark.rawValue): pending" }
            let seconds = String(format: "%.2f", entry.elapsed)
            let clock = entry.at.formatted(date: .omitted, time: .standard)
            return "\(mark.rawValue): \(seconds) s at \(clock)"
        }
    }

    /// The process start, from the kernel's own record rather than a first initializer, so the
    /// launch figure covers dyld and the pre-main work too.
    private static func processStartDate() -> Date? {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let read = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard read == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec)
            + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
