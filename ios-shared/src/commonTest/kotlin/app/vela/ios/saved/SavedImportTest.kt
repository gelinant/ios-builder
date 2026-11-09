package app.vela.ios.saved

import app.vela.core.data.NoGoogle
import app.vela.core.platform.Clock
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class ImportMemStores : KeyValueStores {
    val stores = mutableMapOf<String, ImportMemStore>()
    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { ImportMemStore() }
}

private class ImportMemStore : KeyValueStore {
    private val values = mutableMapOf<String, Any?>()
    override fun contains(key: String) = key in values
    override fun getString(key: String, default: String?) = values[key] as String? ?: default
    override fun getLong(key: String, default: Long) = values[key] as Long? ?: default
    override fun getInt(key: String, default: Int) = values[key] as Int? ?: default
    override fun getBoolean(key: String, default: Boolean) = values[key] as Boolean? ?: default
    override fun getFloat(key: String, default: Float) = values[key] as Float? ?: default
    override fun keys() = values.keys.toSet()
    override fun edit(): KeyValueEditor = Editor()

    private inner class Editor : KeyValueEditor {
        private val pending = mutableMapOf<String, Any?>()
        private var clear = false
        private fun put(key: String, value: Any?): KeyValueEditor { pending[key] = value; return this }
        override fun putString(key: String, value: String?) = put(key, value)
        override fun putLong(key: String, value: Long) = put(key, value)
        override fun putInt(key: String, value: Int) = put(key, value)
        override fun putBoolean(key: String, value: Boolean) = put(key, value)
        override fun putFloat(key: String, value: Float) = put(key, value)
        override fun remove(key: String) = put(key, null)
        override fun clear(): KeyValueEditor = also { clear = true }
        override fun apply() {
            if (clear) values.clear()
            values.putAll(pending)
        }
        override fun commit(): Boolean { apply(); return true }
    }
}

private class ImportClock : Clock {
    override fun nowMillis() = 1_000L
    override fun elapsedRealtimeMillis() = 1_000L
    override fun monotonicNanos() = 1_000_000_000L
}

/** The public list captured for `EntityListParserTest`, trimmed to the fields the import reads. */
private val GOOGLE_PAYLOAD = ")]}'\n" + """[[["IP3Ygq3G8_vrjzxUTTtMspZKVmNcrQ",1,[[1]],1,1],4,[2,1,"https://www.google.com/maps/placelists/list/IP3Ygq3G8_vrjzxUTTtMspZKVmNcrQ"],["Keron Cyst","https://example.invalid/avatar","109276248602198135011"],"Import Me to Vela!","Shared test list of random locations",null,null,[[null,[null,null,"",null,"2160 Linden Dr SE, Cedar Rapids, IA 52403",[null,null,41.9923686,-91.6393313],["-8654527782550677995","-8127173087487969012"],"/m/0d98kc"],"Brucemore","I don't wanna go here alone!",null,null,null,[],[[1],["-8654527782550677995","-8127173087487969012"]],[1783559373,332117000],[1783559373,332117000],null,["Keron Cyst","https://example.invalid/avatar"]],[null,[null,null,"Cedar Rapids, IA",null,"Cedar Rapids, IA",[null,null,41.9778795,-91.6656232],["-8654687603621150127","6191992379313413568"],"/m/0t0n5"],"Cedar Rapids","",null,null,null,[],[[1],["-8654687603621150127","6191992379313413568"]],[1783559332,606310000],[1783559332,606310000],null,["Keron Cyst","https://example.invalid/avatar"]]]]]"""

private const val LIST_LINK = "https://www.google.com/maps/placelists/list/IP3Ygq3G8_vrjzxUTTtMspZKVmNcrQ"

/** A minimal list reply with the fields `EntityListParser` reads: title at root[4], items at [8]. */
private fun listPayload(vararg places: String): String =
    ")]}'\n[[null,null,null,[\"Author\"],\"Weekend list\",\"A short list\",null,null,[" +
        places.joinToString(",") + "]]]"

