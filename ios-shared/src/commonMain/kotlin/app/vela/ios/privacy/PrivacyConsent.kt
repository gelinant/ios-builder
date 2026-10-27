package app.vela.ios.privacy

/**
 * The first-run consent gate (SET-PRIVACY), with no platform type so JVM tests can hold it.
 *
 * Android asks the same question on its welcome screen and remembers the answer with
 * `Onboarding.welcomeDone` (`welcome_done` in `vela_onboarding`); the Google answer itself is
 * Android's `GoogleFree` preference. iOS keeps both keys in its settings suite and, like Android,
 * composes nothing useful behind the question: [googleAllowed] is false until the user answered,
 * whatever the Google switch says.
 */
object PrivacyConsent {
    /** Android's `Onboarding.welcomeDone` key, set once the first-run question is answered. */
    const val KEY_WELCOME_DONE = "welcome_done"

    /** iOS's key for Android's `GoogleFree` switch ("Use Vela without Google"). */
    const val KEY_NO_GOOGLE = "ios_google_disabled"

    fun needsConsent(welcomeDone: Boolean): Boolean = !welcomeDone

    /** Whether a Google request may leave the phone: only after the answer, and only with Google on. */
    fun googleAllowed(welcomeDone: Boolean, noGoogle: Boolean): Boolean = welcomeDone && !noGoogle
}
