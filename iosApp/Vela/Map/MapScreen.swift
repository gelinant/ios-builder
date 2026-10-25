import SwiftUI
import UIKit

struct MapScreen: View {
    @StateObject private var map = MapController()
    @StateObject private var location = LocationPermission()
    @StateObject private var search: SearchModel
    @State private var showsLocationOffAlert = false
    @State private var panelExpanded = true
    @State private var coreLine = "VelaCore \(VelaCoreCheck.version)"

    init() {
        _search = StateObject(wrappedValue: SearchModel(store: AppGraph.session.search))
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
                    onClear: { search.clear() })
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                #if DEBUG
                HStack {
                    DebugCoreLabel(text: coreLine)
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
                .padding(.bottom, search.hasContent ? 0 : 36)
                .padding(.horizontal, 12)
                if search.hasContent {
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
        .onAppear {
            let search = self.search
            map.onViewportChange = { viewport in search.viewportChanged(viewport) }
            map.onUserLocation = { c in search.locationChanged(latitude: c.latitude, longitude: c.longitude) }
            search.start()
        }
        .onChange(of: search.rows) { _, rows in
            if !rows.isEmpty { panelExpanded = true }
            map.showResults(rows, insets: UIEdgeInsets(top: 140, left: 40, bottom: 420, right: 40))
        }
        .task {
            coreLine = await VelaCoreCheck.run()
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
        panelExpanded = true
        search.submit(viewport: map.currentViewport())
    }

    /// Centers the map on the result and folds the list so the pin shows.
    private func pick(_ row: SearchRow) {
        panelExpanded = false
        map.focus(on: row)
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
/// Debug builds only: the line the Kotlin framework answered at launch.
private struct DebugCoreLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier("velacore-debug")
            .allowsHitTesting(false)
    }
}
#endif
