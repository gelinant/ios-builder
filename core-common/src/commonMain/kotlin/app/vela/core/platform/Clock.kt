package app.vela.core.platform

/** Time sources (SPEC "Platform seams"). */
interface Clock {
    /** Wall-clock time in milliseconds since the Unix epoch (`System.currentTimeMillis`). Jumps
     *  when the user or the network changes the time. */
    fun nowMillis(): Long

    /** Milliseconds since boot, counting deep sleep (`SystemClock.elapsedRealtime`). Never jumps.
     *  The base for drive timers. */
    fun elapsedRealtimeMillis(): Long

    /** A monotonic nanosecond counter with an arbitrary origin (`System.nanoTime`), for measuring
     *  short spans and deadlines in one process. */
    fun monotonicNanos(): Long
}
