package app.vela.ios.platform

import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSData
import platform.Foundation.create
import platform.posix.memcpy

/**
 * Bulk copies between Kotlin's `ByteArray` and Foundation's `NSData` (`Data` in Swift), for the
 * Swift seams: one `memcpy` instead of a bridged call per byte.
 */
@OptIn(ExperimentalForeignApi::class, kotlinx.cinterop.BetaInteropApi::class)
object IosBytes {
    fun toByteArray(data: NSData): ByteArray {
        val size = data.length.toInt()
        val out = ByteArray(size)
        if (size > 0) out.usePinned { memcpy(it.addressOf(0), data.bytes, data.length) }
        return out
    }

    fun toData(bytes: ByteArray): NSData {
        if (bytes.isEmpty()) return NSData()
        return bytes.usePinned { NSData.create(bytes = it.addressOf(0), length = bytes.size.toULong()) }
    }

    /** The request's body as `Data`, null when it has none. */
    fun bodyOf(request: HttpRequest): NSData? = request.body?.let(::toData)

    /** A response whose body is [body], copied once. */
    fun response(code: Int, headers: List<HttpHeader>, body: NSData, finalUrl: String): HttpResponse =
        HttpResponse(code, headers, toByteArray(body), finalUrl)
}
