package app.vela.core.location

/** One point of a recorded trip, replayed as a synthetic location (`LocationProvider` on Android). */
data class ReplayFix(val lat: Double, val lng: Double, val t: Long, val bearing: Float, val speed: Float)
