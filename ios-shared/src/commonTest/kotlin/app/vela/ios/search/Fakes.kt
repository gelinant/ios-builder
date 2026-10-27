package app.vela.ios.search

import app.vela.core.platform.Cancellable
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.VelaHttp

/** A [VelaHttp] that answers from [reply] at once and records every request. */
class FakeHttp(private val reply: (HttpRequest) -> HttpResponse) : VelaHttp {
    val requests = mutableListOf<HttpRequest>()

    override fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
        requests += request
        try {
            callback(reply(request), null)
        } catch (e: Exception) {
            callback(null, e)
        }
        return Cancellable { }
    }
}

class FakeLocale(private val tag: String, private val language: String = tag.substringBefore('-')) : PlatformLocale {
    override fun defaultTag() = tag
    override fun defaultLanguage() = language
    override fun preferredTags() = listOf(tag)
    override fun systemTags() = listOf(tag)
}

fun ok(text: String, url: String = "https://www.google.com/") = HttpResponse(200, emptyList(), text.encodeToByteArray(), url)

/**
 * A search reply in the shape `SearchParser` reads (`Calibration.DEFAULT_PATHS`): the anti-JSON
 * guard, then `root[64]` holding `[_, placeNode]` entries. Coffee shops around the San Francisco
 * fixture point; [count] entries from [first] on.
 */
object SearchFixture {
    fun reply(count: Int, first: Int = 0): String {
        val entries = (first until first + count).joinToString(",") { i -> entry(i) }
        val root = (0 until 64).joinToString(",") { "null" } + ",[$entries]"
        return ")]}'\n[$root]"
    }

    private fun entry(i: Int): String {
        val node = arrayOfNulls<String>(40)
        node[4] = "[null,null,\"$1-10\",null,null,null,null,${4.0 + (i % 10) / 10.0},${100 + i}]"
        node[9] = "[null,null,${37.7749 + i * 0.001},${-122.4194 + i * 0.001}]"
        node[10] = "\"0x8085${i.toString(16).padStart(4, '0')}:0x${(i + 1).toString(16)}\""
        node[11] = "\"Fixture Coffee $i\""
        node[13] = "[\"Coffee shop\"]"
        node[39] = "\"${100 + i} Market St, San Francisco, CA 94103\""
        return "[null,[${node.joinToString(",") { it ?: "null" }}]]"
    }
}
