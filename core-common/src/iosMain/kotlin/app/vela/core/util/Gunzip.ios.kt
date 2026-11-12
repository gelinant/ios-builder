package app.vela.core.util

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

/** zlib's inflate with a gzip-only window (15 + 16). */
@OptIn(ExperimentalForeignApi::class)
actual fun gunzip(data: ByteArray): ByteArray {
    if (data.isEmpty()) throw IllegalArgumentException("not a gzip stream")
    val out = ArrayList<ByteArray>()
    var total = 0
    memScoped {
        val s = alloc<z_stream>()
        memset(s.ptr, 0, sizeOf<z_stream>().convert())
        check(inflateInit2_(s.ptr, 31, zlibVersion(), sizeOf<z_stream>().convert()) == Z_OK) { "inflateInit2 failed" }
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
                        if (n > 0) { out += chunk.copyOf(n); total += n }
                        if (ret == Z_STREAM_END) break
                        if (ret == Z_BUF_ERROR && s.avail_in.toInt() == 0) throw IllegalStateException("gzip stream cut short")
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
    for (c in out) { c.copyInto(result, at); at += c.size }
    return result
}
