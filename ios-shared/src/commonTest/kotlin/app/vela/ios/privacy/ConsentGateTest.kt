package app.vela.ios.privacy

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** SET-PRIVACY: no Google request leaves the phone before the first-run answer. */
class ConsentGateTest {
    @Test fun theQuestionIsAskedUntilItIsAnswered() {
        assertTrue(PrivacyConsent.needsConsent(false))
        assertFalse(PrivacyConsent.needsConsent(true))
    }

    @Test fun googleIsBlockedBeforeConsentWhateverTheSwitchSays() {
        assertFalse(PrivacyConsent.googleAllowed(welcomeDone = false, noGoogle = false))
        assertFalse(PrivacyConsent.googleAllowed(welcomeDone = false, noGoogle = true))
    }

    @Test fun googleFollowsTheAnswerAfterConsent() {
        assertTrue(PrivacyConsent.googleAllowed(welcomeDone = true, noGoogle = false))
        assertFalse(PrivacyConsent.googleAllowed(welcomeDone = true, noGoogle = true))
    }

    @Test fun thePerFeatureHoldersCarryTheUsersAnswer() {
        GoogleUses.reset()
        assertTrue(GoogleUses.lookupTappedPlaces)
        assertTrue(GoogleUses.resolveShortLinks)
        GoogleUses.apply(lookupTappedPlaces = false, resolveShortLinks = false)
        assertFalse(GoogleUses.lookupTappedPlaces)
        assertFalse(GoogleUses.resolveShortLinks)
        GoogleUses.apply(lookupTappedPlaces = true, resolveShortLinks = true)
        assertTrue(GoogleUses.lookupTappedPlaces)
        GoogleUses.reset()
        assertEquals(true, GoogleUses.resolveShortLinks)
    }
}
