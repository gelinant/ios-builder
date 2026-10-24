package app.vela.core.util

/**
 * Common stand-ins for JVM helpers that Kotlin common lacks. Each one computes exactly what the
 * JDK 17 method computes, so a file moved here from `:core` gives the same doubles on the JVM.
 */

/** `java.lang.Math.toRadians`: JDK 17 multiplies by this constant. */
fun Double.toRadians(): Double = this * DEGREES_TO_RADIANS

/** `java.lang.Math.toDegrees`: JDK 17 multiplies by this constant. */
fun Double.toDegrees(): Double = this * RADIANS_TO_DEGREES

private const val DEGREES_TO_RADIANS = 0.017453292519943295
private const val RADIANS_TO_DEGREES = 57.29577951308232
