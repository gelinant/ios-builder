import SwiftUI

/// The one-line entry the map chrome adds: `TerrainButton()`. It owns its presentation, so the
/// map screen only places the button and never holds terrain state.
struct TerrainButton: View {
    @State private var showsTerrain = false

    var body: some View {
        Button {
            showsTerrain = true
        } label: {
            Image(systemName: "mountain.2")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Design.Chrome.actionSize, height: Design.Chrome.actionSize)
                .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityIdentifier("terrain-open")
        .accessibilityLabel(VelaL10n.text("map_layers_terrain"))
        .fullScreenCover(isPresented: $showsTerrain) {
            TerrainScreen()
        }
    }
}

/// M-2: the separate Relief screen. It hosts one WKWebView running the bundled MapLibre GL JS
/// with terrain, a sky and distance fog. It is read-only and owns no camera link with the native
/// map: opening it never moves the map behind it, and closing it destroys the page.
struct TerrainScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var documentLoaded = false
    @State private var webLoaded = false
    @State private var demReady = false
    @State private var lastFailure = ""
    @State private var unavailableReason: String?

    /// The dark surround of the screen, including the area behind the sky.
    private static let surround = Color(red: 8 / 255, green: 11 / 255, blue: 14 / 255)
    /// The unavailable state and the credits are fixed strings of this screen; the rest goes
    /// through VelaL10n. A future lot adds the two keys to the Android catalog and the 24
    /// languages.
    private static let unavailableTitle = "Terrain is unavailable"
    private static let attribution = "Terrain: Mapzen terrain tiles (AWS Open Data elevation-tiles-prod). "
        + "© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors"

    var body: some View {
        ZStack(alignment: .top) {
            Self.surround.ignoresSafeArea()

            if let reason = unavailableReason {
                unavailable(reason)
            } else {
                TerrainWebView(onEvent: handle)
                    .ignoresSafeArea()
            }

            chrome
        }
        .background(Self.surround.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .accessibilityIdentifier("terrain-close")
                .accessibilityLabel(VelaL10n.text("place_close"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(VelaL10n.text("map_layers_terrain"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .accessibilityIdentifier("terrain-status")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                #if DEBUG
                Text(debugLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityIdentifier("terrain-debug")
                #endif
                Text(Self.attribution)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityIdentifier("terrain-attribution")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.black.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "mountain.2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text(Self.unavailableTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(reasonText(reason))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
            Button(VelaL10n.text("place_close")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Design.Colors.accentFill)
                .padding(.top, 4)
                .accessibilityIdentifier("terrain-unavailable-close")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.surround)
    }

    private func reasonText(_ reason: String) -> String {
        switch reason {
        case "offline":
            return "The elevation tiles need a network connection. Vela's map is unaffected."
        case "missing-resource":
            return "The bundled terrain document is missing from this build."
        case "webgl":
            return "This device could not start the terrain renderer."
        case "load":
            return "The terrain document did not load."
        default:
            return "The elevation tiles could not be reached. Try again when the network is back."
        }
    }

    private var statusLine: String {
        if unavailableReason != nil { return "Unavailable" }
        if demReady { return "Terrain on, sky and atmosphere" }
        if webLoaded { return "Loading elevation" }
        return "Loading terrain"
    }

    private var debugLine: String {
        let state = unavailableReason != nil ? "unavailable" : (demReady ? "ready" : "loading")
        return "terrain_doc=\(documentLoaded ? 1 : 0) terrain_web=\(webLoaded ? 1 : 0) "
            + "terrain_dem=\(demReady ? 1 : 0) terrain_state=\(state) "
            + "terrain_offline=\(unavailableReason == "offline" ? 1 : 0) "
            + "terrain_failure=\(lastFailure)"
    }

    private func handle(_ event: TerrainScreenEvent) {
        switch event {
        case .document:
            documentLoaded = true
        case .loaded:
            webLoaded = true
        case .dem:
            webLoaded = true
            demReady = true
        case .failure(let message):
            // Keep the diagnostic line short; the last failure is enough to tell a style error
            // from a tile error in the UI scenario.
            let cleaned = message
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: ":", with: ".")
            lastFailure = String(cleaned.prefix(100))
        case .unavailable(let reason):
            unavailableReason = reason
        }
    }
}
