package app.vela.core.platform

import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

private class JvmRandomFile(private val f: RandomAccessFile) : RandomFile {
    override fun length(): Long = f.length()
    override fun filePointer(): Long = f.filePointer
    override fun seek(position: Long) = f.seek(position)
    override fun read(): Int = f.read()
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int = f.read(buffer, offset, length)
    override fun readFully(buffer: ByteArray, offset: Int, length: Int) = f.readFully(buffer, offset, length)
    override fun write(buffer: ByteArray, offset: Int, length: Int) = f.write(buffer, offset, length)
    override fun setLength(length: Long) = f.setLength(length)
    override fun sync() = f.fd.sync()
    override fun close() = f.close()
}

actual fun openRandomFile(path: String, write: Boolean): RandomFile =
    JvmRandomFile(RandomAccessFile(File(path), if (write) "rw" else "r"))

actual fun fileLength(path: String): Long = File(path).length()

actual fun renameFile(from: String, to: String): Boolean = File(from).renameTo(File(to))

actual fun deleteFile(path: String): Boolean = File(path).delete()

actual fun usableSpace(path: String): Long = File(path).usableSpace

actual fun gunzip(bytes: ByteArray): ByteArray = GZIPInputStream(bytes.inputStream()).use { it.readBytes() }

actual fun gzip(bytes: ByteArray): ByteArray =
    java.io.ByteArrayOutputStream().also { sink -> GZIPOutputStream(sink).use { it.write(bytes) } }.toByteArray()

actual fun sha256(): Sha256 = object : Sha256 {
    private val md = MessageDigest.getInstance("SHA-256")
    override fun update(bytes: ByteArray) = md.update(bytes)
    override fun digest(): ByteArray = md.digest()
}
