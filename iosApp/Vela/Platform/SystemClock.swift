import Foundation
import VelaCore

/// The `Clock` seam. `VelaCore.Clock`, not the standard library's `Clock` protocol.
final class SystemClock: NSObject, VelaCore.Clock {
    func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
    }

    /// `CLOCK_MONOTONIC` counts the time the device sleeps, as Android's `elapsedRealtime` does.
    func elapsedRealtimeMillis() -> Int64 {
        Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000)
    }

    func monotonicNanos() -> Int64 {
        Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
    }
}
