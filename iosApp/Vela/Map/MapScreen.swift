import SwiftUI
import UIKit
import VelaCore

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
    @StateObject private var layers: LayersModel
    @State private var showsLayers = false
    @State private var showsLocationOffAlert = false
    @State private var showsOffline = false
    @State private var showsSaved = false
    @State private var showsSettings = false
    @State private var showsTransitOptions = false
    @State private var streetView: StreetViewRequest?
    @State private var searchFocused = false
    @State private var showsRecents = false
    @State private var panelExpanded = true
    @State private var searchBlurTick = 0
    @State private var deepLinkError: String?
    @State private var deepLinkDebug = "route=none error=0"
    @State private var incomingTask: Task<Void, Never>?
    @State private var coreLine = "VelaCore \(VelaCoreCheck.version)"

    init() {
        #if DEBUG
        // The fixture protocols must precede AppGraph's process-wide URLSession.
        NavAlertTestSupport.enableIfRequested()
        MapLayersTestSupport.enableIfRequested()
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
        _layers = StateObject(wrappedValue: LayersModel(session: AppGraph.session))
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
                onOpenShortcut: { openShortcut(home: $0, directions: false) },
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
            let layers = self.layers
            map.onViewportChange = { viewport in
                layers.viewportChanged(viewport)
                search.viewportChanged(viewport)
                route.mapCenterChanged(latitude: (viewport.south + viewport.north) / 2,
                                       longitude: (viewport.west + viewport.east) / 2)
                saved.mapCenterChanged(latitude: (viewport.south + viewport.north) / 2,
                                       longitude: (viewport.west + viewport.east) / 2)
                transit.viewportChanged(viewport)
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
                if TransitKinds.shared.isTransit(kind: kind) {
                    transit.openBoard(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name)
                } else {
                    mapPoi.tap(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude, kind: kind)
                }
            }
            map.onTransitStopTap = { stop in
                guard !nav.active && !transit.active else { return }
                blurSearch()
                route.close()
                place.close()
                mapPoi.close()
                search.clear()
                transit.openBoard(for: stop)
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
            if LaunchOptions.current.transitBoardTest {
                transit.openBoard(latitude: 37.7955, longitude: -122.3937, name: "Ferry Building")
            }
            #endif
            #if DEBUG
            if LaunchOptions.current.streetViewFixture {
                streetView = StreetViewRequest.fixtureRequest
            }
            #endif
            search.start()
            place.start()
            mapPoi.start()
            route.start()
            offline.start()
            saved.start()
            spotlight.start()
            settings.start()
            layers.start()
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
            if !open { showsTransitOptions = false }
        }
        .onChange(of: transit.stopMarkers) { _, markers in
            if route.isOpen || nav.active {
                map.showTransitStops([])
            } else {
                map.showTransitStops(markers)
            }
        }
        .onChange(of: route.mode) { _, _ in
            map.showTransitStops(route.isOpen ? [] : transit.stopMarkers)
        }
    }

    private var mapStateContent: some View {
        mapEventsContent
        .onChange(of: layers.data) { _, data in
            map.applyLayers(data)
        }
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
        .sheet(isPresented: $showsLayers) {
            LayersView(model: layers)
        }
        .sheet(isPresented: $showsTransitOptions) {
            TransitOptionsSheet(model: transit)
        }
        .fullScreenCover(item: $streetView) { request in
            StreetViewView(
                store: AppGraph.session.streetView,
                request: request,
                onClose: { streetView = nil })
        }
        .sheet(isPresented: Binding(
            get: { transit.boardOpen },
            set: { if !$0 { transit.closeBoard() } })) {
            TransitBoardSheet(model: transit)
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
                if !place.isOpen && !route.isOpen && mapPoi.card == nil {
                    SavedMapShortcuts(model: saved, onOpen: { openShortcut(home: $0, directions: true) })
                }
                if route.isOpen && route.mode == .transit {
                    Button {
                        showsTransitOptions = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .accessibilityLabel("Transit options")
                    .accessibilityIdentifier("transit-options-open")
                }
                if place.isOpen, let card = place.card,
                   TransitKinds.shared.isTransit(kind: card.category) {
                    Button {
                        place.close()
                        transit.openBoard(latitude: card.latitude, longitude: card.longitude, name: card.name)
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .accessibilityLabel("Departures")
                    .accessibilityIdentifier("transit-departures")
                }
                Button {
                    showsLayers = true
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .accessibilityLabel("Map layers")
                .accessibilityIdentifier("layers-button")
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
                if route.mode == .transit, transit.detail != nil {
                    TransitDetailSheet(
                        model: transit,
                        onClose: { route.setShowsSteps(false) },
                        onStart: { transit.startIfAvailable() })
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.62 }
                } else {
                    StepsSheet(model: route)
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
                }
            } else if route.choices.contains(where: { $0.isSavedLine }) {
                SavedRoutePickerSheet(
                    model: route, onClose: route.close, onStart: nav.startIfAvailable,
                    onStartTransit: transit.startIfAvailable)
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
            } else {
                RoutePickerSheet(model: route, savedPlaces: saved.markers, onClose: route.close,
                                 onStart: nav.startIfAvailable, onStartTransit: transit.startIfAvailable)
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
            }
        } else if let card = place.card {
            PlaceSheet(
                model: place, saved: saved, card: card, onClose: closePlace,
                onDirections: openDirections,
                onOpenStreetView: { card in
                    streetView = StreetViewRequest.place(
                        name: card.name, latitude: card.latitude, longitude: card.longitude,
                        address: card.address, panoId: card.streetViewPanoId,
                        yawDeg: card.streetViewYawDeg)
                })
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
                DebugLabel(text: nav.debugLine, id: "nav-debug")
                DebugLabel(text: nav.voiceDebugLine, id: "nav-voice-debug")
                DebugLabel(text: deepLinkDebug, id: "intents-debug")
                DebugLabel(text: spotlight.debugLine, id: "spotlight-debug")
                DebugLabel(text: layers.debugLine, id: "layers-debug")
                if transit.hasRun {
                    DebugLabel(text: transit.debugLine, id: "transit-debug")
                }
                if transit.boardOpen {
                    DebugLabel(text: transit.boardDebugLine, id: "transit-board-status")
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
        case .failure(let error):
            failDeepLink(error.userMessage, route: "invalid")
        case .success(let link):
            deepLinkError = nil
            switch link {
            case .search(let query):
                dismissDeepLinkSheets()
                route.close()
                startSearch(query)
                deepLinkDebug = "route=search error=0"
            case .incoming(let incoming):
                openIncoming(incoming)
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

    // MARK: Incoming Google Maps and geo: links

    /// One entry point for every external link, so cold starts and `onOpenURL` share the same
    /// actions as the Vela router.
    private func openIncoming(_ link: VelaIncomingLink) {
        incomingTask?.cancel()
        dismissDeepLinkSheets()
        blurSearch()
        route.close()
        place.close()
        mapPoi.close()
        search.clear()
        showsRecents = false
        panelExpanded = false
        switch link.kind {
        case .search:
            openIncomingSearch(link)
        case .place:
            incomingTask = Task { @MainActor in await openIncomingPlace(link) }
        case .directions:
            incomingTask = Task { @MainActor in await openIncomingDirections(link) }
        }
    }

    private func openIncomingSearch(_ link: VelaIncomingLink) {
        guard let query = link.target?.name, !query.isEmpty else {
            failIncoming(link)
            return
        }
        if let target = link.target, let latitude = target.latitude, let longitude = target.longitude {
            map.focus(latitude: latitude, longitude: longitude, zoom: link.zoom)
        }
        search.search(query, viewport: incomingViewport(
            latitude: link.target?.latitude, longitude: link.target?.longitude, zoom: link.zoom))
        deepLinkDebug = "route=link-search error=0"
    }

    /// A place link opens the place sheet. When the link carries a point (or a feature id whose
    /// S2 cell gives one), the sheet opens there at once with the link's own name; a name with no
    /// point at all is searched instead.
    private func openIncomingPlace(_ link: VelaIncomingLink) async {
        if link.target == nil, let cid = link.cid, let item = saved.incomingPlace(cid: cid) {
            search.clear()
            openSavedPlace(item)
            deepLinkDebug = "route=link-place error=0 saved=1"
            return
        }
        guard let target = link.target, target.hasName || target.hasCoordinates else {
            failIncoming(link)
            return
        }
        if let query = target.name, !query.isEmpty,
           let proximity = incomingProximity(target, featureID: link.featureID) {
            map.focus(latitude: proximity.0, longitude: proximity.1, zoom: link.zoom)
            place.openIncoming(
                name: query, latitude: proximity.0, longitude: proximity.1, featureID: link.featureID)
            map.setBottomInset(sheetInset)
            deepLinkDebug = "route=link-place error=0 pinned=1"
            return
        }
        if let query = target.name, !query.isEmpty {
            let rows = await incomingSearch(query, viewport: nil)
            if let hit = incomingHit(rows, near: nil) {
                pick(hit)
                deepLinkDebug = "route=link-place error=0 results=\(rows.count) picked=1"
                return
            }
            failIncoming(link)
            return
        }
        guard let latitude = target.latitude, let longitude = target.longitude else {
            failIncoming(link)
            return
        }
        map.focus(latitude: latitude, longitude: longitude, zoom: link.zoom)
        mapPoi.longPress(latitude: latitude, longitude: longitude)
        deepLinkDebug = "route=link-place error=0 picked=0 pin=1"
    }

    /// A directions link opens the chooser with the link's start, destination and travel mode.
    /// A name-only start or destination is looked up once, near the other end when known.
    private func openIncomingDirections(_ link: VelaIncomingLink) async {
        guard let target = link.target, target.hasName || target.hasCoordinates else {
            failIncoming(link)
            return
        }
        guard link.stopCount == 0 else {
            failDeepLink(VelaDeepLinkError.unsupportedStops.userMessage, route: "link-directions")
            return
        }
        var origin: (name: String, latitude: Double, longitude: Double)?
        if let start = link.origin, start.hasName || start.hasCoordinates {
            if let latitude = start.latitude, let longitude = start.longitude {
                origin = (start.name ?? VelaL10n.text("mapvm_dropped_pin"), latitude, longitude)
            } else if let name = start.name, !name.isEmpty {
                let rows = await incomingSearch(name, viewport: map.currentViewport())
                guard let row = incomingHit(rows, near: nil) else {
                    failIncoming(link)
                    return
                }
                origin = (row.name, row.latitude, row.longitude)
            }
        }
        let cell = VelaIncomingLinkParser.featureCell(link.featureID)
        let proximity: (Double, Double)?
        if let origin {
            proximity = (origin.latitude, origin.longitude)
        } else if let cell {
            proximity = (cell.latitude, cell.longitude)
        } else {
            proximity = nil
        }
        let destination: (name: String, latitude: Double, longitude: Double)
        if let latitude = target.latitude, let longitude = target.longitude {
            destination = (target.name ?? VelaL10n.text("mapvm_dropped_pin"), latitude, longitude)
        } else if let name = target.name, !name.isEmpty, let cell {
            destination = (name, cell.latitude, cell.longitude)
        } else if let name = target.name, !name.isEmpty {
            let rows = await incomingSearch(name, viewport: incomingViewport(
                latitude: proximity?.0, longitude: proximity?.1, zoom: link.zoom))
            guard let row = incomingHit(rows, near: proximity) else {
                failIncoming(link)
                return
            }
            destination = (row.name, row.latitude, row.longitude)
        } else {
            failIncoming(link)
            return
        }
        search.clear()
        map.focus(latitude: destination.latitude, longitude: destination.longitude, zoom: link.zoom)
        map.setBottomInset(sheetInset)
        route.openIncomingDirections(
            name: destination.name, latitude: destination.latitude, longitude: destination.longitude,
            originName: origin?.name, originLatitude: origin?.latitude, originLongitude: origin?.longitude,
            mode: link.mode)
        deepLinkDebug = "route=link-directions error=0 origin=\(origin == nil ? 0 : 1) mode=\(link.mode ?? "sticky")"
    }

    /// One search for a link, cleared first so a previous query cannot answer for this one.
    private func incomingSearch(_ text: String, viewport: MapViewport?) async -> [SearchRow] {
        search.clear()
        search.search(text, viewport: viewport)
        try? await Task.sleep(nanoseconds: 350_000_000)
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if Task.isCancelled { return [] }
            if !search.searching { return search.rows }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return search.rows
    }

    /// A search's answer, restricted to the nearest hit when the link named a place. Anything
    /// farther than 50 km is another town of the same name, so it is not opened.
    private func incomingHit(_ rows: [SearchRow], near: (Double, Double)?) -> SearchRow? {
        guard !rows.isEmpty else { return nil }
        guard let near else { return rows.first }
        let ranked = rows.map { row in
            (row, incomingDistance(near.0, near.1, row.latitude, row.longitude))
        }
        guard let best = ranked.min(by: { $0.1 < $1.1 }), best.1 <= 50_000 else { return nil }
        return best.0
    }

    private func incomingProximity(_ point: VelaIncomingPoint,
                                   featureID: String?) -> (Double, Double)? {
        if let latitude = point.latitude, let longitude = point.longitude {
            return (latitude, longitude)
        }
        guard let cell = VelaIncomingLinkParser.featureCell(featureID) else { return nil }
        return (cell.latitude, cell.longitude)
    }

    /// A viewport around the link's point, so a name search ranks that town first. The box is at
    /// least about 2 km across: a place's own point is exact but a z=17 link asks for a search,
    /// which needs a wider window than the camera.
    private func incomingViewport(latitude: Double?, longitude: Double?,
                                  zoom: Double?) -> MapViewport? {
        guard let latitude, let longitude else { return nil }
        let level = min(max(zoom ?? 14, 3), 18)
        let span = max(0.02, 360.0 / pow(2.0, level))
        return MapViewport(
            south: max(-90, latitude - span), west: max(-180, longitude - span),
            north: min(90, latitude + span), east: min(180, longitude + span), zoom: level)
    }

    /// Great-circle distance in meters, for the link's anchor check only.
    private func incomingDistance(_ lat1: Double, _ lng1: Double,
                                  _ lat2: Double, _ lng2: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * radius * asin(min(1, sqrt(a)))
    }

    private func failIncoming(_ link: VelaIncomingLink) {
        failDeepLink(VelaDeepLinkError.unreadableLink.userMessage, route: "link-\(link.kind.rawValue)")
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

    private func openShortcut(home: Bool, directions: Bool) {
        guard let item = saved.openShortcut(home: home) else {
            showsSaved = true
            return
        }
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
