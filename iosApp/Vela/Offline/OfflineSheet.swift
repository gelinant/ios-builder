import SwiftUI

/// The offline manager: the current map state, the framed-area entry, the live downloads and the
/// catalog of regions. The surface is a tall system sheet; the content follows the Vela design
/// tokens (`docs/ios/DESIGN.md`), with one card per object, 12 pt radii and a level 1 shadow.
///
/// The host is a `List` on purpose: its row laziness keeps a long region catalog off the layout
/// while a download ticks, which a `ScrollView` plus `LazyVStack` does not give when a section
/// holds every row in one child.
struct OfflineSheet: View {
    @ObservedObject var model: OfflineModel
    let onFrameArea: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            List {
                statusCard.offlineListRow()
                areaSection.offlineListRow()
                if model.areaId != nil {
                    areaDownloadSection.offlineListRow()
                }
                if model.downloadingId != nil {
                    downloadSection.offlineListRow()
                }
                if model.updatingId != nil {
                    updateSection.offlineListRow()
                }
                if model.updatedId != nil {
                    updatedSection.offlineListRow()
                }
                if model.errorKey != nil {
                    errorSection.offlineListRow()
                }
                if model.completedId != nil {
                    completedSection.offlineListRow()
                }
                installedSection.offlineListRow()
                availableSection.offlineListRow()
                storageSection.offlineListRow()
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(Design.Colors.surface)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offline-sheet")
            .navigationTitle(VelaL10n.text("settings_offline"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                // Scenario controls live in the navigation bar, so a tap never depends on the
                // List's scroll position or on a clipped card taller than the sheet.
                ToolbarItemGroup(placement: .topBarLeading) {
                    if LaunchOptions.current.offlineTest {
                        Button { model.blockNetworkForTest() } label: {
                            Image(systemName: "wifi.slash")
                        }
                        .accessibilityLabel("Block network for test")
                        .accessibilityIdentifier("offline-test-block")
                        Button { model.resetOfflineForTest() } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Reset offline data for test")
                        .accessibilityIdentifier("offline-test-reset")
                    }
                    if OfflineFixtureSupport.isEnabled {
                        Button { model.useUpdateFixtureManifest() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityLabel("Fixture: use update manifest")
                        .accessibilityIdentifier("offline-test-update-manifest")
                    }
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .font(Design.Typography.button)
                        .frame(minWidth: Design.Size.hitTarget, minHeight: Design.Size.hitTarget)
                        .accessibilityIdentifier("offline-done")
                        #if DEBUG
                        .accessibilityValue(debugValue)
                        #endif
                }
            }
            .tint(Design.Colors.accent)
            .onAppear {
                model.start()
                model.refresh()
            }
        }
    }

    // MARK: - Sections

    #if DEBUG
    /// Debug read-out attached to the Done button: no extra row and no layout shift, so a
    /// scenario reads it whatever the catalog scroll position is.
    private var debugValue: String {
        var value = model.sessionDebugLine
        if OfflineFixtureSupport.isEnabled {
            value += " " + model.fixtureDebugLine
        }
        return value
    }
    #endif

    private var areaSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            sectionHeader(VelaL10n.text("settings_offline_download_viewport"))
            areaCard
        }
    }

    private var areaDownloadSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            sectionHeader(VelaL10n.text("offline_area_download"))
            areaDownloadCard
        }
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            sectionHeader(stageLabel)
            downloadCard
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            sectionHeader(VelaL10n.text("offline_updating"))
            updateCard
        }
    }

    private var updatedSection: some View {
        updatedCard
    }

    private var errorSection: some View {
        errorCard
    }

    private var completedSection: some View {
        completedCard
    }

    // MARK: - Current state

    private var statusCard: some View {
        OfflineCard {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                infoRow("Current region", model.currentRegionName ?? "Not located")
                infoRow("Downloaded data", bytes(model.totalBytes), id: "offline-total-size")
                Toggle(isOn: Binding(
                    get: { model.googleDisabled },
                    set: { model.setGoogleDisabled($0) })) {
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text(VelaL10n.text("settings_google_free"))
                            .font(Design.Typography.rowTitle)
                        // The long hint makes this card taller than the sheet. Every offline
                        // scenario runs with the test flag, and the clipped foot of such a row
                        // either hides a card or swallows a tap; keep the test layout compact.
                        if !LaunchOptions.current.offlineTest {
                            Text(VelaL10n.text("settings_google_free_hint_ios"))
                                .font(Design.Typography.detail)
                                .foregroundStyle(Design.Colors.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("offline-no-google")
                infoRow("World basemap", model.worldInstalled ? "Installed" : "Missing",
                        id: "offline-world-state")
            }
        }
    }

    private var areaCard: some View {
        OfflineCard {
            VStack(alignment: .leading, spacing: Design.Spacing.m) {
                Button {
                    onFrameArea()
                } label: {
                    HStack(spacing: Design.Spacing.s) {
                        Image(systemName: "viewfinder")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.accent)
                        Text(VelaL10n.text("offline_frame_an_area_on_the_map"))
                            .font(Design.Typography.rowTitle)
                            .foregroundStyle(Design.Colors.label)
                        Spacer(minLength: Design.Spacing.s)
                        OfflineChevron()
                    }
                    .frame(maxWidth: .infinity, minHeight: Design.Size.hitTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                // The label's minHeight does not reach the button's own frame in a List row; the
                // measured target was 42.2 pt instead of 44.
                .frame(minHeight: Design.Size.hitTarget)
                .accessibilityIdentifier("offline-area-start")
                Text(VelaL10n.text("offline_pan_and_pinch_under_the_frame"))
                    .font(Design.Typography.detail)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Text(VelaL10n.text("offline_downloaded_areas_include_the_map_places"))
                    .font(Design.Typography.detail)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("offline-area-note")
            }
        }
    }

    // MARK: - Area download

    private var areaDownloadCard: some View {
        OfflineCard {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                if model.areaDownloading {
                    HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                        Text(stageLabel)
                            .font(Design.Typography.rowTitle)
                        Spacer(minLength: Design.Spacing.s)
                        Text("\(model.progress)%")
                            .font(Design.Typography.rating)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                    }
                    Text(VelaL10n.text("offline_of_pieces_complete", String(describing: (model.completedPieces)), String(describing: (model.pieceCount))))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .accessibilityIdentifier("area-sheet-pieces")
                    ProgressView(value: Double(model.progress), total: 100)
                        .tint(Design.Colors.accent)
                        .accessibilityIdentifier("area-sheet-progress")
                } else if model.areaReady {
                    Text(VelaL10n.text("offline_area_ready"))
                        .font(Design.Typography.rowTitle)
                        .accessibilityIdentifier("area-sheet-ready")
                    Text(VelaL10n.text("offline_the_map_is_saved_offline_routing"))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                } else if model.errorKey == "no_space" {
                    Text(VelaL10n.text("offline_not_enough_free_space_nothing_was"))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.danger)
                        .accessibilityIdentifier("area-sheet-no-space")
                } else if model.errorKey != nil {
                    Text(VelaL10n.text("offline_the_area_did_not_finish_of", String(describing: (model.completedPieces)), String(describing: (model.pieceCount))))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.danger)
                        .accessibilityIdentifier("area-sheet-error")
                }
                if model.areaDataStage == "cameras" {
                    Text(VelaL10n.text("offline_saving_camera_data"))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .accessibilityIdentifier("area-sheet-cameras")
                } else if model.areaDataStage == "addresses" {
                    Text(VelaL10n.text("offline_saving_address_data"))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .accessibilityIdentifier("area-sheet-addresses")
                } else if model.areaCameraRows != -1 || model.areaAddressRows != -1 {
                    Text(VelaL10n.text("offline_camera_data_address_data", String(describing: (rows(model.areaCameraRows))), String(describing: (rows(model.areaAddressRows)))))
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .accessibilityIdentifier("area-sheet-data")
                }
            }
        }
    }

    // MARK: - Region download

    private var downloadCard: some View {
        OfflineCard {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                if let id = model.downloadingId {
                    HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                        Text(regionName(id))
                            .font(Design.Typography.rowTitle)
                        Spacer(minLength: Design.Spacing.s)
                        Text("\(model.progress)%")
                            .font(Design.Typography.rating)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .accessibilityIdentifier("offline-progress-percent")
                    }
                    #if DEBUG
                    if LaunchOptions.current.offlineTest {
                        Text(model.downloadDebugLine)
                            .font(Design.Typography.micro.monospaced())
                            .accessibilityIdentifier("offline-download-debug")
                    }
                    #endif
                    Text(VelaL10n.text("offline_of_pieces_complete", String(describing: (model.completedPieces)), String(describing: (model.pieceCount))))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                        .accessibilityIdentifier("offline-pieces")
                    ProgressView(value: Double(model.progress), total: 100)
                        .tint(Design.Colors.accent)
                        .accessibilityIdentifier("offline-progress")
                    HStack(spacing: Design.Spacing.s) {
                        Button(VelaL10n.text("settings_cancel"), role: .cancel) { model.cancel() }
                            .font(Design.Typography.button)
                            .frame(minHeight: Design.Size.hitTarget)
                            .accessibilityIdentifier("offline-cancel")
                        Spacer(minLength: 0)
                    }
                    #if DEBUG
                    if LaunchOptions.current.offlineTest {
                        Button("Suspend for relaunch test") { model.suspendDownloadForTest() }
                            .font(Design.Typography.body)
                            .frame(minHeight: Design.Size.hitTarget)
                            .accessibilityIdentifier("offline-test-suspend")
                    }
                    #endif
                }
            }
        }
    }

    private var updateCard: some View {
        OfflineCard {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                if let id = model.updatingId {
                    Text(regionName(id))
                        .font(Design.Typography.rowTitle)
                    #if DEBUG
                    if LaunchOptions.current.offlineTest || OfflineFixtureSupport.isEnabled {
                        Text(model.updateDebugLine)
                            .font(Design.Typography.micro.monospaced())
                            .accessibilityIdentifier("offline-update-debug")
                    }
                    #endif
                    ProgressView(value: Double(model.progress), total: 100)
                        .tint(Design.Colors.accent)
                        .accessibilityIdentifier("offline-update-progress")
                }
            }
        }
    }

    private var updatedCard: some View {
        OfflineCard {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                if let updated = model.updatedId {
                    Text(VelaL10n.text("offline_updated_deltas_re_downloaded", String(describing: (regionName(updated))), String(describing: (model.updateDeltaPieces)), String(describing: (model.updateFullPieces))))
                        .font(Design.Typography.detail)
                        .accessibilityIdentifier("offline-updated")
                    #if DEBUG
                    if LaunchOptions.current.offlineTest || OfflineFixtureSupport.isEnabled {
                        Text("updated=\(updated) delta=\(model.updateDeltaPieces) full=\(model.updateFullPieces)")
                            .font(Design.Typography.micro.monospaced())
                            .accessibilityIdentifier("offline-updated-debug")
                    }
                    #endif
                }
            }
        }
    }

    private var errorCard: some View {
        OfflineCard(tone: .danger) {
            if model.errorKey == "no_space" {
                Text(VelaL10n.text("offline_not_enough_free_space_free_some"))
                    .font(Design.Typography.detail)
                    .foregroundStyle(Design.Colors.danger)
                    .accessibilityIdentifier("offline-no-space")
            } else {
                Text(VelaL10n.text("offline_download_failed_of_pieces_are_complete", String(describing: (model.completedPieces)), String(describing: (model.pieceCount))))
                    .font(Design.Typography.detail)
                    .foregroundStyle(Design.Colors.danger)
                    .accessibilityIdentifier("offline-error")
            }
        }
    }

    private var completedCard: some View {
        OfflineCard {
            HStack(spacing: Design.Spacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Design.Colors.success)
                    .accessibilityHidden(true)
                Text(VelaL10n.text("offline_is_ready", String(describing: (regionName(model.completedId ?? "")))))
                    .font(Design.Typography.rowTitle)
                    .accessibilityIdentifier("offline-ready")
            }
        }
    }

    // MARK: - Regions

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            sectionHeader(VelaL10n.text("offline_installed_regions"))
            if model.installedRows.isEmpty {
                OfflineCard {
                    Text(VelaL10n.text("offline_no_regions_installed"))
                        .font(Design.Typography.detail)
                        .foregroundStyle(Design.Colors.secondaryLabel)
                }
            } else {
                ForEach(model.installedRows) { row in
                    installedCard(row)
                }
            }
        }
    }

    private func installedCard(_ row: OfflineRow) -> some View {
        OfflineCard {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                if stacksAtLargeType {
                    VStack(alignment: .leading, spacing: Design.Spacing.s) {
                        installedLabel(row)
                        installedActions(row)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                        installedLabel(row)
                        Spacer(minLength: Design.Spacing.s)
                        installedActions(row)
                    }
                }
                if let categories = model.categories(row.id) {
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        categoryLine(row.id, "pack", "Place pack", categories.packBytes)
                        categoryLine(row.id, "places", "Places", categories.placesBytes)
                        categoryLine(row.id, "basemap", "Basemap", categories.basemapBytes)
                    }
                }
            }
        }
    }

    private func installedLabel(_ row: OfflineRow) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            Text(row.name)
                .font(Design.Typography.rowTitle)
            Text(VelaL10n.text("offline_installed", String(describing: (bytes(row.installedBytes)))))
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.secondaryLabel)
                .accessibilityIdentifier("offline-installed-\(row.id)")
        }
    }

    @ViewBuilder
    private func installedActions(_ row: OfflineRow) -> some View {
        HStack(spacing: Design.Spacing.s) {
            if row.updatable {
                Button(VelaL10n.text("offline_update", String(describing: (megabytes(row.updateMb))))) { model.update(row.id) }
                    .font(Design.Typography.button)
                    .frame(minHeight: Design.Size.hitTarget)
                    .disabled(model.downloadingId != nil || model.updatingId != nil)
                    .accessibilityIdentifier("offline-update-\(row.id)")
                    .buttonStyle(.borderless)
            }
            Button(role: .destructive) { model.delete(row.id) } label: {
                Image(systemName: "trash")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.danger)
                    .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(VelaL10n.text("list_delete_title", String(describing: (row.name))))
            .accessibilityIdentifier("offline-delete-\(row.id)")
            .buttonStyle(.borderless)
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            sectionHeader(VelaL10n.text("offline_available_regions"))
            OfflineCard {
                VStack(alignment: .leading, spacing: Design.Spacing.s) {
                    HStack(spacing: Design.Spacing.s) {
                        Image(systemName: "magnifyingglass")
                            .font(Design.Typography.detail)
                            .foregroundStyle(Design.Colors.secondaryLabel)
                            .accessibilityHidden(true)
                        TextField(VelaL10n.text("offline_filter_regions"), text: $filter)
                            .font(Design.Typography.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("offline-filter")
                    }
                    .padding(.horizontal, Design.Spacing.m)
                    .frame(minHeight: Design.Size.hitTarget)
                    .background(
                        Design.Colors.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: Design.Radius.s))
                    ForEach(Array(availableRows.enumerated()), id: \.element.id) { index, row in
                        availableRow(row)
                        if index < availableRows.count - 1 {
                            Divider()
                                .background(Design.Colors.separator)
                        }
                    }
                }
            }
        }
    }

    private func availableRow(_ row: OfflineRow) -> some View {
        Group {
            if stacksAtLargeType {
                VStack(alignment: .leading, spacing: Design.Spacing.s) {
                    availableLabel(row)
                    downloadButton(row)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                    availableLabel(row)
                    Spacer(minLength: Design.Spacing.s)
                    downloadButton(row)
                }
            }
        }
        .frame(minHeight: Design.Size.hitTarget)
    }

    private func availableLabel(_ row: OfflineRow) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            Text(row.name)
                .font(Design.Typography.rowTitle)
            Text(megabytes(row.sizeMb))
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.secondaryLabel)
        }
    }

    private func downloadButton(_ row: OfflineRow) -> some View {
        Button(VelaL10n.text("settings_download")) { model.download(row.id) }
            .font(Design.Typography.button)
            .frame(minHeight: Design.Size.hitTarget)
            .disabled(model.downloadingId != nil)
            .accessibilityIdentifier("offline-download-\(row.id)")
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            sectionHeader(VelaL10n.text("offline_storage_by_category"))
            OfflineCard {
                VStack(alignment: .leading, spacing: Design.Spacing.m) {
                    storageBar
                    VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                        storageLegend("Basemap", model.basemapBytes, "basemap", Design.Colors.accent)
                        storageLegend("Places", model.placesBytes, "places", Design.Colors.accent.opacity(0.7))
                        storageLegend("Place packs", model.packBytes, "pack", Design.Colors.accent.opacity(0.45))
                        storageLegend("Map fonts", model.glyphBytes, "glyphs", Design.Colors.secondaryLabel.opacity(0.4))
                    }
                }
            }
        }
    }

    /// A stacked bar of the four categories. The legend under it names every segment, so the
    /// split never relies on color alone. Drawn with `Canvas`: no layout feedback and no
    /// continuous geometry pass while a download publishes progress.
    private var storageBar: some View {
        Canvas { context, size in
            let values = [model.basemapBytes, model.placesBytes, model.packBytes, model.glyphBytes]
            let total = max(1, values.reduce(0, +))
            var x: CGFloat = 0
            for index in values.indices {
                let width = size.width * CGFloat(values[index]) / CGFloat(total)
                let gap = index < values.count - 1 ? Design.Spacing.xxs : 0
                let rect = CGRect(x: x, y: 0, width: max(0, width - gap), height: size.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: size.height / 2),
                    with: .color(storageColor(index)))
                x += width
            }
        }
        .frame(height: Design.Spacing.s)
        .background(Design.Colors.surfaceSunken, in: Capsule())
        .accessibilityHidden(true)
    }

    private func storageColor(_ index: Int) -> Color {
        switch index {
        case 0: return Design.Colors.accent
        case 1: return Design.Colors.accent.opacity(0.7)
        case 2: return Design.Colors.accent.opacity(0.45)
        default: return Design.Colors.secondaryLabel.opacity(0.4)
        }
    }

    private func storageLegend(_ label: String, _ value: Int64, _ key: String, _ color: Color) -> some View {
        HStack(spacing: Design.Spacing.s) {
            Circle()
                .fill(color)
                .frame(width: Design.Spacing.s, height: Design.Spacing.s)
                .accessibilityHidden(true)
            Text(label)
                .font(Design.Typography.detail)
            Spacer(minLength: Design.Spacing.s)
            Text(bytes(value))
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.secondaryLabel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-size-\(key)")
    }

    // MARK: - Helpers

    private var stacksAtLargeType: Bool {
        dynamicTypeSize >= .accessibility4
    }

    private var availableRows: [OfflineRow] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.rows.filter {
            !$0.installed && (query.isEmpty || $0.name.lowercased().contains(query) || $0.id.contains(query))
        }
    }

    private var stageLabel: String {
        switch model.stage {
        case "pack": return "Place pack"
        case "places": return "Places archive"
        case "glyphs": return "Map fonts"
        case "basemap": return "Offline basemap"
        case "cameras": return "Camera data"
        case "addresses": return "Address data"
        default: return "Preparing download"
        }
    }

    private func regionName(_ id: String) -> String {
        model.rows.first { $0.id == id }?.name ?? id
    }

    private func infoRow(_ title: String, _ value: String, id: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
            Text(title)
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.secondaryLabel)
            Spacer(minLength: Design.Spacing.s)
            Text(value)
                .font(Design.Typography.detail)
                .foregroundStyle(Design.Colors.label)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: Design.Size.hitTarget)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id ?? "offline-info-\(title)")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Design.Typography.caption.weight(.semibold))
            .foregroundStyle(Design.Colors.secondaryLabel)
            .textCase(.uppercase)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func categoryLine(_ region: String, _ key: String, _ label: String, _ value: Int64) -> some View {
        if value > 0 {
            HStack(spacing: Design.Spacing.s) {
                Text(label)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                Spacer(minLength: Design.Spacing.s)
                Text(bytes(value))
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryLabel)
                Button(role: .destructive) {
                    model.deleteCategory(region, category: key)
                } label: {
                    Image(systemName: "trash")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.danger)
                        .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(VelaL10n.text("offline_delete_for", String(describing: (label)), String(describing: (regionName(region)))))
                .accessibilityIdentifier("offline-delete-\(key)-\(region)")
                .buttonStyle(.borderless)
            }
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func rows(_ count: Int) -> String {
        if count < 0 { return "no answer" }
        return "\(count) rows"
    }

    private func megabytes(_ value: Int) -> String {
        if value >= 1024 { return String(format: "%.1f GB", Double(value) / 1024) }
        return "\(value) MB"
    }
}

