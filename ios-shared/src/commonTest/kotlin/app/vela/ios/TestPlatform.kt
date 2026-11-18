package app.vela.ios

import app.vela.core.platform.FileEntry
import app.vela.core.platform.PlatformFiles

/** [PlatformFiles] in memory for tests that build a MapSession without touching disk. */
class MemFiles : PlatformFiles {
    private val entries = mutableMapOf<String, ByteArray>()

    override val filesDir: String get() = "/files"
    override val cacheDir: String get() = "/cache"
    override val noBackupDir: String get() = "/nobackup"

    override fun exists(path: String) = entries.containsKey(path)
    override fun isDirectory(path: String) = entries.keys.any { it.startsWith("$path/") }
    override fun size(path: String) = entries[path]?.size?.toLong() ?: 0L
    override fun lastModifiedMillis(path: String) = 0L
    override fun list(path: String): List<FileEntry>? = emptyList()
    override fun mkdirs(path: String) = true
    override fun readBytes(path: String) = entries[path] ?: throw IllegalStateException("missing $path")
    override fun readText(path: String) =
        (entries[path] ?: throw IllegalStateException("missing $path")).decodeToString()

    override fun writeBytes(path: String, bytes: ByteArray) { entries[path] = bytes }
    override fun writeText(path: String, text: String) { entries[path] = text.encodeToByteArray() }
    override fun writeTextAtomic(path: String, text: String) { entries[path] = text.encodeToByteArray() }
    override fun delete(path: String): Boolean = entries.remove(path) != null

    override fun deleteRecursively(path: String): Boolean {
        entries.keys.filter { it == path || it.startsWith("$path/") }.forEach { entries.remove(it) }
        return true
    }

    override fun rename(from: String, to: String): Boolean {
        val data = entries.remove(from) ?: return false
        entries[to] = data
        return true
    }
}
