package app.vela.core.platform

/**
 * The spoken guidance a drive talks through (SPEC 2.5). `NavSession` hands it the lines its engine
 * builds and two chimes; the voice owns the engine, the queue, the audio focus and the mute.
 * Every call returns at once and may be made from any thread.
 */
interface NavVoice {
    /** Readies the speech engine; [enginePackage] names a system engine (Android), null for the
     *  default. Safe to call again. */
    fun init(enginePackage: String? = null)

    /** Speaks [text]; [interrupt] cuts off what is playing, [ignoreMute] speaks through the mute. */
    fun speak(text: String, interrupt: Boolean = false, ignoreMute: Boolean = false)

    /** Renders [text] ahead of time so its [speak] starts at once; [onDone] runs when it is ready
     *  or cannot be, on any thread. */
    fun prepare(text: String, onDone: () -> Unit = {})

    /** The first line of a drive, spoken when the engine is ready. */
    fun speakOpener(text: String)

    /** Stops speaking and drops what is queued. */
    fun stop()

    /** Two falling tones: the drive left the route. */
    fun reroutingChime()

    /** Two rising tones: a faster route was taken. */
    fun fasterRouteChime()
}
