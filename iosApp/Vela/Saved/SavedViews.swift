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
                TextField("Name", text: $text)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("saved-name-field")
            }
            .navigationTitle(edit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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

/// The Saved sheet: quick-saved places, lists, recents, shortcuts, routes and parking.
struct SavedView: View {
    @ObservedObject var model: SavedModel
    let canSaveRoute: Bool
    let defaultRouteName: String
    let onSaveRoute: (String) -> Void
    let onOpenPlace: (SavedPlaceItem) -> Void
    let onOpenShortcut: (Bool) -> Void
    let onRecentSearch: (String) -> Void
    let onOpenRecentPlace: (RecentItem) -> Void
    let onOpenRoute: (SavedRouteItem) -> Void
    let onClose: () -> Void

    @State private var nameEdit: SavedNameEdit?
    @State private var showsImporter = false
    @State private var importError: String?
    @State private var exportError: String?
    @State private var shareItems: SavedShareItems?
    @State private var confirmsClearParkingHistory = false

    var body: some View {
        NavigationStack {
            List {
                if canSaveRoute {
                    Section("Current route") {
                        Button {
                            nameEdit = SavedNameEdit(title: "Save this route", text: defaultRouteName) { name in
                                onSaveRoute(name)
                            }
                        } label: {
                            Label("Save this route", systemImage: "plus.square.on.square")
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
                                ? "Importing places \(model.importDone) of \(model.importTotal)"
                                : "Importing places")
                            Spacer()
                            Button("Cancel", action: model.cancelImport)
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
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { SavedTestSupport.importFixtureIfNeeded(model: model) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose).accessibilityIdentifier("saved-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import places")
                    .accessibilityIdentifier("saved-import")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Export") {
                            Menu("Saved places") {
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
                            Button("All lists (JSON)") {
                                guard let document = model.exportAllLists() else {
                                    exportError = "Nothing to export"
                                    return
                                }
                                shareItems = SavedShareItems(urls: [document.url])
                            }
                            .accessibilityIdentifier("saved-export-lists")
                            Button("Everything (JSON, two files)") {
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
                    .accessibilityLabel("Export saved places")
                    .accessibilityIdentifier("saved-export-menu")
                }
            }
            .sheet(item: $nameEdit) { edit in SavedNameEditor(edit: edit) }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let text = try SavedDocumentReader.read(url)
                        model.importFile(text: text, name: url.lastPathComponent)
                    } catch {
                        importError = "The file could not be read"
                    }
                case .failure:
                    importError = "The file could not be read"
                }
            }
            .alert("Import places", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .alert("Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .sheet(item: $shareItems) { items in
                ActivityView(items: items.urls)
            }
            .confirmationDialog(
                "Clear parking history?",
                isPresented: $confirmsClearParkingHistory,
                titleVisibility: .visible
            ) {
                Button("Clear history", role: .destructive, action: model.clearParkingHistory)
                    .accessibilityIdentifier("parking-clear-confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Past parking spots will be removed. The current spot is kept.")
            }
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
            Section("Home and Work") {
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
        Section("Saved (\(model.savedPlaces.count))") {
            if model.savedPlaces.isEmpty {
                Text("Places you save appear here")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.savedPlaces) { item in
                SavedPlaceButton(
                    model: model, item: item, identifier: "saved-place",
                    onOpen: onOpenPlace, onRename: rename,
                    onShare: { shareItems = SavedShareItems(urls: $0) })
            }
        }
    }

    private var listsSection: some View {
        Section("Lists") {
            ForEach(model.lists) { list in
                NavigationLink {
                    SavedListDetailView(model: model, listId: list.id, onOpenPlace: onOpenPlace)
                } label: {
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(Color(argb: list.color))
                        Text(list.name)
                        Spacer()
                        Text("\(list.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("saved-list")
                .accessibilityLabel("\(list.name), \(list.count) places")
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { model.deleteList(list.id) }
                }
                .swipeActions(edge: .leading) {
                    Button("Rename") { rename(list) }.tint(.orange)
                }
                .contextMenu {
                    Button("Move up") { model.moveList(list.id, by: -1) }
                    Button("Move down") { model.moveList(list.id, by: 1) }
                }
            }
            Button {
                nameEdit = SavedNameEdit(title: "New list", text: "") { name in
                    _ = model.createList(named: name)
                }
            } label: {
                Label("New list", systemImage: "plus")
            }
            .accessibilityIdentifier("saved-create-list")
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
                        Button("Remove", role: .destructive) { model.removeRecent(item) }
                    }
                }
            } header: {
                HStack {
                    Text("Recents")
                    Spacer()
                    Button("Clear", action: model.clearRecents)
                        .font(.caption)
                        .accessibilityIdentifier("recents-clear")
                }
            }
        }
    }

    @ViewBuilder private var routesSection: some View {
        if !model.routes.isEmpty {
            Section("Saved routes") {
                ForEach(model.routes) { route in
                    Button {
                        onOpenRoute(route)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.name).foregroundStyle(.primary)
                                Text(route.originLabel.isEmpty ? route.destLabel : "\(route.originLabel) to \(route.destLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(route.mode), saved \(route.createdAt.formatted(date: .abbreviated, time: .omitted))")
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
                        Button("Delete", role: .destructive) { model.deleteRoute(route.id) }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Rename") { rename(route) }.tint(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder private var parkingSection: some View {
        if model.parking != nil || !model.parkingHistory.isEmpty {
            Section("Parking") {
                if let parking = model.parking {
                    HStack {
                        Label("Parked car", systemImage: "car.fill")
                            .accessibilityIdentifier("parking-current")
                        Spacer()
                        Text(model.parkingAge(parking)).foregroundStyle(.secondary)
                        Button("Find my car") {
                            guard model.openParking() != nil else { return }
                            // The Saved sheet closes first; the place sheet underneath then shows
                            // the spot with its Directions action, walking included.
                            onClose()
                        }
                        .accessibilityIdentifier("parking-find")
                        Button("Clear", action: model.clearParking)
                            .accessibilityIdentifier("parking-clear")
                    }
                }
                if !model.parkingHistory.isEmpty {
                    DisclosureGroup("Parking history") {
                        ForEach(model.parkingHistory) { spot in
                            HStack {
                                Text(model.parkingAge(spot))
                                Spacer()
                                Button("Restore") { model.restoreParking(spot) }
                                    .accessibilityIdentifier("parking-restore")
                                Button("Delete", role: .destructive) { model.deleteParking(spot) }
                                    .accessibilityIdentifier("parking-delete")
                            }
                        }
                        Button("Clear history", role: .destructive) {
                            confirmsClearParkingHistory = true
                        }
                        .accessibilityIdentifier("parking-clear-history")
                    }
                }
            }
        }
    }

    private func rename(_ item: SavedPlaceItem) {
        nameEdit = SavedNameEdit(title: "Rename place", text: item.name) { name in
            model.rename(item, to: name)
        }
    }

    private func rename(_ list: SavedListItem) {
        nameEdit = SavedNameEdit(title: "Rename list", text: list.name) { name in
            model.renameList(list.id, to: name)
        }
    }

    private func rename(_ route: SavedRouteItem) {
        nameEdit = SavedNameEdit(title: "Rename route", text: route.name) { name in
            model.renameRoute(route.id, to: name)
        }
    }
}

private struct SavedListDetailView: View {
    @ObservedObject var model: SavedModel
    let listId: String
    let onOpenPlace: (SavedPlaceItem) -> Void
    @State private var nameEdit: SavedNameEdit?
    @State private var shareItems: SavedShareItems?
    @Environment(\.dismiss) private var dismiss

    private var list: SavedListItem? { model.lists.first { $0.id == listId } }

    var body: some View {
        List {
            let places = model.places(in: listId)
            if places.isEmpty {
                Text("No places in this list").foregroundStyle(.secondary)
            }
            ForEach(places) { item in
                SavedPlaceButton(
                    model: model, item: item, identifier: "saved-list-place",
                    onOpen: onOpenPlace, onRename: rename,
                    onShare: { shareItems = SavedShareItems(urls: $0) })
            }
        }
        .navigationTitle(list?.name ?? "List")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let list {
                        Button("Rename") { rename(list) }
                        Button("Share list (JSON)") {
                            if let document = model.exportList(list, format: "JSON") {
                                shareItems = SavedShareItems(urls: [document.url])
                            }
                        }
                        .accessibilityIdentifier("saved-list-share")
                        Menu("Export list") {
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
                    Button("Delete list", role: .destructive) {
                        model.deleteList(listId)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("List actions")
            }
        }
        .sheet(item: $nameEdit) { edit in SavedNameEditor(edit: edit) }
        .sheet(item: $shareItems) { items in ActivityView(items: items.urls) }
    }

    private func rename(_ item: SavedPlaceItem) {
        nameEdit = SavedNameEdit(title: "Rename place", text: item.name) { name in
            model.rename(item, to: name)
        }
    }

    private func rename(_ list: SavedListItem) {
        nameEdit = SavedNameEdit(title: "Rename list", text: list.name) { name in
            model.renameList(list.id, to: name)
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

    var body: some View {
        Button { onOpen(item) } label: {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(.primary)
                    if let address = item.address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(item.name)
        .swipeActions(edge: .trailing) {
            Button("Remove", role: .destructive) { model.remove(item) }
        }
        .swipeActions(edge: .leading) {
            Button("Rename") { onRename(item) }.tint(.orange)
        }
        .contextMenu {
            Button("Rename") { onRename(item) }
            Menu("Export place") {
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
                Button("Move to \(list.name)") { model.move(item, to: list.id) }
            }
            Button("Remove", role: .destructive) { model.remove(item) }
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
            Button("Clear", action: onClear)
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
        .accessibilityLabel(home ? "Directions home" : "Directions to work")
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
                        Label(model.selectedSaved ? "Remove from Saved" : "Save to Saved",
                              systemImage: model.selectedSaved ? "star.fill" : "star")
                    }
                    .accessibilityIdentifier("save-toggle")
                }
                Section("Lists") {
                    ForEach(model.lists) { list in
                        Button {
                            if model.selectedListIds.contains(list.id) {
                                model.removeSelected(from: list.id)
                            } else {
                                model.addSelected(to: list.id)
                            }
                        } label: {
                            HStack {
                                Label(list.name, systemImage: model.selectedListIds.contains(list.id) ? "checkmark.circle.fill" : "circle")
                                Spacer()
                                Text("\(list.count)").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("save-list")
                        .accessibilityLabel(list.name)
                    }
                    Button {
                        nameEdit = SavedNameEdit(title: "New list", text: "") { name in
                            _ = model.createList(named: name, addPlace: true)
                        }
                    } label: {
                        Label("New list and add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("save-create-list")
                }
                Section("Shortcuts and parking") {
                    Button("Set as Home") { model.setSelectedShortcut(home: true) }
                    Button("Set as Work") { model.setSelectedShortcut(home: false) }
                    Button("Save parking spot here", action: model.saveParkingAtSelected)
                }
            }
            .navigationTitle("Save place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
