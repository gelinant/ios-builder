package app.vela.core.util

actual fun Double.toRadians(): Double = this * DEGREES_TO_RADIANS

actual fun Double.toDegrees(): Double = this * RADIANS_TO_DEGREES

private const val DEGREES_TO_RADIANS = 0.017453292519943295
private const val RADIANS_TO_DEGREES = 57.29577951308232
