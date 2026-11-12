package app.vela.ios.voice

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DirectionsLanguageTest {
    @Test fun normalizesRegionsScriptsAndLegacyCodes() {
        assertEquals("en", DirectionsLanguage.normalize("en-GB"))
        assertEquals("pt", DirectionsLanguage.normalize("pt-PT"))
        assertEquals("pt-br", DirectionsLanguage.normalize("pt_BR"))
        assertEquals("zh", DirectionsLanguage.normalize("zh-Hans"))
        assertEquals("zh-tw", DirectionsLanguage.normalize("zh-Hant"))
        assertEquals("zh-tw", DirectionsLanguage.normalize("zh-HK"))
        assertEquals("he", DirectionsLanguage.normalize("iw"))
        assertEquals("", DirectionsLanguage.normalize("  "))
    }

    @Test fun explicitChoiceWinsOverTheAppLanguage() {
        assertEquals("fr", DirectionsLanguage.effectiveTag("fr", appTag = "de", systemTag = "de-DE"))
        assertEquals("pt-br", DirectionsLanguage.effectiveTag("pt-BR", appTag = "en", systemTag = "en-US"))
    }

    @Test fun emptyChoiceFollowsTheAppLanguageThenTheSystem() {
        assertEquals("de", DirectionsLanguage.effectiveTag("", appTag = "de", systemTag = "en-US"))
        assertEquals("fr", DirectionsLanguage.effectiveTag(null, appTag = "", systemTag = "fr-FR"))
    }

    @Test fun unsupportedLanguagesFallBackToEnglish() {
        assertEquals("en", DirectionsLanguage.effectiveTag("", appTag = "ar", systemTag = "ar"))
        assertEquals("en", DirectionsLanguage.effectiveTag("ko", appTag = "ar", systemTag = "ar"))
        // A supported app language still wins over an unreadable explicit value.
        assertEquals("it", DirectionsLanguage.effectiveTag("ko", appTag = "it", systemTag = "ar"))
    }

    @Test fun registryPartsKeepPortugueseAndChineseApart() {
        assertEquals(NavLanguageParts("pt", "BR", ""), DirectionsLanguage.parts("pt-br"))
        assertEquals(NavLanguageParts("pt", "", ""), DirectionsLanguage.parts("pt"))
        assertEquals(NavLanguageParts("zh", "TW", "Hant"), DirectionsLanguage.parts("zh-tw"))
        assertEquals(NavLanguageParts("zh", "", ""), DirectionsLanguage.parts("zh"))
        assertEquals(NavLanguageParts("en", "", ""), DirectionsLanguage.parts("ar"))
    }

    @Test fun neuralVoiceAvailabilityMatchesTheCatalog() {
        assertTrue(DirectionsLanguage.hasNeuralVoice("fr"))
        assertTrue(DirectionsLanguage.hasNeuralVoice("pt-br"))
        assertFalse(DirectionsLanguage.hasNeuralVoice("ja"))
        assertFalse(DirectionsLanguage.hasNeuralVoice("he"))
    }

    @Test fun labelsAndVoiceSearchLanguage() {
        assertEquals("Français", DirectionsLanguage.label("fr"))
        assertEquals("Português (Brasil)", DirectionsLanguage.label("pt-BR"))
        assertEquals("English", DirectionsLanguage.label(""))
        assertEquals("pt", DirectionsLanguage.appLanguage("pt-BR"))
        assertEquals("zh", DirectionsLanguage.appLanguage("zh-Hant"))
        assertEquals("ar", DirectionsLanguage.appLanguage("ar"))
    }
}
