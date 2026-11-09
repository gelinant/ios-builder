package app.vela.ios.privacy

/**
 * The privacy rules iOS shares with its tests, with no platform type in sight.
 *
 * Android keeps the same three choices in `app.vela.web.SessionRotation`; Swift stores them in the
 * settings suite and applies them to the two in-memory cookie stores (the HTTP jar and the hidden
 * WebView's data store). [isGoogleHost] is the request counter's and the NoGoogle guard's one
 * predicate, so a host counted as Google is also the host the guard refuses.
 */
object PrivacyPolicy {
    const val ROTATION_WEEK = "week"
    const val ROTATION_DAY = "day"
    const val ROTATION_LAUNCH = "launch"

    val rotationModes: List<String> = listOf(ROTATION_WEEK, ROTATION_DAY, ROTATION_LAUNCH)

    fun normalizeRotation(mode: String): String =
        if (mode in rotationModes) mode else ROTATION_WEEK

    /** The longest history one session may keep. Launch mode is due as soon as it starts. */
    fun rotationPeriodMillis(mode: String): Long = when (normalizeRotation(mode)) {
        ROTATION_LAUNCH -> 0L
        ROTATION_DAY -> 24L * 3_600_000L
        else -> 7L * 24L * 3_600_000L
    }

    /**
     * Whether a session that began at [startedMs] is due for replacement at [nowMs]. A zero stamp
     * is the first run: it starts a session rather than replacing one.
     */
    fun isRotationDue(mode: String, startedMs: Long, nowMs: Long): Boolean {
        if (startedMs <= 0L) return false
        return nowMs - startedMs >= rotationPeriodMillis(mode)
    }

    /**
     * Whether [host] is a Google host. Country domains (google.fr, google.co.uk) count, as do the
     * image, logging and ad hosts the app can reach. A lookalike such as notgoogle.com is not one.
     */
    fun isGoogleHost(host: String): Boolean {
        val h = host.trim().lowercase().trimEnd('.')
        if (h.isEmpty()) return false
        val known = listOf(
            "google.com", "googleapis.com", "gstatic.com", "googleusercontent.com",
            "googlesyndication.com", "googleadservices.com", "google-analytics.com",
            "googletagmanager.com", "googletagservices.com", "doubleclick.net",
        )
        if (known.any { h == it || h.endsWith("." + it) }) return true
        // google.fr, www.google.co.uk: a "google" label with one or two labels after it.
        val labels = h.split('.')
        val index = labels.indexOf("google")
        return index >= 0 && labels.size - index in 2..3
    }

    /**
     * The page telemetry the user may block: logging uploads, gen_204 beacons and the account bar's
     * ogads-pa calls. Main-content requests are deliberately absent, so blocking leaves the page
     * usable. Android strips the same set in `WebProxy`.
     */
    val telemetryRuleFilters: List<String> = listOf(
        "^https?://play\\.google\\.com/log",
        "/gen_204",
        "^https?://([a-z0-9-]+\\.)*ogads-pa\\.",
    )

    /** A WKContentRuleList source: every telemetry filter blocks, nothing is redirected. */
    fun telemetryRulesJson(): String {
        val rules = telemetryRuleFilters.joinToString(",") { filter ->
            "{\"trigger\":{\"url-filter\":\"${jsonEscape(filter)}\"},\"action\":{\"type\":\"block\"}}"
        }
        return "[$rules]"
    }

    /**
     * One diagnostics line with the location hygiene of CLAUDE.md applied: URLs keep only the
     * host, coordinate pairs and long decimal runs become [REDACTED], quoted text is dropped. The
     * caller also limits which log categories reach this point.
     */
    fun redactDiagnosticLine(line: String): String {
        var out = line
        out = out.replace(URL_ARG, "$1<redacted>")
        out = out.replace(QUOTED, "\"<redacted>\"")
        out = out.replace(COORDINATE_PAIR, "<coordinates>")
        out = out.replace(LONG_NUMBER, "<number>")
        return out.take(500)
    }

    /**
     * The export a user shares after tapping Export diagnostics. It carries versions, the privacy
     * switches and redacted log lines, never a coordinate, a typed query or a place name.
     */
    fun diagnosticsReport(
        appVersion: String,
        buildNumber: String,
        calibrationVersion: Int,
        flags: List<String>,
        logLines: List<String>,
    ): String {
        val lines = buildString {
            appendLine("Vela iOS diagnostics")
            appendLine("app: $appVersion ($buildNumber)")
            appendLine("calibration: $calibrationVersion")
            appendLine("flags:")
            for (flag in flags) appendLine("  $flag")
            appendLine("log (${logLines.size} lines, redacted):")
            for (line in logLines.takeLast(200)) appendLine("  " + redactDiagnosticLine(line))
        }
        return lines
    }

    private const val REDACTED = "<redacted>"
    private val URL_ARG = Regex("(https?://[^\\s?#\"']+)[^\\s\"']*")
    private val QUOTED = Regex("\"[^\"]{2,}\"")
    private val COORDINATE_PAIR =
        Regex("-?\\d{1,3}\\.\\d{3,}\\s*,\\s*-?\\d{1,3}\\.\\d{3,}")
    private val LONG_NUMBER = Regex("\\b\\d{5,}\\b")

    private fun jsonEscape(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")
}
