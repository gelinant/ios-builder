import Foundation
import OSLog
import SwiftUI
import UIKit
import VelaCore

/// Settings > Privacy on iOS: the Google session schedule, the page-telemetry switch and the
/// diagnostics export. The pure rules (periods, Google hosts, telemetry filters, redaction) live
/// in `PrivacyPolicy` so JVM and simulator tests can hold them without WebKit.
///
/// A Google session here is the process's in-memory HTTP cookie jar plus the hidden WebView's
/// non-persistent data store and its caches. Both are already gone at every launch; the weekly and
/// daily choices therefore matter to a process that stays alive, and to the start stamp shown in
/// Settings. Saved places, lists and downloaded regions live in their own stores and are untouched.
final class PrivacySettings: ObservableObject {
    static let shared = PrivacySettings()

    static let rotationKey = "google_session_rotate"
    static let startedKey = "google_session_started"
    static let telemetryKey = "block_google_telemetry"
    static let noGoogleKey = "ios_google_disabled"

    @Published private(set) var rotationMode: String
    @Published private(set) var sessionStarted: Date?
    @Published private(set) var telemetryBlocked: Bool

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "app.vela.ios", category: "Privacy")

    private init() {
        defaults = UserDefaults(suiteName: SettingsPersistence.settingsSuite) ?? .standard
        let rawMode = defaults.string(forKey: Self.rotationKey) ?? ""
        rotationMode = PrivacyPolicy.shared.normalizeRotation(mode: rawMode)
        telemetryBlocked = defaults.bool(forKey: Self.telemetryKey)
        let stamp = defaults.double(forKey: Self.startedKey)
        sessionStarted = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Stamps the session that this launch just started. Both stores are non-persistent, so the
    /// launch already has a fresh Google session whatever the weekly/daily choice says; stamping
    /// here keeps the shown start time honest instead of showing the first install's date.
    func startAtLaunch(now: Date = Date()) {
        stamp(Int64(now.timeIntervalSince1970 * 1000))
    }

    /// Replaces the session when its period has passed, for a process that stays alive. Call when
    /// the app comes back to the foreground; the first activation right after launch is skipped.
    func rotateIfDue(now: Date = Date()) {
        let started = defaults.double(forKey: Self.startedKey)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let startedMs = Int64(started * 1000)
        if started <= 0 {
            stamp(nowMs)
            return
        }
        sessionStarted = Date(timeIntervalSince1970: started)
        if nowMs - startedMs < 1_000 { return }
        if PrivacyPolicy.shared.isRotationDue(mode: rotationMode, startedMs: startedMs, nowMs: nowMs) {
            clearSessions()
            stamp(nowMs)
            log.notice("new Google session on schedule, mode \(self.rotationMode, privacy: .public)")
        }
    }

    /// "Start a new session now". Clears the HTTP jar and the hidden WebView store and caches.
    func startNewNow() {
        clearSessions()
        stamp(Int64(Date().timeIntervalSince1970 * 1000))
        log.notice("new Google session by hand")
    }

    func setRotationMode(_ mode: String) {
        rotationMode = PrivacyPolicy.shared.normalizeRotation(mode: mode)
        defaults.set(rotationMode, forKey: Self.rotationKey)
    }

    func setTelemetryBlocked(_ on: Bool) {
        telemetryBlocked = on
        defaults.set(on, forKey: Self.telemetryKey)
        log.notice("page telemetry blocked: \(on, privacy: .public)")
    }

    /// Whether every request to a Google host must be refused locally. Read from the shared
    /// settings suite, the one OfflineStore writes when the user flips "Use Vela without Google".
    static var noGoogleEnabled: Bool {
        UserDefaults(suiteName: SettingsPersistence.settingsSuite)?.bool(forKey: noGoogleKey) ?? false
    }

    /// Telemetry blocking is read when a hidden page is created, so a change reaches the next one.
    static var telemetryBlockedNow: Bool {
        UserDefaults(suiteName: SettingsPersistence.settingsSuite)?.bool(forKey: telemetryKey) ?? false
    }

    private func stamp(_ millis: Int64) {
        defaults.set(Double(millis) / 1000, forKey: Self.startedKey)
        sessionStarted = Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    private func clearSessions() {
        CookieJar.app.reset()
        HiddenWebView.startNewSession()
    }
}

/// Counts the requests the main HTTP client sends to Google hosts, for the Debug scenarios and
/// the Privacy page. Hidden WebView traffic is not in here: it never passes this client.
enum GoogleRequestCounter {
    private static let lock = NSLock()
    private static var sentCount = 0
    private static var blockedCount = 0

    /// Requests that actually left the phone.
    static var sent: Int {
        lock.lock(); defer { lock.unlock() }; return sentCount
    }

    /// Requests to a Google host refused locally because "Use Vela without Google" is on.
    static var blocked: Int {
        lock.lock(); defer { lock.unlock() }; return blockedCount
    }

    static func reset() {
        lock.lock(); sentCount = 0; blockedCount = 0; lock.unlock()
    }

    static func noteSent(_ host: String) {
        guard PrivacyPolicy.shared.isGoogleHost(host: host) else { return }
        lock.lock(); sentCount += 1; lock.unlock()
    }

    static func noteBlocked(_ host: String) {
        guard PrivacyPolicy.shared.isGoogleHost(host: host) else { return }
        lock.lock(); blockedCount += 1; lock.unlock()
    }

    /// The Debug line the UI scenarios read through the settings screen.
    static var debugLine: String { "greq=\(sent) gblocked=\(blocked)" }
}

/// The text of an "Export diagnostics" file: versions, privacy flags and log lines that carry no
/// coordinate, typed text or place name. Android's DiagLog and its DiagSink are not wired on iOS
/// (the shared sources get `DiagSink.NONE`), so the lines come from this app's OSLog categories.
enum DiagnosticsExport {
    static func text() -> String {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "?"
        let calibration = AppGraph.session.calibration?.current().version ?? 0
        let privacy = PrivacySettings.shared
        let flags = [
            "no_google=\(PrivacySettings.noGoogleEnabled ? 1 : 0)",
            "session_rotation=\(privacy.rotationMode)",
            "telemetry_blocked=\(privacy.telemetryBlocked ? 1 : 0)",
            "google_requests_sent=\(GoogleRequestCounter.sent)",
            "google_requests_blocked=\(GoogleRequestCounter.blocked)",
            "calibration_version=\(calibration)",
        ]
        return PrivacyPolicy.shared.diagnosticsReport(
            appVersion: appVersion,
            buildNumber: buildNumber,
            calibrationVersion: Int32(calibration),
            flags: flags,
            logLines: recentLogLines())
    }

    /// The app's own log lines. Only Web, Calibration and Privacy are kept: those never carry a
    /// query, a place name or a position, and `redactDiagnosticLine` strips what could.
    private static func recentLogLines(limit: Int = 200) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let since = Date().addingTimeInterval(-3_600)
        guard let entries = try? store.getEntries(at: store.position(date: since)) else { return [] }
        var lines: [String] = []
        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            let category = log.category
            guard ["Web", "Calibration", "Privacy"].contains(category) else { continue }
            lines.append("\(category): \(log.composedMessage)")
        }
        return Array(lines.suffix(limit))
    }

    /// Writes the export to a temporary file, the item the share sheet hands over.
    static func fileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-diagnostics.txt")
        try text().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// UIActivityViewController for the diagnostics file, iPhone-only as the target declares.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