private fun listPlace(name: String, note: String, lat: Double, lng: Double, id: Int): String =
    """[null,[null,null,null,null,"Davis, CA",[null,null,$lat,$lng],["$id","$id"]],"$name","$note"]"""

/** Two My Maps folders: two food pins (one note, one icon) and one sight. */
private const val KML = """<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
  <name>Davis weekend</name>
  <description>Where to eat and walk</description>
  <Style id="icon-1577-FFD600"><IconStyle><color>ff00d6ff</color><Icon><href>https://example.invalid/fork.png</href></Icon></IconStyle></Style>
  <Folder><name>Food</name>
    <Placemark><name>Davis Food Co-op</name><description><![CDATA[<b>Bulk bins</b><br>Saturday market]]></description><styleUrl>#icon-1577-FFD600</styleUrl><Point><coordinates>-121.7405,38.5449,0</coordinates></Point></Placemark>
    <Placemark><name>Mishka's Cafe</name><Point><coordinates>-121.7400,38.5440,0</coordinates></Point></Placemark>
  </Folder>
  <Folder><name>Sights</name>
    <Placemark><name>Tower Bridge</name><description>Gold and green</description><Point><coordinates>-121.5085,38.5816,0</coordinates></Point></Placemark>
  </Folder>
</Document></kml>"""

@OptIn(ExperimentalCoroutinesApi::class)
class SavedImportTest {
    private fun TestScope.store(): SavedStore {
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        return SavedStore(ImportMemStores(), ImportClock(), scope).also { it.start() }
    }

    private fun SavedStore.importGoogle(payload: String = GOOGLE_PAYLOAD, link: String = LIST_LINK) {
        assertTrue(beginGoogleListImport(link))
        googleListProgress(2)
        finishGoogleListImport(payload, link)
    }

    @Test fun aSharedListKeepsItsOrderNamesNotesAndColour() = runTest {
        val store = store()
        store.importGoogle()

        val result = assertNotNull(store.state.value.lastImport)
        assertEquals(SavedImportKind.LIST_ADDED, result.kind)
        assertEquals(2, result.count)
        assertEquals("Import Me to Vela!", result.name)
        val list = store.state.value.lists.single()
        assertEquals("Import Me to Vela!", list.name)
        assertEquals(0xFF1A73E8L, list.color)
        assertEquals(listOf("Brucemore", "Cedar Rapids"), list.places.map { it.name })
        assertEquals("I don't wanna go here alone!", list.places[0].note)
        assertNull(list.places[1].note)
        assertEquals(41.9923686, list.places[0].lat, 1e-9)
        assertEquals("0x87e4f0d5de515615:0x8f367b22f42a390c", list.places[0].featureId)
        assertNull(store.state.value.pendingImport)
    }

    @Test fun importingTheSameListTwiceAsksMergeOrReplaceAndNeverDoubles() = runTest {
        val store = store()
        store.importGoogle()
        val listId = store.state.value.lists.single().id

        // The second import finds its list and writes nothing until the user answers.
        store.importGoogle()
        val pending = assertNotNull(store.state.value.pendingImport)
        assertEquals("GOOGLE", pending.source)
        assertEquals(2, pending.count)
        assertTrue(pending.hasExisting)
        assertEquals(listId, pending.lists.single().existingListId)
        assertEquals(2, store.state.value.lists.single().places.size)

        store.commitPendingImport("MERGE")
        assertNull(store.state.value.pendingImport)
        assertEquals(2, store.state.value.lists.single().places.size)
        assertEquals(listId, store.state.value.lists.single().id)
        assertEquals(SavedImportKind.NOTHING_NEW, store.state.value.lastImport?.kind)

        store.importGoogle()
        assertNotNull(store.state.value.pendingImport)
        store.commitPendingImport("REPLACE")
        assertEquals(2, store.state.value.lists.single().places.size)
        assertEquals(listId, store.state.value.lists.single().id)
    }

