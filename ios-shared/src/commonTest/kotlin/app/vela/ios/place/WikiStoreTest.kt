package app.vela.ios.place

import app.vela.core.platform.Cancellable
import app.vela.core.platform.Clock
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.VelaHttp
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * W-1 without a network: the Wikidata fields, the cleaned Wikivoyage extract, the language
 * fallback, the 24-hour cache, the absence of images and the no-request cases.
 */
class WikiStoreTest {
    private val start = 1_700_000_000_000L
    private var now = start

    private val wikidata = """
        {"entities":{"Q90":{
          "id":"Q90",
          "labels":{"de":{"language":"de","value":"Paris"},"en":{"language":"en","value":"Paris"}},
          "claims":{
            "P1082":[{"rank":"normal","mainsnak":{"snaktype":"value","datavalue":{"value":{"amount":"+2145906","unit":"1"},"type":"quantity"}}}],
            "P1619":[{"rank":"normal","mainsnak":{"snaktype":"value","datavalue":{"value":{"time":"+1889-03-31T00:00:00Z","precision":11},"type":"time"}}}],
            "P856":[{"rank":"normal","mainsnak":{"snaktype":"value","datavalue":{"value":"https://www.paris.fr/","type":"string"}}}],
            "P625":[{"rank":"normal","mainsnak":{"snaktype":"value","datavalue":{"value":{"latitude":48.85666666666667,"longitude":2.352222222222222},"type":"globecoordinate"}}}]
          },
          "sitelinks":{
            "frwikivoyage":{"site":"frwikivoyage","title":"Paris"},
            "enwikivoyage":{"site":"enwikivoyage","title":"Paris"},
            "dewiki":{"site":"dewiki","title":"Paris"}
          }
        }}}
    """.trimIndent()

    private val parisHtml = """
        <!DOCTYPE html><html><body><div class="mw-parser-output">
        <table class="infobox"><tr><td>infobox</td></tr></table>
        <p><b>Paris</b> is the capital of <a href="/wiki/France">France</a> and its largest city.
        It sits on the Seine and is one of the most visited destinations in Europe.</p>
        <figure><img src="https://upload.wikimedia.org/eiffel.jpg"><figcaption>The tower</figcaption></figure>
        <p>The city is divided into twenty arrondissements, each with its own character and
        a handful of sights worth the walk from the river.</p>
        <h2>Districts</h2><p>This heading and what follows must not enter the lead extract.</p>
        </div></body></html>
    """.trimIndent()

    @Test fun wikidataFieldsAndOpeningDate() = runTest {
        val http = FakeHttp { request -> if (request.url.contains("wbgetentities")) ok(wikidata) else ok(parisHtml) }
        val knowledge = WikiStore(http, MemStores(), locale("en"), clock()).knowledge("wikidata:Q90", true)
        assertNotNull(knowledge)
        val facts = assertNotNull(knowledge.facts)
        assertEquals("Q90", facts.wikidataId)
        assertEquals(2_145_906L, facts.population)
        assertEquals("1889-03-31", facts.opened)
        assertEquals("https://www.paris.fr/", facts.website)
        assertEquals(48.85666666666667, facts.latitude)
        assertEquals("Paris", facts.label)
        assertTrue(facts.fieldCount >= 2, "the section needs at least two fields")
        assertEquals(4, knowledge.fieldCount)
        assertEquals("en", facts.language)
    }

    @Test fun wikivoyageExtractHasNoImages() = runTest {
        val http = FakeHttp { request -> if (request.url.contains("wbgetentities")) ok(wikidata) else ok(parisHtml) }
        val article = assertNotNull(
            WikiStore(http, MemStores(), locale("en"), clock())
                .knowledge("wikidata:Q90", true)?.article)
        assertTrue(article.extract.contains("capital of France"))
        assertTrue(article.extract.contains("twenty arrondissements"))
        assertFalse(article.extract.contains("<"), "markup leaked into the extract")
        assertFalse(article.extract.contains("upload.wikimedia.org"), "an image URL leaked")
        assertFalse(article.extract.contains("tower"), "the figure caption leaked")
        assertFalse(article.extract.contains("Districts"), "a section heading entered the lead")
        assertTrue(article.images.isEmpty(), "W-1 shows no image")
        assertFalse(WikiKnowledge(article = article).hasImages)
        assertEquals("https://en.wikivoyage.org/wiki/Paris", article.url)
    }

