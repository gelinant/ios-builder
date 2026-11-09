package app.vela.ios.nav

import app.vela.core.model.ManeuverType
import app.vela.core.model.TravelMode
import app.vela.core.platform.Clock
import app.vela.core.platform.Log
import app.vela.core.platform.LogLevel
import app.vela.core.platform.NavHaptics
import app.vela.core.platform.NavVoice

/** Inert defaults for tests and for the short graph-startup window before Swift injects Apple. */
internal object InertNavVoice : NavVoice {
    override fun init(enginePackage: String?) {}
    override fun speak(text: String, interrupt: Boolean, ignoreMute: Boolean) {}
    override fun prepare(text: String, onDone: () -> Unit) = onDone()
    override fun speakOpener(text: String) {}
    override fun stop() {}
    override fun reroutingChime() {}
    override fun fasterRouteChime() {}
}

internal object InertNavHaptics : NavHaptics {
    override fun cue(type: ManeuverType, approaching: Boolean, mode: TravelMode) {}
    override fun reroute(mode: TravelMode) {}
}

internal object InertClock : Clock {
    override fun nowMillis() = 0L
    override fun elapsedRealtimeMillis() = 0L
    override fun monotonicNanos() = 0L
}

internal object InertLog : Log {
    override fun isLoggable(tag: String, level: LogLevel) = false
    override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {}
}
