import Foundation
import OSLog
import VelaCore

/// The trips sheet's state: the saved list, the opt-in switch, rename and delete. The Kotlin
/// `TripsStore` does the file work; this only mirrors its rows for SwiftUI.
@MainActor
final class TripsModel: ObservableObject {
    @Published private(set) var trips: [TripSummary] = []
    @Published private(set) var recording: Bool

    private let store: TripsStore?
    private let log = TripLogLine()

    init(store: TripsStore?) {
        self.store = store
        recording = store?.recordingEnabled ?? false
        reload()
    }

    func reload() {
        trips = store?.list() ?? []
    }

    func setRecording(_ on: Bool) {
        store?.recordingEnabled = on
        recording = on
    }

    func rename(_ id: String, to label: String) {
        guard store?.rename(id: id, label: label) == true else { return }
        log.info("renamed a trip")
        reload()
    }

    func delete(_ id: String) {
        store?.delete(id: id)
        reload()
    }

    func keepPartial(_ id: String) {
        _ = store?.keepPartial(id: id)
        reload()
    }

    func detailModel(_ summary: TripSummary, onChanged: @escaping () -> Void) -> TripDetailModel {
        TripDetailModel(store: store, summary: summary, onChanged: onChanged)
    }

    /// The file-safe stem of a trip: its start date, never its label, which may name a place.
    static func fileStem(_ startedAt: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "vela-trip-\(formatter.string(from: date))"
    }

    /// The list row's date and clock time, localized by the system.
    static func dateText(_ startedAt: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Just the clock time, for the row's "Start" and "End" labels.
    static func timeText(_ epochMillis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochMillis) / 1000)
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func distanceText(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    static func durationText(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1000)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(seconds) s"
    }

    static func speedText(_ metersPerSecond: Double) -> String {
        String(format: "%.0f km/h", metersPerSecond * 3.6)
    }
}

/// The detail screen: the parsed trace, the trim preview and the two exports.
@MainActor
final class TripDetailModel: ObservableObject {
    let summary: TripSummary
    @Published private(set) var detail: TripDetail?
    @Published private(set) var trim: TripTrim?
    @Published private(set) var radius: Double = 400
    @Published private(set) var exportError = false
    @Published private(set) var currentLabel: String

    private let store: TripsStore?
    private let onChanged: () -> Void

    init(store: TripsStore?, summary: TripSummary, onChanged: @escaping () -> Void) {
        self.store = store
        self.summary = summary
        self.onChanged = onChanged
        currentLabel = summary.label
        reload()
    }

    func reload() {
        detail = store?.detail(id: summary.id)
        updateTrim(radius)
    }

    func updateTrim(_ value: Double) {
        radius = value
        trim = store?.previewTrim(id: summary.id, radiusM: value)
    }

    func rename(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, store?.rename(id: summary.id, label: trimmed) == true else { return }
        currentLabel = trimmed
        onChanged()
    }

    func delete() {
        store?.delete(id: summary.id)
        onChanged()
    }

    func keepPartial() {
        _ = store?.keepPartial(id: summary.id)
        onChanged()
        reload()
    }

    /// A scrubbed export, or nil when the trim leaves nothing. The label and destination are
    /// already gone; only the file name is added here, and it is the trip's start date.
    func exportFile(gpx: Bool) -> URL? {
        let stem = TripsModel.fileStem(summary.startedAt)
        let name = "\(stem).\(gpx ? "gpx" : "csv")"
        guard let text = gpx
            ? store?.exportGpx(id: summary.id, radiusM: radius)
            : store?.exportScrubbedCsv(id: summary.id, radiusM: radius) else {
            exportError = true
            return nil
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            exportError = true
            return nil
        }
    }

    var trimmedSummary: String {
        guard let trim else { return "No shareable trace after trimming." }
        if !trim.trimmable { return "This drive is too short to trim; nothing can be shared." }
        return "Keeps \(Int(trim.fixesAfter)) of \(Int(trim.fixesBefore)) fixes, ends trimmed by \(Int(trim.radiusM)) m."
    }
}

/// A tiny logger that never receives a coordinate, a label or typed text.
struct TripLogLine {
    private let logger = Logger(subsystem: OSLogLog.subsystem, category: "Trips")

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
