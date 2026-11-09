package app.vela.core.diag

/**
 * Where the data sources leave a diagnostics breadcrumb. Android: `DiagLog` (opt-in, local only,
 * exported by the user).
 */
interface DiagSink {
    /** Append a breadcrumb; cheap and safe from any thread. [detail] should stay small. */
    fun record(kind: String, summary: String, detail: String? = null)

    companion object {
        /** Records nothing. */
        val NONE: DiagSink = object : DiagSink {
            override fun record(kind: String, summary: String, detail: String?) {}
        }
    }
}
