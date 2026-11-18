package app.vela.ios.privacy

import kotlin.concurrent.Volatile

/**
 * The process holders behind the two per-feature switches SET-PRIVACY adds, the iOS counterparts of
 * Android's `MapPoiPrefs.lookupTappedPlaces` and `GoogleFree.resolveLinks`.
 *
 * `SettingsStore` does not know these keys; the Swift `PrivacySettings` writes them into the same
 * settings suite (same key names as Android) and calls [apply] before the first request of a
 * session, so a store that runs on another thread reads the value the user chose.
 */
object GoogleUses {
    /** Off: tapping a place on the map keeps Vela's own row and asks Google nothing. */
    @Volatile
    var lookupTappedPlaces: Boolean = true
        private set

    /** With Google off: may one cookieless request ask Google's shortener where a link points. */
    @Volatile
    var resolveShortLinks: Boolean = true
        private set

    fun apply(lookupTappedPlaces: Boolean, resolveShortLinks: Boolean) {
        this.lookupTappedPlaces = lookupTappedPlaces
        this.resolveShortLinks = resolveShortLinks
    }

    /** Back to the defaults, for tests and a clean Debug launch. */
    fun reset() = apply(lookupTappedPlaces = true, resolveShortLinks = true)
}
