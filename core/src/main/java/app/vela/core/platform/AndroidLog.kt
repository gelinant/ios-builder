package app.vela.core.platform

/** [Log] over logcat (`android.util.Log`). */
object AndroidLog : Log {
    override fun isLoggable(tag: String, level: LogLevel): Boolean =
        android.util.Log.isLoggable(tag, priority(level))

    override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {
        when (level) {
            LogLevel.DEBUG -> if (error == null) android.util.Log.d(tag, message) else android.util.Log.d(tag, message, error)
            LogLevel.INFO -> if (error == null) android.util.Log.i(tag, message) else android.util.Log.i(tag, message, error)
            LogLevel.WARN -> if (error == null) android.util.Log.w(tag, message) else android.util.Log.w(tag, message, error)
            LogLevel.ERROR -> if (error == null) android.util.Log.e(tag, message) else android.util.Log.e(tag, message, error)
        }
    }

    private fun priority(level: LogLevel): Int = when (level) {
        LogLevel.DEBUG -> android.util.Log.DEBUG
        LogLevel.INFO -> android.util.Log.INFO
        LogLevel.WARN -> android.util.Log.WARN
        LogLevel.ERROR -> android.util.Log.ERROR
    }
}
