import SwiftUI
import UIKit
import VelaCore

/// The About hub: one searchable page over Settings rows, help topics, notices and support.
/// Tapping a Settings result closes this sheet and scrolls the Settings form to the real row.
struct AboutScreen: View {
    var onOpenSetting: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var path: [AboutRoute] = []
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var exportFailed = false
    @State private var copied = false

    private let notices = NoticesCatalog.load()

    private var hits: [AboutSearch.Hit] {
        AboutSearch.hits(query: query, notices: notices)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        TextField("Search settings, help and licenses", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("about-search")
                        if trimmedQuery.isEmpty {
                            Text("Finds a Settings row, a help topic, a license or the support entry.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !trimmedQuery.isEmpty {
                        results(proxy: proxy)
                    } else {
                        helpSection
                        noticesSection
                        supportSection
                        projectSection
                    }
                }
                .accessibilityIdentifier("about-screen")
                .navigationTitle("About Vela")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("about-done")
                    }
                }
                .navigationDestination(for: AboutRoute.self) { route in
                    destination(route)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .alert(VelaL10n.text("settings_diagnostics"), isPresented: $exportFailed) {
            Button(VelaL10n.text("settings_trip_select_done"), role: .cancel) {}
        } message: {
            Text(VelaL10n.text("settings_diag_nothing"))
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private func results(proxy: ScrollViewProxy) -> some View {
        Section("Results") {
            if hits.isEmpty {
                Text("No match in Vela.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("about-no-results")
            }
            ForEach(hits) { hit in
                Button {
                    open(hit, proxy: proxy)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.title)
                                .foregroundStyle(.primary)
                            Text(hit.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("about-result-\(hit.kind.rawValue)-\(hit.target)")
            }
        }
    }

    private func open(_ hit: AboutSearch.Hit, proxy: ScrollViewProxy) {
        switch hit.kind {
        case .setting:
            onOpenSetting(hit.target)
        case .help:
            path.append(.help(hit.target))
        case .notice:
            path.append(.notice(hit.target))
        case .support:
            if hit.target == "notices" {
                path.append(.notices)
            } else {
                query = ""
                // Let the full sections replace the results before asking for their position.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("about-support", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var helpSection: some View {
        Section("Help") {
            ForEach(HelpCatalog.topics) { topic in
                NavigationLink(value: AboutRoute.help(topic.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.title)
                        Text(topic.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("about-help-\(topic.id)")
            }
        }
    }

    private var noticesSection: some View {
        Section("Notices") {
            NavigationLink(value: AboutRoute.notices) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notices and licenses")
                        Text("Bundled libraries, map data and services")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(notices.count)")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("about-notices-link")
        }
    }

    private var supportSection: some View {
        Section("Support") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version and build")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(AboutInfo.versionLine)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("about-version-line")
                }
                Spacer(minLength: 8)
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = AboutInfo.versionLine
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("about-version-copy")
            }
            .id("about-support")

            Text("Installed by")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(AboutInfo.installerName)
                .accessibilityIdentifier("about-installer-name")
            Text(AboutInfo.installerExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("about-installer")

            Text("Diagnostics")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Exports the same text file as Settings, Privacy. It holds the version and build, the calibration version, the privacy switches and at most 200 redacted log lines. The Kotlin search, route and parsing logs are not included.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Export diagnostics") {
                exportDiagnostics()
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("about-export-diagnostics")

            if let donate = URL(string: VelaLinks.shared.donate()) {
                Link("Support Vela", destination: donate)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("about-donate")
                Text("Optional. The donation page is the one the Vela repository documents.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var projectSection: some View {
        Section("Project") {
            if let site = URL(string: VelaLinks.shared.site()) {
                Link("Website", destination: site)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("about-website")
            }
            if let repo = URL(string: VelaLinks.shared.repo()) {
                Link("Vela on GitHub", destination: repo)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("about-repo")
            }
            Link("GNU GPL-3.0 license", destination: URL(string: "https://github.com/PimpinPumpkin/Vela/blob/main/LICENSE")!)
                .frame(minHeight: 44)
                .accessibilityIdentifier("about-license")
        }
    }

    @ViewBuilder
    private func destination(_ route: AboutRoute) -> some View {
        switch route {
        case .help(let id):
            HelpTopicView(topic: HelpCatalog.topic(id: id))
        case .notices:
            NoticesScreen(entries: notices)
        case .notice(let id):
            if let entry = notices.first(where: { $0.id == id }) {
                NoticeDetailView(entry: entry)
            } else {
                Text("This notice is missing from the bundle.")
                    .padding()
            }
        }
    }

    private func exportDiagnostics() {
        do {
            shareItems = [try DiagnosticsExport.fileURL()]
            showShare = true
        } catch {
            exportFailed = true
        }
    }
}

private enum AboutRoute: Hashable {
    case help(String)
    case notices
    case notice(String)
}

struct HelpTopicView: View {
    let topic: HelpTopic?

    var body: some View {
        Group {
            if let topic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(topic.summary)
                            .font(.headline)
                        ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("help-detail-\(topic.id)")
                .navigationTitle(topic.title)
            } else {
                Text("This help topic is missing.")
                    .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NoticesScreen: View {
    let entries: [NoticeEntry]

    var body: some View {
        List {
            if !entries.isEmpty {
                if !appEntries.isEmpty {
                    Section("Vela") {
                        ForEach(appEntries) { NoticeRow(entry: $0) }
                    }
                }
                if !libraries.isEmpty {
                    Section("Bundled libraries") {
                        ForEach(libraries) { NoticeRow(entry: $0) }
                    }
                }
                if !dataSources.isEmpty {
                    Section("Map and data sources") {
                        ForEach(dataSources) { NoticeRow(entry: $0) }
                    }
                }
            } else {
                Text("The notices file is missing from the bundle. Reinstall Vela or report this build.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("notices-missing")
            }
        }
        .accessibilityIdentifier("notices-screen")
        .navigationTitle("Notices and licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appEntries: [NoticeEntry] { NoticesCatalog.grouped(entries, kind: "app") }
    private var libraries: [NoticeEntry] { NoticesCatalog.grouped(entries, kind: "library") }
    private var dataSources: [NoticeEntry] { NoticesCatalog.grouped(entries, kind: "data") }
}

private struct NoticeRow: View {
    let entry: NoticeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.body.weight(.medium))
            Text(entry.license)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(entry.note)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let link = entry.link {
                Link("License and terms", destination: link)
                    .font(.footnote)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("notice-link-\(entry.id)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("notice-\(entry.id)")
    }
}

struct NoticeDetailView: View {
    let entry: NoticeEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.title)
                    .font(.title3.weight(.semibold))
                Text(entry.license)
                    .font(.headline)
                if let link = entry.link {
                    Link("Open source page", destination: link)
                        .font(.footnote)
                }
                Text(entry.note)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("notice-detail-\(entry.id)")
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
