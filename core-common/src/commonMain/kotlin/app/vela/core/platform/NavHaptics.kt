package app.vela.core.platform

import app.vela.core.model.ManeuverType
import app.vela.core.model.TravelMode

/** The vibration cues of a drive (SPEC 2.5). Each call returns at once; the implementation decides
 *  per [TravelMode] whether cues are on. */
interface NavHaptics {
    /** A turn cue: [approaching] for the warning before it, false at the turn itself. */
    fun cue(type: ManeuverType, approaching: Boolean, mode: TravelMode)

    /** The drive left the route. */
    fun reroute(mode: TravelMode)
}
