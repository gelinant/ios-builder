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
                        SettingsSearchField(
                            placeholder: VelaL10n.text("settings_search_settings_help_and_licenses"),
                            text: $query,
                            identifier: "about-search")
                        if trimmedQuery.isEmpty {
                            Text(VelaL10n.text("settings_finds_a_settings_row_a_help"))
                                .settingsHint()
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
                .environment(\.defaultMinListRowHeight, Design.Size.hitTarget)
                .scrollContentBackground(.hidden)
                .background(Design.Colors.surface)
                .tint(Design.Colors.accent)
                .navigationTitle(VelaL10n.text("settings_about_vela"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                            .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
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
        Section {
            if hits.isEmpty {
                Text(VelaL10n.text("settings_no_match_in_vela"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("about-no-results")
            }
            ForEach(hits) { hit in
                Button {
                    open(hit, proxy: proxy)
                } label: {
                    HStack(spacing: Design.Spacing.s) {
                        SettingsRowLabel(title: hit.title, subtitle: hit.subtitle)
                        Spacer(minLength: Design.Spacing.s)
                        SettingsChevron()
                    }
                    .settingsRowFrame()
                }
                .accessibilityIdentifier("about-result-\(hit.kind.rawValue)-\(hit.target)")
            }
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_results"))
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
        Section {
            ForEach(HelpCatalog.topics) { topic in
                NavigationLink(value: AboutRoute.help(topic.id)) {
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text(topic.title)
                            .font(Design.Typography.rowTitle)
                        Text(topic.summary)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .lineLimit(2)
                    }
                    .frame(minHeight: Design.Size.hitTarget)
                }
                .accessibilityIdentifier("about-help-\(topic.id)")
            }
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_help"))
        }
    }

    private var noticesSection: some View {
        Section {
            NavigationLink(value: AboutRoute.notices) {
                HStack(spacing: Design.Spacing.s) {
                    SettingsRowLabel(
                        title: VelaL10n.text("settings_notices_and_licenses"),
                        subtitle: VelaL10n.text("settings_bundled_libraries_map_data_and_services"))
                    Spacer(minLength: Design.Spacing.s)
                    SettingsValue(text: "\(notices.count)")
                    SettingsChevron()
                }
                .frame(minHeight: Design.Size.hitTarget)
            }
            .accessibilityIdentifier("about-notices-link")
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_notices"))
        }
    }

    private var supportSection: some View {
        Section {
            HStack(spacing: Design.Spacing.m) {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    Text(VelaL10n.text("settings_version_and_build"))
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                    Text(AboutInfo.versionLine)
                        .font(Design.Typography.caption.monospaced())
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .accessibilityIdentifier("about-version-line")
                }
                Spacer(minLength: Design.Spacing.s)
                Button(copied ? VelaL10n.text("settings_copied") : VelaL10n.text("settings_copy")) {
                    UIPasteboard.general.string = AboutInfo.versionLine
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .font(Design.Typography.button)
                .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("about-version-copy")
            }
            .id("about-support")

            Text(VelaL10n.text("settings_installed_by"))
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryLabel)
            Text(AboutInfo.installerName)
                .font(Design.Typography.body)
                .accessibilityIdentifier("about-installer-name")
            Text(AboutInfo.installerExplanation)
                .settingsHint()
                .accessibilityIdentifier("about-installer")

            Text(VelaL10n.text("settings_diagnostics"))
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryLabel)
            Text(VelaL10n.text("settings_exports_the_same_text_file_as"))
                .settingsHint()
            Button(VelaL10n.text("settings_export_diagnostics")) {
                exportDiagnostics()
            }
            .font(Design.Typography.body)
            .frame(minHeight: Design.Size.hitTarget)
            .accessibilityIdentifier("about-export-diagnostics")

            if let donate = URL(string: VelaLinks.shared.donate()) {
                Link(VelaL10n.text("settings_support_button"), destination: donate)
                    .frame(minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("about-donate")
                Text(VelaL10n.text("settings_optional_the_donation_page_is_the"))
                    .settingsHint()
            }
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_support"))
        }
    }

    private var projectSection: some View {
        Section {
            if let site = URL(string: VelaLinks.shared.site()) {
                Link(VelaL10n.text("place_website"), destination: site)
                    .frame(minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("about-website")
            }
            if let repo = URL(string: VelaLinks.shared.repo()) {
                Link(VelaL10n.text("settings_project_github_button"), destination: repo)
                    .frame(minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("about-repo")
            }
            Link(VelaL10n.text("settings_gnu_gpl_3_0_license"), destination: URL(string: "https://github.com/PimpinPumpkin/Vela/blob/main/LICENSE")!)
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("about-license")
        } header: {
            SettingsSectionHeader(title: VelaL10n.text("settings_project"))
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
                    VStack(alignment: .leading, spacing: Design.Spacing.l) {
                        Text(topic.summary)
                            .font(Design.Typography.section)
                            .foregroundStyle(Design.Colors.label)
                        ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(Design.Typography.body)
                                .foregroundStyle(Design.Colors.label)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Padding.page)
                    .padding(.vertical, Design.Spacing.l)
                }
                .background(Design.Colors.surface)
                .accessibilityIdentifier("help-detail-\(topic.id)")
                .navigationTitle(topic.title)
            } else {
                Text(VelaL10n.text("settings_this_help_topic_is_missing"))
                    .padding(Design.Padding.page)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NoticesScreen: View {
    let entries: [NoticeEntry]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.Spacing.xxl) {
                if entries.isEmpty {
                    Text(VelaL10n.text("settings_the_notices_file_is_missing_from"))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .accessibilityIdentifier("notices-missing")
                } else {
                    group("Vela", appEntries)
                    group(VelaL10n.text("settings_bundled_libraries"), libraries)
                    group(VelaL10n.text("settings_map_and_data_sources"), dataSources)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Padding.page)
            .padding(.vertical, Design.Spacing.l)
        }
        .background(Design.Colors.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notices-screen")
        .navigationTitle(VelaL10n.text("settings_notices_and_licenses"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One group of sources under its header, as a `Radius.m` card. Every source states its
    /// license in text, so the page reads as a list of sources rather than a wall of notes.
    @ViewBuilder
    private func group(_ title: String, _ items: [NoticeEntry]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                SettingsSectionHeader(title: title)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                        NoticeRow(entry: entry)
                        if index < items.count - 1 {
                            Divider()
                                .background(Design.Colors.separator)
                                .padding(.leading, Design.Padding.rowH)
                        }
                    }
                }
                .background(
                    Design.Colors.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: Design.Radius.m))
            }
        }
    }

    private var appEntries: [NoticeEntry] { NoticesCatalog.grouped(entries, kind: "app") }
    private var libraries: [NoticeEntry] { NoticesCatalog.grouped(entries, kind: "library") }
    private var dataSources: [NoticeEntry] { NoticesCatalog.grouped(entries, kind: "data") }
}

private struct NoticeRow: View {
    let entry: NoticeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(entry.title)
                .font(Design.Typography.rowTitle)
                .foregroundStyle(Design.Colors.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.license)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.note)
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            if let link = entry.link {
                Link(VelaL10n.text("settings_license_and_terms"), destination: link)
                    .font(Design.Typography.button)
                    .foregroundStyle(Design.Colors.accentFill)
                    .frame(minHeight: Design.Size.hitTarget)
                    .accessibilityIdentifier("notice-link-\(entry.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Padding.rowH)
        .padding(.vertical, Design.Padding.rowV)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notice-\(entry.id)")
    }
}

struct NoticeDetailView: View {
    let entry: NoticeEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.l) {
                Text(entry.title)
                    .font(Design.Typography.section)
                Text(entry.license)
                    .font(Design.Typography.detail)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                if let link = entry.link {
                    Link(VelaL10n.text("settings_open_source_page"), destination: link)
                        .font(Design.Typography.button)
                        .foregroundStyle(Design.Colors.accentFill)
                        .frame(minHeight: Design.Size.hitTarget)
                }
                Text(entry.note)
                    .font(Design.Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Padding.page)
            .padding(.vertical, Design.Spacing.l)
        }
        .background(Design.Colors.surface)
        .accessibilityIdentifier("notice-detail-\(entry.id)")
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
