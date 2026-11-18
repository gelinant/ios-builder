package app.vela.ios.net

/**
 * `java.net.URLEncoder.encode(s, "UTF-8")`, byte for byte, so a URL built on iOS is the one
 * Android sends: letters, digits and `.-*_` stay, a space becomes `+`, everything else is its
 * UTF-8 bytes as `%XX` in upper case. A lone surrogate is encoded as `?` (`%3F`), as the JVM's
 * UTF-8 encoder replaces it.
 */
object FormUrlEncoder {
    private const val HEX = "0123456789ABCDEF"

    fun encode(s: String): String {
        val out = StringBuilder(s.length + 16)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            when {
                c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '.' || c == '-' || c == '*' || c == '_' -> out.append(c)
                c == ' ' -> out.append('+')
                c.code < 0x80 -> byte(out, c.code)
                c.code < 0x800 -> {
                    byte(out, 0xC0 or (c.code shr 6))
                    byte(out, 0x80 or (c.code and 0x3F))
                }
                c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate() -> {
                    val cp = 0x10000 + ((c.code - 0xD800) shl 10) + (s[i + 1].code - 0xDC00)
                    byte(out, 0xF0 or (cp shr 18))
                    byte(out, 0x80 or ((cp shr 12) and 0x3F))
                    byte(out, 0x80 or ((cp shr 6) and 0x3F))
                    byte(out, 0x80 or (cp and 0x3F))
                    i++
                }
                c.isSurrogate() -> byte(out, '?'.code)
                else -> {
                    byte(out, 0xE0 or (c.code shr 12))
                    byte(out, 0x80 or ((c.code shr 6) and 0x3F))
                    byte(out, 0x80 or (c.code and 0x3F))
                }
            }
            i++
        }
        return out.toString()
    }

    private fun byte(out: StringBuilder, b: Int) {
        out.append('%').append(HEX[(b shr 4) and 0xF]).append(HEX[b and 0xF])
    }
}
