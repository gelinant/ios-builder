package app.vela.core.util

/**
 * A small XML pull parser over a whole document, for the feeds Vela reads element by element
 * (`NdwBridgeOpenings`). It does what `KXmlParser.next()` did for them with namespaces off: a
 * prefixed name stays as written, attributes are skipped, character data and CDATA come as
 * [TEXT] with the five predefined and numeric entities resolved, comments, processing
 * instructions and the DOCTYPE are skipped. A tag that does not close, a mismatched end tag or an
 * unknown entity throws [IllegalArgumentException], as kxml2 threw; a document that ends with
 * elements still open just ends, as it did in kxml2.
 */
class XmlPull(private val doc: String) {
    private var pos = if (doc.startsWith('\uFEFF')) 1 else 0
    private val open = ArrayList<String>()
    private var pendingEnd: String? = null

    /** The element name of the last [START_TAG] or [END_TAG]. */
    var name: String = ""
        private set

    /** The text of the last [TEXT]. */
    var text: String = ""
        private set

    fun next(): Int {
        pendingEnd?.let { pendingEnd = null; name = it; return END_TAG }
        while (true) {
            // kxml2 ends a cut-off document there too, with no end tags for what is still open.
            if (pos >= doc.length) return END_DOCUMENT
            if (doc[pos] != '<') {
                val end = doc.indexOf('<', pos).let { if (it < 0) doc.length else it }
                text = decode(doc, pos, end)
                pos = end
                return TEXT
            }
            when {
                doc.startsWith("<!--", pos) -> pos = after("-->", pos + 4)
                doc.startsWith("<![CDATA[", pos) -> {
                    val end = doc.indexOf("]]>", pos + 9).also { if (it < 0) fail("unclosed CDATA") }
                    text = doc.substring(pos + 9, end)
                    pos = end + 3
                    return TEXT
                }
                doc.startsWith("<?", pos) -> pos = after("?>", pos + 2)
                doc.startsWith("<!", pos) -> pos = skipDeclaration(pos + 2)
                doc.startsWith("</", pos) -> {
                    val close = doc.indexOf('>', pos).also { if (it < 0) fail("unclosed end tag") }
                    val n = doc.substring(pos + 2, close).trim()
                    if (open.isEmpty() || open.last() != n) fail("</$n> does not match")
                    open.removeAt(open.lastIndex)
                    pos = close + 1
                    name = n
                    return END_TAG
                }
                else -> return startTag()
            }
        }
    }

    private fun startTag(): Int {
        var i = pos + 1
        while (i < doc.length && !doc[i].isWhitespace() && doc[i] != '>' && doc[i] != '/') i++
        val n = doc.substring(pos + 1, i)
        if (n.isEmpty()) fail("empty tag name")
        var quote = 0.toChar()
        while (true) {
            if (i >= doc.length) fail("unclosed <$n>")
            val c = doc[i]
            if (quote != 0.toChar()) {
                if (c == quote) quote = 0.toChar()
            } else if (c == '"' || c == '\'') {
                quote = c
            } else if (c == '>') {
                break
            }
            i++
        }
        val selfClosing = doc[i - 1] == '/' && i - 1 > pos + n.length
        pos = i + 1
        name = n
        if (selfClosing) pendingEnd = n else open += n
        return START_TAG
    }

    private fun after(marker: String, from: Int): Int {
        val end = doc.indexOf(marker, from)
        if (end < 0) fail("unclosed $marker")
        return end + marker.length
    }

    private fun skipDeclaration(from: Int): Int {
        var depth = 0
        var i = from
        while (i < doc.length) {
            when (doc[i]) {
                '[' -> depth++
                ']' -> depth--
                '>' -> if (depth <= 0) return i + 1
            }
            i++
        }
        fail("unclosed declaration")
    }

    private fun decode(s: String, start: Int, end: Int): String {
        val amp = s.indexOf('&', start)
        if (amp < 0 || amp >= end) return s.substring(start, end)
        val out = StringBuilder(end - start)
        var i = start
        while (i < end) {
            val c = s[i]
            if (c != '&') { out.append(c); i++; continue }
            val semi = s.indexOf(';', i)
            if (semi < 0 || semi >= end) fail("unterminated entity")
            val ref = s.substring(i + 1, semi)
            when {
                ref == "lt" -> out.append('<')
                ref == "gt" -> out.append('>')
                ref == "amp" -> out.append('&')
                ref == "quot" -> out.append('"')
                ref == "apos" -> out.append('\'')
                ref.startsWith("#x") -> appendCode(out, ref.substring(2).toIntOrNull(16), ref)
                ref.startsWith("#") -> appendCode(out, ref.substring(1).toIntOrNull(), ref)
                else -> fail("unknown entity &$ref;")
            }
            i = semi + 1
        }
        return out.toString()
    }

    private fun appendCode(out: StringBuilder, code: Int?, ref: String) {
        if (code == null || code < 0 || code > 0x10FFFF) fail("bad character reference &$ref;")
        if (code < 0x10000) {
            out.append(code.toChar())
        } else {
            val v = code - 0x10000
            out.append((0xD800 + (v shr 10)).toChar()).append((0xDC00 + (v and 0x3FF)).toChar())
        }
    }

    private fun fail(message: String): Nothing = throw IllegalArgumentException("XML: $message at $pos")

    companion object {
        const val START_TAG = 2
        const val END_TAG = 3
        const val TEXT = 4
        const val END_DOCUMENT = 1
    }
}
