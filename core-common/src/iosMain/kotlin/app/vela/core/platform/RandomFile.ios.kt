@file:OptIn(ExperimentalForeignApi::class, UnsafeNumber::class)

package app.vela.core.platform

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.UnsafeNumber
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.convert
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.sizeOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSFileManager
import platform.Foundation.NSFileSystemFreeSize
import platform.Foundation.NSNumber
import platform.posix.O_CREAT
import platform.posix.O_RDONLY
import platform.posix.O_RDWR
import platform.posix.SEEK_END
import platform.posix.close
import platform.posix.errno
import platform.posix.fsync
import platform.posix.ftruncate
import platform.posix.lseek
import platform.posix.open
import platform.posix.pread
import platform.posix.pwrite
import platform.posix.rename
import platform.posix.stat
import platform.posix.unlink
import platform.posix.strerror
import platform.zlib.Z_BUF_ERROR
import platform.zlib.Z_DEFAULT_COMPRESSION
import platform.zlib.Z_DEFAULT_STRATEGY
import platform.zlib.Z_DEFLATED
import platform.zlib.Z_FINISH
import platform.zlib.Z_NO_FLUSH
import platform.zlib.Z_OK
import platform.zlib.Z_STREAM_END
import platform.zlib.ZLIB_VERSION
import platform.zlib.deflate
import platform.zlib.deflateEnd
import platform.zlib.deflateInit2_
import platform.zlib.inflate
import platform.zlib.inflateEnd
import platform.zlib.inflateInit2_
import platform.zlib.z_stream
import kotlinx.cinterop.toKString

private fun fail(what: String): Nothing = throw RandomFileException("$what: ${strerror(errno)?.toKString()}")

private class PosixRandomFile(private val path: String, private val fd: Int) : RandomFile {
    private var pos = 0L

    override fun length(): Long {
        val end = lseek(fd, 0, SEEK_END)
        if (end < 0) fail("length of $path")
        return end
    }

    override fun filePointer(): Long = pos
    override fun seek(position: Long) {
        if (position < 0) throw RandomFileException("negative seek")
        pos = position
    }

    override fun read(): Int {
        val one = ByteArray(1)
        return if (read(one, 0, 1) <= 0) -1 else one[0].toInt() and 0xFF
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        val n = buffer.usePinned { pread(fd, it.addressOf(offset), length.convert(), pos).toLong() }
        if (n < 0) fail("read $path")
        if (n == 0L) return -1
        pos += n
        return n.toInt()
    }

    override fun readFully(buffer: ByteArray, offset: Int, length: Int) {
        var done = 0
        while (done < length) {
            val n = read(buffer, offset + done, length - done)
            if (n < 0) throw RandomFileException("end of $path")
            done += n
        }
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int) {
        var done = 0
        while (done < length) {
            val n = buffer.usePinned { pwrite(fd, it.addressOf(offset + done), (length - done).convert(), pos).toLong() }
            if (n <= 0) fail("write $path")
            pos += n
            done += n.toInt()
        }
    }

    override fun setLength(length: Long) {
        if (ftruncate(fd, length) != 0) fail("truncate $path")
        if (pos > length) pos = length
    }

    override fun sync() {
        if (fsync(fd) != 0) fail("sync $path")
    }

    override fun close() {
        close(fd)
    }
}

actual fun openRandomFile(path: String, write: Boolean): RandomFile {
    val fd = if (write) open(path, O_RDWR or O_CREAT, 0x1A4) else open(path, O_RDONLY)
    if (fd < 0) fail("open $path")
    return PosixRandomFile(path, fd)
}

actual fun fileLength(path: String): Long = memScoped {
    val st = alloc<stat>()
    if (stat(path, st.ptr) != 0) 0L else st.st_size
}

actual fun renameFile(from: String, to: String): Boolean = rename(from, to) == 0

actual fun deleteFile(path: String): Boolean = unlink(path) == 0

actual fun usableSpace(path: String): Long {
    val attrs = NSFileManager.defaultManager.attributesOfFileSystemForPath(path, null) ?: return 0L
    return (attrs[NSFileSystemFreeSize] as? NSNumber)?.longLongValue ?: 0L
}

private const val CHUNK = 64 * 1024

actual fun gunzip(bytes: ByteArray): ByteArray = memScoped {
    val z = alloc<z_stream>()
    // 15 + 16: a gzip wrapper, as GZIPInputStream reads.
    if (inflateInit2_(z.ptr, 15 + 16, ZLIB_VERSION, sizeOf<z_stream>().toInt()) != Z_OK) throw RandomFileException("inflateInit")
    val out = ArrayList<ByteArray>()
    val buf = ByteArray(CHUNK)
    var total = 0
    try {
        val src = if (bytes.isEmpty()) ByteArray(1) else bytes
        src.usePinned { input ->
            z.next_in = input.addressOf(0).reinterpret()
            z.avail_in = bytes.size.convert()
            while (true) {
                val status = buf.usePinned { o ->
                    z.next_out = o.addressOf(0).reinterpret()
                    z.avail_out = CHUNK.convert()
                    inflate(z.ptr, Z_NO_FLUSH)
                }
                val got = CHUNK - z.avail_out.toInt()
                if (got > 0) { out += buf.copyOf(got); total += got }
                if (status == Z_STREAM_END) break
                if (status != Z_OK && !(status == Z_BUF_ERROR && got > 0)) throw RandomFileException("corrupt gzip stream ($status)")
                if (z.avail_in.toInt() == 0 && got == 0) throw RandomFileException("truncated gzip stream")
            }
        }
    } finally {
        inflateEnd(z.ptr)
    }
    join(out, total)
}

actual fun gzip(bytes: ByteArray): ByteArray = memScoped {
    val z = alloc<z_stream>()
    if (deflateInit2_(z.ptr, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, sizeOf<z_stream>().toInt()) != Z_OK) {
        throw RandomFileException("deflateInit")
    }
    val out = ArrayList<ByteArray>()
    val buf = ByteArray(CHUNK)
    var total = 0
    try {
        val src = if (bytes.isEmpty()) ByteArray(1) else bytes
        src.usePinned { input ->
            z.next_in = input.addressOf(0).reinterpret()
            z.avail_in = bytes.size.convert()
            while (true) {
                val status = buf.usePinned { o ->
                    z.next_out = o.addressOf(0).reinterpret()
                    z.avail_out = CHUNK.convert()
                    deflate(z.ptr, Z_FINISH)
                }
                val got = CHUNK - z.avail_out.toInt()
                if (got > 0) { out += buf.copyOf(got); total += got }
                if (status == Z_STREAM_END) break
                if (status != Z_OK && status != Z_BUF_ERROR) throw RandomFileException("deflate ($status)")
            }
        }
    } finally {
        deflateEnd(z.ptr)
    }
    join(out, total)
}

private fun join(parts: List<ByteArray>, total: Int): ByteArray {
    val all = ByteArray(total)
    var at = 0
    for (p in parts) { p.copyInto(all, at); at += p.size }
    return all
}

actual fun sha256(): Sha256 = Sha256Kt()
