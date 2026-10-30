import CoreLocation
import SwiftUI
import UIKit
import VelaCore

/// The map's modal destinations, one at a time.
enum MapSheet: String, Identifiable {
    case saved, offline, settings, layers, transitOptions, trips
    var id: String { rawValue }
}

struct MapScreen: View {
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @StateObject private var traceRecorder: TraceRecorder
    /// MAP-GESTE: north lock, zoom buttons, button shape and start position, persisted in the
    /// shared settings suite.
    @ObservedObject private var gestures = MapGestureSettings.shared
    /// The card of the pin a long press dropped. It shows the coordinate and asks for nothing.
    @State private var droppedPinCoordinate: CLLocationCoordinate2D?
    @State private var demoReplay: DemoReplayRequest?
    @State private var showsLocationOffAlert = false
    /// The in-drive stop search: an overlay, not a sheet, so guidance keeps its camera and chrome.
    @State private var showsNavStop = false
    /// One sheet at a time: several `.sheet(isPresented:)` on the same view made the saved
    /// sheet silently refuse to present once the layers and transit sheets existed.
    @State private var activeSheet: MapSheet?
    /// SETTINGS-REGRESSION: counts the overflow menu's Settings action, so a refused sheet can be
    /// told apart from a tap that never reached the action.
    @State private var settingsTapCount = 0
    @State private var streetView: StreetViewRequest?
    @State private var searchFocused = false
    @State private var showsRecents = false
    @State private var panelExpanded = false
    /// Mirrors RoutePickerSheet's grabber so its host frame follows the presentation: half the
    /// screen compact, 85 percent expanded (RTE-SHEET).
    @State private var routeSheetExpanded = false
    /// The place sheet's current detent, owned here so the map inset follows it (DESIGN.md 3.7).
    @State private var placeDetent: SheetDetent = .compact
    /// Measured sheet heights; the map inset is the real height, never a guessed fraction.
    @State private var placeSheetHeight: CGFloat = 0
    @State private var resultsSheetHeight: CGFloat = 0
    /// The last inset handed to MapLibre, so the debug line can prove the map matches the sheet.
    @State private var appliedBottomInset: CGFloat = 0
    @State private var searchBlurTick = 0
    @State private var deepLinkError: String?
    /// Set when a directions link carried more stops than Vela keeps; shown in the same alert.
    @State private var deepLinkNotice: String?
    @State private var deepLinkDebug = "route=none error=0"
    @State private var incomingTask: Task<Void, Never>?
    @State private var coreLine = "VelaCore \(VelaCoreCheck.version)"
    /// START-LOCATION: the launch camera decision and its evidence for the UI scenarios.
    @State private var startCamera: StartCamera?
    @State private var startSource = "default"
    @State private var startDebug = "start_camera=default start_distance_m=-1"
    /// The fix the launch camera moved to, kept to measure where the map actually landed.
    @State private var startFix: CLLocationCoordinate2D?
    /// The camera a programmatic move asked for, so a later viewport that differs is the user's.
    @State private var startExpected: CLLocationCoordinate2D?
    @State private var startIgnoreUntil = Date.distantPast
    /// A region change before the first layout settled must not overwrite the saved camera.
    @State private var persistsCamera = false
    /// A full-screen cover can make the map appear again; the launch decision runs only once.
    @State private var startPrepared = false
    /// UX-JOURNEY: the list a saved place was opened from, so closing the place returns there.
    @State private var savedListReturnId: String?
    /// The list the Saved sheet opens on, when the flow returns to a list instead of its root.
    @State private var savedSheetListId: String?
    /// The camera before guidance started, restored when the drive or the trip ends.
    @State private var guidanceCamera: (latitude: Double, longitude: Double, zoom: Double)?

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
        _traceRecorder = StateObject(wrappedValue: TraceRecorder(store: AppGraph.session.trips))
        VelaIntentTestSupport.prepareIfNeeded()
    }

    var body: some View {
        screenContent
    }

    private var mapLifecycleContent: some View {
        mapRoot
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .saved:
                SavedView(
                    model: saved,
                canSaveRoute: route.hasRoute,
                defaultRouteName: defaultRouteName,
                initialListId: savedSheetListId,
                onSaveRoute: { _ = AppGraph.session.saveActiveRoute(name: $0) },
                onOpenPlace: { openSavedPlace($0) },
                onOpenPlaceFromList: { openSavedListPlace($0) },
                onOpenShortcut: { openShortcut(home: $0, directions: false) },
                onRecentSearch: { query in
                    activeSheet = nil
                    startSearch(query)
                },
                onOpenRecentPlace: { item in
                    activeSheet = nil
                    route.close()
                    mapPoi.close()
                    search.clear()
                    saved.open(item)
                },
                onOpenRoute: { item in
                    activeSheet = nil
                    route.close()
                    mapPoi.close()
                    search.clear()
                    saved.open(item)
                },
                onClose: {
                    activeSheet = nil
                    savedSheetListId = nil
                    savedListReturnId = nil
                })
            case .offline:
                OfflineSheet(
                    model: offline,
                    onFrameArea: {
                        activeSheet = nil
                        offline.startAreaPick(viewport: map.currentViewport())
                    })
                    // The offline host is a high map companion, not a medium system sheet:
                    // 0.85 keeps the map visible, 1.0 gives the region list the full window.
                    .presentationDetents([
                        .fraction(Design.Sheet.expanded), .fraction(Design.Sheet.full)
                    ])
                    .presentationDragIndicator(.visible)
            case .settings:
                SettingsScreen(model: settings, offline: offline)
            case .layers:
                LayersView(model: layers)
            case .transitOptions:
                TransitOptionsSheet(model: transit)
            case .trips:
                TripsView(store: AppGraph.session.trips)
            }
        }
        .environment(\.locale, settings.locale)
        .environment(\.layoutDirection, settings.layoutDirection)
        .onAppear {
            prepareStartCamera()
            let search = self.search
            let route = self.route
            let saved = self.saved
            let layers = self.layers
            map.onViewportChange = { viewport in
                startViewportChanged(viewport)
                layers.viewportChanged(viewport)
                search.viewportChanged(viewport)
                route.mapCenterChanged(latitude: (viewport.south + viewport.north) / 2,
                                       longitude: (viewport.west + viewport.east) / 2)
                saved.mapCenterChanged(latitude: (viewport.south + viewport.north) / 2,
                                       longitude: (viewport.west + viewport.east) / 2)
                transit.viewportChanged(viewport)
                offline.areaViewportChanged(viewport)
            }
            map.onUserLocation = { c in
                search.locationChanged(latitude: c.latitude, longitude: c.longitude)
                route.locationChanged(latitude: c.latitude, longitude: c.longitude)
                offline.onLocation(latitude: c.latitude, longitude: c.longitude)
                saved.locationChanged(latitude: c.latitude, longitude: c.longitude)
            }
            map.onRouteTap = { index in
                if !nav.active && !nav.freeDriving && !transit.active { route.select(index) }
            }
            map.onResultTap = { index in
                guard !nav.active && !nav.freeDriving && !transit.active, index < search.rows.count else { return }
                pick(search.rows[index])
            }
            map.onPoiTap = { name, coordinate, kind in
                guard !nav.active && !nav.freeDriving && !transit.active else { return }
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
                guard !nav.active && !nav.freeDriving && !transit.active else { return }
                blurSearch()
                route.close()
                place.close()
                mapPoi.close()
                search.clear()
                transit.openBoard(for: stop)
            }
            map.onMapLongPress = { coordinate in
                guard !nav.active && !nav.freeDriving && !transit.active else {
                    map.clearDroppedPin()
                    return
                }
                blurSearch()
                route.close()
                place.close()
                mapPoi.close()
                search.clear()
                showsRecents = false
                droppedPinCoordinate = coordinate
            }
            map.onSavedTap = { index in
                guard !nav.active && !nav.freeDriving, index < saved.markers.count else { return }
                let marker = saved.markers[index]
                if marker.parking {
                    activeSheet = .saved
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
            TraceFolderStore.shared.install(store: AppGraph.session.trips)
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
            if let requested = LaunchOptions.current.demoReplay {
                let id = requested == "latest"
                    ? AppGraph.session.trips.list().first?.id : requested
                if let id { demoReplay = DemoReplayRequest(tripID: id) }
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
                // The follow camera owns the map; the launch position must not fight it.
                startCamera?.cancel()
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
            if open {
                placeDetent = .compact
                placeSheetHeight = 0
            }
            if !nav.active { applyBottomInset() }
        }
        // The sheet's measured height and the active surface decide the map inset together. A
        // detent change, a result list arriving or a place closing all land here.
        .onChange(of: sheetInset) { _, _ in
            if !nav.active { applyBottomInset() }
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
                applyBottomInset()
            }
            if !open {
                activeSheet = nil
                routeSheetExpanded = false
            }
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
            map.applyLayers(nav.freeDriving && nav.simpleMap ? simpleDrivingLayers(data) : data)
        }
        .onChange(of: nav.simpleMap) { _, _ in
            map.applyLayers(nav.freeDriving && nav.simpleMap
                ? simpleDrivingLayers(layers.data) : layers.data)
        }
        .onChange(of: nav.freeDriving) { _, driving in
            if driving {
                blurSearch()
                route.close()
                place.close()
                mapPoi.close()
                search.clear()
                activeSheet = nil
            }
            map.applyLayers(driving && nav.simpleMap
                ? simpleDrivingLayers(layers.data) : layers.data)
        }
        .onChange(of: offline.revision) { _, _ in
            map.refreshOfflineStyle()
        }
        .onChange(of: nav.active) { _, active in
            if !active { showsNavStop = false }
            // UX-JOURNEY: guidance owns the map, so the chooser must not stay behind the end
            // banner. Closing it while the drive is active keeps the live line untouched.
            if active { route.close() }
            if !active && !nav.freeDriving { restoreGuidanceCamera() }
            // Guided navigation records its own trip; two writers would fight over one file.
            if active && traceRecorder.active { traceRecorder.stop() }
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
                restoreGuidanceCamera()
                applyBottomInset()
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
            // The pins stay above the results sheet at whatever detent it rests on, not a fixed
            // 420 pt band.
            let bottom = rows.isEmpty ? 0 : sheetInset + Design.Spacing.xxl
            map.showResults(rows, insets: UIEdgeInsets(
                top: 140, left: Design.Spacing.huge, bottom: bottom, right: Design.Spacing.huge))
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
        // START-LOCATION: an answer to the permission prompt still lands on the position, without
        // blocking the launch behind the prompt.
        .onChange(of: location.status) { _, _ in
            startPermissionAnswered()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { rememberStartCamera() }
        }
        .onDisappear {
            rememberStartCamera()
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
        .alert(VelaL10n.text("loc_off_title"), isPresented: $showsLocationOffAlert) {
            Button(VelaL10n.text("loc_off_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
        } message: {
            Text(VelaL10n.text("map_allow_location_for_vela_in_settings"))
        }
        .alert(deepLinkError != nil ? VelaL10n.text("map_cannot_open_link") : VelaL10n.text("map_some_stops_were_skipped"), isPresented: Binding(
            get: { deepLinkError != nil || deepLinkNotice != nil },
            set: { presented in
                if !presented {
                    deepLinkError = nil
                    deepLinkNotice = nil
                }
            })) {
            if deepLinkError != nil {
                Button(VelaL10n.text("map_open_saved")) {
                    deepLinkError = nil
                    activeSheet = .saved
                }
                .accessibilityIdentifier("intents-open-saved")
                Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
            } else {
                Button(VelaL10n.text("map_ok"), role: .cancel) {}
            }
        } message: {
            if deepLinkError != nil {
                Text(deepLinkError ?? "")
                    .accessibilityIdentifier("intents-error")
            } else {
                Text(deepLinkNotice ?? "")
                    .accessibilityIdentifier("link-stops-notice")
            }
        }
    }

    private var mapRoot: some View {
        ZStack {
            MapView(controller: map)
                .ignoresSafeArea()
            #if DEBUG
            // A transit card or a sheet replaces the browser chrome, so the debug block inside it
            // disappears exactly when a UI scenario needs to read the map's state. This overlay
            // belongs to the map, takes no layout height and never receives a touch.
            alwaysDebugOverlay
            #endif
            if nav.active {
                NavChrome(model: nav, onAddStop: { showsNavStop = true })
            } else if nav.freeDriving {
                FreeDriveChrome(model: nav, onLocate: locate)
            } else if transit.active {
                TransitGuidanceCard(model: transit)
            } else if offline.areaPicking {
                // OFF-AREA: the frame owns the map while the user chooses what to save.
                OfflineAreaOverlay(model: offline)
            } else {
                browserChrome
                if traceRecorder.active {
                    VStack {
                        TraceRecordingCard(
                            model: traceRecorder,
                            onStop: {
                                traceRecorder.stop()
                                activeSheet = .trips
                            },
                            onDiscard: { traceRecorder.discard() })
                            .padding(.top, 68)
                        Spacer()
                    }
                }
                if offline.areaReportVisible && offline.areaId != nil {
                    VStack {
                        OfflineAreaProgressCard(model: offline)
                            .padding(.horizontal, 12)
                            .padding(.top, 68)
                        Spacer()
                    }
                }
            }
            if showsNavStop && nav.active {
                NavStopOverlay(model: nav, search: search, onClose: { showsNavStop = false })
            }
        }
        .fullScreenCover(item: $demoReplay) { request in
            TripReplayView(
                tripID: request.tripID, store: AppGraph.session.trips,
                onClose: { demoReplay = nil })
        }
        .alert(VelaL10n.text("map_cannot_record"), isPresented: Binding(
            get: { traceRecorder.errorMessage != nil },
            set: { if !$0 { traceRecorder.clearError() } })) {
            Button(VelaL10n.text("map_ok"), role: .cancel) {}
        } message: {
            Text(traceRecorder.errorMessage ?? "")
        }
        .alert(VelaL10n.text("map_saved_drive"), isPresented: Binding(
            get: { traceRecorder.notice != nil },
            set: { if !$0 { traceRecorder.clearNotice() } })) {
            Button(VelaL10n.text("map_ok"), role: .cancel) {}
        } message: {
            Text(traceRecorder.notice ?? "")
        }
    }

    private var browserChrome: some View {
        // The chrome used to be one VStack: search, a tall action column, the bottom sheet and the
        // footer. When their intrinsic heights exceeded the window, SwiftUI centred the stack and
        // it overflowed at both ends, so the search row slid under the status bar and the bottom
        // sheet pushed `saved-open` and `steps-close` off screen. The three anchors below keep
        // the top controls at the safe area top and let only the bottom sheet own the bottom.
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 8) {
                    searchChrome
                    // The debug block keeps its place under the search bar without taking vertical
                    // space, and never receives touches.
                    debugStatus
                        .frame(height: 0, alignment: .top)
                        .allowsHitTesting(false)
                    // Clear the voice-search microphone drawn at the browser chrome's top-right
                    // corner: the compass is the first control of this column and used to sit
                    // underneath it once the column was anchored to the safe area top.
                    mapActionButtons
                        .padding(.top, 56)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(spacing: Design.Spacing.s) {
                    Spacer(minLength: 0)
                    // The scale and attribution sit on the map, above the sheet, never under it:
                    // a content sheet owns the bottom edge so it reads as an iOS sheet.
                    mapFooter
                    bottomPanel
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            // A centred free-height stack overflowed a compact-landscape window and pushed the
            // search bar and its menu above the frame; anchor it to the top and clip.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        // The keyboard must not compress the whole chrome: doing so pushed the search bar and the
        // Saved button above the status bar, where taps missed them (suggestions, saved sheet).
        // The search field is at the top, so the map chrome never needs to move for the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // RTE-SHEET: the picker is an overlay so the expanded sheet can grow upward over the
        // map controls from the same bottom edge as the compact one; keeping 85 percent inside
        // the VStack pushed the pinned action rows and the attribution under the window.
        .overlay(alignment: .bottom) {
            if showsRoutePicker {
                RoutePickerSheet(
                    model: route, expanded: $routeSheetExpanded,
                    savedPlaces: saved.markers, onClose: route.close,
                    onStart: startDriveGuidance, onStartTransit: startTransitGuidance,
                    onFreeDrive: { beginFreeDrive() })
                    .containerRelativeFrame(.vertical) { height, _ in
                        height * (routeSheetExpanded
                            ? Design.Sheet.expanded : Design.Sheet.half)
                    }
                    // The VStack gap and the attribution row the compact sheet sat above.
                    .padding(.bottom, Design.Spacing.xxl)
            }
        }
        // VO-2: the voice-search microphone and its listening card (iOS/Voice/VoiceSearchView).
        .voiceSearchOverlay(search: search, route: route, saved: saved)
    }

    @ViewBuilder private var searchChrome: some View {
        HStack(spacing: Design.Chrome.searchGap) {
            SearchBar(
                text: $search.query,
                searching: search.searching,
                onSubmit: { text in submit(text) },
                onClear: clearSearch,
                onOffline: { activeSheet = .offline },
                onFocusChange: {
                    searchFocused = $0
                    if $0 { showsRecents = true }
                },
                blurTick: searchBlurTick,
                onSettings: {
                    settingsTapCount += 1
                    activeSheet = .settings
                })
            Button {
                savedSheetListId = nil
                activeSheet = .saved
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: Design.Size.icon, weight: .semibold))
                    .frame(width: Design.Chrome.actionSize, height: Design.Chrome.actionSize)
            }
            .background(.regularMaterial, in: Circle())
            .shadow(color: Design.Elevation.level2.color, radius: Design.Elevation.level2.radius,
                    y: Design.Elevation.level2.y)
            .accessibilityLabel(VelaL10n.text("place_saved"))
            .accessibilityIdentifier("saved-open")
        }
        .padding(.horizontal, Design.Chrome.sideInset)
        .padding(.top, Design.Chrome.topInset)
        if search.hasSuggestions && searchFocused {
            SuggestionsPanel(rows: search.suggestions, onPick: pickSuggestion)
        } else if showsQuickCategories {
            QuickCategoriesView(onPick: { startSearch($0.query) })
        }
    }

    private var mapActionButtons: some View {
        HStack {
            Spacer()
            VStack(spacing: Design.Chrome.actionSpacing) {
                MapCompassButton(bearing: map.bearing, shape: gestures.buttonShape,
                                 action: map.returnToNorth)
                if gestures.preferButtons {
                    MapZoomButtons(shape: gestures.buttonShape,
                                   onZoomIn: map.zoomIn, onZoomOut: map.zoomOut)
                }
                if !place.isOpen && !route.isOpen && mapPoi.card == nil {
                    SavedMapShortcuts(model: saved, onOpen: { openShortcut(home: $0, directions: true) })
                }
                // One primary control (locate) and one grouped stack for the rest, so the map
                // keeps a hierarchy instead of a column of eight equal buttons (delta 3).
                secondaryMapActions
                LocateButton(isFollowing: map.isFollowingUser, shape: gestures.buttonShape,
                             action: locate)
            }
        }
        .padding(.horizontal, Design.Chrome.sideInset)
    }

    /// The secondary map controls, drawn as one grouped surface with 48 pt rows. The identifiers
    /// stay on each row, so every existing scenario keeps its tap target.
    private var secondaryMapActions: some View {
        VStack(spacing: 0) {
            if route.isOpen && route.mode == .transit {
                groupedAction(symbol: "slider.horizontal.3",
                              label: VelaL10n.text("transit_transit_options"),
                              id: "transit-options-open") { activeSheet = .transitOptions }
            }
            if place.isOpen, let card = place.card,
               TransitKinds.shared.isTransit(kind: card.category) {
                groupedAction(symbol: "list.bullet.rectangle",
                              label: VelaL10n.text("place_departures"),
                              id: "transit-departures") {
                    place.close()
                    transit.openBoard(latitude: card.latitude, longitude: card.longitude, name: card.name)
                }
            }
            groupedAction(symbol: "square.3.layers.3d",
                          label: VelaL10n.text("map_map_layers"),
                          id: "layers-button") { activeSheet = .layers }
            // M-2: the relief screen opens from its own button and owns its presentation.
            TerrainButton()
            groupedAction(symbol: "steeringwheel",
                          label: VelaL10n.text("map_drive_without_a_destination"),
                          id: "free-drive-open") { beginFreeDrive() }
            if !traceRecorder.active {
                groupedAction(symbol: "record.circle",
                              label: VelaL10n.text("map_record_a_drive_trace"),
                              id: "trace-record-open") { traceRecorder.start() }
            }
            groupedAction(symbol: "car.2",
                          label: VelaL10n.text("settings_recorded_trips"),
                          id: "trips-open") { activeSheet = .trips }
            groupedAction(symbol: saved.parking == nil ? "car" : "car.fill",
                          label: saved.parking == nil
                            ? VelaL10n.text("map_parking_save")
                            : VelaL10n.text("map_show_parked_car"),
                          id: "parking-button") {
                if saved.parking == nil {
                    _ = saved.saveParkingHere()
                } else {
                    activeSheet = .saved
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Design.Radius.l,
                                                          style: .continuous))
        .shadow(color: Design.Elevation.level2.color, radius: Design.Elevation.level2.radius,
                y: Design.Elevation.level2.y)
    }

    private func groupedAction(symbol: String, label: String, id: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Design.Size.icon, weight: .semibold))
                .frame(width: Design.Chrome.actionSize, height: Design.Chrome.actionSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// The route chooser owns the bottom slot unless the steps sheet or a saved-line picker does.
    private var showsRoutePicker: Bool {
        route.isOpen && !route.showsSteps
            && !route.choices.contains(where: { $0.isSavedLine })
    }

    @ViewBuilder private var bottomPanel: some View {
        if route.isOpen {
            if route.showsSteps {
                if route.mode == .transit, transit.detail != nil {
                    TransitDetailSheet(
                        model: transit,
                        onClose: { route.setShowsSteps(false) },
                        onStart: { transit.startIfAvailable() })
                        .containerRelativeFrame(.vertical) { height, _ in
                            height * Design.Sheet.tall
                        }
                } else {
                    StepsSheet(model: route)
                        .containerRelativeFrame(.vertical) { height, _ in
                            height * Design.Sheet.tall
                        }
                }
            } else if route.choices.contains(where: { $0.isSavedLine }) {
                SavedRoutePickerSheet(
                    model: route, onClose: route.close, onStart: startDriveGuidance,
                    onStartTransit: startTransitGuidance)
                    .containerRelativeFrame(.vertical) { height, _ in height * Design.Sheet.half }
            } else {
                // The picker is drawn by browserChrome's overlay so its expanded height can
                // grow upward over the map controls; this slot keeps the compact height
                // reserved, so those controls and the attribution do not move (RTE-SHEET).
                Color.clear
                    .containerRelativeFrame(.vertical) { height, _ in height * Design.Sheet.half }
            }
        } else if let card = place.card {
            SheetSurface(detent: $placeDetent,
                         detents: [.compact, .expanded, .full],
                         showsGrabber: false,
                         onHeightChange: { height in
                             placeSheetHeight = height
                             if !nav.active { applyBottomInset() }
                         }) {
                PlaceSheet(
                    model: place, saved: saved, card: card, onClose: closePlace,
                    onDirections: openDirections,
                    onOpenStreetView: { card in
                        streetView = StreetViewRequest.place(
                            name: card.name, latitude: card.latitude, longitude: card.longitude,
                            address: card.address, panoId: card.streetViewPanoId,
                            yawDeg: card.streetViewYawDeg)
                    })
            }
            .containerRelativeFrame(.vertical) { height, _ in height * placeDetent.fraction }
        } else if let card = mapPoi.card {
            MapPoiSheet(
                card: card, resolving: mapPoi.resolving, googleUnavailable: mapPoi.googleUnavailable,
                onDirections: mapPoi.directions, onClose: mapPoi.close)
        } else if let coordinate = droppedPinCoordinate {
            DroppedPinCard(
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                onDirections: { openDroppedPinDirections(coordinate) },
                onLookUp: { lookUpDroppedPin(coordinate) },
                onClose: closeDroppedPin)
        } else if search.hasContent {
            ResultsPanel(
                rows: search.rows,
                message: search.message,
                searching: search.searching,
                detent: resultsDetent,
                onHeightChange: { height in
                    resultsSheetHeight = height
                    if !nav.active { applyBottomInset() }
                },
                onPick: pick)
                .containerRelativeFrame(.vertical) { height, _ in
                    height * resultsDetent.wrappedValue.fraction
                }
        } else if search.query.isEmpty && (searchFocused || showsRecents) && !saved.recents.isEmpty {
            RecentsPanel(rows: saved.recents, onPick: pickRecent, onRemove: saved.removeRecent, onClear: saved.clearRecents)
        }
    }

    private var mapFooter: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MapScaleBarView(
                metersPerPoint: map.metersPerPoint,
                imperial: settings.imperial)
            attribution
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

    #if DEBUG
    /// Debug-only evidence that must survive a transit card, a place sheet or a route sheet.
    /// It sits over the map, not in the browser chrome, and its zero height keeps it out of the
    /// layout; `DebugLabel` already refuses touches.
    private var alwaysDebugOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            InvisibleDebugLabel(text: map.tapChainLine, id: "tap-chain-debug")
            InvisibleDebugLabel(text: layers.debugLine, id: "layers-debug")
            InvisibleDebugLabel(text: deepLinkDebug, id: "intents-debug")
            if transit.hasRun {
                InvisibleDebugLabel(text: transit.debugLine, id: "transit-debug")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 0, alignment: .top)
        .allowsHitTesting(false)
    }
    #endif

    @ViewBuilder private var debugStatus: some View {
        #if DEBUG
        // START-LOCATION's evidence stays visible behind a place or route sheet, so the UI
        // scenarios can read where the launch camera landed.
        VStack(alignment: .leading, spacing: 4) {
            DebugLabel(text: startDebug, id: "start-debug")
            DebugLabel(text: gestureDebug, id: "gesture-debug")
            DebugLabel(text: sheetDebug, id: "sheet-debug")
            // The tap chain, layers and intent lines live in the invisible overlay above, so they
            // stay readable while a sheet is open; only the sheet layout line stays in the chrome.
            DebugLabel(text: sheetLayoutDebug, id: "sheet-layout-debug")
            DebugLabel(text: deepLinkDebug, id: "intents-debug")
        }
        .padding(.horizontal, 12)
        // The debug block is tall. With a bottom sheet open it compressed the chrome and pushed the
        // search bar and the Saved button under the status bar, where taps missed them. The map
        // owned labels above stay outside this condition and outside the chrome.
        if !place.isOpen && !route.isOpen && !sizeCategory.isAccessibilityCategory
            && verticalSizeClass == .regular {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                DebugLabel(text: coreLine, id: "velacore-debug")
                DebugLabel(text: "calibration \(calibration.version)", id: "calibration-debug")
                DebugLabel(text: offline.debugLine, id: "offline-debug")
                DebugLabel(text: search.debugLine, id: "search-debug")
                DebugLabel(text: nav.debugLine, id: "nav-debug")
                DebugLabel(text: nav.voiceDebugLine, id: "nav-voice-debug")
                DebugLabel(text: spotlight.debugLine, id: "spotlight-debug")
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
        // START-LOCATION: a link or saved-place target is explicit and outranks the position.
        startCamera?.cancel()
        startExpected = nil
        if startSource != "explicit" {
            startSource = "explicit"
            startDebug = "start_camera=explicit start_distance_m=-1"
        }
        switch request.outcome {
        case .failure(let error):
            failDeepLink(error.userMessage, route: "invalid")
        case .success(let link):
            deepLinkError = nil
            deepLinkNotice = nil
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
                activeSheet = .saved
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
        activeSheet = nil
        activeSheet = nil
        activeSheet = nil
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
        applyBottomInset()
        if directions { route.openFromPlace() }
    }

    private func submit(_ text: String) {
        // Typed commands take the same parser as dictation and run an action, never a keyword
        // search. The parser reads the committed field text, and it runs before the search path,
        // so no command can cost a Google or Photon request.
        if search.handleTypedCommand(text: text, viewport: map.currentViewport()) {
            blurSearch()
            place.close()
            mapPoi.close()
            showsRecents = false
            panelExpanded = false
        } else {
            startSearch(text)
        }
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
            applyBottomInset()
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

    /// A directions link opens the chooser with the link's start, destination, travel mode and
    /// intermediate stops. A name-only start, destination or stop is looked up once, near the other
    /// places of the trip; a stop that cannot be found is an error, never a shorter trip.
    private func openIncomingDirections(_ link: VelaIncomingLink) async {
        guard let target = link.target, target.hasName || target.hasCoordinates else {
            failIncoming(link)
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
        // Stops follow the link's order. Each name is searched near the place before it, so two
        // towns of the same name do not swap places.
        var stops: [VelaIncomingPoint] = []
        var anchor: (Double, Double) = origin.map { ($0.latitude, $0.longitude) }
            ?? (destination.latitude, destination.longitude)
        for stop in link.stops {
            if let latitude = stop.latitude, let longitude = stop.longitude {
                stops.append(VelaIncomingPoint(
                    name: incomingStopName(stop), latitude: latitude, longitude: longitude))
                anchor = (latitude, longitude)
                continue
            }
            guard let name = stop.name, !name.isEmpty else {
                failDeepLink(VelaDeepLinkError.malformedStop.userMessage, route: "link-directions")
                return
            }
            let rows = await incomingSearch(name, viewport: incomingViewport(
                latitude: anchor.0, longitude: anchor.1, zoom: link.zoom))
            guard let row = incomingHit(rows, near: anchor) else {
                failDeepLink(VelaDeepLinkError.unresolvableStop.userMessage, route: "link-directions")
                return
            }
            stops.append(VelaIncomingPoint(
                name: row.name, latitude: row.latitude, longitude: row.longitude))
            anchor = (row.latitude, row.longitude)
        }
        search.clear()
        map.focus(latitude: destination.latitude, longitude: destination.longitude, zoom: link.zoom)
        applyBottomInset()
        route.openIncomingDirections(
            name: destination.name, latitude: destination.latitude, longitude: destination.longitude,
            originName: origin?.name, originLatitude: origin?.latitude, originLongitude: origin?.longitude,
            mode: link.mode, stops: stops)
        deepLinkDebug = "route=link-directions error=0 origin=\(origin == nil ? 0 : 1)"
            + " stops=\(stops.count) mode=\(link.mode ?? "sticky")"
        if link.droppedStops > 0 {
            deepLinkNotice = "This link has \(link.stopCount) stops. Vela kept the first \(stops.count)."
        }
    }

    /// What a stop shows as before or after lookup: the link's own name, else its coordinate.
    private func incomingStopName(_ stop: VelaIncomingPoint) -> String {
        if let name = stop.name, !name.isEmpty { return name }
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return "" }
        return String(
            format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"),
            latitude, longitude)
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
        savedListReturnId = nil
        savedSheetListId = nil
        place.close()
        mapPoi.close()
        showsRecents = false
        panelExpanded = false
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
        savedListReturnId = nil
        savedSheetListId = nil
        mapPoi.close()
        showsRecents = false
        panelExpanded = false
        applyBottomInset()
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
        applyBottomInset()
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
        savedListReturnId = nil
        saved.open(item)
        presentOpenedPlace(latitude: item.latitude, longitude: item.longitude, directions: directions)
    }

    /// UX-JOURNEY: a place opened from a Saved list keeps that list as its return point. Closing
    /// the place reopens Saved on the same list instead of dropping the user on the bare map.
    private func openSavedListPlace(_ item: SavedPlaceItem) {
        savedListReturnId = item.listId
        savedSheetListId = nil
        saved.open(item)
        presentOpenedPlace(latitude: item.latitude, longitude: item.longitude, directions: false)
    }

    private func openShortcut(home: Bool, directions: Bool) {
        savedListReturnId = nil
        savedSheetListId = nil
        guard let item = saved.openShortcut(home: home) else {
            activeSheet = .saved
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

    /// UX-JOURNEY: remember the camera before guidance, so End puts the user back where the
    /// journey started instead of at the last simulated fix.
    private func startDriveGuidance() {
        rememberGuidanceCamera()
        nav.startIfAvailable()
    }

    private func startTransitGuidance() {
        rememberGuidanceCamera()
        transit.startIfAvailable()
    }

    private func rememberGuidanceCamera() {
        guard let viewport = map.currentViewport() else { return }
        guidanceCamera = (
            latitude: (viewport.south + viewport.north) / 2,
            longitude: (viewport.west + viewport.east) / 2,
            zoom: viewport.zoom)
    }

    private func restoreGuidanceCamera() {
        guard let camera = guidanceCamera else { return }
        guidanceCamera = nil
        let map = self.map
        // End runs after the last live fix and the drive chrome has already released the map.
        // Wait for that frame, then close the loop: the visible viewport includes the safe area
        // and any inset the drive leaves behind, so one setCenter can land a few dozen points
        // off. Re-measure and correct until the camera reads the captured center.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            map.focus(latitude: camera.latitude, longitude: camera.longitude, zoom: camera.zoom)
            try? await Task.sleep(nanoseconds: 500_000_000)
            for _ in 0..<8 {
                guard let now = map.currentViewport() else { break }
                let latitude = (now.south + now.north) / 2
                let longitude = (now.west + now.east) / 2
                let dLat = camera.latitude - latitude
                let dLon = camera.longitude - longitude
                let dZoom = camera.zoom - now.zoom
                if abs(dLat) < 0.000004, abs(dLon) < 0.000004, abs(dZoom) < 0.05 { break }
                NSLog("UXJ_RESTORE target=%.5f,%.5f now=%.5f,%.5f d=%.5f,%.5f",
                      camera.latitude, camera.longitude, latitude, longitude, dLat, dLon)
                map.focus(
                    latitude: camera.latitude + dLat,
                    longitude: camera.longitude + dLon,
                    zoom: camera.zoom)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private var defaultRouteName: String {
        let destination = route.destinationName.isEmpty
            ? VelaL10n.text("saved_current_route") : route.destinationName
        if let origin = route.originName, !origin.isEmpty {
            return VelaL10n.text("route_save_default_from", origin, destination)
        }
        return VelaL10n.text("route_save_default", destination)
    }

    /// Room around a fitted route: the search bar above, the chooser below.
    private var routeInsets: UIEdgeInsets {
        UIEdgeInsets(top: 170, left: 40, bottom: sheetInset + 30, right: 40)
    }

    /// Back to the results list, or back to the Saved list the place came from.
    private func closePlace() {
        place.close()
        panelExpanded = false
        guard let listId = savedListReturnId else { return }
        savedListReturnId = nil
        savedSheetListId = listId
        activeSheet = .saved
    }

    /// The results sheet's detent; `panelExpanded` stays the source of truth so the existing
    /// search paths keep working, while the sheet itself receives a real detent.
    private var resultsDetent: Binding<SheetDetent> {
        Binding(
            get: { panelExpanded ? .expanded : .compact },
            set: { panelExpanded = $0 != .compact })
    }

    /// The window height the detents are fractions of. `containerRelativeFrame` uses the same
    /// window, so the fallback before a sheet is measured matches the surface.
    private var windowHeight: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?
            .screen.bounds.height ?? 800
    }

    /// The detent of the content surface currently over the map, or nil when none is open.
    private var activeDetent: SheetDetent? {
        if route.isOpen {
            if route.showsSteps { return .tall }
            if route.choices.contains(where: { $0.isSavedLine }) { return .half }
            return routeSheetExpanded ? .expanded : .half
        }
        if place.isOpen { return placeDetent }
        if search.hasContent { return panelExpanded ? .expanded : .compact }
        return nil
    }

    /// The part of the map the content sheet covers. A measured height wins once the surface has
    /// laid out; before that the detent fraction is the same number the frame will use.
    private var sheetInset: CGFloat {
        if route.isOpen {
            return windowHeight * (activeDetent ?? .half).fraction
        }
        if place.isOpen {
            return placeSheetHeight > 1
                ? placeSheetHeight : windowHeight * placeDetent.fraction
        }
        if search.hasContent {
            return resultsSheetHeight > 1
                ? resultsSheetHeight
                : windowHeight * (panelExpanded ? SheetDetent.expanded : .compact).fraction
        }
        return 0
    }

    /// Hands the current sheet height to MapLibre. The recenter and follow camera both read this
    /// inset, so the car never lands under the sheet at any detent.
    private func applyBottomInset() {
        let inset = max(0, sheetInset)
        guard abs(inset - appliedBottomInset) > 0.5 else { return }
        appliedBottomInset = inset
        withAnimation(Design.Motion.animation(Design.Motion.sheetSpring, reduceMotion: reduceMotion)) {
            map.setBottomInset(inset)
        }
    }

    /// The wave 2 evidence line: the active detent, the measured sheet height, the applied map
    /// inset and whether they agree.
    private var sheetLayoutDebug: String {
        let detent = activeDetent?.debugValue ?? "none"
        let matches = abs(sheetInset - appliedBottomInset) < 1 ? 1 : 0
        return "detent=\(detent) sheet_height=\(Int(sheetInset.rounded()))"
            + " inset=\(Int(appliedBottomInset.rounded())) map_inset_matches_sheet=\(matches)"
    }

    // MARK: Start camera (START-LOCATION)

    /// Applies the one launch-camera decision. The map is already on `LaunchOptions.current.camera`
    /// (explicit, last or default), so nothing here blocks the first frame: only the late position
    /// move is left, and it is dropped as soon as the user pans or an explicit target arrives.
    private func prepareStartCamera() {
        guard !startPrepared else { return }
        startPrepared = true
        let model = StartCamera(explicit: LaunchOptions.current.explicitCamera,
                                store: StartCameraStore())
        startCamera = model
        startSource = model.decision.source.rawValue
        startExpected = model.decision.camera.center
        startIgnoreUntil = Date().addingTimeInterval(0.6)
        startDebug = "start_camera=\(startSource) start_distance_m=-1"
        persistsCamera = true

        let hasLaunchTarget = model.decision.source == .explicit
            || deepLinks.pending != nil
            || LaunchOptions.current.demoReplay != nil
        if hasLaunchTarget {
            model.cancel()
            startExpected = nil
            if model.decision.source != .explicit {
                startSource = "explicit"
                startDebug = "start_camera=explicit start_distance_m=-1"
            }
        } else {
            model.begin(granted: location.isGranted)
            // Core Location's recent cached fix may be here before the first live update.
            if location.isGranted, let fix = AppGraph.location.lastKnownFix() {
                acceptStartFix(fix, from: model)
            }
        }

        let camera = model
        AppGraph.location.onStartFix = { fix in
            acceptStartFix(fix, from: camera)
        }
    }

    /// The permission answer arrived. An allow opens a fresh short deadline; a denial leaves the
    /// last or default camera in place, and the locate button keeps its calm "location is off"
    /// message for the moment the user asks again.
    private func startPermissionAnswered() {
        guard let model = startCamera else { return }
        if location.isGranted {
            guard model.permissionAnswered(granted: true) else { return }
            if let fix = AppGraph.location.lastKnownFix() {
                acceptStartFix(fix, from: model)
            }
        } else if location.isDenied {
            model.permissionAnswered(granted: false)
        }
    }

    /// One animated move, only for the first fix inside the deadline. `StartCamera` refuses every
    /// later fix, and a pan closes the gate for good.
    private func acceptStartFix(_ fix: CLLocation, from camera: StartCamera?) {
        guard let model = camera ?? startCamera,
              CLLocationCoordinate2DIsValid(fix.coordinate),
              let move = model.fix(latitude: fix.coordinate.latitude,
                                   longitude: fix.coordinate.longitude) else { return }
        startSource = "position"
        startFix = fix.coordinate
        startExpected = move.camera.center
        startIgnoreUntil = Date().addingTimeInterval(0.8)
        map.focus(latitude: move.camera.latitude, longitude: move.camera.longitude,
                  zoom: move.camera.zoom)
    }

    /// Tracks the real viewport: it is the evidence for the scenarios, the pan detector that keeps
    /// a late fix from stealing the camera, and the source of the persisted last camera.
    private func startViewportChanged(_ viewport: MapViewport) {
        let latitude = (viewport.south + viewport.north) / 2
        let longitude = (viewport.west + viewport.east) / 2
        let center = CLLocation(latitude: latitude, longitude: longitude)
        if let expected = startExpected, Date() >= startIgnoreUntil {
            let target = CLLocation(latitude: expected.latitude, longitude: expected.longitude)
            if center.distance(from: target) > StartCamera.panToleranceM {
                startCamera?.userPanned()
                startExpected = nil
            }
        }
        let place = String(format: "%.5f,%.5f,%.1f", latitude, longitude, viewport.zoom)
        if let fix = startFix {
            let distance = center.distance(
                from: CLLocation(latitude: fix.latitude, longitude: fix.longitude))
            let meters = Int(distance.rounded())
            startDebug = "start_camera=position start_distance_m=\(meters) start_center=\(place)"
        } else {
            startDebug = "start_camera=\(startSource) start_distance_m=-1 start_center=\(place)"
        }
        if persistsCamera {
            startCamera?.remember(latitude: latitude, longitude: longitude, zoom: viewport.zoom)
        }
    }

    /// Saves where the map is now, on a background transition and on close.
    private func rememberStartCamera() {
        guard persistsCamera, let viewport = map.currentViewport() else { return }
        startCamera?.remember(latitude: (viewport.south + viewport.north) / 2,
                              longitude: (viewport.west + viewport.east) / 2,
                              zoom: viewport.zoom)
    }

    /// SETTINGS-REGRESSION: which sheet the map believes is active, whether the transit board is
    /// holding the presentation, and how often the overflow's Settings action ran.
    private var sheetDebug: String {
        "sheet=\(activeSheet?.rawValue ?? "none") board=\(transit.boardOpen ? 1 : 0) settings_taps=\(settingsTapCount)"
    }

    /// The left-to-right evidence the MAP-GESTE scenarios read: the live heading, whether the map
    /// is north-up, and the scale-bar step for the current latitude.
    private var gestureDebug: String {
        let step = MapScaleBar.scale(metersPerPoint: map.metersPerPoint,
                                     imperial: settings.imperial)?.label ?? "-"
        let north = map.bearing < 0.5 || map.bearing > 359.5 ? 1 : 0
        return "gesture_bearing=\(Int(map.bearing.rounded())) gesture_north=\(north) gesture_scale=\(step)"
    }

    /// Routes to the pin a long press dropped. Only the route planner runs; no geocoder is called.
    private func openDroppedPinDirections(_ coordinate: CLLocationCoordinate2D) {
        closeDroppedPin()
        route.openIncomingDirections(
            name: "Dropped pin", latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// The card's explicit "Look up address": the one path where a dropped pin may ask a service.
    private func lookUpDroppedPin(_ coordinate: CLLocationCoordinate2D) {
        closeDroppedPin()
        mapPoi.longPress(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func closeDroppedPin() {
        droppedPinCoordinate = nil
        map.clearDroppedPin()
    }

    private func locate() {
        if location.isDenied {
            showsLocationOffAlert = true
            return
        }
        let map = self.map
        location.requestWhenInUse { map.showUser() }
    }

    /// The map's free-drive entry: a drive chrome with no destination, and no browse panel under
    /// it. The session, the route and any persisted guided drive stay untouched.
    private func beginFreeDrive() {
        blurSearch()
        activeSheet = nil
        route.close()
        place.close()
        mapPoi.close()
        search.clear()
        panelExpanded = false
        showsRecents = false
        nav.startFreeDrive()
    }

    /// The simple map: the driver keeps the roads, the cameras and the route line, and loses the
    /// browse furniture (places, transit, painted marks, fuel and bridge pins). It is a copy, so
    /// leaving free driving re-applies the layer sheet's own choice unchanged.
    private func simpleDrivingLayers(_ data: MapLayerData) -> MapLayerData {
        var simple = data
        simple.showPlaces = false
        simple.showTransit = false
        simple.paintedRoads = false
        simple.paintedMarks = []
        simple.fuelPrices = false
        simple.fuelPoints = []
        simple.bridgeOpenings = false
        simple.bridgePoints = []
        simple.trafficControls = false
        simple.controlPoints = []
        simple.trafficOn = false
        simple.satelliteOn = false
        return simple
    }
}

private struct LocateButton: View {
    let isFollowing: Bool
    let shape: MapButtonShape
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFollowing ? "location.fill" : "location")
                .font(.system(size: Design.Size.icon, weight: .semibold))
                // The single primary map control: the accent marks it without a second fill.
                .foregroundStyle(Design.Colors.accent)
                .frame(width: Design.Chrome.actionSize, height: Design.Chrome.actionSize)
                .contentShape(Rectangle())
        }
        .mapButtonBackground(shape)
        .accessibilityLabel(VelaL10n.text("map_show_my_location"))
        .accessibilityIdentifier("locate-button")
    }
}

/// The bearing, drawn as a needle that turns with the map. A tap returns the map to north; the
/// angle is also its accessibility value, so the bearing is never carried by the picture alone.
private struct MapCompassButton: View {
    let bearing: Double
    let shape: MapButtonShape
    let action: () -> Void

    private var degrees: Int { Int(bearing.rounded()) % 360 }

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 20, weight: .semibold))
                .rotationEffect(.degrees(-bearing))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .mapButtonBackground(shape)
        .accessibilityLabel(VelaL10n.text("map_compass"))
        .accessibilityValue(VelaL10n.text("map_degrees", String(describing: (degrees))))
        .accessibilityHint(VelaL10n.text("map_returns_the_map_to_north"))
        .accessibilityIdentifier("map-compass")
    }
}

/// "Prefer buttons over swipes" adds a two-step zoom control under the compass.
private struct MapZoomButtons: View {
    let shape: MapButtonShape
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    var body: some View {
        VStack(spacing: Design.Spacing.s) {
            zoomButton(symbol: "plus", label: "Zoom in", id: "map-zoom-in", action: onZoomIn)
            zoomButton(symbol: "minus", label: "Zoom out", id: "map-zoom-out", action: onZoomOut)
        }
    }

    private func zoomButton(symbol: String, label: String, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .mapButtonBackground(shape)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// The scale bar: a round distance in real metres at the map's centre latitude, drawn as an
/// open-topped bracket under its label, as on Android. It reads the live metres per point, not a
/// fixed zoom table, so it stays true when the projection moves with the latitude.
private struct MapScaleBarView: View {
    let metersPerPoint: Double
    let imperial: Bool

    var body: some View {
        if let scale = MapScaleBar.scale(metersPerPoint: metersPerPoint, imperial: imperial),
           metersPerPoint > 0 {
            let width = CGFloat(scale.meters / metersPerPoint)
            VStack(alignment: .leading, spacing: 0) {
                Text(scale.label)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("map-scale-label")
                ScaleBracket()
                    .stroke(Color.primary.opacity(0.8), lineWidth: 2)
                    .frame(width: max(1, width), height: 6)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Design.Spacing.s)
            .padding(.vertical, Design.Spacing.xxs)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Design.Radius.xs))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(VelaL10n.text("map_scale"))
            .accessibilityValue(scale.label)
        }
    }
}

private struct ScaleBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: 1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: 1))
        return path
    }
}

/// The card of a pin dropped by a long press. It shows the coordinate before anything is looked
/// up, and asks no service unless "Look up address" is tapped.
private struct DroppedPinCard: View {
    let latitude: Double
    let longitude: Double
    let onDirections: () -> Void
    let onLookUp: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            HStack(alignment: .top) {
                Text(VelaL10n.text("mapvm_dropped_pin"))
                    .font(Design.Typography.sheetTitle)
                    .accessibilityIdentifier("dropped-pin-title")
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: Design.Size.hitTarget, height: Design.Size.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(VelaL10n.text("place_close"))
                .accessibilityIdentifier("dropped-pin-close")
            }
            Text(coordinateText)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("dropped-pin-coordinates")
            HStack(spacing: Design.Spacing.s) {
                Button(action: onDirections) {
                    Label(VelaL10n.text("place_directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(Design.Typography.button)
                        .padding(.horizontal, Design.Padding.buttonH)
                        .padding(.vertical, Design.Padding.buttonV)
                        .frame(minHeight: Design.Size.hitTarget)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("dropped-pin-directions")
                Button(action: onLookUp) {
                    Text(VelaL10n.text("map_look_up_address"))
                        .font(Design.Typography.button)
                        .padding(.horizontal, Design.Padding.buttonH)
                        .padding(.vertical, Design.Padding.buttonV)
                        .frame(minHeight: Design.Size.hitTarget)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("dropped-pin-lookup")
            }
        }
        .padding(Design.Padding.sheet)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface, in: RoundedRectangle(cornerRadius: Design.Radius.l))
        .shadow(color: Design.Elevation.level2.color, radius: Design.Elevation.level2.radius,
                y: -Design.Elevation.level2.y)
        .padding(.horizontal, Design.Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dropped-pin-card")
    }

    private var coordinateText: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}

private extension View {
    /// One material and one shadow for every floating map button, in the shape the Map buttons
    /// setting asks for: round by default, square-cornered when chosen.
    func mapButtonBackground(_ shape: MapButtonShape) -> some View {
        background(.regularMaterial, in: shape.shape)
            .shadow(color: Design.Elevation.level2.color, radius: Design.Elevation.level2.radius,
                    y: Design.Elevation.level2.y)
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

/// The same text as `DebugLabel`, but with a clear foreground and no background. It stays in the
/// accessibility tree for the UI scenarios without painting over the map or consuming layout.
private struct InvisibleDebugLabel: View {
    let text: String
    let id: String

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1, alignment: .topLeading)
            .accessibilityIdentifier(id)
            .allowsHitTesting(false)
    }
}
#endif
