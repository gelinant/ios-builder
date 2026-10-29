import Combine
import SwiftUI
import UIKit
import VelaCore

/// The diagnostics screen: versions, engine flags, counts and the last warnings. Everything it
/// shows is safe to export as text; the Kotlin store never holds a coordinate or typed text.
///
/// TRIP-DIAG adds three sections on top of the DG-1 text: the four launch measurements with their
/// timestamps, a live map performance reading, and the last three crash reports with copy and
/// export. A crash report leaves the phone only after `CrashReport.redact`, the same rule the trip
/// exports use.
@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var text = ""
    @Published private(set) var failure = false

    private let store: DiagnosticsStore?

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        store = AppGraph.session.diagnostics(
            appVersion: "\(version) (\(build))",
            frameworkVersion: VelaCoreCheck.version)
        refresh()
    }

    func refresh() {
        guard let store else {
            failure = true
            return
        }
        text = store.exportText()
        failure = false
    }

    /// Writes the same text to a temporary file so Share offers a file, not a paste.
    func exportFile() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-diagnostics.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            failure = true
            return nil
        }
    }
}

struct DiagnosticsView: View {
    @StateObject private var model = DiagnosticsModel()
    @State private var share: DiagnosticsShare?
    @State private var perfLine = PerfMonitor.shared.snapshot().text
    @State private var measurements = DiagnosticsMeasurements.shared.lines()
    @State private var reports: [CrashLog.Report] = []
    @State private var copyStatus = ""
    @State private var crashFailure = ""
    @Environment(\.dismiss) private var dismiss

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let keep = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Measurements") {
                        Text(measurements.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("diagnostics-measurements")
                    }

                    section("Map performance") {
                        Text(perfLine)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("diagnostics-perf")
                        Toggle("Performance overlay on the map", isOn: Binding(
                            get: { PerfOverlaySettings.isEnabled },
                            set: { PerfOverlaySettings.isEnabled = $0 }))
                            .accessibilityIdentifier("diagnostics-perf-toggle")
                    }

                    section("Crash reports (\(reports.count) of \(Self.keep))",
                            titleID: "diagnostics-crash-count") {
                        if reports.isEmpty {
                            Text("No crash report on this phone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(reports) { report in
                                Text(report.title)
                                    .font(.system(.caption, design: .monospaced))
                                    .accessibilityIdentifier("diagnostics-crash-row")
                            }
                        }
                        Text("iOS keeps only an uncaught Objective-C exception. A Swift trap or a memory fault leaves no report, and release frames may be addresses without names. Copy and export redact quotes, links and coordinates.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Copy redacted") { copyNewest() }
                                .accessibilityIdentifier("diagnostics-crash-copy")
                                .disabled(reports.isEmpty)
                            Button("Export crash report") { exportNewest() }
                                .accessibilityIdentifier("diagnostics-crash-export")
                                .disabled(reports.isEmpty)
                        }
                        #if DEBUG
                        // A sample report lets the UI scenario exercise copy and export without
                        // killing the process. Its header says "sample"; it is never sent.
                        Button("Write a sample crash report") {
                            CrashLog.shared.writeSample()
                            reloadCrashes()
                        }
                        .accessibilityIdentifier("diagnostics-crash-sample")
                        #endif
                        if !copyStatus.isEmpty {
                            Text(copyStatus)
                                .font(.caption)
                                .accessibilityIdentifier("diagnostics-crash-status")
                        }
                        if !crashFailure.isEmpty {
                            Text(crashFailure)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Text(model.text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("diagnostics-text")
                }
                .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("diagnostics-view")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") { refresh() }
                        .accessibilityIdentifier("diagnostics-refresh")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("diagnostics-done")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Export text") {
                        if let url = model.exportFile() {
                            share = DiagnosticsShare(url: url)
                        }
                    }
                    .accessibilityIdentifier("diagnostics-share")
                }
            }
            .onAppear { refresh() }
            .onReceive(tick) { _ in
                perfLine = PerfMonitor.shared.snapshot().text
                measurements = DiagnosticsMeasurements.shared.lines()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: DiagnosticsMeasurements.changedNotification)) { _ in
                measurements = DiagnosticsMeasurements.shared.lines()
            }
            .sheet(item: $share) { payload in
                ActivitySheet(items: [payload.url])
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, titleID: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let titleID {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier(titleID)
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refresh() {
        model.refresh()
        measurements = DiagnosticsMeasurements.shared.lines()
        perfLine = PerfMonitor.shared.snapshot().text
        reloadCrashes()
    }

    private func reloadCrashes() {
        reports = CrashLog.shared.reports()
    }

    /// Both actions hand over the redacted body, never the raw file.
    private func copyNewest() {
        guard let report = reports.first else { return }
        UIPasteboard.general.string = CrashLog.shared.exportText(for: report)
        copyStatus = "Copied the redacted crash report."
    }

    private func exportNewest() {
        guard let report = reports.first else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-crash-report.txt")
        do {
            try CrashLog.shared.exportText(for: report)
                .write(to: url, atomically: true, encoding: .utf8)
            crashFailure = ""
            share = DiagnosticsShare(url: url)
        } catch {
            crashFailure = "Could not write the crash report."
        }
    }
}

private struct DiagnosticsShare: Identifiable {
    let id = UUID()
    let url: URL
}
