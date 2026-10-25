package app.vela.core.util

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromStream

@OptIn(ExperimentalSerializationApi::class)
actual fun <T> Json.decodeFromBytes(deserializer: DeserializationStrategy<T>, bytes: ByteArray): T =
    decodeFromStream(deserializer, bytes.inputStream())
