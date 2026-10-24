package app.vela.core.util

/**
 * Common stand-ins for JVM helpers that Kotlin common lacks. On the JVM they call `java.lang.Math`,
 * so Android keeps the exact doubles its runtime computes today (ART before Android 14 divides by
 * 180 and multiplies by pi; JDK 17 multiplies by one constant). Native multiplies by the JDK 17
 * constants.
 */

/** `java.lang.Math.toRadians`. */
expect fun Double.toRadians(): Double

/** `java.lang.Math.toDegrees`. */
expect fun Double.toDegrees(): Double

/** `java.lang.Math.round(double)`: ties toward positive infinity, NaN gives 0, clamped to the
 *  `Long` range. */
expect fun Double.mathRound(): Long

/** A map keyed by reference, as `java.util.IdentityHashMap`. On native it is a `LinkedHashMap`, so
 *  two equal keys share one entry there. */
expect fun <K, V> identityMap(): MutableMap<K, V>
