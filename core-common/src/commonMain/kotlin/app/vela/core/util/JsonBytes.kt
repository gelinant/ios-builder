package app.vela.core.util

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json

/**
 * Decodes a UTF-8 JSON body straight into a DTO. The JVM streams the bytes (`decodeFromStream`), so a
 * large Overpass reply never exists as a String too; native decodes the String.
 */
expect fun <T> Json.decodeFromBytes(deserializer: DeserializationStrategy<T>, bytes: ByteArray): T

inline fun <reified T> Json.decodeFromBytes(bytes: ByteArray): T = decodeFromBytes(kotlinx.serialization.serializer<T>(), bytes)
