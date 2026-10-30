package app.vela.core.util

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json

actual fun <T> Json.decodeFromBytes(deserializer: DeserializationStrategy<T>, bytes: ByteArray): T =
    decodeFromString(deserializer, bytes.decodeToString())