    @Test fun languageFallbackEndsOnEnglishForBothSources() = runTest {
        val englishOnly = """
            {"entities":{"Q90":{
              "labels":{"en":{"language":"en","value":"Paris"}},
              "claims":{"P856":[{"rank":"normal","mainsnak":{"snaktype":"value","datavalue":{"value":"https://www.paris.fr/","type":"string"}}}]},
              "sitelinks":{"enwikivoyage":{"site":"enwikivoyage","title":"Paris"}}
            }}}
        """.trimIndent()
        val http = FakeHttp { request -> if (request.url.contains("wbgetentities")) ok(englishOnly) else ok(parisHtml) }
        val knowledge = assertNotNull(
            WikiStore(http, MemStores(), locale("de-DE", "de"), clock())
                .knowledge("wikidata:Q90", true))
        assertEquals("en", knowledge.facts?.language)
        assertEquals("en", knowledge.article?.language)
        val entityUrl = http.requests.first().url
        assertTrue(entityUrl.contains("languages=de%7Cen"), entityUrl)
        assertTrue(entityUrl.contains("sitefilter=dewikivoyage%7Cenwikivoyage"), entityUrl)
    }

    @Test fun preferredLanguageWinsWhenTheSitelinkExists() = runTest {
        val french = """
            {"entities":{"Q90":{
              "labels":{"fr":{"language":"fr","value":"Paris"}},
              "claims":{"P625":[{"rank":"normal","mainsnak":{"snaktype":"value","datavalue":{"value":{"latitude":48.85,"longitude":2.35},"type":"globecoordinate"}}}]},
              "sitelinks":{"frwikivoyage":{"site":"frwikivoyage","title":"Paris"},"enwikivoyage":{"site":"enwikivoyage","title":"Paris"}}
            }}}
        """.trimIndent()
        val http = FakeHttp { request ->
            if (request.url.contains("wbgetentities")) ok(french)
            else ok("<div><p>Paris est la capitale de la France et la plus grande ville du pays.</p></div>")
        }
        val knowledge = assertNotNull(
            WikiStore(http, MemStores(), locale("fr-FR", "fr"), clock())
                .knowledge("Q90", true))
        assertEquals("fr", knowledge.facts?.language)
        assertEquals("fr", knowledge.article?.language)
        assertTrue(knowledge.article?.extract?.contains("capitale") == true)
        assertTrue(http.requests.last().url.contains("/wikivoyage/fr/page/Paris/html"))
    }

    @Test fun twentyFourHourCacheMakesOneRequestPerSource() = runTest {
        val http = FakeHttp { request -> if (request.url.contains("wbgetentities")) ok(wikidata) else ok(parisHtml) }
        val store = WikiStore(http, MemStores(), locale("en"), clock())
        store.knowledge("wikidata:Q90", true)
        assertEquals(2, http.requests.size)
        now = start + WikiStore.CACHE_MS - 1_000L
        store.knowledge("wikidata:Q90", true)
        assertEquals(2, http.requests.size, "inside 24 h the cache answers both sources")
        now = start + WikiStore.CACHE_MS + 1_000L
        store.knowledge("wikidata:Q90", true)
        assertEquals(4, http.requests.size, "past 24 h each source is fetched again")
    }

    @Test fun noRequestWithoutIdOrWhileTheLayerIsOff() = runTest {
        val http = FakeHttp { ok(wikidata) }
        val store = WikiStore(http, MemStores(), locale("en"), clock())
        assertNull(store.knowledge("google:0x0:0x1", true), "no Wikidata id, no section")
        assertNull(store.knowledge("osm:node/42", true), "an OSM id names no Wikidata item")
        assertNull(store.knowledge("wikidata:Q90", false), "the layer is off, so no request")
        assertTrue(http.requests.isEmpty(), "a skipped load must not touch the network")
        assertEquals("Q90", store.wikidataId(" wikidata:q90 "))
        assertEquals("Q90", store.wikidataId("Q90"))
        assertNull(store.wikidataId("Q90x"))
    }

