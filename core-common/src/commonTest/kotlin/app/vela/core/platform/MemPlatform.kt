package app.vela.core.platform

/** A wall clock the test sets. */
class TestClock(var now: Long = 1_700_000_000_000L) : Clock {
    override fun nowMillis(): Long = now
    override fun elapsedRealtimeMillis(): Long = now
    override fun monotonicNanos(): Long = now * 1_000_000
}

/** [KeyValueStores] in memory, with the seam's contract: one type per key, clear first. */
class MemKeyValueStores : KeyValueStores {
    val stores = HashMap<String, MemKeyValueStore>()
    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { MemKeyValueStore() }
}

class MemKeyValueStore : KeyValueStore {
    val values = LinkedHashMap<String, Any>()
    var commits = 0
    var applies = 0

    private inline fun <reified T> get(key: String, default: T): T {
        val v = values[key] ?: return default
        return v as? T ?: throw ClassCastException("$key is ${v::class.simpleName}")
    }

    override fun contains(key: String): Boolean = key in values
    override fun getString(key: String, default: String?): String? = values[key]?.let { it as? String ?: throw ClassCastException(key) } ?: default
    override fun getLong(key: String, default: Long): Long = get(key, default)
    override fun getInt(key: String, default: Int): Int = get(key, default)
    override fun getBoolean(key: String, default: Boolean): Boolean = get(key, default)
    override fun getFloat(key: String, default: Float): Float = get(key, default)
    override fun keys(): Set<String> = values.keys.toSet()

    override fun edit(): KeyValueEditor = object : KeyValueEditor {
        private var clear = false
        private val ops = ArrayList<(MutableMap<String, Any>) -> Unit>()
        private fun op(f: (MutableMap<String, Any>) -> Unit): KeyValueEditor = also { ops += f }
        override fun putString(key: String, value: String?) = op { if (value == null) it.remove(key) else it[key] = value }
        override fun putLong(key: String, value: Long) = op { it[key] = value }
        override fun putInt(key: String, value: Int) = op { it[key] = value }
        override fun putBoolean(key: String, value: Boolean) = op { it[key] = value }
        override fun putFloat(key: String, value: Float) = op { it[key] = value }
        override fun remove(key: String) = op { it.remove(key) }
        override fun clear(): KeyValueEditor = also { clear = true }
        private fun run() {
            if (clear) values.clear()
            ops.forEach { it(values) }
        }
        override fun apply() { run(); applies++ }
        override fun commit(): Boolean { run(); commits++; return true }
    }
}

/** [PlatformFiles] in memory. Every write stamps the file with [clock]. */
class MemFiles(private val clock: TestClock = TestClock()) : PlatformFiles {
    override val filesDir = "/data/files"
    override val cacheDir = "/data/cache"
    override val noBackupDir = "/data/nobackup"

    class Node(val bytes: ByteArray?, val modified: Long)

    /** Path to file contents; a folder has null bytes. */
    val nodes = HashMap<String, Node>()

    private fun parent(path: String) = path.substringBeforeLast('/', "")

    override fun exists(path: String) = path in nodes
    override fun isDirectory(path: String) = nodes[path]?.let { it.bytes == null } ?: false
    override fun size(path: String) = nodes[path]?.bytes?.size?.toLong() ?: 0L
    override fun lastModifiedMillis(path: String) = nodes[path]?.modified ?: 0L

    override fun list(path: String): List<FileEntry>? {
        if (!isDirectory(path)) return null
        return nodes.filterKeys { parent(it) == path }.map { (p, n) ->
            FileEntry(p.substringAfterLast('/'), p, n.bytes == null, n.bytes?.size?.toLong() ?: 0L, n.modified)
        }
    }

    override fun mkdirs(path: String): Boolean {
        var p = path
        while (p.isNotEmpty()) {
            if (nodes[p]?.bytes != null) return false
            nodes.getOrPut(p) { Node(null, clock.now) }
            p = parent(p)
        }
        return true
    }

    override fun readBytes(path: String): ByteArray = nodes[path]?.bytes ?: throw Exception("missing $path")
    override fun readText(path: String): String = readBytes(path).decodeToString()

    override fun writeBytes(path: String, bytes: ByteArray) {
        if (!isDirectory(parent(path))) throw Exception("no folder for $path")
        nodes[path] = Node(bytes.copyOf(), clock.now)
    }

    override fun writeText(path: String, text: String) = writeBytes(path, text.encodeToByteArray())
    override fun writeTextAtomic(path: String, text: String) = writeText(path, text)

    override fun rename(from: String, to: String): Boolean {
        val n = nodes.remove(from) ?: return false
        nodes[to] = n
        return true
    }

    override fun delete(path: String): Boolean {
        if (isDirectory(path) && list(path).orEmpty().isNotEmpty()) return false
        return nodes.remove(path) != null
    }

    override fun deleteRecursively(path: String): Boolean {
        nodes.keys.filter { it == path || it.startsWith("$path/") }.forEach { nodes.remove(it) }
        return true
    }
}