    @Test fun mergeAddsOnlyThePlacesTheListDoesNotHold() = runTest {
        val store = store()
        val first = listPayload(
            listPlace("Brucemore", "Bring a friend", 41.9923686, -91.6393313, 1),
            listPlace("Cedar Rapids", "", 41.9778795, -91.6656232, 2),
        )
        val more = listPayload(
            listPlace("Brucemore", "Bring a friend", 41.9923686, -91.6393313, 1),
            listPlace("Cedar Rapids", "", 41.9778795, -91.6656232, 2),
            listPlace("New Cafe", "Third place", 38.5430, -121.7410, 3),
        )
        store.importGoogle(first)
        store.importGoogle(more)
        assertEquals(3, store.state.value.pendingImport?.count)
        store.commitPendingImport("MERGE")
        assertEquals(
            listOf("Brucemore", "Cedar Rapids", "New Cafe"),
            store.state.value.lists.single().places.map { it.name },
        )
        assertEquals("Third place", store.state.value.lists.single().places[2].note)
        assertEquals(1, store.state.value.lastImport?.count)
        assertEquals(3, store.state.value.lists.single().places.size)
    }

    @Test fun foldersBecomeOneListEachWithNotesAndIconHints() = runTest {
        val store = store()
        assertTrue(store.importKmlText(KML, "Davis weekend.kml"))

        assertEquals(listOf("Food", "Sights"), store.state.value.lists.map { it.name })
        val food = store.state.value.lists[0]
        assertEquals(2, food.places.size)
        assertEquals(listOf("Davis Food Co-op", "Mishka's Cafe"), food.places.map { it.name })
        assertEquals("Bulk bins\nSaturday market", food.places[0].note)
        assertEquals("Gold and green", store.state.value.lists[1].places.single().note)
        // The folder's pin color and the icon file the map links are hints, not invented icons.
        assertEquals(0xFFFFD600L, food.color)
        assertEquals(0xFFFFD600L, food.places[0].color)
        assertEquals("https://example.invalid/fork.png", food.places[0].iconUrl)
        assertEquals(38.5816, store.state.value.lists[1].places.single().lat, 1e-6)
        assertEquals(3, store.state.value.lastImport?.count)
        assertEquals(2, store.state.value.lastImport?.lists)
    }

    @Test fun theSameFileTwiceAsksMergeAndKeepsItsLists() = runTest {
        val store = store()
        store.importKmlText(KML, "Davis weekend.kml")
        val ids = store.state.value.lists.map { it.id }

        assertTrue(store.importKmlText(KML, "Davis weekend.kml"))
        val pending = assertNotNull(store.state.value.pendingImport)
        assertEquals("FILE", pending.source)
        assertEquals(2, pending.lists.count { it.existingListId != null })
        assertEquals(ids, store.state.value.lists.map { it.id })
        assertEquals(listOf(2, 1), store.state.value.lists.map { it.places.size })

        store.commitPendingImport("MERGE")
        assertEquals(ids, store.state.value.lists.map { it.id })
        assertEquals(listOf(2, 1), store.state.value.lists.map { it.places.size })
        assertEquals(SavedImportKind.NOTHING_NEW, store.state.value.lastImport?.kind)
    }

