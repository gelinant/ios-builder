// Deterministic camera sequence for the runner: switch to globe, settle at z3, rotate, zoom out to
// the planet, probe camera limits, then tilt. Writes markers for the CI screenshots and a JSON
// report with the measured numbers.
import MapLibre
import UIKit

final class Autopilot {
    private let model: GlobeModel
    private weak var map: MLNMapView?
    private var report: [String: Any] = [:]
    private var rotation: (frames: Int, seconds: Double, renderMs: Double)?
    private var zoomOut: (frames: Int, seconds: Double, renderMs: Double)?

    init(model: GlobeModel, mapView: MLNMapView) {
        self.model = model
        self.map = mapView
        report["startedAt"] = ISO8601DateFormatter().string(from: Date())
        report["mapLibreRelease"] = "ios-v2026.10.19-globe"
        report["device"] = UIDevice.current.model
        report["system"] = UIDevice.current.systemVersion
        report["screenScale"] = Double(UIScreen.main.scale)
    }

    func start() {
        SpikeFiles.write("globe-state-booting")
        // Go through the same path as the picker, so the measured reload is the real switch.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.setProjection("globe")
            self.after(4) { self.settleAtZ3() }
        }
    }

    private func settleAtZ3() {
        guard let map else { return }
        report["styleLoadSeconds"] = model.styleLoadSeconds
        report["projection"] = model.projection
        setCamera(lat: 20, lon: 0, zoom: 3, heading: 0, pitch: 0)
        after(5) { [weak self] in
            guard let self else { return }
            SpikeFiles.write("globe-state-z3")
            self.measureRotation()
        }
    }

    private func measureRotation() {
        guard let map else { return }
        model.startMeasuring()
        let started = CACurrentMediaTime()
        let camera = map.camera
        camera.heading = 90
        map.setCamera(camera, withDuration: 10, animationTimingFunction: .init(name: .linear))
        after(10.5) { [weak self] in
            guard let self else { return }
            let (frames, renderMs) = self.model.stopMeasuring()
            let seconds = CACurrentMediaTime() - started
            self.rotation = (frames, seconds, renderMs)
            self.report["rotate"] = [
                "frames": frames,
                "seconds": seconds,
                "fps": Double(frames) / seconds,
                "avgRenderMs": renderMs / Double(max(frames, 1)),
            ]
            self.measureZoomOut()
        }
    }

    private func measureZoomOut() {
        guard let map else { return }
        model.startMeasuring()
        let started = CACurrentMediaTime()
        // The camera carries altitude, not zoom: three zoom levels out is eight times the altitude.
        let camera = map.camera
        camera.altitude = map.camera.altitude * 8
        map.setCamera(camera, withDuration: 10, animationTimingFunction: .init(name: .linear))
        after(10.5) { [weak self] in
            guard let self else { return }
            let (frames, renderMs) = self.model.stopMeasuring()
            let seconds = CACurrentMediaTime() - started
            self.zoomOut = (frames, seconds, renderMs)
            self.report["zoomOut"] = [
                "frames": frames,
                "seconds": seconds,
                "fps": Double(frames) / seconds,
                "avgRenderMs": renderMs / Double(max(frames, 1)),
            ]
            self.after(2.5) {
                SpikeFiles.write("globe-state-z0")
                self.after(2.5) {
                    self.probeLimitsAndOcclusion()
                }
            }
        }
    }

    private func probeLimitsAndOcclusion() {
        guard let map else { return }
        report["camera"] = [
            "minimumZoomLevel": Double(map.minimumZoomLevel),
            "maximumZoomLevel": Double(map.maximumZoomLevel),
            "maximumPitch": Double(map.maximumPitch),
        ]

        // Ask for a zoom beyond both ends and record what the camera keeps.
        map.setZoomLevel(-3, animated: false)
        let zoomOutClamped = map.zoomLevel
        map.setZoomLevel(30, animated: false)
        let zoomInClamped = map.zoomLevel
        map.setZoomLevel(0, animated: false)

        var camera = map.camera
        camera.pitch = 80
        map.setCamera(camera, animated: false)
        let pitchClamped = Double(map.camera.pitch)
        report["limits"] = [
            "zoomRequestedBelow": -3.0,
            "zoomKeptAfterBelow": zoomOutClamped,
            "zoomRequestedAbove": 30.0,
            "zoomKeptAfterAbove": zoomInClamped,
            "pitchRequested": 80.0,
            "pitchKept": pitchClamped,
        ]

        camera = map.camera
        camera.pitch = 0
        map.setCamera(camera, animated: false)
        let center = map.centerCoordinate
        let antipode = CLLocationCoordinate2D(
            latitude: -center.latitude,
            longitude: center.longitude > 0 ? center.longitude - 180 : center.longitude + 180
        )
        // On the planet at z0 the far side must be hidden; the point at the centre must not be.
        map.setZoomLevel(0, animated: false)
        report["occlusion"] = [
            "center": map.isCoordinateOccluded(center),
            "antipode": map.isCoordinateOccluded(antipode),
            "atZoom": map.zoomLevel,
        ]

        setCamera(lat: 30, lon: 10, zoom: 1.5, heading: 20, pitch: 45)
        after(4) { [weak self] in
            guard let self else { return }
            SpikeFiles.write("globe-state-tilted")
            self.close()
        }
    }

    private func close() {
        guard let map else { return }
        report["endedAt"] = ISO8601DateFormatter().string(from: Date())
        report["finalCamera"] = [
            "zoom": map.zoomLevel,
            "heading": Double(map.camera.heading),
            "pitch": Double(map.camera.pitch),
            "latitude": map.centerCoordinate.latitude,
            "longitude": map.centerCoordinate.longitude,
        ]
        report["styleLoaded"] = true
        SpikeFiles.writeJSON("globe-report.json", report)
        SpikeFiles.write("globe-done")
    }

    private func setCamera(lat: Double, lon: Double, zoom: Double, heading: Double, pitch: Double) {
        guard let map else { return }
        map.setCenter(CLLocationCoordinate2D(latitude: lat, longitude: lon), animated: false)
        map.setZoomLevel(zoom, animated: false)
        map.setDirection(heading, animated: false)
        let camera = map.camera
        camera.pitch = pitch
        map.setCamera(camera, animated: false)
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
