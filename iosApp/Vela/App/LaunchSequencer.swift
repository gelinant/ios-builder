import Foundation
import VelaCore

/// PERF-1: runs the work that the first map frame does not need once that frame has been drawn.
///
/// `MapSession.start()` never blocks on the offline catalog: it leaves it to `startDeferred()`.
/// The bundled region table follows the same rule through `enqueue`, because parsing it next to
/// MapLibre's own style load made the frame later on a busy runner instead of earlier.
///
/// Everything runs on the first `first map frame` mark. A launch that never draws a map (a
/// background URL session handoff, or a test that only reads state) gets its work eight seconds
/// after launch instead: the frame normally lands well before that, and eight seconds is past the
/// slowest measured Debug launch. Every call is idempotent, and with `-VelaPerfLegacy YES` the
/// session has already started everything and nothing was queued.
enum LaunchSequencer {
    private static var observing = false
    private static var released = false
    private static var queued: [() -> Void] = []

    static func start() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: DiagnosticsMeasurements.changedNotification, object: nil, queue: .main
        ) { _ in
            if DiagnosticsMeasurements.shared.entry(.firstMapFrame) != nil { release() }
        }
        // A launch that shows no map still gets its offline catalog.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { release() }
    }

    /// Adds work to run once the map is on screen. A queue entry added after the release runs at
    /// once on the same background queue.
    static func enqueue(_ work: @escaping () -> Void) {
        queued.append(work)
        if released { runQueued() }
    }

    private static func release() {
        guard !released else { return }
        released = true
        // Reading the Kotlin session builds nothing: `nil` means the graph was never started, and
        // `start()` will then run the whole session as before.
        IosGraph.shared.session?.startDeferred()
        runQueued()
    }

    /// The queued work is file and JSON work, so it never runs on the main thread.
    private static func runQueued() {
        let work = queued
        queued = []
        for item in work {
            DispatchQueue.global(qos: .utility).async(execute: item)
        }
    }
}
