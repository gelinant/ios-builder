package app.vela.core.data

import app.vela.core.model.LatLng
import org.kxml2.io.KXmlParser
import org.xmlpull.v1.XmlPullParser
import java.io.InputStream
import java.time.Instant

/** [NdwBridgeOpenings.parse] as it was before it moved to `:core-common` (kxml2), kept unchanged as
 *  the oracle of `NdwParityTest`. */
object NdwKxmlOracle {
    /** Parse the uncompressed feed. A record without coordinates or a start time is skipped,
     *  and so is one whose opening is ending (`beingTerminated`). */
    fun parse(input: InputStream): List<BridgeOpening> {
        val p = KXmlParser()
        p.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        p.setInput(input, "UTF-8")
        val out = ArrayList<BridgeOpening>()
        var inRecord = false
        var lat: Double? = null
        var lng: Double? = null
        var start: Long? = null
        var end: Long? = null
        var status: String? = null
        var bridge = false
        var text = StringBuilder()
        while (true) {
            when (p.next()) {
                XmlPullParser.END_DOCUMENT -> return out
                XmlPullParser.START_TAG -> {
                    text = StringBuilder()
                    if (local(p.name) == "situationRecord") {
                        inRecord = true
                        lat = null; lng = null; start = null; end = null; status = null; bridge = false
                    }
                }
                XmlPullParser.TEXT -> text.append(p.text)
                XmlPullParser.END_TAG -> {
                    val t = text.toString().trim()
                    when (local(p.name)) {
                        "latitude" -> if (inRecord) lat = t.toDoubleOrNull()
                        "longitude" -> if (inRecord) lng = t.toDoubleOrNull()
                        "overallStartTime" -> if (inRecord) start = instantMs(t)
                        "overallEndTime" -> if (inRecord) end = instantMs(t)
                        "operatorActionStatus" -> if (inRecord) status = t
                        "generalNetworkManagementType" -> if (inRecord) bridge = t == "bridgeSwingInOperation"
                        "situationRecord" -> {
                            inRecord = false
                            val la = lat; val ln = lng; val s = start
                            if (bridge && la != null && ln != null && s != null && status != "beingTerminated") {
                                val openNow = status == "implemented" || status == "beingImplemented"
                                out += BridgeOpening(LatLng(la, ln), s, end, openNow)
                            }
                        }
                    }
                    text = StringBuilder()
                }
            }
        }
    }

    fun local(name: String): String = name.substringAfter(':')

    fun instantMs(s: String): Long? = runCatching { Instant.parse(s).toEpochMilli() }.getOrNull()
}
