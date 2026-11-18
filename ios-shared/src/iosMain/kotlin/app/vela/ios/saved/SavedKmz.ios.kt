package app.vela.ios.saved

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.UByteVar
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.convert
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.sizeOf
import kotlinx.cinterop.usePinned
import platform.posix.memset
import platform.zlib.Z_BUF_ERROR
import platform.zlib.Z_NO_FLUSH
import platform.zlib.Z_OK
import platform.zlib.Z_STREAM_END
import platform.zlib.inflate
import platform.zlib.inflateEnd
import platform.zlib.inflateInit2_
import platform.zlib.zlibVersion
import platform.zlib.z_stream

/**
 * zlib's inflate with a RAW window (-15). A ZIP method-8 member carries no zlib header, and
 * inflating it with the default window fails on the first byte. [sizeHint] is only a hint; the
 * loop reads until the stream ends.
 */
@OptIn(ExperimentalForeignApi::class)
@Suppress("UNUSED_PARAMETER")
actual fun inflateRaw(data: ByteArray, sizeHint: Int): ByteArray {
    if (data.isEmpty()) throw IllegalArgumentException("empty deflate stream")
    val out = ArrayList<ByteArray>()
    var total = 0
    memScoped {
        val s = alloc<z_stream>()
        memset(s.ptr, 0, sizeOf<z_stream>().convert())
        check(inflateInit2_(s.ptr, -15, zlibVersion(), sizeOf<z_stream>().convert()) == Z_OK) { "inflateInit2 failed" }
        try {
            data.usePinned { input ->
                s.next_in = input.addressOf(0).reinterpret<UByteVar>()
                s.avail_in = data.size.convert()
                val chunk = ByteArray(64 * 1024)
                chunk.usePinned { buf ->
                    while (true) {
                        s.next_out = buf.addressOf(0).reinterpret<UByteVar>()
                        s.avail_out = chunk.size.convert()
                        val ret = inflate(s.ptr, Z_NO_FLUSH)
                        val n = chunk.size - s.avail_out.toInt()
                        if (n > 0) {
                            out += chunk.copyOf(n)
                            total += n
                            if (total > SavedKmz.MAX_KML_BYTES) throw IllegalStateException("KML too large")
                        }
                        if (ret == Z_STREAM_END) break
                        if (ret == Z_BUF_ERROR && s.avail_in.toInt() == 0) throw IllegalStateException("deflate stream cut short")
                        if (ret != Z_OK && ret != Z_BUF_ERROR) throw IllegalStateException("inflate failed: $ret")
                    }
                }
            }
        } finally {
            inflateEnd(s.ptr)
        }
    }
    val result = ByteArray(total)
    var at = 0
    for (c in out) {
        c.copyInto(result, at)
        at += c.size
    }
    return result
}