    @Test fun malformedPagesFilesAndLinksWriteNothing() = runTest {
        val store = store()

        assertTrue(store.beginGoogleListImport(LIST_LINK))
        store.finishGoogleListImport("<!doctype html><html>consent wall</html>", LIST_LINK)
        assertEquals(SavedImportKind.GOOGLE_CHANGED, store.state.value.lastImport?.kind)
        assertTrue(store.state.value.lists.isEmpty())

        assertTrue(store.beginGoogleListImport(LIST_LINK))
        store.finishGoogleListImport("", LIST_LINK)
        assertEquals(SavedImportKind.GOOGLE_CHANGED, store.state.value.lastImport?.kind)
        assertTrue(store.state.value.lists.isEmpty())

        assertFalse(store.importKmlText("this is not a map", "notes.kml"))
        assertEquals(SavedImportKind.UNREADABLE, store.state.value.lastImport?.kind)
        assertTrue(store.state.value.lists.isEmpty())

        assertFalse(store.importKmlFile(byteArrayOf(0x50, 0x4B, 1, 2, 3), "broken.kmz"))
        assertEquals(SavedImportKind.UNREADABLE, store.state.value.lastImport?.kind)
        assertTrue(store.state.value.lists.isEmpty())

        assertFalse(store.beginGoogleListImport("https://example.com/maps/placelists/list/x"))
        assertEquals(SavedImportKind.LINK_INVALID, store.state.value.lastImport?.kind)
        assertTrue(store.state.value.lists.isEmpty())
    }

    @Test fun withoutGoogleTheLinkIsRefusedAndTheKmlStillImports() = runTest {
        val store = store()
        NoGoogle.enabled = true
        try {
            assertFalse(store.beginGoogleListImport(LIST_LINK))
            assertEquals(SavedImportKind.GOOGLE_DISABLED, store.state.value.lastImport?.kind)
            assertFalse(store.googleListAvailable())
            assertTrue(store.importKmlText(KML, "Davis weekend.kml"))
            assertEquals(listOf("Food", "Sights"), store.state.value.lists.map { it.name })
        } finally {
            NoGoogle.enabled = false
        }
    }

    @Test fun aRunningPageImportLeavesAFileImportBusy() = runTest {
        val store = store()
        assertTrue(store.beginGoogleListImport(LIST_LINK))
        store.importFile("[]", "backup.json")
        assertEquals(SavedImportKind.BUSY, store.state.value.lastImport?.kind)
        store.finishGoogleListImport(GOOGLE_PAYLOAD, LIST_LINK)
        assertEquals(SavedImportKind.LIST_ADDED, store.state.value.lastImport?.kind)
        assertEquals(1, store.state.value.lists.size)
    }

    @Test fun theShortenerFormsAreGoogleLinks() {
        for (link in listOf(
            "https://maps.app.goo.gl/Q4yLjYJHie7kEQKf6",
            "https://goo.gl/maps/abc123",
            "https://maps.google.com/maps/placelists/list/x",
            "https://www.google.com/maps/placelists/list/x",
            "https://www.google.fr/maps/@/data=!3m1!4b1!4m3!11m2!2sabc!3e2",
            "https://consent.google.fr/m?continue=x",
        )) {
            assertTrue(SavedListImport.isGoogleLink(link), link)
        }
        assertFalse(SavedListImport.isGoogleLink("https://example.com/maps/placelists/list/x"))
        assertFalse(SavedListImport.isGoogleLink("maps.app.goo.gl/Q4yLjYJHie7kEQKf6"))
    }

    @Test fun aShortLinkFindsItsListIdInTheResolvedUrlOrThePage() {
        val id = "1dkBeF70N6tuqOyNym67VIshJ3JY"
        val resolved = "https://www.google.fr/maps/@/data=!3m1!4b1!4m3!11m2!2s$id!3e2?entry=tts"
        assertEquals(id, SavedListImport.listIdFromPage(resolved, null))
        assertEquals("", SavedListImport.listId("https://maps.app.goo.gl/Q4yLjYJHie7kEQKf6"))
        assertEquals(id, SavedListImport.listIdFromPage("https://consent.google.fr/m?continue=$resolved", null))
        // The consent gate's continue target has a single `11m` block and no `!3e` marker.
        val afterConsent = "https://www.google.com/maps/@/data=!3m1!4b1!4m2!11m1!2s$id!18m1!1e1"
        assertEquals(id, SavedListImport.listIdFromPage(afterConsent, null))
        assertEquals(id, SavedListImport.listId("https://www.google.com/local/userlists/list/$id?shh=CAE"))
        // The page shape the shortener lands on: the id in the ES5DGURL blob and in the
        // userlists link, no placelists path.
        val html = """<script>window.ES5DGURL='/maps/@/data\x3d!3m1!4b1!4m3!11m2!2s$id!3e2';</script>"""
        assertEquals(id, SavedListImport.listIdFromPage("https://www.google.com/maps/", html))
        val older = """<a href="https://www.google.com/local/userlists/list/$id">"""
        assertEquals(id, SavedListImport.listIdFromPage("https://www.google.com/maps/", older))
        assertEquals("", SavedListImport.listIdFromPage("https://www.google.com/maps/", "<html></html>"))
    }

