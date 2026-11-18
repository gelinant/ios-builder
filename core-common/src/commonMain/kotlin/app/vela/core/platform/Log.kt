package app.vela.core.platform

/** The level of a [Log] line, in Android's order. */
enum class LogLevel { DEBUG, INFO, WARN, ERROR }

/**
 * The platform log (SPEC "Platform seams"). Android writes to logcat (`android.util.Log`); iOS to
 * the unified log.
 *
 * A log line never carries a coordinate, typed text or a place name (CLAUDE.md, Location
 * hygiene). Tags are the existing `Vela*` tags.
 */
interface Log {
    /** Whether a line at [level] under [tag] would be written (`Log.isLoggable` on Android). */
    fun isLoggable(tag: String, level: LogLevel): Boolean

    /** Writes one line. [error], when given, is printed with its stack trace. */
    fun log(level: LogLevel, tag: String, message: String, error: Throwable?)
}

fun Log.d(tag: String, message: String) = log(LogLevel.DEBUG, tag, message, null)
fun Log.i(tag: String, message: String) = log(LogLevel.INFO, tag, message, null)
fun Log.w(tag: String, message: String, error: Throwable? = null) = log(LogLevel.WARN, tag, message, error)
fun Log.e(tag: String, message: String, error: Throwable? = null) = log(LogLevel.ERROR, tag, message, error)
