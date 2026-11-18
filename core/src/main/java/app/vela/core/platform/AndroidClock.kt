package app.vela.core.platform

/** [Clock] over `System.currentTimeMillis`, `SystemClock.elapsedRealtime` and `System.nanoTime`. */
object AndroidClock : Clock {
    override fun nowMillis(): Long = System.currentTimeMillis()
    override fun elapsedRealtimeMillis(): Long = android.os.SystemClock.elapsedRealtime()
    override fun monotonicNanos(): Long = System.nanoTime()
}