    @Test fun aNotFoundReplyIsPrivateOrDeletedNotAChangedPage() = runTest {
        val store = store()
        val id = "uRVzP8G9JOf73vXjQWgg3Y8_kwPSUg"
        assertTrue(store.beginGoogleListImport("https://www.google.com/local/userlists/list/$id"))
        store.finishGoogleListImport(")]}'\n[null,null,[4,\"$id\"]]", "https://www.google.com/local/userlists/list/$id")
        assertEquals(SavedImportKind.GOOGLE_PRIVATE, store.state.value.lastImport?.kind)
        assertTrue(store.state.value.lists.isEmpty())

        assertTrue(store.beginGoogleListImport(LIST_LINK))
        store.finishGoogleListImport(")]}'\n[null,null,[9,\"changed\"]]", LIST_LINK)
        assertEquals(SavedImportKind.GOOGLE_CHANGED, store.state.value.lastImport?.kind)
        assertTrue(store.state.value.lists.isEmpty())
    }

    @Test fun theSameListThroughTwoShortLinksAsksMergeOrReplace() = runTest {
        val store = store()
        val id = "1dkBeF70N6tuqOyNym67VIshJ3JY"
        assertTrue(store.beginGoogleListImport("https://maps.app.goo.gl/Q4yLjYJHie7kEQKf6"))
        store.finishGoogleListImport(GOOGLE_PAYLOAD, "https://maps.app.goo.gl/Q4yLjYJHie7kEQKf6", id)

        assertTrue(store.beginGoogleListImport("https://maps.app.goo.gl/BDT7uygAEXfCn9GZ7"))
        store.finishGoogleListImport(GOOGLE_PAYLOAD, "https://maps.app.goo.gl/BDT7uygAEXfCn9GZ7", id)
        val pending = assertNotNull(store.state.value.pendingImport)
        assertEquals(2, pending.count)
        assertTrue(pending.hasExisting)
        assertEquals(1, store.state.value.lists.size)
    }

    @Test fun honestPageFailuresHaveTheirOwnKind() = runTest {
        val store = store()
        val cases = mapOf(
            SavedListImport.FAIL_CONSENT to SavedImportKind.GOOGLE_CONSENT,
            SavedListImport.FAIL_PRIVATE to SavedImportKind.GOOGLE_PRIVATE,
            SavedListImport.FAIL_CHANGED to SavedImportKind.GOOGLE_CHANGED,
            SavedListImport.FAIL_NO_ID to SavedImportKind.GOOGLE_NO_ID,
        )
        for ((payload, kind) in cases) {
            assertTrue(store.beginGoogleListImport(LIST_LINK))
            store.finishGoogleListImport(payload, LIST_LINK)
            assertEquals(kind, store.state.value.lastImport?.kind)
            assertTrue(store.state.value.lists.isEmpty())
        }

        assertTrue(store.beginGoogleListImport(LIST_LINK))
        store.finishGoogleListImport(SavedListImport.FAIL_PLACE, LIST_LINK)
        assertEquals(SavedImportKind.GOOGLE_PLACE, store.state.value.lastImport?.kind)
        assertTrue(store.state.value.lists.isEmpty())
    }
}
