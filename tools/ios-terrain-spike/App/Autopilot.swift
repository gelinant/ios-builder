// Deterministic sequence for the runner: build sizes are already measured at launch, then the
// autopilot measures fps at three mesh resolutions, probes camera agreement in five camera states,
// holds three states for screenshots and finally measures the sibling-overlay route.
import Foundation
import UIKit

final class Autopilot {
    private weak var model: TerrainModel?
    private var fps: [String: [String: Any]] = [:]
    private var idle: [String: [String: Any]] = [:]
    private var overlay: [String: Any] = [:]

    init(model: TerrainModel) {
        self.model = model
    }

    func start() {
        log("autopilot start")
        after(1.0) { self.valleyShot() }
    }

    private func valleyShot() {
        guard let model else { return }
        model.setMode("custom")
        model.setMesh("128")
        model.setCamera(latitude: 45.8200, longitude: 6.8700, zoom: 12.30, pitch: 55, heading: 0)
        after(2.5) {
            SpikeFiles.write("terrain-state-valley")
            self.after(5.0) { self.measure("128") }
        }
    }

    private func measure(_ name: String) {
        guard let model else { return }
        model.setMesh(name)
        model.setCamera(latitude: 45.8200, longitude: 6.8500, zoom: 12.60, pitch: 55, heading: 10)
        after(1.0) {
            model.beginMeasurement()
            model.animateCamera(latitude: 45.8200, longitude: 6.9300, seconds: 4.0)
            self.after(4.3) {
                self.fps[name] = model.endMeasurement()
                self.after(1.5) {
                    model.beginMeasurement()
                    self.after(2.0) { self.idle[name] = model.endMeasurement(); self.next(after: name) }
                }
            }
        }
    }

    private func next(after name: String) {
        switch name {
        case "128": measure("256")
        case "256": measure("512")
        default: probes()
        }
    }

    private func probes() {
        guard let model else { return }
        model.setMesh("512")
        let states: [(String, Double, Double, Double, Double, Double)] = [
            ("pitch0", 45.8200, 6.8700, 13.0, 0, 0),
            ("pan", 45.8400, 6.9000, 13.0, 0, 0),
            ("zoom", 45.8200, 6.8700, 15.0, 0, 0),
            ("rotate", 45.8200, 6.8700, 13.0, 0, 45),
            ("pitch60", 45.8000, 6.8700, 13.0, 60, 20),
        ]
        runProbe(states, index: 0)
    }

    private func runProbe(_ states: [(String, Double, Double, Double, Double, Double)], index: Int) {
        guard let model else { return }
        guard index < states.count else {
            tiltedShot()
            return
        }
        let state = states[index]
        model.setCamera(latitude: state.1, longitude: state.2, zoom: state.3, pitch: state.4, heading: state.5)
        after(1.3) {
            model.runProbe(state.0)
            self.runProbe(states, index: index + 1)
        }
    }

    private func tiltedShot() {
        guard let model else { return }
        model.setMesh("512")
        model.setMode("custom")
        model.setCamera(latitude: 45.9240, longitude: 6.8694, zoom: 15.20, pitch: 60, heading: 25)
        after(2.5) {
            SpikeFiles.write("terrain-state-tilted")
            self.after(5.0) { self.overlayShot() }
        }
    }

    private func overlayShot() {
        guard let model else { return }
        model.setMode("overlay")
        after(1.5) {
            SpikeFiles.write("terrain-state-overlay")
            self.after(3.0) {
                model.beginMeasurement()
                self.after(4.2) {
                    self.overlay = model.endMeasurement()
                    model.setMode("custom")
                    self.finish()
                }
            }
        }
    }

    private func finish() {
        guard let model else { return }
        model.finish(extra: [
            "fps": fps,
            "idle": idle,
            "overlay": overlay,
            "screenshots": ["terrain-valley.png", "terrain-tilted.png", "terrain-overlay.png"],
        ])
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }
}
