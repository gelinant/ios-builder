package app.vela.ios

/**
 * Whether a test may rely on wall-clock scheduling of background coroutines. The traffic-offer
 * acceptance test waits for a live recheck on `Dispatchers.Default`; on the Kotlin/Native test
 * binary that wait is not deterministic (the same code passes on the JVM), so the test runs there
 * only. The logic itself stays covered on both platforms by the session-level tests.
 */
expect fun backgroundSchedulingIsDeterministic(): Boolean
