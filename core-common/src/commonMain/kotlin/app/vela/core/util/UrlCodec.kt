package app.vela.core.util

/**
 * `application/x-www-form-urlencoded` in UTF-8, with the output of `java.net.URLEncoder.encode(s,
 * "UTF-8")` and `java.net.URLDecoder.decode(s, "UTF-8")`. `jvmTest` checks both against the JDK.
 */
object UrlCodec {
    private const val HEX = "0123456789ABCDEF"

    private fun unreserved(c: Char): Boolean =
        c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '.' || c == '-' || c == '*' || c == '_'

    /** Letters, digits and `.-*_` stay; a space becomes `+`; everything else is `%XX` of its UTF-8
     *  bytes. A lone surrogate encodes as `?` (`%3F`), as the JDK's encoder replaces it. */
    fun encode(s: String): String {
        val sb = StringBuilder(s.length + 16)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            when {
                unreserved(c) -> { sb.append(c); i++ }
                c == ' ' -> { sb.append('+'); i++ }
                else -> {
                    var cp: Int
                    if (c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate()) {
                        cp = 0x10000 + ((c.code - 0xD800) shl 10) + (s[i + 1].code - 0xDC00)
                        i += 2
                    } else {
                        cp = if (c.isSurrogate()) '?'.code else c.code
                        i++
                    }
                    for (b in utf8(cp)) {
                        sb.append('%').append(HEX[(b shr 4) and 0xF]).append(HEX[b and 0xF])
                    }
                }
            }
        }
        return sb.toString()
    }

    private fun utf8(cp: Int): IntArray = when {
        cp < 0x80 -> intArrayOf(cp)
        cp < 0x800 -> intArrayOf(0xC0 or (cp shr 6), 0x80 or (cp and 0x3F))
        cp < 0x10000 -> intArrayOf(0xE0 or (cp shr 12), 0x80 or ((cp shr 6) and 0x3F), 0x80 or (cp and 0x3F))
        else -> intArrayOf(
            0xF0 or (cp shr 18), 0x80 or ((cp shr 12) and 0x3F),
            0x80 or ((cp shr 6) and 0x3F), 0x80 or (cp and 0x3F),
        )
    }

    /** `+` becomes a space and each run of `%XX` is decoded as UTF-8. Throws
     *  [IllegalArgumentException] on a bad or incomplete escape, as the JDK's decoder does. */
    fun decode(s: String): String {
        if ('%' !in s && '+' !in s) return s
        val sb = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            when (c) {
                '+' -> { sb.append(' '); i++ }
                '%' -> {
                    val bytes = ArrayList<Byte>()
                    while (i + 2 < s.length && s[i] == '%') {
                        val v = hex2(s[i + 1], s[i + 2])
                        if (v < 0) throw IllegalArgumentException("URLDecoder: Illegal hex characters in escape (%) pattern")
                        bytes.add(v.toByte())
                        i += 3
                    }
                    if (i < s.length && s[i] == '%') throw IllegalArgumentException("URLDecoder: Incomplete trailing escape (%) pattern")
                    sb.append(bytes.toByteArray().decodeToString())
                }
                else -> { sb.append(c); i++ }
            }
        }
        return sb.toString()
    }

    /** `Integer.parseInt(two chars, 16)`: a leading sign is allowed, so `+F` is 15 and `-1` is
     *  negative. -1 for anything that does not parse. */
    private fun hex2(a: Char, b: Char): Int {
        val lo = b.digitToIntOrNull(16) ?: return -1
        return when (a) {
            '+' -> lo
            '-' -> if (lo == 0) 0 else -1
            else -> (a.digitToIntOrNull(16) ?: return -1) * 16 + lo
        }
    }
}
