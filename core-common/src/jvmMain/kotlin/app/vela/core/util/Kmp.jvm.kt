package app.vela.core.util

actual fun Double.toRadians(): Double = Math.toRadians(this)

actual fun Double.toDegrees(): Double = Math.toDegrees(this)

actual fun Double.mathRound(): Long = Math.round(this)

actual fun <K, V> identityMap(): MutableMap<K, V> = java.util.IdentityHashMap()
