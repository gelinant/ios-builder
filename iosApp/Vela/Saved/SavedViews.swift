import SwiftUI
import UniformTypeIdentifiers

private struct SavedShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct SavedNameEdit: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let onSave: (String) -> Void
}

private struct SavedNameEditor: View {
    let edit: SavedNameEdit
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(edit: SavedNameEdit) {
        self.edit = edit
        _text = State(initialValue: edit.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(VelaL10n.text("route_save_hint"), text: $text)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("saved-name-field")
            }
            .navigationTitle(edit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(VelaL10n.text("settings_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("place_save")) {
                        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { edit.onSave(name) }
                        dismiss()
                    }
                    .accessibilityIdentifier("saved-name-save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct SavedNoteEdit: Identifiable {
    let id = UUID()
    let text: String
    let onSave: (String?) -> Void
}

private struct SavedNoteEditor: View {
    let edit: SavedNoteEdit
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(edit: SavedNoteEdit) {
        self.edit = edit
        _text = State(initialValue: edit.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(VelaL10n.text("place_note_label"), text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("saved-note-field")
            }
            .navigationTitle(VelaL10n.text("place_note_label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(VelaL10n.text("settings_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("place_save")) {
                        edit.onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .accessibilityIdentifier("saved-note-save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// One create-or-edit request for the list editor, including an optional selection to move once the
/// list exists. Keeping the pending ids here lets "New list" in the bulk bar finish in one save.
/// The editor is a pushed screen of the Saved stack, so this value is also its route.
private struct SavedListEditorDraft: Hashable {
    let id = UUID()
    var listId: String? = nil
    var moveIds: Set<String> = []
    var fromListId: String?
}

/// One page of the Saved navigation stack. The list editor is pushed like a list, not presented
/// as a sheet over the Saved sheet: a second sheet lost the keyboard focus of its name field.
private enum SavedRoute: Hashable {
    case list(String)
    case editor(SavedListEditorDraft)
}

private let savedListColors: [UInt32] = [
    0xFF1A73E8, 0xFF00897B, 0xFFE8710A, 0xFFD93025, 0xFF9334E6, 0xFF1E8E3E, 0xFFF9AB00, 0xFF5F6368,
]

private let savedListSymbols = ["bookmark", "star.fill", "heart.fill", "flag.fill", "cart.fill", "fork.knife"]
private let savedListEmoji = ["❤️", "⭐", "📍", "☕", "🍕", "🍜", "🛒", "🎁", "🏖️", "✈️", "🐾", "⚽"]

/// A list's icon key is either an SF Symbol name or "emoji:X".
private struct SavedListIcon: View {
    let key: String

    var body: some View {
        if key.hasPrefix("emoji:") {
            Text(String(key.dropFirst(VelaL10n.text("saved_emoji").count)))
        } else if key.isEmpty {
            Image(systemName: "bookmark.fill")
        } else {
            Image(systemName: key)
        }
    }
}

/// Shows a list's sound choice as one of the shared PassAlerts keys.
private struct SavedSoundChoices: View {
    let selected: String?
    let onPick: (String?) -> Void

    private let choices: [(String?, String)] = [
        (nil, VelaL10n.text("list_sound_off")),
        ("ping", VelaL10n.text("list_sound_ping")),
        ("bell", VelaL10n.text("list_sound_bell")),
        ("double", VelaL10n.text("list_sound_double")),
        ("low", VelaL10n.text("list_sound_low")),
        ("name", VelaL10n.text("list_sound_name")),
    ]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                Button {
                    onPick(choice.0)
                } label: {
                    Text(choice.1)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected == choice.0 ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground), in: Capsule())
                        .overlay(
                            Capsule().stroke(selected == choice.0 ? Color.accentColor : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("list-sound-\(choice.0 ?? "off")")
            }
        }
    }
}

/// A minimal wrapping row for the sound and color choices. SwiftUI has no grid that wraps by
/// intrinsic width on every supported OS, and the choices are short.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The list editor: name, colour, icon, emoji and drive-by sound in one save. It is a pushed
/// screen inside the Saved navigation stack. As a sheet over the Saved sheet, its name field
/// could stay unfocused after every tap, so the editor owns no presentation of its own.
private struct SavedListEditorScreen: View {
    @ObservedObject var model: SavedModel
    let draft: SavedListEditorDraft
    let onSaved: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var icon: String
    @State private var color: UInt32
    @State private var alert: String?
    @State private var emoji: String
    @FocusState private var nameFocused: Bool

    init(model: SavedModel, draft: SavedListEditorDraft, onSaved: @escaping (String) -> Void) {
        self.model = model
        self.draft = draft
        self.onSaved = onSaved
        let list = draft.listId.flatMap { id in model.lists.first(where: { $0.id == id }) }
        _name = State(initialValue: list?.name ?? "")
        _icon = State(initialValue: list?.icon ?? "bookmark")
        _color = State(initialValue: list?.color ?? savedListColors[0])
        _alert = State(initialValue: list?.alert)
        _emoji = State(initialValue: list?.icon.hasPrefix("emoji:") == true
            ? String(list!.icon.dropFirst("emoji:".count)) : "")
    }

    private var problem: String? { model.listNameProblem(name, excluding: draft.listId) }

    var body: some View {
        Form {
            Section {
                TextField(VelaL10n.text("list_name_label"), text: $name)
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
                    .accessibilityIdentifier("saved-name-field")
                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("list-editor-error")
                }
            }
            Section(VelaL10n.text("list_color_label")) {
                FlowLayout(spacing: 10) {
                    ForEach(savedListColors, id: \.self) { value in
                        Button {
                            color = value
                            AppGraph.navHaptics.savedTick()
                        } label: {
                            Circle()
                                .fill(Color(argb: value))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(Color.primary, lineWidth: value == color ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("list-color-\(String(value, radix: 16))")
                    }
                }
            }
            Section(VelaL10n.text("list_icon_label")) {
                FlowLayout(spacing: 10) {
                    ForEach(savedListSymbols, id: \.self) { symbol in
                        Button {
                            icon = symbol
                            emoji = ""
                        } label: {
                            Image(systemName: symbol)
                                .frame(width: 36, height: 36)
                                .background(icon == symbol ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("list-icon-\(symbol)")
                    }
                    ForEach(savedListEmoji, id: \.self) { value in
                        Button {
                            icon = "emoji:" + value
                            emoji = value
                        } label: {
                            Text(value).frame(width: 36, height: 36)
                                .background(icon == "emoji:" + value ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("list-emoji-\(value)")
                    }
                }
                TextField(VelaL10n.text("saved_or_type_an_emoji"), text: $emoji)
                    .onChange(of: emoji) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        icon = trimmed.isEmpty ? "bookmark" : "emoji:" + trimmed
                    }
                    .accessibilityIdentifier("list-editor-emoji")
            }
            Section(VelaL10n.text("saved_sound")) {
                Text(VelaL10n.text("saved_a_drive_past_one_of_this"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SavedSoundChoices(selected: alert) { picked in
                    alert = picked
                    AppGraph.navHaptics.savedTick()
                    model.playListSound(picked, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "this place" : name.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                // Without containment the container swallows the six choices: VoiceOver and the
                // tests saw one element instead of the sound buttons.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("list-editor-sounds")
                #if DEBUG
                if let feedback = model.feedback {
                    Text(feedback)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("saved-feedback")
                }
                #endif
            }
        }
        .accessibilityIdentifier("list-editor-form")
        .navigationTitle(draft.listId == nil ? VelaL10n.text("list_new_title") : VelaL10n.text("list_edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(VelaL10n.text("place_save")) {
                    guard problem == nil else { return }
                    if let saved = model.saveList(id: draft.listId, name: name, icon: icon, color: color, alert: alert) {
                        if !draft.moveIds.isEmpty {
                            model.movePlaces(draft.moveIds, from: draft.fromListId, to: saved)
                        }
                        onSaved(saved)
                        dismiss()
                    }
                }
                .disabled(problem != nil)
                .accessibilityIdentifier("saved-name-save")
            }
        }
        .onAppear {
            // The push animation swallows a tap made in its first moments on a loaded simulator.
            // Focus follows the push, so the keyboard is up even when that first tap was lost.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nameFocused = true }
        }
    }
}

/// The count, All, Move, Rename (one picked), Remove and Done bar shared by quick saves and a list.
private struct SavedSelectionBar: View {
    let count: Int
    let total: Int
    let targets: [SavedListItem]
    let canRename: Bool
    let onAll: () -> Void
    let onMove: (String) -> Void
    let onNewList: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(VelaL10n.text("saved_selected", String(describing: (count))))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("saved-selected-count")
            Spacer(minLength: 4)
            Button(count == total ? VelaL10n.text("saved_none") : VelaL10n.text("place_photo_category_all"), action: onAll)
                .accessibilityIdentifier("saved-bulk-all")
            Menu {
                ForEach(targets) { list in
                    Button(VelaL10n.text("saved_move_to", String(describing: (list.name)))) { onMove(list.id) }
                }
                Button(VelaL10n.text("list_new_title"), action: onNewList)
            } label: {
                Image(systemName: "bookmark")
            }
            .accessibilityLabel(VelaL10n.text("bulk_move"))
            .accessibilityIdentifier("saved-bulk-move")
            .disabled(count == 0)
            if canRename {
                Button(action: onRename) {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(VelaL10n.text("settings_trip_rename"))
                .accessibilityIdentifier("saved-bulk-rename")
            }
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .accessibilityLabel(VelaL10n.text("nav_stops_remove_action"))
            .accessibilityIdentifier("saved-bulk-remove")
            .disabled(count == 0)
            Button(VelaL10n.text("settings_trip_select_done"), action: onDone)
                .accessibilityIdentifier("saved-bulk-done")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// The Saved sheet: quick-saved places, lists, recents, shortcuts, routes and parking.
struct SavedView: View {
    @ObservedObject var model: SavedModel
    let canSaveRoute: Bool
    let defaultRouteName: String
    /// UX-JOURNEY: the list to open on presentation, for the return from a place opened in a list.
    var initialListId: String? = nil
    let onSaveRoute: (String) -> Void
    let onOpenPlace: (SavedPlaceItem) -> Void
    /// A place opened from a list keeps that list as its return point.
    var onOpenPlaceFromList: ((SavedPlaceItem) -> Void)? = nil
    let onOpenShortcut: (Bool) -> Void
    let onRecentSearch: (String) -> Void
    let onOpenRecentPlace: (RecentItem) -> Void
    let onOpenRoute: (SavedRouteItem) -> Void
    let onClose: () -> Void

    @State private var nameEdit: SavedNameEdit?
    @State private var showsImporter = false
    @State private var showsLinkImport = false
    @State private var importError: String?
    @State private var selectingSaved: Set<String>?
    @State private var removingSelection = false
    @State private var editMode: EditMode = .inactive
    @State private var reorderingLists = false
    @State private var exportError: String?
    @State private var shareItems: SavedShareItems?
    @State private var confirmsClearParkingHistory = false
    /// The pushed pages, so a return from a place can reopen the same list.
    @State private var path: [SavedRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            savedList
                .environment(\.editMode, $editMode)
                .navigationTitle(VelaL10n.text("place_saved"))
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: SavedRoute.self) { route in
                    switch route {
                    case .list(let listId):
                        SavedListDetailView(
                            model: model, listId: listId,
                            onOpenPlace: onOpenPlaceFromList ?? onOpenPlace,
                            onEditList: { draft in path.append(.editor(draft)) })
                    case .editor(let draft):
                        SavedListEditorScreen(model: model, draft: draft) { _ in
                            selectingSaved = nil
                        }
                    }
                }
                .onAppear {
                    SavedImportSupport.install(model: model)
                    SavedTestSupport.importFixtureIfNeeded(model: model)
                    if path.isEmpty, let initialListId,
                       model.lists.contains(where: { $0.id == initialListId }) {
                        path = [.list(initialListId)]
                    }
                }
                .safeAreaInset(edge: .bottom) { selectionInset }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(VelaL10n.text("place_close"), action: onClose).accessibilityIdentifier("saved-close")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if reorderingLists {
                            Button(VelaL10n.text("settings_trip_select_done")) {
                                reorderingLists = false
                                editMode = .inactive
                            }
                            .accessibilityIdentifier("saved-reorder-done")
                        }
                        Menu {
                            Button {
                                showsImporter = true
                            } label: {
                                Label(VelaL10n.text("saved_kml_kmz_or_other_file"), systemImage: "doc")
                            }
                            .accessibilityIdentifier("saved-import-file")
                            Button {
                                showsLinkImport = true
                            } label: {
                                Label(VelaL10n.text("saved_google_maps_list_link"), systemImage: "link")
                            }
                            .accessibilityIdentifier("saved-import-google")
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel(VelaL10n.text("saved_import_places"))
                        .accessibilityIdentifier("saved-import")                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Section(VelaL10n.text("settings_export")) {
                                Menu(VelaL10n.text("settings_saved_places")) {
                                    exportButton("JSON", identifier: "saved-export-json") {
                                        model.exportSaved(format: "JSON")
                                    }
                                    exportButton("GPX", identifier: "saved-export-gpx") {
                                        model.exportSaved(format: "GPX")
                                    }
                                    exportButton("KML", identifier: "saved-export-kml") {
                                        model.exportSaved(format: "KML")
                                    }
                                }
                                Button(VelaL10n.text("saved_all_lists_json")) {
                                    guard let document = model.exportAllLists() else {
                                        exportError = "Nothing to export"
                                        return
                                    }
                                    shareItems = SavedShareItems(urls: [document.url])
                                }
                                .accessibilityIdentifier("saved-export-lists")
                                Button(VelaL10n.text("saved_everything_json_two_files")) {
                                    let documents = model.exportEverything()
                                    guard !documents.isEmpty else {
                                        exportError = "Nothing to export"
                                        return
                                    }
                                    shareItems = SavedShareItems(urls: documents.map(\.url))
                                }
                                .accessibilityIdentifier("saved-export-everything")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(VelaL10n.text("mapvm_export_saved_chooser"))
                        .accessibilityIdentifier("saved-export-menu")
                    }
                }
                .sheet(item: $nameEdit) { edit in SavedNameEditor(edit: edit) }
                .sheet(isPresented: $showsLinkImport, onDismiss: {
                    model.runQueuedGoogleLinkImport()
                }) {
                    SavedLinkImportSheet(model: model)
                }
                .confirmationDialog(
                    model.pendingImport?.question ?? "",
                    isPresented: Binding(
                        get: { model.pendingImport != nil },
                        set: { if !$0 { model.cancelPendingImport() } }),
                    titleVisibility: .visible
                ) {
                    Button(VelaL10n.text("saved_merge")) { model.resolvePendingImport(merge: true) }
                        .accessibilityIdentifier("saved-import-merge")
                    Button(VelaL10n.text("saved_replace")) { model.resolvePendingImport(merge: false) }
                        .accessibilityIdentifier("saved-import-replace")
                    Button(VelaL10n.text("settings_cancel"), role: .cancel) { model.cancelPendingImport() }
                } message: {
                    Text(model.pendingImport?.detail ?? "")
                }
                .confirmationDialog(
                    removingSelection ? VelaL10n.text("saved_remove_places_2", String(describing: (selectingSaved?.count ?? 0))) : "",
                    isPresented: $removingSelection, titleVisibility: .visible) {
                    Button(VelaL10n.text("nav_stops_remove_action"), role: .destructive) {
                        if let selectingSaved {
                            model.removePlaces(selectingSaved, in: nil)
                        }
                        selectingSaved = nil
                    }
                    .accessibilityIdentifier("saved-bulk-remove-confirm")
                    Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
                }
                .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        do {
                            let ext = url.pathExtension.lowercased()
                            if ext == "kml" || ext == "kmz" {
                                let data = try SavedImportReader.readData(url)
                                model.importKml(data: data, name: url.lastPathComponent)
                            } else {
                                let text = try SavedDocumentReader.read(url)
                                model.importFile(text: text, name: url.lastPathComponent)
                            }
                        } catch {
                            importError = "The file could not be read"
                        }
                    case .failure:
                        importError = "The file could not be read"
                    }
                }
                .alert(VelaL10n.text("saved_import_places"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                    Button(VelaL10n.text("map_ok"), role: .cancel) {}
                } message: {
                    Text(importError ?? "")
                }
                .alert(VelaL10n.text("settings_export"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                    Button(VelaL10n.text("map_ok"), role: .cancel) {}
                } message: {
                    Text(exportError ?? "")
                }
                .sheet(item: $shareItems) { items in
                    ActivityView(items: items.urls)
                }
                .confirmationDialog(
                    VelaL10n.text("saved_clear_parking_history"),
                    isPresented: $confirmsClearParkingHistory,
                    titleVisibility: .visible
                ) {
                    Button(VelaL10n.text("settings_clear_history"), role: .destructive, action: model.clearParkingHistory)
                        .accessibilityIdentifier("parking-clear-confirm")
                    Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
                } message: {
                    Text(VelaL10n.text("saved_past_parking_spots_will_be_removed"))
                }
        }
    }

    private var savedList: some View {
        List {
            if canSaveRoute {
                Section(VelaL10n.text("saved_current_route")) {
                    Button {
                        nameEdit = SavedNameEdit(title: VelaL10n.text("route_save_title"), text: defaultRouteName) { name in
                            onSaveRoute(name)
                        }
                    } label: {
                        Label(VelaL10n.text("route_save"), systemImage: "plus.square.on.square")
                    }
                    .accessibilityIdentifier("route-save")
                }
            }
            shortcuts
            savedSection
            listsSection
            recentsSection
            routesSection
            parkingSection
            if model.importing {
                Section {
                    HStack {
                        ProgressView()
                        Text(model.importTotal > 0
                            ? VelaL10n.text("saved_importing_places_of", String(describing: (model.importDone)), String(describing: (model.importTotal)))
                            : VelaL10n.text("saved_importing_places"))
                        Spacer()
                        Button(VelaL10n.text("settings_cancel"), action: model.cancelImport)
                            .accessibilityIdentifier("saved-import-cancel")
                    }
                    if model.importTotal > 0 {
                        ProgressView(value: Double(model.importDone), total: Double(model.importTotal))
                            .accessibilityIdentifier("saved-import-progress")
                    }
                }
            }
            if let message = model.importMessage {
                Section { Text(message).font(.footnote).accessibilityIdentifier("saved-import-message") }
            }
        }
    }

    @ViewBuilder private var selectionInset: some View {
        if let selectingSaved {
            SavedSelectionBar(
                count: selectingSaved.count,
                total: model.savedPlaces.count,
                targets: model.lists,
                canRename: selectingSaved.count == 1,
                onAll: {
                    self.selectingSaved = selectingSaved.count == model.savedPlaces.count
                        ? [] : Set(model.savedPlaces.map(\.id))
                },
                onMove: { target in
                    model.movePlaces(selectingSaved, from: nil, to: target)
                    self.selectingSaved = nil
                },
                onNewList: {
                    path.append(.editor(SavedListEditorDraft(moveIds: selectingSaved, fromListId: nil)))
                },
                onRename: {
                    guard let id = selectingSaved.first,
                          let item = model.savedPlaces.first(where: { $0.id == id }) else { return }
                    self.selectingSaved = nil
                    rename(item)
                },
                onRemove: { removingSelection = true },
                onDone: { self.selectingSaved = nil })
        }
    }

    @ViewBuilder private func exportButton(
        _ title: String, identifier: String, document: @escaping () -> SavedShareDocument?
    ) -> some View {
        Button(title) {
            guard let exported = document() else {
                exportError = "Nothing to export"
                return
            }
            shareItems = SavedShareItems(urls: [exported.url])
        }
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var shortcuts: some View {
        if model.home != nil || model.work != nil {
            Section(VelaL10n.text("saved_home_and_work")) {
                if let home = model.home {
                    ShortcutRow(
                        title: "Home", place: home,
                        onOpen: { onOpenShortcut(true) }, onClear: { model.clearShortcut(home: true) })
                }
                if let work = model.work {
                    ShortcutRow(
                        title: "Work", place: work,
                        onOpen: { onOpenShortcut(false) }, onClear: { model.clearShortcut(home: false) })
                }
            }
        }
    }

    private var savedSection: some View {
        Section {
            if model.savedPlaces.isEmpty {
                Text(VelaL10n.text("saved_places_you_save_appear_here"))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.savedPlaces) { item in
                if let selectingSaved {
                    SavedSelectableRow(
                        item: item,
                        checked: selectingSaved.contains(item.id),
                        identifier: "saved-place") {
                        if selectingSaved.contains(item.id) {
                            self.selectingSaved?.remove(item.id)
                        } else {
                            self.selectingSaved?.insert(item.id)
                        }
                    }
                } else {
                    SavedPlaceButton(
                        model: model, item: item, identifier: "saved-place",
                        onOpen: onOpenPlace, onRename: rename,
                        onShare: { shareItems = SavedShareItems(urls: $0) })
                        .simultaneousGesture(LongPressGesture().onEnded { _ in
                            selectingSaved = [item.id]
                        })
                }
            }
        } header: {
            HStack {
                Text(VelaL10n.text("saved_saved", String(describing: (model.savedPlaces.count))))
                Spacer()
                if !model.savedPlaces.isEmpty && selectingSaved == nil {
                    Button(VelaL10n.text("saved_select")) { selectingSaved = [] }
                        .font(.caption)
                        .accessibilityIdentifier("saved-select")
                }
            }
        }
    }

    private var listsSection: some View {
        Section {
            ForEach(model.lists) { list in
                NavigationLink(value: SavedRoute.list(list.id)) {
                    HStack {
                        SavedListIcon(key: list.icon)
                            .foregroundStyle(Color(argb: list.color))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name)
                            if let alert = list.alert {
                                Text(VelaL10n.text("saved_sound") + " " + (alert == "name" ? VelaL10n.text("list_sound_name") : alert))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(list.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("saved-list")
                .accessibilityLabel(VelaL10n.text("saved_places", String(describing: (list.name)), String(describing: (list.count))))
                .swipeActions(edge: .trailing) {
                    Button(VelaL10n.text("parking_history_delete"), role: .destructive) { model.deleteList(list.id) }
                }
                .swipeActions(edge: .leading) {
                    Button(VelaL10n.text("settings_saved_route_edit")) { edit(list) }.tint(.orange)
                }
                .contextMenu {
                    Button(VelaL10n.text("list_edit")) { edit(list) }
                    Button(VelaL10n.text("saved_move_up")) { model.moveList(list.id, by: -1) }
                    Button(VelaL10n.text("saved_move_down")) { model.moveList(list.id, by: 1) }
                }
            }
            .onMove { indices, target in
                var ids = model.lists.map(\.id)
                ids.move(fromOffsets: indices, toOffset: target)
                model.reorderLists(ids)
            }
            Button {
                path.append(.editor(SavedListEditorDraft()))
            } label: {
                Label(VelaL10n.text("list_new_title"), systemImage: "plus")
            }
            .accessibilityIdentifier("saved-create-list")
        } header: {
            HStack {
                Text(VelaL10n.text("saved_lists"))
                Spacer()
                if !model.lists.isEmpty && selectingSaved == nil {
                    Button(reorderingLists ? VelaL10n.text("settings_trip_select_done") : VelaL10n.text("saved_reorder")) {
                        reorderingLists.toggle()
                        editMode = reorderingLists ? .active : .inactive
                    }
                    .font(.caption)
                    .accessibilityIdentifier("saved-reorder")
                }
            }
        }
    }

    @ViewBuilder private var recentsSection: some View {
        if !model.recents.isEmpty {
            Section {
                ForEach(model.recents) { item in
                    Button {
                        if item.kind == "search" { onRecentSearch(item.title) } else { onOpenRecentPlace(item) }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: item.kind == "search" ? "magnifyingglass" : "clock")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(item.title).foregroundStyle(.primary)
                                if let subtitle = item.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(item.kind == "search" ? "recent-search" : "recent-place")
                    .accessibilityLabel(item.title)
                    .swipeActions(edge: .trailing) {
                        Button(VelaL10n.text("nav_stops_remove_action"), role: .destructive) { model.removeRecent(item) }
                    }
                }
            } header: {
                HStack {
                    Text(VelaL10n.text("search_recents"))
                    Spacer()
                    Button(VelaL10n.text("settings_clear_history_action"), action: model.clearRecents)
                        .font(.caption)
                        .accessibilityIdentifier("recents-clear")
                }
            }
        }
    }

    @ViewBuilder private var routesSection: some View {
        if !model.routes.isEmpty {
            Section(VelaL10n.text("settings_saved_routes")) {
                ForEach(model.routes) { route in
                    Button {
                        onOpenRoute(route)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.name).foregroundStyle(.primary)
                                Text(route.originLabel.isEmpty ? route.destLabel : VelaL10n.text("route_save_default_from", String(describing: (route.originLabel)), String(describing: (route.destLabel))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(VelaL10n.text("saved_saved_2", String(describing: (route.mode)), String(describing: (route.createdAt.formatted(date: .abbreviated, time: .omitted)))))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("saved-route")
                    .accessibilityLabel(route.name)
                    .swipeActions(edge: .trailing) {
                        Button(VelaL10n.text("parking_history_delete"), role: .destructive) { model.deleteRoute(route.id) }
                    }
                    .swipeActions(edge: .leading) {
                        Button(VelaL10n.text("settings_trip_rename")) { rename(route) }.tint(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder private var parkingSection: some View {
        if model.parking != nil || !model.parkingHistory.isEmpty {
            Section(VelaL10n.text("cat_parking")) {
                if let parking = model.parking {
                    HStack {
                        Label(VelaL10n.text("map_parked_car"), systemImage: "car.fill")
                            .accessibilityIdentifier("parking-current")
                        Spacer()
                        Text(model.parkingAge(parking)).foregroundStyle(.secondary)
                        Button(VelaL10n.text("map_parking_find")) {
                            guard model.openParking() != nil else { return }
                            // The Saved sheet closes first; the place sheet underneath then shows
                            // the spot with its Directions action, walking included.
                            onClose()
                        }
                        .accessibilityIdentifier("parking-find")
                        Button(VelaL10n.text("settings_clear_history_action"), action: model.clearParking)
                            .accessibilityIdentifier("parking-clear")
                    }
                }
                if !model.parkingHistory.isEmpty {
                    DisclosureGroup("Parking history") {
                        ForEach(model.parkingHistory) { spot in
                            HStack {
                                Text(model.parkingAge(spot))
                                Spacer()
                                Button(VelaL10n.text("parking_history_restore")) { model.restoreParking(spot) }
                                    .accessibilityIdentifier("parking-restore")
                                Button(VelaL10n.text("parking_history_delete"), role: .destructive) { model.deleteParking(spot) }
                                    .accessibilityIdentifier("parking-delete")
                            }
                        }
                        Button(VelaL10n.text("settings_clear_history"), role: .destructive) {
                            confirmsClearParkingHistory = true
                        }
                        .accessibilityIdentifier("parking-clear-history")
                    }
                }
            }
        }
    }

    private func rename(_ item: SavedPlaceItem) {
        nameEdit = SavedNameEdit(title: VelaL10n.text("saved_rename_title"), text: item.name) { name in
            model.rename(item, to: name)
        }
    }

    private func rename(_ route: SavedRouteItem) {
        nameEdit = SavedNameEdit(title: VelaL10n.text("settings_saved_route_rename"), text: route.name) { name in
            model.renameRoute(route.id, to: name)
        }
    }

    private func edit(_ list: SavedListItem) {
        path.append(.editor(SavedListEditorDraft(listId: list.id)))
    }
}

private struct SavedSelectableRow: View {
    let item: SavedPlaceItem
    let checked: Bool
    let identifier: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(.primary)
                    if let address = item.address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let note = item.note {
                        Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(item.name)
        .accessibilityValue(checked ? "selected" : "not selected")
    }
}

private struct SavedListDetailView: View {
    @ObservedObject var model: SavedModel
    let listId: String
    let onOpenPlace: (SavedPlaceItem) -> Void
    /// Pushes the editor on the Saved stack, so it stays a page and never a second sheet.
    let onEditList: (SavedListEditorDraft) -> Void
    @State private var nameEdit: SavedNameEdit?
    @State private var noteEdit: SavedNoteEdit?
    @State private var shapeEdit: SavedNameEdit?
    @State private var shareItems: SavedShareItems?
    @State private var selecting: Set<String>?
    @State private var removingSelection = false
    @State private var editMode: EditMode = .inactive
    @State private var reordering = false
    @Environment(\.dismiss) private var dismiss

    private var list: SavedListItem? { model.lists.first { $0.id == listId } }
    private var places: [SavedPlaceItem] { model.places(in: listId) }
    private var shapes: [SavedShapeItem] { model.shapes(in: listId) }

    var body: some View {
        placesList
            .environment(\.editMode, $editMode)
            .navigationTitle(list?.name ?? VelaL10n.text("saved_list"))
            .safeAreaInset(edge: .bottom) { selectionBar }
            .toolbar { detailToolbar }
            .sheet(item: $nameEdit) { edit in SavedNameEditor(edit: edit) }
            .sheet(item: $noteEdit) { edit in SavedNoteEditor(edit: edit) }
            .sheet(item: $shapeEdit) { edit in SavedNameEditor(edit: edit) }
            .sheet(item: $shareItems) { items in ActivityView(items: items.urls) }
            .confirmationDialog(
                removingSelection ? VelaL10n.text("saved_remove_places", String(describing: (selecting?.count ?? 0))) : "",
                isPresented: $removingSelection, titleVisibility: .visible) {
                Button(VelaL10n.text("nav_stops_remove_action"), role: .destructive) {
                    if let selecting {
                        model.removePlaces(selecting, in: listId)
                    }
                    selecting = nil
                }
                .accessibilityIdentifier("saved-bulk-remove-confirm")
                Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
            }
    }

    private var placesList: some View {
        List {
            if places.isEmpty && shapes.isEmpty {
                Text(VelaL10n.text("saved_no_places_in_this_list")).foregroundStyle(.secondary)
            }
            ForEach(places) { item in
                placeRow(item)
            }
            .onMove { indices, target in
                var ids = places.map(\.id)
                ids.move(fromOffsets: indices, toOffset: target)
                model.reorderPlaces(in: listId, orderedIds: ids)
            }
            if !shapes.isEmpty { shapesSection }
        }
    }

    /// The list's drawn lines and areas, edited here: rename, line or area, colour, delete. The
    /// points themselves come from an import or a drawing on the map, which this screen does not
    /// create; the shared store's `addShape` is what such a drawing calls.
    private var shapesSection: some View {
        Section(VelaL10n.text("saved_lines_and_areas")) {
            ForEach(shapes) { shape in
                HStack(spacing: 10) {
                    Image(systemName: shape.closed ? "square.dashed" : "scribble")
                        .foregroundStyle(Color(argb: shape.color))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shape.name.isEmpty ? (shape.closed ? VelaL10n.text("shape_area") : VelaL10n.text("shape_line")) : shape.name)
                        Text(shape.closed ? VelaL10n.text("saved_area_points", String(describing: (shape.pointCount))) : VelaL10n.text("saved_line_points", String(describing: (shape.pointCount))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button(VelaL10n.text("settings_trip_rename")) {
                            shapeEdit = SavedNameEdit(title: VelaL10n.text("settings_trip_rename"), text: shape.name) { name in
                                model.renameShape(shape, to: name)
                            }
                        }
                        Button(shape.closed ? VelaL10n.text("saved_make_a_line") : VelaL10n.text("saved_make_an_area")) {
                            model.setShapeClosed(shape, closed: !shape.closed)
                        }
                        Button(VelaL10n.text("parking_history_delete"), role: .destructive) { model.deleteShape(shape) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(VelaL10n.text("saved_shape_actions"))
                    .accessibilityIdentifier("saved-shape-actions")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("saved-list-shape")
                .accessibilityLabel(shape.name)
            }
        }
    }

    @ViewBuilder private func placeRow(_ item: SavedPlaceItem) -> some View {
        if let selecting {
            SavedSelectableRow(
                item: item,
                checked: selecting.contains(item.id),
                identifier: "saved-list-place") {
                toggle(item.id)
            }
        } else {
            SavedPlaceButton(
                model: model, item: item, identifier: "saved-list-place",
                onOpen: onOpenPlace, onRename: rename,
                onShare: { shareItems = SavedShareItems(urls: $0) }, onNote: note)
                .simultaneousGesture(LongPressGesture().onEnded { _ in
                    self.selecting = [item.id]
                })
        }
    }

    private func toggle(_ id: String) {
        guard var picked = selecting else { return }
        if picked.contains(id) {
            picked.remove(id)
        } else {
            picked.insert(id)
        }
        selecting = picked
    }

    @ViewBuilder private var selectionBar: some View {
        if let picked = selecting {
            SavedSelectionBar(
                count: picked.count,
                total: places.count,
                targets: model.lists.filter { $0.id != listId },
                canRename: picked.count == 1,
                onAll: {
                    self.selecting = picked.count == places.count ? [] : Set(places.map(\.id))
                },
                onMove: { target in
                    model.movePlaces(picked, from: listId, to: target)
                    self.selecting = nil
                },
                onNewList: {
                    let ids = picked
                    self.selecting = nil
                    onEditList(SavedListEditorDraft(moveIds: ids, fromListId: listId))
                },
                onRename: {
                    guard let id = picked.first,
                          let item = places.first(where: { $0.id == id }) else { return }
                    self.selecting = nil
                    rename(item)
                },
                onRemove: { removingSelection = true },
                onDone: { self.selecting = nil })
        }
    }

    @ToolbarContentBuilder private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if reordering {
                Button(VelaL10n.text("settings_trip_select_done")) {
                    reordering = false
                    editMode = .inactive
                }
                .accessibilityIdentifier("saved-reorder-done")
            } else if selecting == nil {
                Button(VelaL10n.text("saved_select")) { selecting = [] }
                    .accessibilityIdentifier("saved-select")
                Menu {
                    if let list {
                        Button(VelaL10n.text("list_edit")) { onEditList(SavedListEditorDraft(listId: list.id)) }
                        Button(VelaL10n.text("saved_reorder_places")) {
                            reordering = true
                            editMode = .active
                        }
                        Button(VelaL10n.text("saved_share_list_json")) {
                            if let document = model.exportList(list, format: "JSON") {
                                shareItems = SavedShareItems(urls: [document.url])
                            }
                        }
                        .accessibilityIdentifier("saved-list-share")
                        Menu(VelaL10n.text("mapvm_export_list_chooser")) {
                            Button("GPX") {
                                if let document = model.exportList(list, format: "GPX") {
                                    shareItems = SavedShareItems(urls: [document.url])
                                }
                            }
                            .accessibilityIdentifier("saved-list-export-gpx")
                            Button("KML") {
                                if let document = model.exportList(list, format: "KML") {
                                    shareItems = SavedShareItems(urls: [document.url])
                                }
                            }
                            .accessibilityIdentifier("saved-list-export-kml")
                        }
                    }
                    Button(VelaL10n.text("saved_delete_list"), role: .destructive) {
                        model.deleteList(listId)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(VelaL10n.text("saved_list_actions"))
            }
        }
    }

    private func rename(_ item: SavedPlaceItem) {
        nameEdit = SavedNameEdit(title: VelaL10n.text("saved_rename_title"), text: item.name) { name in
            model.rename(item, to: name)
        }
    }

    private func note(_ item: SavedPlaceItem) {
        noteEdit = SavedNoteEdit(text: item.note ?? "") { text in
            model.setNote(item, note: text)
        }
    }
}

private struct SavedPlaceButton: View {
    @ObservedObject var model: SavedModel
    let item: SavedPlaceItem
    let identifier: String
    let onOpen: (SavedPlaceItem) -> Void
    let onRename: (SavedPlaceItem) -> Void
    let onShare: ([URL]) -> Void
    var onNote: ((SavedPlaceItem) -> Void)? = nil

    var body: some View {
        Button { onOpen(item) } label: {
            HStack(alignment: .firstTextBaseline) {
                if let icon = item.icon, !icon.isEmpty {
                    SavedListIcon(key: icon).foregroundStyle(.red)
                } else {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(.primary)
                    if let address = item.address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let note = item.note {
                        Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(item.name)
        .swipeActions(edge: .trailing) {
            Button(VelaL10n.text("nav_stops_remove_action"), role: .destructive) { model.remove(item) }
        }
        .swipeActions(edge: .leading) {
            Button(VelaL10n.text("settings_trip_rename")) { onRename(item) }.tint(.orange)
        }
        .contextMenu {
            Button(VelaL10n.text("settings_trip_rename")) { onRename(item) }
            if let onNote {
                Button(item.note == nil ? VelaL10n.text("saved_add_note") : VelaL10n.text("place_edit_note")) { onNote(item) }
            }
            Menu(VelaL10n.text("saved_export_place")) {
                ForEach(["JSON", "GPX", "KML"], id: \.self) { format in
                    Button(format) {
                        if let document = model.exportPlace(item, format: format) {
                            onShare([document.url])
                        }
                    }
                    .accessibilityIdentifier("saved-place-export-\(format.lowercased())")
                }
            }
            ForEach(model.lists.filter { $0.id != item.listId }) { list in
                Button(VelaL10n.text("saved_move_to", String(describing: (list.name)))) { model.move(item, to: list.id) }
            }
            Button(VelaL10n.text("nav_stops_remove_action"), role: .destructive) { model.remove(item) }
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let place: ShortcutItem
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Button(action: onOpen) {
                HStack {
                    Image(systemName: title == "Home" ? "house.fill" : "briefcase.fill")
                    VStack(alignment: .leading) {
                        Text(title)
                        Text(place.name).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(title == "Home" ? "shortcut-home" : "shortcut-work")
            .accessibilityLabel(title)
            Button(VelaL10n.text("settings_clear_history_action"), action: onClear)
                .accessibilityIdentifier(title == "Home" ? "shortcut-home-clear" : "shortcut-work-clear")
        }
    }
}

/// One-tap map shortcuts. They use the same SavedModel.openShortcut path as Siri and deep links.
struct SavedMapShortcuts: View {
    @ObservedObject var model: SavedModel
    let onOpen: (Bool) -> Void

    var body: some View {
        if model.home != nil {
            button(home: true)
        }
        if model.work != nil {
            button(home: false)
        }
    }

    private func button(home: Bool) -> some View {
        Button {
            onOpen(home)
        } label: {
            Image(systemName: home ? "house.fill" : "briefcase.fill")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .background(.regularMaterial, in: Circle())
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        .accessibilityLabel(home ? VelaL10n.text("saved_directions_home") : VelaL10n.text("saved_directions_to_work"))
        .accessibilityIdentifier(home ? "map-shortcut-home" : "map-shortcut-work")
    }
}

/// The Save menu on a place sheet: quick save, list membership, shortcuts and parking.
struct SavePlaceSheet: View {
    @ObservedObject var model: SavedModel
    @Environment(\.dismiss) private var dismiss
    @State private var nameEdit: SavedNameEdit?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: model.toggleSelected) {
                        Label(model.selectedSaved ? VelaL10n.text("saved_remove_from_saved") : VelaL10n.text("saved_save_to_saved"),
                              systemImage: model.selectedSaved ? VelaL10n.text("saved_star_fill") : "star")
                    }
                    .accessibilityIdentifier("save-toggle")
                }
                Section(VelaL10n.text("saved_lists")) {
                    ForEach(model.lists) { list in
                        Button {
                            if model.selectedListIds.contains(list.id) {
                                model.removeSelected(from: list.id)
                            } else {
                                model.addSelected(to: list.id)
                            }
                        } label: {
                            HStack {
                                Label(list.name, systemImage: model.selectedListIds.contains(list.id) ? VelaL10n.text("saved_checkmark_circle_fill") : "circle")
                                Spacer()
                                Text("\(list.count)").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("save-list")
                        .accessibilityLabel(list.name)
                        .accessibilityValue(model.selectedListIds.contains(list.id) ? "selected" : "not selected")
                    }
                    Button {
                        nameEdit = SavedNameEdit(title: VelaL10n.text("list_new_title"), text: "") { name in
                            _ = model.createList(named: name, addPlace: true)
                        }
                    } label: {
                        Label(VelaL10n.text("saved_new_list_and_add"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("save-create-list")
                }
                Section(VelaL10n.text("saved_shortcuts_and_parking")) {
                    Button(VelaL10n.text("place_set_as_home")) { model.setSelectedShortcut(home: true) }
                    Button(VelaL10n.text("place_set_as_work")) { model.setSelectedShortcut(home: false) }
                    Button(VelaL10n.text("saved_save_parking_spot_here"), action: model.saveParkingAtSelected)
                }
                #if DEBUG
                if let feedback = model.feedback {
                    Section { Text(feedback).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("saved-feedback") }
                }
                #endif
            }
            .navigationTitle(VelaL10n.text("saved_save_place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                }
            }
            .sheet(item: $nameEdit) { edit in SavedNameEditor(edit: edit) }
        }
        .presentationDetents([.medium, .large])
    }
}

extension Color {
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}
