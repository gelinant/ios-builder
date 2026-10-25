import SwiftUI
import UIKit

struct MapScreen: View {
    @StateObject private var map = MapController()
    @StateObject private var location = LocationPermission()
    @StateObject private var search: SearchModel
    @StateObject private var calibration: CalibrationModel
    @StateObject private var place: PlaceModel
    @StateObject private var route: RouteModel
    @StateObject private var offline: OfflineModel
    @StateObject private var saved: SavedModel
    @StateObject private var nav: NavModel
    @State private var showsLocationOffAlert = false
    @State private var showsOffline = false
    @State private var showsSaved = false
    @State private var searchFocused = false
    @State private var showsRecents = false
    @State private var panelExpanded = true
    @State private var coreLine = "VelaCore \(VelaCoreCheck.version)"

    init() {
        _search = StateObject(wrappedValue: SearchModel(store: AppGraph.session.search))
        _calibration = StateObject(wrappedValue: CalibrationModel(calibration: AppGraph.session.calibration))
        _place = StateObject(wrappedValue: PlaceModel(session: AppGraph.session))
        _route = StateObject(wrappedValue: RouteModel(session: AppGraph.session))
        _offline = StateObject(wrappedValue: OfflineModel(store: AppGraph.session.offline))
        _saved = StateObject(wrappedValue: SavedModel(session: AppGraph.session))
        _nav = StateObject(wrappedValue: NavModel(
            session: AppGraph.session, location: AppGraph.location, voice: AppGraph.navVoice))
    }

    var body: some View {
        ZStack {
            MapView(controller: map)
                .ignoresSafeArea()
            if nav.active {
                NavChrome(model: nav)
            } else {
                VStack(spacing: 8) {
                HStack(spacing: 8) {
                    SearchBar(
                        text: $search.query,
                        searching: search.searching,
                        onSubmit: submit,
                        onClear: {
                            route.close()
                            place.close()
                            search.clear()
                            showsRecents = true
                        },
                        onOffline: { showsOffline = true },
                        onFocusChange: { searchFocused = $0 })
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
                #if DEBUG
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        DebugLabel(text: coreLine, id: "velacore-debug")
                        DebugLabel(text: "calibration \(calibration.version)", id: "calibration-debug")
                        DebugLabel(text: offline.debugLine, id: "offline-debug")
                        DebugLabel(text: search.debugLine, id: "search-debug")
                        DebugLabel(text: nav.debugLine, id: "nav-debug")
                        DebugLabel(text: nav.voiceDebugLine, id: "nav-voice-debug")
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
                #endif
                Spacer()
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
                .padding(.bottom, search.hasContent || place.isOpen || route.isOpen ? 0 : 36)
                .padding(.horizontal, 12)
                if route.isOpen {
                    if route.showsSteps {
                        StepsSheet(model: route)
                            .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
                    } else {
                        RoutePickerSheet(model: route, onClose: route.close, onStart: nav.startIfAvailable)
                            .containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
                    }
                } else if let card = place.card {
                    PlaceSheet(model: place, saved: saved, card: card, onClose: closePlace, onDirections: openDirections)
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
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
                HStack {
                    AttributionLabel()
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                }
            }
        }
        .sheet(isPresented: $showsSaved) {
            SavedView(
                model: saved,
                canSaveRoute: route.hasRoute,
                defaultRouteName: defaultRouteName,
                onSaveRoute: { _ = AppGraph.session.saveActiveRoute(name: $0) },
                onOpenPlace: openSavedPlace,
                onRecentSearch: { query in
                    showsSaved = false
                    search.query = query
                    submit()
                },
                onOpenRecentPlace: { item in
                    showsSaved = false
                    route.close()
                    search.clear()
                    saved.open(item)
                },
                onOpenRoute: { item in
                    showsSaved = false
                    route.close()
                    search.clear()
                    saved.open(item)
                },
                onClose: { showsSaved = false })
        }
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
                if !nav.active { route.select(index) }
            }
            map.onSavedTap = { index in
                guard index < saved.markers.count else { return }
                let marker = saved.markers[index]
                if marker.parking {
                    showsSaved = true
                } else {
                    route.close()
                    search.clear()
                    saved.open(marker)
                    map.focus(onSaved: marker)
                }
            }
            nav.attach(map: map)
            nav.start()
            search.start()
            place.start()
            route.start()
            offline.start()
            saved.start()
            calibration.start()
            map.showSaved(saved.markers)
            if LaunchOptions.current.followUser {
                locate()
            }
        }
        .onChange(of: place.isOpen) { _, open in
            if !nav.active { map.setBottomInset(open ? sheetInset : 0) }
        }
        .onChange(of: route.lines) { _, lines in
            if !nav.active {
                map.showRoutes(lines, selected: route.activeIndex, fit: !lines.isEmpty, insets: routeInsets)
            }
        }
        .onChange(of: route.activeIndex) { _, index in
            if !nav.active { map.showRoutes(route.lines, selected: index, fit: false, insets: routeInsets) }
        }
        .onChange(of: route.isOpen) { _, open in
            if !open && !nav.active {
                map.clearRoutes()
                map.setBottomInset(place.isOpen ? sheetInset : 0)
            }
        }
        .onChange(of: offline.revision) { _, _ in
            map.refreshOfflineStyle()
        }
        .onChange(of: nav.navigating) { _, navigating in
            if navigating {
                place.close()
                search.clear()
            }
        }
        .onChange(of: search.rows) { _, rows in
            if !rows.isEmpty { panelExpanded = true }
            map.showResults(rows, insets: UIEdgeInsets(top: 140, left: 40, bottom: 420, right: 40))
        }
        .onChange(of: saved.markers) { _, markers in
            map.showSaved(markers)
        }
        .task {
            coreLine = await VelaCoreCheck.run()
        }
        .sheet(isPresented: $showsOffline) {
            OfflineSheet(model: offline)
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
    }

    private func submit() {
        place.close()
        showsRecents = false
        panelExpanded = true
        search.submit(viewport: map.currentViewport())
    }

    /// Opens the result's sheet and centers the map on it, above the sheet.
    private func pick(_ row: SearchRow) {
        showsRecents = false
        panelExpanded = false
        map.setBottomInset(sheetInset)
        map.focus(on: row)
        place.open(resultIndex: row.id)
    }

    private func pickRecent(_ item: RecentItem) {
        showsRecents = false
        if item.kind == "search" {
            search.query = item.title
            submit()
        } else {
            route.close()
            place.close()
            saved.open(item)
        }
    }

    private func openSavedPlace(_ item: SavedPlaceItem) {
        showsSaved = false
        route.close()
        search.clear()
        saved.open(item)
        map.focus(latitude: item.latitude, longitude: item.longitude)
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
