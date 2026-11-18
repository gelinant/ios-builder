import Foundation
import OSLog
import SwiftUI
import UIKit
import VelaCore

/// Settings > Privacy on iOS: the Google session schedule, the page-telemetry switch, the two
/// per-feature Google switches SET-PRIVACY adds and the diagnostics export. The pure rules
/// (periods, Google hosts, telemetry filters, redaction, the consent gate) live in `PrivacyPolicy`
/// and `PrivacyConsent` so JVM and simulator tests can hold them without WebKit.
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

    /// Android's keys, so the same answer moves between the platforms.
    static let resolveLinksKey = "google_free_resolve_links"
    static let lookupTappedKey = "map_places_google_lookup"

    @Published private(set) var rotationMode: String
    @Published private(set) var sessionStarted: Date?
    @Published private(set) var telemetryBlocked: Bool
    /// With Google off: may one cookieless request ask Google's shortener where a link points.
    @Published private(set) var resolveShortLinks: Bool
    /// Off: tapping a place on the map keeps Vela's own row and asks Google nothing.
    @Published private(set) var lookupTappedPlaces: Bool

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "app.vela.ios", category: "Privacy")

    private init() {
        defaults = UserDefaults(suiteName: SettingsPersistence.settingsSuite) ?? .standard
        let rawMode = defaults.string(forKey: Self.rotationKey) ?? ""
        rotationMode = PrivacyPolicy.shared.normalizeRotation(mode: rawMode)
        telemetryBlocked = defaults.bool(forKey: Self.telemetryKey)
        resolveShortLinks = defaults.object(forKey: Self.resolveLinksKey) as? Bool ?? true
        lookupTappedPlaces = defaults.object(forKey: Self.lookupTappedKey) as? Bool ?? true
        let stamp = defaults.double(forKey: Self.startedKey)
        sessionStarted = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        // Before the first request of the session: the map-POI store and the short-link resolver
        // read these process holders, not the settings screen's state.
        GoogleUses.shared.apply(lookupTappedPlaces: lookupTappedPlaces,
                                resolveShortLinks: resolveShortLinks)
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

    /// "Open shared Google Maps links": only read while Google is off, and only by the one
    /// cookieless shortener request. Saved lists still need Google and stay unavailable.
    func setResolveShortLinks(_ on: Bool) {
        resolveShortLinks = on
        defaults.set(on, forKey: Self.resolveLinksKey)
        GoogleUses.shared.apply(lookupTappedPlaces: lookupTappedPlaces, resolveShortLinks: on)
        log.notice("short link resolution with Google off: \(on, privacy: .public)")
    }

    func setLookupTappedPlaces(_ on: Bool) {
        lookupTappedPlaces = on
        defaults.set(on, forKey: Self.lookupTappedKey)
        GoogleUses.shared.apply(lookupTappedPlaces: on, resolveShortLinks: resolveShortLinks)
        log.notice("tapped place lookup on Google: \(on, privacy: .public)")
    }

    /// Whether every request to a Google host must be refused locally. Read from the shared
    /// settings suite, the one OfflineStore writes when the user flips "Use Vela without Google".
    static var noGoogleEnabled: Bool {
        UserDefaults(suiteName: SettingsPersistence.settingsSuite)?.bool(forKey: noGoogleKey) ?? false
    }

    /// Android's `Onboarding.welcomeDone` key, set once the first-run question is answered.
    static let welcomeDoneKey = "welcome_done"

    /// Whether the user answered the first-run Google question. Debug builds treat a missing
    /// answer as answered, unless a scenario asks for the question, so the other UI scenarios on a
    /// fresh simulator are not held behind it; a Release build always asks on a fresh install.
    static var consentAnswered: Bool {
        let defaults = UserDefaults(suiteName: SettingsPersistence.settingsSuite)
        if defaults?.object(forKey: welcomeDoneKey) == nil {
            #if DEBUG
            return !LaunchOptions.current.firstRunConsent
            #else
            return false
            #endif
        }
        return defaults?.bool(forKey: welcomeDoneKey) ?? false
    }

    /// The one gate of the HTTP client: no Google request before the answer, none with Google off,
    /// except the single shortener hop the user explicitly allowed.
    static var googleAllowed: Bool {
        PrivacyConsent.shared.googleAllowed(welcomeDone: consentAnswered, noGoogle: noGoogleEnabled)
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

/// Counts the requests the main HTTP client sends to Google hosts, for the Privacy page, the
/// Debug scenarios and the diagnostics export. The Kotlin `GoogleRequestCounter` keeps the counts
/// per host, per purpose and per day; this facade loads them at launch and writes them back, so a
/// relaunch continues the same day's count. Hidden WebView traffic and map tiles are not in here:
/// they never pass this client, and the Privacy page says so.
enum PrivacyRequestCounter {
    static let defaultsKey = "google_request_counter"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SettingsPersistence.settingsSuite)
    }
    private static let queue = DispatchQueue(label: "app.vela.privacy.counter")
    private static var saveScheduled = false

    /// The phone's local day key, the same one the shared counter uses.
    private static var today: String { VelaCore.GoogleRequestCounter.shared.today() }

    /// Reads the stored counts. Call once at launch, after the Debug reset and before any request.
    static func start() {
        let saved = defaults?.string(forKey: defaultsKey) ?? ""
        VelaCore.GoogleRequestCounter.shared.restore(text: saved)
    }

    static func noteSent(_ url: URL) {
        VelaCore.GoogleRequestCounter.shared.recordSentUrl(
            url: url.absoluteString, kind: nil, day: today)
        scheduleSave()
    }

    static func noteBlocked(_ url: URL) {
        VelaCore.GoogleRequestCounter.shared.recordBlockedUrl(url: url.absoluteString, day: today)
        scheduleSave()
    }

    /// Requests that left the phone today.
    static var sentToday: Int { Int(VelaCore.GoogleRequestCounter.shared.totalToday()) }
    /// Requests the phone refused today because Google is off or the first-run question is open.
    static var blockedToday: Int { Int(VelaCore.GoogleRequestCounter.shared.blockedToday()) }
    static var sentWeek: Int { Int(VelaCore.GoogleRequestCounter.shared.totalWeek()) }
    static var dailyAverage: Int { Int(VelaCore.GoogleRequestCounter.shared.dailyAverage()) }

    /// One row per purpose, today and this week, busiest first.
    static var purposeRows: [CounterRow] {
        VelaCore.GoogleRequestCounter.shared.rows().map(CounterRow.init)
    }

    /// One row per Google server, today and this week, busiest first.
    static var hostRows: [CounterRow] {
        VelaCore.GoogleRequestCounter.shared.hostRows().map(CounterRow.init)
    }

    /// Empties the count only. Saved places, lists, recent searches and trips stay untouched.
    static func clear() {
        VelaCore.GoogleRequestCounter.shared.clear()
        saveNow()
    }

    /// The Debug line the UI scenarios read through the settings screen.
    static var debugLine: String {
        "greq=\(sentToday) gblocked=\(blockedToday)"
    }

    /// Writes the count now, for a page that is closing or a process going to the background.
    static func saveNow() {
        let text = VelaCore.GoogleRequestCounter.shared.save()
        queue.sync {
            defaults?.set(text, forKey: defaultsKey)
        }
    }

    /// A busy map settle can count dozens of requests in a second: one write per second is enough,
    /// and the pending write still lands after the last request.
    private static func scheduleSave() {
        queue.async {
            guard !saveScheduled else { return }
            saveScheduled = true
            queue.asyncAfter(deadline: .now() + 1) {
                saveScheduled = false
                defaults?.set(VelaCore.GoogleRequestCounter.shared.save(), forKey: defaultsKey)
            }
        }
    }

    struct CounterRow {
        let label: String
        let today: Int
        let week: Int

        init(_ row: VelaCore.GoogleRequestRow) {
            label = row.label
            today = Int(row.today)
            week = Int(row.week)
        }
    }
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
            "consent_answered=\(PrivacySettings.consentAnswered ? 1 : 0)",
            "no_google=\(PrivacySettings.noGoogleEnabled ? 1 : 0)",
            "session_rotation=\(privacy.rotationMode)",
            "telemetry_blocked=\(privacy.telemetryBlocked ? 1 : 0)",
            "lookup_tapped_places=\(privacy.lookupTappedPlaces ? 1 : 0)",
            "resolve_short_links=\(privacy.resolveShortLinks ? 1 : 0)",
            "google_requests_today=\(PrivacyRequestCounter.sentToday)",
            "google_requests_week=\(PrivacyRequestCounter.sentWeek)",
            "google_requests_blocked_today=\(PrivacyRequestCounter.blockedToday)",
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