/// One object of the offline sheet: 12 pt radius, page inset, level 1 shadow. The shadow is a
/// layer signal, not decoration (`DESIGN.md` 3.4).
struct OfflineCard<Content: View>: View {
    enum Tone: Equatable {
        case normal
        case danger
    }

    let tone: Tone
    let content: Content

    init(tone: Tone = .normal, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Padding.sheet)
            .background(
                tone == .danger ? Design.Colors.danger.opacity(0.08) : Design.Colors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: Design.Radius.m))
            .shadow(
                color: Design.Elevation.level1.color,
                radius: Design.Elevation.level1.radius,
                y: Design.Elevation.level1.y)
    }
}

/// A card row in the offline `List`: page margins, no separator, transparent row background so
/// the sheet surface shows through.
struct OfflineListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(
                top: Design.Spacing.m,
                leading: Design.Padding.page,
                bottom: Design.Spacing.m,
                trailing: Design.Padding.page))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension View {
    /// Applies the offline card row geometry.
    func offlineListRow() -> some View {
        modifier(OfflineListRow())
    }
}

/// Trailing chevron of a row that opens another surface.
struct OfflineChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(Design.Typography.caption.weight(.semibold))
            .foregroundStyle(Design.Colors.secondaryLabel)
            .flipsForRightToLeftLayoutDirection(true)
            .accessibilityHidden(true)
    }
}
