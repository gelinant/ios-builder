package app.vela.core.util

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

actual fun Double.toRadians(): Double = Math.toRadians(this)

actual fun Double.toDegrees(): Double = Math.toDegrees(this)

actual val ioDispatcher: CoroutineDispatcher get() = Dispatchers.IO
