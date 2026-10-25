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
    @StateObject private var settings: SettingsModel
    @State private var showsLocationOffAlert = false
    @State private var showsOffline = false
    @State private var showsSettings = false
    @State private var panelExpanded = true
    @State private var coreLine = "VelaCore \(VelaCoreCheck.version)"

    init() {
        _search = StateObject(wrappedValue: SearchModel(store: AppGraph.session.search))
        _calibration = StateObject(wrappedValue: CalibrationModel(calibration: AppGraph.session.calibration))
        _place = StateObject(wrappedValue: PlaceModel(session: AppGraph.session))
        _route = StateObject(wrappedValue: RouteModel(session: AppGraph.session))
        _offline = StateObject(wrappedValue: OfflineModel(store: AppGraph.session.offline))
        _settings = StateObject(wrappedValue: SettingsModel(store: AppGraph.session.settings))
    }

    var body: some View {
        ZStack {
            MapView(controller: map)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                SearchBar(
                    text: $search.query,
                    searching: search.searching,
                    onSubmit: submit,
                    onClear: { route.close(); place.close(); search.clear() },
                    onOffline: { showsOffline = true },
                    onSettings: { showsSettings = true })
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                #if DEBUG
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        DebugLabel(text: coreLine, id: "velacore-debug")
                        DebugLabel(text: "calibration \(calibration.version)", id: "calibration-debug")
                        DebugLabel(text: offline.debugLine, id: "offline-debug")
                        DebugLabel(text: search.debugLine, id: "search-debug")
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
                    LocateButton(isFollowing: map.isFollowingUser, action: locate)
                }
                // Clears the map's attribution info button in the bottom right corner.
                .padding(.bottom, search.hasContent || place.isOpen || route.isOpen ? 0 : 36)
                .padding(.horizontal, 12)
                if route.isOpen {
                    if route.showsSteps {
                        StepsSheet(model: route)
                            .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
                    } else {
                        RoutePickerSheet(model: route, onClose: route.close)
                            .containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
                    }
                } else if let card = place.card {
                    PlaceSheet(model: place, card: card, onClose: closePlace, onDirections: openDirections)
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
                } else if search.hasContent {
                    ResultsPanel(
                        rows: search.rows,
                        message: search.message,
                        searching: search.searching,
                        expanded: $panelExpanded,
                        onPick: pick)
                }
                HStack {
                    AttributionLabel()
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .environment(\.locale, settings.locale)
        .environment(\.layoutDirection, settings.layoutDirection)
        .onAppear {
            let search = self.search
            let route = self.route
            map.onViewportChange = { viewport in
                search.viewportChanged(viewport)
                route.mapCenterChanged(latitude: (viewport.south + viewport.north) / 2,
                                       longitude: (viewport.west + viewport.east) / 2)
            }
            map.onUserLocation = { c in
                search.locationChanged(latitude: c.latitude, longitude: c.longitude)
                route.locationChanged(latitude: c.latitude, longitude: c.longitude)
                offline.onLocation(latitude: c.latitude, longitude: c.longitude)
            }
            map.onRouteTap = { index in route.select(index) }
            search.start()
            place.start()
            route.start()
            offline.start()
            settings.start()
            calibration.start()
            if LaunchOptions.current.followUser {
                locate()
            }
        }
        .onChange(of: place.isOpen) { _, open in
            map.setBottomInset(open ? sheetInset : 0)
        }
        .onChange(of: route.lines) { _, lines in
            map.showRoutes(lines, selected: route.activeIndex, fit: !lines.isEmpty, insets: routeInsets)
        }
        .onChange(of: route.activeIndex) { _, index in
            map.showRoutes(route.lines, selected: index, fit: false, insets: routeInsets)
        }
        .onChange(of: route.isOpen) { _, open in
            if !open {
                map.clearRoutes()
                map.setBottomInset(place.isOpen ? sheetInset : 0)
            }
        }
        .onChange(of: offline.revision) { _, _ in
            map.refreshOfflineStyle()
        }
        .onChange(of: search.rows) { _, rows in
            if !rows.isEmpty { panelExpanded = true }
            map.showResults(rows, insets: UIEdgeInsets(top: 140, left: 40, bottom: 420, right: 40))
        }
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
    }

    private func submit() {
        place.close()
        panelExpanded = true
        search.submit(viewport: map.currentViewport())
    }

    /// Opens the result's sheet and centers the map on it, above the sheet.
    private func pick(_ row: SearchRow) {
        panelExpanded = false
        map.setBottomInset(sheetInset)
        map.focus(on: row)
        place.open(resultIndex: row.id)
    }

    /// The place sheet's Directions: the route chooser to the open place.
    private func openDirections() {
        route.openFromPlace()
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
