import XCTest

/// PERF-1: the cold-start budget, measured from the kernel's process record rather than from a
/// test timer, so dyld and the pre-main work are included.
///
/// Each launch reads the `launch-probe` accessibility label that `LaunchProbe` publishes, which
/// carries the same marks the diagnostics screen shows plus the sampled process footprint:
/// `cold_first_frame_ms`, `cold_map_tap_ms` (first style and gestures on the live map),
/// `cold_first_fix_ms` and `cold_peak_mb` (largest `phys_footprint` in the first eight seconds).
///
/// Six launches, three per case, alternating so a warming or slowing runner does not favour one
/// case. The legacy case (`-VelaPerfLegacy YES`) is the pre-PERF-1 path, so the before and after
/// figures come from the same run and the same machine. Medians are asserted, never the best run.
///
/// Run: `VELA_ONLY_UI=PerformanceUITests,LaunchUITests` with `ci-ipa.sh` (Debug simulator).
final class PerformanceUITests: VelaUITestCase {
    /// The absolute ceiling for a cold first frame on the shared Debug simulator. The first run of
    /// this guard measured a 3 782 ms median for the previous launch path on the GitHub runner,
    /// so 5 000 ms is that median with room for a loaded runner. The budget is raised to the
    /// same-run baseline plus a quarter when the runner is slower than that, and the strict gate
    /// is the same-run comparison itself.
    private let firstFrameBudgetMs = 5_000.0
    /// The regression the guard refuses: a median more than a quarter above the same-run baseline.
    private let regressionShare = 1.25

    private struct Reading {
        let firstFrameMs: Double
        let mapTapMs: Double
        let firstFixMs: Double
        let peakMb: Double
    }

    func testColdStartBudget() throws {
        var current: [Reading] = []
        var legacy: [Reading] = []
        for round in 0..<3 {
            // Alternate the order: a first launch pays the cold caches, the third does not.
            if round % 2 == 0 {
                current.append(try launch(legacy: false))
                legacy.append(try launch(legacy: true))
            } else {
                legacy.append(try launch(legacy: true))
                current.append(try launch(legacy: false))
            }
        }

        let frame = median(current.map(\.firstFrameMs))
        let tap = median(current.map(\.mapTapMs))
        let fix = median(current.map(\.firstFixMs))
        let peak = median(current.map(\.peakMb))
        let legacyFrame = median(legacy.map(\.firstFrameMs))
        let legacyTap = median(legacy.map(\.mapTapMs))
        let legacyFix = median(legacy.map(\.firstFixMs))
        let legacyPeak = median(legacy.map(\.peakMb))
        // The absolute ceiling, raised to the same-run baseline plus a quarter when the runner is
        // slower than the 3 782 ms the previous path measured: a loaded runner moves both cases
        // together, and the guard must not turn that into a failure.
        let budget = max(firstFrameBudgetMs, legacyFrame * regressionShare)

        report("cold_first_frame_ms", Int(frame))
        report("cold_map_tap_ms", Int(tap))
        report("cold_first_fix_ms", Int(fix))
        report("cold_peak_mb", Int(peak))
        report("cold_budget_ms", Int(budget))
        report("cold_baseline_first_frame_ms", Int(legacyFrame))
        report("cold_baseline_map_tap_ms", Int(legacyTap))
        report("cold_baseline_first_fix_ms", Int(legacyFix))
        report("cold_baseline_peak_mb", Int(legacyPeak))
        report("cold_first_frame_gain_ms", Int(legacyFrame - frame))

        XCTAssertGreaterThan(frame, 0, "no first frame measurement")
        XCTAssertGreaterThan(tap, 0, "no map tap measurement")
        XCTAssertGreaterThan(fix, 0, "no first fix measurement")
        XCTAssertLessThanOrEqual(
            frame, budget,
            "cold first frame \(Int(frame)) ms is over the \(Int(budget)) ms budget")
        XCTAssertLessThanOrEqual(
            frame, legacyFrame * regressionShare,
            "cold first frame regressed from \(Int(legacyFrame)) ms to \(Int(frame)) ms")
        XCTAssertLessThanOrEqual(
            tap, legacyTap * regressionShare,
            "time to a tappable map regressed from \(Int(legacyTap)) ms to \(Int(tap)) ms")
        XCTAssertLessThanOrEqual(
            fix, legacyFix * regressionShare,
            "first fix regressed from \(Int(legacyFix)) ms to \(Int(fix)) ms")
        XCTAssertLessThanOrEqual(
            peak, legacyPeak * regressionShare,
            "launch footprint regressed from \(Int(legacyPeak)) MB to \(Int(peak)) MB")
    }

    /// One launch over the probe. Waits for the finished line, parses it, terminates the app so
    /// the next measurement starts from a fresh process.
    private func launch(legacy: Bool) throws -> Reading {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            // The first fix is only marked when the map follows the user (ci-ipa grants the
            // permission and pins the simulated location before the UI scenarios).
            "-VelaFollowUser", "YES",
            "-VelaLaunchProbe", "YES",
        ]
        if legacy { app.launchArguments += ["-VelaPerfLegacy", "YES"] }
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 30), "no map screen")
        let probe = app.descendants(matching: .any)
            .matching(identifier: "launch-probe").firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "no launch probe")
        XCTAssertTrue(waitUntil(20) { probe.label.contains("cold_complete=1") },
                      "the probe did not finish: \(probe.label)")
        // The first fix can land after the footprint window; wait for it, but not forever.
        XCTAssertTrue(waitUntil(12) { !probe.label.contains("cold_first_fix_ms=-1") },
                      "no first fix in the probe: \(probe.label)")
        let line = probe.label
        return Reading(
            firstFrameMs: value("cold_first_frame_ms", in: line),
            mapTapMs: value("cold_map_tap_ms", in: line),
            firstFixMs: value("cold_first_fix_ms", in: line),
            peakMb: value("cold_peak_mb", in: line))
    }

    /// One `key=number` field from the probe line; `-1` when a mark never happened.
    private func value(_ key: String, in line: String) -> Double {
        for field in line.split(separator: " ") {
            let parts = field.split(separator: "=", maxSplits: 1)
            if parts.count == 2, String(parts[0]) == key {
                return Double(parts[1]) ?? -1
            }
        }
        return -1
    }

    private func median(_ values: [Double]) -> Double {
        precondition(!values.isEmpty, "no readings")
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
