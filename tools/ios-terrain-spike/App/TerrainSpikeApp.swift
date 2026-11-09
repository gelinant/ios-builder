// Throwaway spike app for the terrain renderer. Not part of Vela (docs/ios/TERRAIN-SPIKE.md).
import SwiftUI

@main
struct TerrainSpikeApp: App {
    @StateObject private var model = TerrainModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: TerrainModel

    var body: some View {
        ZStack(alignment: .top) {
            MapContainer(model: model)
                .ignoresSafeArea()

            Text(model.readout)
                .font(.caption.monospaced())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 8)
                .padding(.top, 4)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

struct MapContainer: UIViewRepresentable {
    let model: TerrainModel

    func makeUIView(context: Context) -> UIView {
        model.makeContainer()
    }

    func updateUIView(_: UIView, context: Context) {}
}
