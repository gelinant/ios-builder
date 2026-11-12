package app.vela.core.util

import java.io.ByteArrayInputStream
import java.util.zip.GZIPInputStream

actual fun gunzip(data: ByteArray): ByteArray = GZIPInputStream(ByteArrayInputStream(data)).use { it.readBytes() }
