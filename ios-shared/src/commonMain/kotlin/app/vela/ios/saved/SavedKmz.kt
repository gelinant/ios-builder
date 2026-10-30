package app.vela.ios.saved

/**
 * The KML inside a `.kmz` file: a KMZ is a plain ZIP whose document is the `.kml` entry. My Maps
 * writes it as `doc.kml`, normally deflated; a map a user re-zipped may name it anything.
 *
 * The archive is read here rather than in Swift so the same parser runs in the JVM tests and on the
 * phone. Only the little ZIP surface a KMZ uses is read: the end-of-central-directory record, the
 * central entries and one local header. ZIP64 and encrypted entries are refused rather than
 * guessed. [inflateRaw] is the only platform call: raw DEFLATE, no zlib or gzip wrapper.
 */
object SavedKmz {
    /** A KML document larger than this is not a list a phone should try to import. */
    const val MAX_KML_BYTES = 40_000_000

    private const val EOCD = 0x06054b50
    private const val CENTRAL = 0x02014b50
    private const val LOCAL = 0x04034b50

    private data class Entry(val name: String, val method: Int, val compressed: Int, val size: Int, val local: Int)

    /** The first `.kml` entry's text, or null when [bytes] is not a readable KMZ. */
    fun kml(bytes: ByteArray): String? = try {
        read(bytes)
    } catch (_: Exception) {
        null
    }

    private fun read(bytes: ByteArray): String? {
        if (bytes.size < 22 || bytes[0] != 'P'.code.toByte() || bytes[1] != 'K'.code.toByte()) return null
        val eocd = findEnd(bytes) ?: return null
        val count = u16(bytes, eocd + 10) ?: return null
        var at = u32(bytes, eocd + 16) ?: return null
        var found: Entry? = null
        repeat(count) {
            if (u32(bytes, at) != CENTRAL) return null
            val method = u16(bytes, at + 10) ?: return null
            val compressed = u32(bytes, at + 20) ?: return null
            val size = u32(bytes, at + 24) ?: return null
            val nameLength = u16(bytes, at + 28) ?: return null
            val extra = u16(bytes, at + 30) ?: return null
            val comment = u16(bytes, at + 32) ?: return null
            val local = u32(bytes, at + 42) ?: return null
            val nameStart = at + 46
            val nameEnd = nameStart + nameLength
            if (nameEnd > bytes.size) return null
            val name = bytes.decodeToString(nameStart, nameEnd)
            // ZIP64 writes -1 here; guessing at a 4 GB document is worse than refusing it.
            if (compressed < 0 || size < 0) return null
            if (name.endsWith(".kml", ignoreCase = true) && size <= MAX_KML_BYTES) {
                val entry = Entry(name, method, compressed, size, local)
                if (name.equals("doc.kml", ignoreCase = true)) found = entry
                else if (found == null) found = entry
            }
            at = nameEnd + extra + comment
        }
        val entry = found ?: return null
        if (u32(bytes, entry.local) != LOCAL) return null
        val nameLength = u16(bytes, entry.local + 26) ?: return null
        val extra = u16(bytes, entry.local + 28) ?: return null
        val start = entry.local + 30 + nameLength + extra
        val end = start + entry.compressed
        if (start < 0 || end > bytes.size) return null
        val raw = bytes.copyOfRange(start, end)
        val document = when (entry.method) {
            0 -> raw
            8 -> inflateRaw(raw, entry.size)
            else -> return null
        }
        if (document.size > MAX_KML_BYTES) return null
        return document.decodeToString().removePrefix("\uFEFF")
    }

    private fun findEnd(bytes: ByteArray): Int? {
        val first = maxOf(0, bytes.size - 22 - 65_535)
        var at = bytes.size - 22
        while (at >= first) {
            if (u32(bytes, at) == EOCD) return at
            at -= 1
        }
        return null
    }

    private fun u16(bytes: ByteArray, at: Int): Int? {
        if (at < 0 || at + 2 > bytes.size) return null
        return (bytes[at].toInt() and 0xFF) or ((bytes[at + 1].toInt() and 0xFF) shl 8)
    }

    /** A little-endian 32-bit field, or null when it is ZIP64's 0xFFFFFFFF. */
    private fun u32(bytes: ByteArray, at: Int): Int? {
        if (at < 0 || at + 4 > bytes.size) return null
        val value = (bytes[at].toLong() and 0xFF) or
            ((bytes[at + 1].toLong() and 0xFF) shl 8) or
            ((bytes[at + 2].toLong() and 0xFF) shl 16) or
            ((bytes[at + 3].toLong() and 0xFF) shl 24)
        return value.takeIf { it != 0xFFFFFFFFL }?.toInt()
    }
}

/** One raw-DEFLATE stream (ZIP method 8), as `Inflater(nowrap = true)` reads it. */
expect fun inflateRaw(data: ByteArray, sizeHint: Int): ByteArray
