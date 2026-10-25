package app.vela.core.util

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO

actual fun Double.toRadians(): Double = this * DEGREES_TO_RADIANS

actual fun Double.toDegrees(): Double = this * RADIANS_TO_DEGREES

actual fun Double.mathRound(): Long {
    if (isNaN()) return 0L
    val f = kotlin.math.floor(this)
    return (if (this - f >= 0.5) f + 1.0 else f).toLong()
}

actual fun <K, V> identityMap(): MutableMap<K, V> = LinkedHashMap()

actual val ioDispatcher: CoroutineDispatcher get() = Dispatchers.IO

private const val DEGREES_TO_RADIANS = 0.017453292519943295
private const val RADIANS_TO_DEGREES = 57.29577951308232
