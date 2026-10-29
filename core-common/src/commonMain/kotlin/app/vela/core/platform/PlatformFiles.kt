package app.vela.core.platform

/** One child of a folder, as [PlatformFiles.list] saw it. */
data class FileEntry(
    val name: String,
    /** Absolute path: the folder's path, `/`, then [name]. */
    val path: String,
    val isDirectory: Boolean,
    /** Bytes; 0 for a folder. */
    val size: Long,
    /** Last modification, milliseconds since the Unix epoch. */
    val lastModifiedMillis: Long,
)

/**
 * The app's folders and the file operations the core uses on them (SPEC "Platform seams"). Paths
 * are absolute strings with `/` separators; build them with [joinPath].
 *
 * Reads and writes throw when they fail (`java.io.IOException` on Android). Queries never throw:
 * a missing file has size 0, no modification time and no children.
 */
interface PlatformFiles {
    /** Private app data that the platform backs up. Android `Context.filesDir`; iOS
     *  `Application Support`. */
    val filesDir: String

    /** Data the system may delete when space runs low. Android `Context.cacheDir`; iOS `Caches`. */
    val cacheDir: String

    /** Private app data that is never backed up. Android `Context.noBackupFilesDir`; iOS a folder
     *  in `Application Support` excluded from backup. */
    val noBackupDir: String

    fun exists(path: String): Boolean
    fun isDirectory(path: String): Boolean

    /** Bytes in the file, 0 when it is missing or a folder (`File.length`). */
    fun size(path: String): Long

    /** Milliseconds since the Unix epoch, 0 when the file is missing (`File.lastModified`). */
    fun lastModifiedMillis(path: String): Long

    /** The folder's children in no set order, or null when [path] is not a folder
     *  (`File.listFiles`). */
    fun list(path: String): List<FileEntry>?

    /** Creates the folder and its missing parents. True when it exists afterward. */
    fun mkdirs(path: String): Boolean

    @Throws(Exception::class)
    fun readBytes(path: String): ByteArray

    /** The file as UTF-8 text. */
    @Throws(Exception::class)
    fun readText(path: String): String

    /** Replaces the file in place (`File.writeBytes`). A process kill mid-write leaves it torn. */
    @Throws(Exception::class)
    fun writeBytes(path: String, bytes: ByteArray)

    /** Replaces the file in place with UTF-8 text (`File.writeText`). A process kill mid-write
     *  leaves it torn. */
    @Throws(Exception::class)
    fun writeText(path: String, text: String)

    /**
     * Replaces the file so that a reader sees the old content or the new, never part of either
     * (`util/AtomicFiles.writeText`): the text goes to the sibling `<name>.tmp`, is synced to disk
     * and renamed over the target. Where the rename cannot replace an existing file, the target is
     * deleted and the rename retried; a second failure deletes the temp file and throws.
     */
    @Throws(Exception::class)
    fun writeTextAtomic(path: String, text: String)

    /** Renames [from] to [to] (`File.renameTo`). False when it failed, which it does across
     *  volumes and, on some filesystems, over an existing file. */
    fun rename(from: String, to: String): Boolean

    /** Deletes a file or an empty folder. True when something was deleted. */
    fun delete(path: String): Boolean

    /** Deletes a file or a folder with everything in it. True when nothing is left. */
    fun deleteRecursively(path: String): Boolean
}

/** [dir] joined with each of [names] by `/`. */
fun joinPath(dir: String, vararg names: String): String =
    names.fold(dir.trimEnd('/')) { acc, n -> "$acc/$n" }

/** Bytes in every file under [path], all levels down (`File.walkTopDown` summing `length`). */
fun PlatformFiles.treeSize(path: String): Long {
    if (!isDirectory(path)) return size(path)
    return list(path).orEmpty().sumOf { if (it.isDirectory) treeSize(it.path) else it.size }
}
