package app.vela.ios.net

import kotlin.test.Test
import kotlin.test.assertEquals

/** Expected values are `java.net.URLEncoder.encode(s, "UTF-8")` output. */
class FormUrlEncoderTest {
    @Test fun keepsLettersDigitsAndTheFourMarks() {
        assertEquals("coffee", FormUrlEncoder.encode("coffee"))
        assertEquals("AZaz09.-*_", FormUrlEncoder.encode("AZaz09.-*_"))
    }

    @Test fun spaceIsPlusAndPunctuationIsEscaped() {
        assertEquals("coffee+near+me", FormUrlEncoder.encode("coffee near me"))
        assertEquals("a%26b%3Dc%2Bd%2Fe%3Ff%23g", FormUrlEncoder.encode("a&b=c+d/e?f#g"))
        assertEquals("%7E%27%28%29%21%40%24%25%5E%7B%7D%5B%5D%7C%5C%3A%3B%22%3C%3E%2C%60", FormUrlEncoder.encode("~'()!@$%^{}[]|\\:;\"<>,`"))
    }

    @Test fun pbTokensAreEscaped() {
        assertEquals("%211scoffee%214m8%211m3%211d2500.0%212d-122.4194%213d37.7749", FormUrlEncoder.encode("!1scoffee!4m8!1m3!1d2500.0!2d-122.4194!3d37.7749"))
    }

    @Test fun nonAsciiIsUtf8() {
        assertEquals("caf%C3%A9", FormUrlEncoder.encode("café"))
        assertEquals("%E6%97%A5%E6%9C%AC", FormUrlEncoder.encode("日本"))
        assertEquals("%E2%98%95", FormUrlEncoder.encode("\u2615"))
        assertEquals("%F0%9F%98%80", FormUrlEncoder.encode("\uD83D\uDE00"))
        assertEquals("%D7%A7%D7%A4%D7%94", FormUrlEncoder.encode("קפה"))
    }

    @Test fun controlCharactersAndALoneSurrogate() {
        assertEquals("%0A%09%00", FormUrlEncoder.encode("\n\t\u0000"))
        assertEquals("a%3Fb", FormUrlEncoder.encode("a\uD800b"))
        assertEquals("%3F", FormUrlEncoder.encode("\uDC00"))
    }
}
