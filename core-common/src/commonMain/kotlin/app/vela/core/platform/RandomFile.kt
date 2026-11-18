package app.vela.core.platform

/**
 * A file read and written at any offset, as `java.io.RandomAccessFile` (SPEC "Platform seams",
 * platform functions). Reads and writes start at [filePointer] and move it. Errors throw
 * (`java.io.IOException` on the JVM, [RandomFileException] on iOS).
 */
interface RandomFile : AutoCloseable {
    fun length(): Long
    fun filePointer(): Long
    fun seek(position: Long)

    /** One byte, or -1 at the end of the file. */
    fun read(): Int

    /** Up to [length] bytes into [buffer] at [offset]; the count read, or -1 at the end. */
    fun read(buffer: ByteArray, offset: Int = 0, length: Int = buffer.size): Int

    /** Exactly [length] bytes, or throws at the end of the file. */
    fun readFully(buffer: ByteArray, offset: Int = 0, length: Int = buffer.size)

    fun write(buffer: ByteArray, offset: Int = 0, length: Int = buffer.size)

    /** Truncates or extends the file. */
    fun setLength(length: Long)

    /** Forces what was written to the disk (`FileDescriptor.sync`, `fsync`). */
    fun sync()
}

class RandomFileException(message: String) : Exception(message)

/** Opens [path] for reading, or for reading and writing when [write] (created when missing). */
expect fun openRandomFile(path: String, write: Boolean = false): RandomFile

/** Bytes in the file, 0 when it is missing (`File.length`). */
expect fun fileLength(path: String): Long

/** Renames [from] over [to] (`File.renameTo`, `rename(2)`). False when it failed. */
expect fun renameFile(from: String, to: String): Boolean

/** Deletes a file (`File.delete`). True when it was deleted. */
expect fun deleteFile(path: String): Boolean

/** Bytes free to this app on the volume holding [path] (`File.usableSpace`); 0 when unknown. */
expect fun usableSpace(path: String): Long

/** The bytes of a gzip stream (`java.util.zip.GZIPInputStream`). Throws on a corrupt stream. */
expect fun gunzip(bytes: ByteArray): ByteArray

/** [bytes] as a gzip stream at the default level (`java.util.zip.GZIPOutputStream`). */
expect fun gzip(bytes: ByteArray): ByteArray

/** An incremental SHA-256 (`MessageDigest.getInstance("SHA-256")`). */
interface Sha256 {
    fun update(bytes: ByteArray)

    /** The 32-byte hash; the digest starts over afterwards. */
    fun digest(): ByteArray
}

expect fun sha256(): Sha256

/** The SHA-256 of [bytes]. */
fun sha256(bytes: ByteArray): ByteArray = sha256().apply { update(bytes) }.digest()

/** Lowercase hex, two digits a byte (`"%02x".format(b)` for each). */
fun ByteArray.toHex(): String = joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }
