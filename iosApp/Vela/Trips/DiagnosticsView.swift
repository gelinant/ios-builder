import SwiftUI
import VelaCore

/// The diagnostics screen: versions, engine flags, counts and the last warnings. Everything it
/// shows is safe to export as text; the Kotlin store never holds a coordinate or typed text.
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(model.text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("diagnostics-text")
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("diagnostics-view")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") { model.refresh() }
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
            .sheet(item: $share) { payload in
                ActivitySheet(items: [payload.url])
            }
        }
    }
}

private struct DiagnosticsShare: Identifiable {
    let id = UUID()
    let url: URL
}
