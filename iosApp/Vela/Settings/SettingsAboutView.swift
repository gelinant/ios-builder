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
                        TextField(VelaL10n.text("settings_search_settings_help_and_licenses"), text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("about-search")
                        if trimmedQuery.isEmpty {
                            Text(VelaL10n.text("settings_finds_a_settings_row_a_help"))
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
                .navigationTitle(VelaL10n.text("settings_about_vela"))
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
        Section(VelaL10n.text("settings_results")) {
            if hits.isEmpty {
                Text(VelaL10n.text("settings_no_match_in_vela"))
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
        Section(VelaL10n.text("settings_help")) {
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
        Section(VelaL10n.text("settings_notices")) {
            NavigationLink(value: AboutRoute.notices) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(VelaL10n.text("settings_notices_and_licenses"))
                        Text(VelaL10n.text("settings_bundled_libraries_map_data_and_services"))
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
        Section(VelaL10n.text("settings_support")) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(VelaL10n.text("settings_version_and_build"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(AboutInfo.versionLine)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("about-version-line")
                }
                Spacer(minLength: 8)
                Button(copied ? VelaL10n.text("settings_copied") : VelaL10n.text("settings_copy")) {
                    UIPasteboard.general.string = AboutInfo.versionLine
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("about-version-copy")
            }
            .id("about-support")

            Text(VelaL10n.text("settings_installed_by"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(AboutInfo.installerName)
                .accessibilityIdentifier("about-installer-name")
            Text(AboutInfo.installerExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("about-installer")

            Text(VelaL10n.text("settings_diagnostics"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(VelaL10n.text("settings_exports_the_same_text_file_as"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(VelaL10n.text("settings_export_diagnostics")) {
                exportDiagnostics()
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("about-export-diagnostics")

            if let donate = URL(string: VelaLinks.shared.donate()) {
                Link(VelaL10n.text("settings_support_button"), destination: donate)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("about-donate")
                Text(VelaL10n.text("settings_optional_the_donation_page_is_the"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var projectSection: some View {
        Section(VelaL10n.text("settings_project")) {
            if let site = URL(string: VelaLinks.shared.site()) {
                Link(VelaL10n.text("place_website"), destination: site)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("about-website")
            }
            if let repo = URL(string: VelaLinks.shared.repo()) {
                Link(VelaL10n.text("settings_project_github_button"), destination: repo)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("about-repo")
            }
            Link(VelaL10n.text("settings_gnu_gpl_3_0_license"), destination: URL(string: "https://github.com/PimpinPumpkin/Vela/blob/main/LICENSE")!)
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
                Text(VelaL10n.text("settings_this_notice_is_missing_from_the"))
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
                Text(VelaL10n.text("settings_this_help_topic_is_missing"))
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
                    Section(VelaL10n.text("settings_bundled_libraries")) {
                        ForEach(libraries) { NoticeRow(entry: $0) }
                    }
                }
                if !dataSources.isEmpty {
                    Section(VelaL10n.text("settings_map_and_data_sources")) {
                        ForEach(dataSources) { NoticeRow(entry: $0) }
                    }
                }
            } else {
                Text(VelaL10n.text("settings_the_notices_file_is_missing_from"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("notices-missing")
            }
        }
        .accessibilityIdentifier("notices-screen")
        .navigationTitle(VelaL10n.text("settings_notices_and_licenses"))
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
                Link(VelaL10n.text("settings_license_and_terms"), destination: link)
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
                    Link(VelaL10n.text("settings_open_source_page"), destination: link)
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
