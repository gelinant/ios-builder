package app.vela.core.util

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class XmlPullTest {

    private fun events(xml: String): List<String> {
        val p = XmlPull(xml)
        val out = ArrayList<String>()
        while (true) {
            when (p.next()) {
                XmlPull.END_DOCUMENT -> return out
                XmlPull.START_TAG -> out += "<${p.name}"
                XmlPull.END_TAG -> out += "/${p.name}"
                XmlPull.TEXT -> if (p.text.isNotBlank()) out += "'${p.text}'"
            }
        }
    }

    @Test fun elementsTextAndEntities() {
        assertEquals(
            listOf("<a:root", "<b", "'x & y <A'", "/b", "<c", "/c", "<d", "'<raw>'", "/d", "/a:root"),
            events("""<?xml version="1.0"?><!DOCTYPE r [<!ENTITY e "v">]><!-- c --><a:root k='1 > 0'><b>x &amp; y &lt;&#65;</b><c/><d><![CDATA[<raw>]]></d></a:root>"""),
        )
    }

    @Test fun brokenDocumentsThrowAndACutOneEnds() {
        assertFailsWith<IllegalArgumentException> { events("<a><b></a>") }
        assertEquals(listOf("<a"), events("<a>"))
        assertFailsWith<IllegalArgumentException> { events("<a>&nope;</a>") }
    }
}
