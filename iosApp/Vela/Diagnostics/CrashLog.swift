import Darwin
import Foundation
import UIKit
import VelaCore

/// Keeps the last three crash reports on this phone so the next launch can offer them.
///
/// What iOS actually allows: `NSSetUncaughtExceptionHandler` sees an Objective-C exception, and
/// nothing else. A Swift trap (`fatalError`, a force unwrap), a watchpoint or `EXC_BAD_ACCESS` is
/// delivered as a signal and kills the process before any handler of ours runs, so it leaves no
/// report here. For the exception that does arrive, `callStackReturnAddresses` is symbolicated
/// with `dladdr` against the images loaded in this process: release builds keep few local symbols,
/// so app frames may read `Vela + <offset>` instead of a function name. That is the limit of
/// in-process symbolication; a full name needs the matching dSYM and the raw addresses.
///
/// The report is written before the process dies, never uploaded, and is redacted only when the
/// user copies or exports it (`CrashReport.redact`, the same rule as the trip exports).
final class CrashLog {
    static let shared = CrashLog()

    struct Report: Identifiable, Equatable {
        let id: String
        let url: URL
        let recordedAt: Date
        let kind: String

        var title: String {
            "\(kind) · \(recordedAt.formatted(date: .abbreviated, time: .standard))"
        }
    }

    private static let keep: Int32 = 3
    private let lock = NSLock()
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("diagnostics/crashes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Called from `VelaAppDelegate` before the first view is built.
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            CrashLog.shared.record(exception)
        }
    }

    // MARK: Writing

    private func record(_ exception: NSException) {
        let report = build(kind: "uncaught_exception",
                           name: exception.name.rawValue,
                           reason: exception.reason ?? "",
                           addresses: exception.callStackReturnAddresses,
                           fallback: exception.callStackSymbols)
        write(report)
    }

    /// Debug only: writes a report with a sample backtrace so the diagnostics screen and the UI
    /// scenario can exercise copy/export without killing the app. The kind says `sample`.
    func writeSample() {
        let report = build(kind: "sample",
                           name: "VelaSampleCrash",
                           reason: "written by the diagnostics screen, not a real crash",
                           addresses: Thread.callStackReturnAddresses,
                           fallback: Thread.callStackSymbols)
        write(report)
    }

    private func build(kind: String, name: String, reason: String,
                       addresses: [NSNumber], fallback: [String]) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: system.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        var out = """
        Vela crash report
        kind: \(kind)
        name: \(name)
        reason: \(reason.replacingOccurrences(of: "\n", with: " "))
        app: \(version) (\(build))
        ios: \(UIDevice.current.systemVersion)
        device: \(machine)
        uptime_s: \(Int(ProcessInfo.processInfo.systemUptime))
        === backtrace ===

        """
        let lines = symbolize(addresses, fallback: fallback)
        if lines.isEmpty {
            out += "none\n"
        } else {
            for (index, line) in lines.enumerated() {
                out += String(format: "%2d %@\n", index, line)
            }
        }
        return out
    }

    /// `dladdr` names the image and the nearest exported symbol. `fallback` is the system's own
    /// `callStackSymbols`, used only when an address cannot be resolved at all.
    private func symbolize(_ addresses: [NSNumber], fallback: [String]) -> [String] {
        addresses.enumerated().map { index, number in
            let address = UInt(number.uint64Value)
            var info = Dl_info()
            if let pointer = UnsafeRawPointer(bitPattern: address),
               dladdr(pointer, &info) != 0 {
                let image = info.dli_fname.map {
                    String(cString: $0).split(separator: "/").last.map(String.init) ?? "?"
                } ?? "?"
                let symbol = info.dli_sname.map { String(cString: $0) }
                let offset = info.dli_saddr.map { address - UInt(bitPattern: $0) } ?? 0
                if let symbol {
                    return "\(image) \(symbol) + \(offset)"
                }
                return "\(image) 0x\(String(address, radix: 16))"
            }
            if index < fallback.count { return fallback[index] }
            return "0x\(String(address, radix: 16))"
        }
    }

    private func write(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let name = "crash-\(Int64(Date().timeIntervalSince1970 * 1000)).txt"
        let url = directory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        prune()
    }

    /// Kotlin owns the policy so the JVM test can pin the three-newest rule.
    private func prune() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in CrashReport.shared.rotate(names: names, keep: Self.keep) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: Reading

    /// Newest first. At most three by construction, never more even if an older build left files.
    func reports() -> [Report] {
        lock.lock()
        defer { lock.unlock() }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let kept = Set(names).subtracting(
            CrashReport.shared.rotate(names: names, keep: Self.keep))
        return kept.compactMap { name -> Report? in
            guard let stamp = Int64(name.replacingOccurrences(of: "crash-", with: "")
                .replacingOccurrences(of: ".txt", with: "")) else { return nil }
            let url = directory.appendingPathComponent(name)
            let header = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let kind = header
                .split(separator: "\n")
                .first { $0.hasPrefix("kind: ") }
                .map { String($0.dropFirst("kind: ".count)) } ?? "crash"
            return Report(id: name, url: url,
                          recordedAt: Date(timeIntervalSince1970: Double(stamp) / 1000),
                          kind: kind)
        }
        .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// The redacted body of one report, the only form copy and share ever see.
    func exportText(for report: Report) -> String {
        let raw = (try? String(contentsOf: report.url, encoding: .utf8)) ?? ""
        return CrashReport.shared.redact(
            text: raw,
            redactPlaces: ContentSettingsKeys.redactPlacesInExportsValue)
    }
}
