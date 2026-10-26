import SwiftUI
import UIKit

struct MapScreen: View {
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var deepLinks: VelaDeepLinkCenter
    @StateObject private var map: MapController
    @StateObject private var location = LocationPermission()
    @StateObject private var search: SearchModel
    @StateObject private var calibration: CalibrationModel
    @StateObject private var place: PlaceModel
    @StateObject private var mapPoi: MapPoiModel
    @StateObject private var route: RouteModel
    @StateObject private var transit: TransitModel
    @StateObject private var offline: OfflineModel
    @StateObject private var saved: SavedModel
    @StateObject private var spotlight: SpotlightIndexer
    @StateObject private var nav: NavModel
    @StateObject private var settings: SettingsModel
    @State private var showsLocationOffAlert = false
    @State private var showsOffline = false
    @State private var showsSaved = false
    @State private var showsSettings = false
    @State private var searchFocused = false
    @State private var showsRecents = false
    @State private var panelExpanded = true
    @State private var searchBlurTick = 0
    @State private var deepLinkError: String?
    @State private var deepLinkDebug = "route=none error=0"
    @State private var coreLine = "VelaCore \(VelaCoreCheck.version)"

    init() {
        #if DEBUG
        // The fixture protocol must precede AppGraph's process-wide URLSession.
        NavAlertTestSupport.enableIfRequested()
        #endif
        _map = StateObject(wrappedValue: MapController())
        _search = StateObject(wrappedValue: SearchModel(store: AppGraph.session.search))
        _calibration = StateObject(wrappedValue: CalibrationModel(calibration: AppGraph.session.calibration))
        _place = StateObject(wrappedValue: PlaceModel(session: AppGraph.session))
        _mapPoi = StateObject(wrappedValue: MapPoiModel(session: AppGraph.session))
        _route = StateObject(wrappedValue: RouteModel(session: AppGraph.session))
        _transit = StateObject(wrappedValue: TransitModel(
            session: AppGraph.session, location: AppGraph.location))
        _offline = StateObject(wrappedValue: OfflineModel(store: AppGraph.session.offline))
        _saved = StateObject(wrappedValue: SavedModel(session: AppGraph.session))
        _spotlight = StateObject(wrappedValue: AppGraph.spotlight)
        _nav = StateObject(wrappedValue: NavModel(
            session: AppGraph.session, location: AppGraph.location, voice: AppGraph.navVoice))
        _settings = StateObject(wrappedValue: SettingsModel(store: AppGraph.session.settings))
        VelaIntentTestSupport.prepareIfNeeded()
    }

    var body: some View {
        screenContent
    }

