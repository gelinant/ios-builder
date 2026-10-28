package app.vela.core.data.google

/**
 * The pure part of the browser identity checks: what a pushed calibration bundle is validated
 * with (`CalibrationStore.parseBundle`) and what `BrowserHeaders` in `:core` builds its header set
 * from. `BrowserHeaders.sanitize`, `secChUaFor` and `chromeMajor` delegate here.
 */
object ChromeHints {

    /** Longest plausible UA. Real ones sit near 120 chars; this is slack, not a target. */
    private const val MAX_UA_LENGTH = 400

    /**
     * A header-safe version of [value], or null when it cannot be sent.
     *
     * Order matters, and it is deliberate:
     *  1. **Trim first.** Kotlin's `trim` drops surrounding `\n`, `\r`, `\t` and even NBSP, so a
     *     trailing newline (the likeliest cosmetic artifact in a hand-edited JSON bundle) is
     *     RECOVERED into a valid UA rather than rejected. Recovering beats silently falling back
     *     to a stale compiled default, which is the failure the remote channel exists to avoid.
     *  2. **Then reject what's left**: blanks, anything longer than [MAX_UA_LENGTH], and any
     *     character outside printable US-ASCII (0x20..0x7E), exactly OkHttp's accepted range, so
     *     a value that survives this can never throw at request-build time.
     *
     * The security-relevant case is an INTERIOR control character (`"Mozilla/5.0\r\nX-Evil: 1"`),
     * which trim cannot reach and step 2 always rejects. Callers fall back to the compiled
     * default, never to an empty header.
     */
    fun sanitize(value: String?): String? {
        val v = value?.trim() ?: return null
        if (v.isEmpty() || v.length > MAX_UA_LENGTH) return null
        if (v.any { it.code < 0x20 || it.code > 0x7E }) return null
        return v
    }

    /**
     * The `Sec-CH-UA` value desktop Chrome [major] actually sends. Chrome derives all of it from the
     * major version (components/embedder_support/user_agent_utils.cc): a GREASE brand
     * "Not<c1>A<c2>Brand" whose two characters, version and position in the list are picked by
     * `major` modulo the table sizes, so each release has one exact header. Checked against real
     * headers: 120 `"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"`, 124 and 130
     * (BrowserHeadersTest). Until 2026-09-23 the compiled hint was hand-edited from an older release
     * and carried Chrome 137's GREASE brand under a 153 version number.
     */
    fun secChUaFor(major: Int): String {
        val chars = listOf(" ", "(", ":", "-", ".", "/", ")", ";", "=", "?", "_")
        val greaseVersions = listOf("8", "99", "24")
        val list = listOf(
            "Not${chars[major % chars.size]}A${chars[(major + 1) % chars.size]}Brand" to greaseVersions[major % greaseVersions.size],
            "Chromium" to "$major",
            "Google Chrome" to "$major",
        )
        val orders = listOf(listOf(0, 1, 2), listOf(0, 2, 1), listOf(1, 0, 2), listOf(1, 2, 0), listOf(2, 0, 1), listOf(2, 1, 0))
        val order = orders[major % orders.size]
        val out = arrayOfNulls<Pair<String, String>>(3)
        for (i in list.indices) out[order[i]] = list[i]
        return out.joinToString(", ") { "\"${it!!.first}\";v=\"${it.second}\"" }
    }

    /** The major version in a Chrome user-agent string, or null. */
    fun chromeMajor(ua: String): String? = Regex("""Chrome/(\d+)\.""").find(ua)?.groupValues?.get(1)

}