    @Test fun layerKeepsOnlyGeolocatedArticlesInTheViewport() = runTest {
        val layerJson = """
            {"entities":{
              "Q62":{"id":"Q62","claims":{"P625":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"latitude":37.775,"longitude":-122.419},"type":"globecoordinate"}}}]},"sitelinks":{"enwikivoyage":{"title":"San Francisco"}}},
              "Q90":{"id":"Q90","claims":{"P625":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"latitude":48.8566,"longitude":2.3522},"type":"globecoordinate"}}}]},"sitelinks":{"enwikivoyage":{"title":"Paris"}}},
              "Q999999":{"id":"Q999999","claims":{},"sitelinks":{"enwikivoyage":{"title":"Nowhere"}}}
            }}
        """.trimIndent()
        val http = FakeHttp { ok(layerJson) }
        val store = WikiStore(http, MemStores(), locale("en"), clock())
        val near = store.articlesNear(south = 37.0, west = -123.0, north = 38.0, east = -122.0)
        assertEquals(listOf("San Francisco"), near.map { it.title })
        assertEquals(1, http.requests.size)
        assertTrue(near.first().url.startsWith("https://en.wikivoyage.org/wiki/"))
        val second = store.articlesNear(south = 48.0, west = 2.0, north = 49.0, east = 3.0)
        assertEquals(listOf("Paris"), second.map { it.title })
        assertEquals(1, http.requests.size, "the layer payload is cached for 24 h")
    }

    private fun clock() = object : Clock {
        override fun nowMillis(): Long = now
        override fun elapsedRealtimeMillis(): Long = now
        override fun monotonicNanos(): Long = now * 1_000_000L
    }

    private fun locale(tag: String, language: String = "en"): PlatformLocale = object : PlatformLocale {
        override fun defaultTag() = tag
        override fun defaultLanguage() = language
        override fun preferredTags() = listOf(tag)
        override fun systemTags() = listOf(tag)
    }

    private fun ok(body: String) = HttpResponse(
        200, emptyList(), body.encodeToByteArray(), "https://example.test/")
}

/** A [VelaHttp] that answers from [reply] at once and records every request. */
private class FakeHttp(private val reply: (HttpRequest) -> HttpResponse) : VelaHttp {
    private val lock = SynchronizedObject()
    private val recorded = mutableListOf<HttpRequest>()

    val requests: List<HttpRequest> get() = synchronized(lock) { recorded.toList() }

    override fun execute(
        request: HttpRequest,
        callback: (HttpResponse?, Throwable?) -> Unit,
    ): Cancellable {
        synchronized(lock) { recorded += request }
        try {
            callback(reply(request), null)
        } catch (e: Exception) {
            callback(null, e)
        }
        return Cancellable { }
    }
}

private class MemStores : KeyValueStores {
    private val stores = mutableMapOf<String, MemStore>()
    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { MemStore() }
}

private class MemStore : KeyValueStore {
    private val values = mutableMapOf<String, Any>()

    override fun contains(key: String) = key in values
    override fun getString(key: String, default: String?) = values[key] as? String ?: default
    override fun getLong(key: String, default: Long) = values[key] as? Long ?: default
    override fun getInt(key: String, default: Int) = values[key] as? Int ?: default
    override fun getBoolean(key: String, default: Boolean) = values[key] as? Boolean ?: default
    override fun getFloat(key: String, default: Float) = values[key] as? Float ?: default
    override fun keys(): Set<String> = values.keys
    override fun edit(): KeyValueEditor = Editor()

    private inner class Editor : KeyValueEditor {
        private var clear = false
        private val changes = mutableListOf<Pair<String, Any?>>()

        override fun putString(key: String, value: String?) = put(key, value)
        override fun putLong(key: String, value: Long) = put(key, value)
        override fun putInt(key: String, value: Int) = put(key, value)
        override fun putBoolean(key: String, value: Boolean) = put(key, value)
        override fun putFloat(key: String, value: Float) = put(key, value)
        override fun remove(key: String) = put(key, null)
        override fun clear(): KeyValueEditor = also { clear = true }

        private fun put(key: String, value: Any?): KeyValueEditor = also { changes += key to value }

        override fun apply() { commit() }
        override fun commit(): Boolean {
            if (clear) values.clear()
            for ((key, value) in changes) {
                if (value == null) values.remove(key) else values[key] = value
            }
            return true
        }
    }
}