    private var mapLifecycleContent: some View {
        mapRoot
        .sheet(isPresented: $showsSaved) {
            SavedView(
                model: saved,
                canSaveRoute: route.hasRoute,
                defaultRouteName: defaultRouteName,
                onSaveRoute: { _ = AppGraph.session.saveActiveRoute(name: $0) },
                onOpenPlace: { openSavedPlace($0) },
                onRecentSearch: { query in
                    showsSaved = false
                    startSearch(query)
                },
                onOpenRecentPlace: { item in
                    showsSaved = false
                    route.close()
                    mapPoi.close()
                    search.clear()
                    saved.open(item)
                },
                onOpenRoute: { item in
                    showsSaved = false
                    route.close()
                    mapPoi.close()
                    search.clear()
                    saved.open(item)
                },
                onClose: { showsSaved = false })
        }
        .environment(\.locale, settings.locale)
        .environment(\.layoutDirection, settings.layoutDirection)
        .onAppear {
            let search = self.search
            let route = self.route
            let saved = self.saved
            map.onViewportChange = { viewport in
                search.viewportChanged(viewport)
                route.mapCenterChanged(latitude: (viewport.south + viewport.north) / 2,
                                       longitude: (viewport.west + viewport.east) / 2)
                saved.mapCenterChanged(latitude: (viewport.south + viewport.north) / 2,
                                       longitude: (viewport.west + viewport.east) / 2)
            }
            map.onUserLocation = { c in
                search.locationChanged(latitude: c.latitude, longitude: c.longitude)
                route.locationChanged(latitude: c.latitude, longitude: c.longitude)
                offline.onLocation(latitude: c.latitude, longitude: c.longitude)
                saved.locationChanged(latitude: c.latitude, longitude: c.longitude)
            }
            map.onRouteTap = { index in
                if !nav.active && !transit.active { route.select(index) }
            }
            map.onResultTap = { index in
                guard !nav.active && !transit.active, index < search.rows.count else { return }
                pick(search.rows[index])
            }
            map.onPoiTap = { name, coordinate, kind in
                guard !nav.active && !transit.active else { return }
                blurSearch()
                route.close()
                place.close()
                mapPoi.close()
                search.clear()
                map.focus(latitude: coordinate.latitude, longitude: coordinate.longitude)
                mapPoi.tap(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude, kind: kind)
            }
            map.onMapLongPress = { coordinate in
                guard !nav.active && !transit.active else { return }
                blurSearch()
                route.close()
                place.close()
                mapPoi.close()
                search.clear()
                mapPoi.longPress(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            map.onSavedTap = { index in
                guard index < saved.markers.count else { return }
                let marker = saved.markers[index]
                if marker.parking {
                    showsSaved = true
                } else {
                    route.close()
                    mapPoi.close()
                    search.clear()
                    saved.open(marker)
                    map.focus(onSaved: marker)
                }
            }
            nav.attach(map: map)
            nav.start()
            transit.attach(map: map)
            transit.start()
            #if DEBUG
            if LaunchOptions.current.transitFixture { transit.startFixture() }
            #endif
            search.start()
            place.start()
            mapPoi.start()
            route.start()
            offline.start()
            saved.start()
            spotlight.start()
            settings.start()
            nav.setImperial(settings.imperial)
            calibration.start()
            map.showSaved(saved.markers)
            if LaunchOptions.current.followUser {
                locate()
            }
            if let url = VelaIntentTestSupport.consumeFirstSavedLink() {
                deepLinks.open(url)
            }
            handlePendingDeepLink()
        }
    }

    private var mapEventsContent: some View {
        mapLifecycleContent
        .onChange(of: deepLinks.pending) { _, request in
            if request != nil { handlePendingDeepLink() }
        }
        .onChange(of: place.isOpen) { _, open in
            if !nav.active { map.setBottomInset(open ? sheetInset : 0) }
        }
        .onChange(of: route.lines) { _, lines in
            if !nav.active && !transit.active {
                map.showRoutes(lines, selected: route.activeIndex, fit: !lines.isEmpty, insets: routeInsets)
            }
        }
        .onChange(of: route.activeIndex) { _, index in
            if !nav.active && !transit.active {
                map.showRoutes(route.lines, selected: index, fit: false, insets: routeInsets)
            }
        }
        .onChange(of: route.isOpen) { _, open in
            if !open && !nav.active && !transit.active {
                map.clearRoutes()
                map.setBottomInset(place.isOpen ? sheetInset : 0)
            }
        }
    }

    private var mapStateContent: some View {
        mapEventsContent
        .onChange(of: offline.revision) { _, _ in
            map.refreshOfflineStyle()
        }
        .onChange(of: nav.navigating) { _, navigating in
            if navigating {
                place.close()
                mapPoi.close()
                search.clear()
            }
        }
        .onChange(of: settings.imperial) { _, imperial in
            nav.setImperial(imperial)
        }
        .onChange(of: transit.active) { _, active in
            if active {
                place.close()
                mapPoi.close()
                search.clear()
            } else {
                map.setBottomInset(place.isOpen ? sheetInset : 0)
            }
        }
        .onChange(of: mapPoi.card) { _, card in
            if let card, card.droppedPin {
                map.showDroppedPin(latitude: card.latitude, longitude: card.longitude, title: card.name)
            } else {
                map.clearDroppedPin()
            }
        }
        .onChange(of: search.rows) { _, rows in
            if !rows.isEmpty { panelExpanded = true }
            map.showResults(rows, insets: UIEdgeInsets(top: 140, left: 40, bottom: 420, right: 40))
        }
        .onChange(of: saved.markers) { _, markers in
            map.showSaved(markers)
        }
    }

    private var screenContent: some View {
        mapStateContent
        .task {
            coreLine = await VelaCoreCheck.run()
        }
        .sheet(isPresented: $showsOffline) {
            OfflineSheet(model: offline)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsScreen(model: settings, offline: offline)
        }
        .alert("Location is off", isPresented: $showsLocationOffAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow location for Vela in Settings to see where you are on the map.")
        }
        .alert("Cannot open link", isPresented: Binding(
            get: { deepLinkError != nil },
            set: { if !$0 { deepLinkError = nil } })) {
            Button("Open Saved") {
                deepLinkError = nil
                showsSaved = true
            }
            .accessibilityIdentifier("intents-open-saved")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deepLinkError ?? "")
                .accessibilityIdentifier("intents-error")
        }
    }

    private var mapRoot: some View {
        ZStack {
            MapView(controller: map)
                .ignoresSafeArea()
            if nav.active {
                NavChrome(model: nav)
            } else if transit.active {
                TransitGuidanceCard(model: transit)
            } else {
                browserChrome
            }
        }
    }

    private var browserChrome: some View {
        VStack(spacing: 8) {
            searchChrome
            debugStatus
            Spacer()
            mapActionButtons
            bottomPanel
            attribution
        }
    }

    @ViewBuilder private var searchChrome: some View {
        HStack(spacing: 8) {
            SearchBar(
                text: $search.query,
                searching: search.searching,
                onSubmit: submit,
                onClear: clearSearch,
                onOffline: { showsOffline = true },
                onFocusChange: {
                    searchFocused = $0
                    if $0 { showsRecents = true }
                },
                blurTick: searchBlurTick,
                onSettings: { showsSettings = true })
            Button {
                showsSaved = true
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .background(.regularMaterial, in: Circle())
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .accessibilityLabel("Saved")
            .accessibilityIdentifier("saved-open")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        if search.hasSuggestions && searchFocused {
            SuggestionsPanel(rows: search.suggestions, onPick: pickSuggestion)
        } else if showsQuickCategories {
            QuickCategoriesView(onPick: { startSearch($0.query) })
        }
    }

    private var mapActionButtons: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Button {
                    if saved.parking == nil {
                        _ = saved.saveParkingHere()
                    } else {
                        showsSaved = true
                    }
                } label: {
                    Image(systemName: saved.parking == nil ? "car" : "car.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .accessibilityLabel(saved.parking == nil ? "Save parking spot" : "Show parked car")
                .accessibilityIdentifier("parking-button")
                LocateButton(isFollowing: map.isFollowingUser, action: locate)
            }
        }
        // Clears the map's attribution info button in the bottom right corner.
        .padding(.bottom, search.hasContent || place.isOpen || mapPoi.card != nil || route.isOpen ? 0 : 36)
        .padding(.horizontal, 12)
    }

    @ViewBuilder private var bottomPanel: some View {
        if route.isOpen {
            if route.showsSteps {
                StepsSheet(model: route)
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
            } else {
                RoutePickerSheet(model: route, onClose: route.close, onStart: nav.startIfAvailable,
                                 onStartTransit: transit.startIfAvailable)
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
            }
        } else if let card = place.card {
            PlaceSheet(model: place, saved: saved, card: card, onClose: closePlace, onDirections: openDirections)
                .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
        } else if let card = mapPoi.card {
            MapPoiSheet(
                card: card, resolving: mapPoi.resolving, googleUnavailable: mapPoi.googleUnavailable,
                onDirections: mapPoi.directions, onClose: mapPoi.close)
        } else if search.hasContent {
            ResultsPanel(
                rows: search.rows,
                message: search.message,
                searching: search.searching,
                expanded: $panelExpanded,
                onPick: pick)
        } else if search.query.isEmpty && (searchFocused || showsRecents) && !saved.recents.isEmpty {
            RecentsPanel(rows: saved.recents, onPick: pickRecent, onRemove: saved.removeRecent, onClear: saved.clearRecents)
        }
    }

    private var attribution: some View {
        HStack {
            AttributionLabel()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder private var debugStatus: some View {
        #if DEBUG
        if !sizeCategory.isAccessibilityCategory && verticalSizeClass == .regular {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                DebugLabel(text: coreLine, id: "velacore-debug")
                DebugLabel(text: "calibration \(calibration.version)", id: "calibration-debug")
                DebugLabel(text: offline.debugLine, id: "offline-debug")
                DebugLabel(text: search.debugLine, id: "search-debug")
                DebugLabel(text: saved.debugLine, id: "saved-debug")
                DebugLabel(text: nav.debugLine, id: "nav-debug")
                DebugLabel(text: nav.voiceDebugLine, id: "nav-voice-debug")
                DebugLabel(text: deepLinkDebug, id: "intents-debug")
                DebugLabel(text: spotlight.debugLine, id: "spotlight-debug")
                if transit.hasRun {
                    DebugLabel(text: transit.debugLine, id: "transit-debug")
                }
                if !map.offlineMapStatus.isEmpty {
                    DebugLabel(text: map.offlineMapStatus, id: "offline-map-debug")
                }
                if route.isOpen {
                    DebugLabel(text: route.debugLine, id: "route-debug")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        }
        #else
        EmptyView()
        #endif
    }

    private func handlePendingDeepLink() {
        guard let request = deepLinks.pending else { return }
        deepLinks.consume(request)
        switch request.outcome {
        case .failure:
            failDeepLink("This Vela link is invalid.", route: "invalid")
        case .success(let link):
            deepLinkError = nil
            switch link {
            case .search(let query):
                dismissDeepLinkSheets()
                route.close()
                startSearch(query)
                deepLinkDebug = "route=search error=0"
            case .savedPlace(let placeID, let listID, let directions):
                guard let item = saved.place(placeId: placeID, listId: listID) else {
                    failDeepLink("This saved place no longer exists. Choose another place in Saved.", route: "place")
                    return
                }
                openSavedPlace(item, directions: directions)
                deepLinkDebug = "route=place error=0"
            case .saved:
                dismissDeepLinkSheets()
                blurSearch()
                route.close()
                place.close()
                mapPoi.close()
                search.clear()
                showsSaved = true
                deepLinkDebug = "route=saved error=0"
            case .parking:
                guard let parking = saved.openParking() else {
                    failDeepLink("No parked car is saved. Use Vela's parking button after parking.", route: "parking")
                    return
                }
                presentOpenedPlace(latitude: parking.latitude, longitude: parking.longitude, directions: false)
                deepLinkDebug = "route=parking error=0"
            case .navigate(let shortcut):
                guard let item = saved.openShortcut(home: shortcut == .home) else {
                    failDeepLink(
                        "\(shortcut.displayName) is not set. Choose a \(shortcut.displayName) place in Saved.",
                        route: shortcut.rawValue)
                    return
                }
                presentOpenedPlace(latitude: item.latitude, longitude: item.longitude, directions: true)
                deepLinkDebug = "route=\(shortcut.rawValue) error=0"
            }
        }
    }

    private func failDeepLink(_ message: String, route: String) {
        deepLinkDebug = "route=\(route) error=1"
        deepLinkError = message
    }

    private func dismissDeepLinkSheets() {
        showsSaved = false
        showsOffline = false
        showsSettings = false
    }

    private func presentOpenedPlace(latitude: Double, longitude: Double, directions: Bool) {
        dismissDeepLinkSheets()
        blurSearch()
        route.close()
        mapPoi.close()
        search.clear()
        showsRecents = false
        panelExpanded = false
        map.focus(latitude: latitude, longitude: longitude)
        map.setBottomInset(sheetInset)
        if directions { route.openFromPlace() }
    }

    private func submit() {
        startSearch()
    }

    private func startSearch(_ text: String? = nil) {
        blurSearch()
        place.close()
        mapPoi.close()
        showsRecents = false
        panelExpanded = true
        if let text {
            search.search(text, viewport: map.currentViewport())
        } else {
            search.submit(viewport: map.currentViewport())
        }
    }

    private func clearSearch() {
        blurSearch()
        route.close()
        place.close()
        mapPoi.close()
        search.clear()
        showsRecents = true
    }

    private func blurSearch() {
        searchFocused = false
        searchBlurTick += 1
    }

    /// Opens the result's sheet and centers the map on it, above the sheet.
    private func pick(_ row: SearchRow) {
        blurSearch()
        mapPoi.close()
        showsRecents = false
        panelExpanded = false
        map.setBottomInset(sheetInset)
        map.focus(on: row)
        place.open(resultIndex: row.id)
    }

    private func pickSuggestion(_ row: SuggestionRow) {
        if let query = row.query {
            startSearch(query)
            return
        }
        blurSearch()
        route.close()
        place.close()
        mapPoi.close()
        showsRecents = false
        panelExpanded = false
        AppGraph.session.openSearchSuggestion(index: Int32(row.index))
        map.setBottomInset(sheetInset)
        if let latitude = row.latitude, let longitude = row.longitude {
            map.focus(latitude: latitude, longitude: longitude)
        }
    }

    private func pickRecent(_ item: RecentItem) {
        showsRecents = false
        if item.kind == "search" {
            startSearch(item.title)
        } else {
            blurSearch()
            route.close()
            place.close()
            mapPoi.close()
            saved.open(item)
        }
    }

    private func openSavedPlace(_ item: SavedPlaceItem, directions: Bool = false) {
        saved.open(item)
        presentOpenedPlace(latitude: item.latitude, longitude: item.longitude, directions: directions)
    }

    private var showsQuickCategories: Bool {
        !searchFocused && search.query.isEmpty && !search.hasContent && !place.isOpen
            && mapPoi.card == nil && !route.isOpen
    }

    /// The place sheet's Directions: the route chooser to the open place.
    private func openDirections() {
        route.openFromPlace()
    }

    private var defaultRouteName: String {
        let destination = route.destinationName.isEmpty ? "Saved route" : route.destinationName
        if let origin = route.originName, !origin.isEmpty { return "\(origin) to \(destination)" }
        return "Route to \(destination)"
    }

    /// Room around a fitted route: the search bar above, the chooser below.
    private var routeInsets: UIEdgeInsets {
        UIEdgeInsets(top: 170, left: 40, bottom: sheetInset + 30, right: 40)
    }

    /// Back to the results list.
    private func closePlace() {
        place.close()
        panelExpanded = true
    }

    /// The part of the map the place sheet covers.
    private var sheetInset: CGFloat {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height ?? 800) * 0.5
    }

    private func locate() {
        if location.isDenied {
            showsLocationOffAlert = true
            return
        }
        let map = self.map
        location.requestWhenInUse { map.showUser() }
    }
}

private struct LocateButton: View {
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFollowing ? "location.fill" : "location")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .background(.regularMaterial, in: Circle())
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        .accessibilityLabel("Show my location")
    }
}

private struct AttributionLabel: View {
    var body: some View {
        Link(destination: MapDefaults.attributionURL) {
            Text(MapDefaults.attribution)
                .font(.caption2)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

#if DEBUG
/// Debug builds only: one status line (the Kotlin call at launch, the calibration version), read
/// by the UI tests through its accessibility identifier.
private struct DebugLabel: View {
    let text: String
    let id: String

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier(id)
            .allowsHitTesting(false)
    }
}
#endif
