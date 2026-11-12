package app.vela.core.platform

import java.io.File

/** [PlatformFiles] over `java.io.File`. The three folders are `Context.filesDir`, `cacheDir` and
 *  `noBackupFilesDir` (see `di/PlatformModule`). */
class AndroidPlatformFiles(filesDir: File, cacheDir: File, noBackupDir: File) : PlatformFiles {
    override val filesDir: String = filesDir.path
    override val cacheDir: String = cacheDir.path
    override val noBackupDir: String = noBackupDir.path

    override fun exists(path: String): Boolean = File(path).exists()
    override fun isDirectory(path: String): Boolean = File(path).isDirectory
    override fun size(path: String): Long = File(path).length()
    override fun lastModifiedMillis(path: String): Long = File(path).lastModified()

    override fun list(path: String): List<FileEntry>? =
        File(path).listFiles()?.map { FileEntry(it.name, it.path, it.isDirectory, if (it.isDirectory) 0L else it.length(), it.lastModified()) }

    override fun mkdirs(path: String): Boolean = File(path).let { it.mkdirs() || it.isDirectory }
    override fun readBytes(path: String): ByteArray = File(path).readBytes()
    override fun readText(path: String): String = File(path).readText()
    override fun writeBytes(path: String, bytes: ByteArray) = File(path).writeBytes(bytes)
    override fun writeText(path: String, text: String) = File(path).writeText(text)
    override fun writeTextAtomic(path: String, text: String) = app.vela.core.util.AtomicFiles.writeText(File(path), text)
    override fun rename(from: String, to: String): Boolean = File(from).renameTo(File(to))
    override fun delete(path: String): Boolean = File(path).delete()
    override fun deleteRecursively(path: String): Boolean = File(path).deleteRecursively()
}
