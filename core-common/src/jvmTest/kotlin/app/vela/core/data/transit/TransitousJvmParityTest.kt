package app.vela.core.data.transit

import app.vela.core.data.ClockFormat
import app.vela.core.model.LatLng
import org.json.JSONArray
import org.json.JSONObject
import java.time.ZoneId
import java.util.TimeZone
import kotlin.random.Random
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The common [Transitous] against [TransitousOracle], the code it replaced: the plan reply on the
 * fixture and on variants of it, across process time zones and both clocks; the ISO parse, the
 * `time` parameter and the clock text native uses, against the JDK.
 */
class TransitousJvmParityTest {

    private val fixture = javaClass.getResourceAsStream("/transitous/plan-davis-sacramento.json")!!.bufferedReader().readText()
    private val origin = LatLng(38.5449, -121.7405)
    private val dest = LatLng(38.5816, -121.4944)
    private val savedZone: TimeZone = TimeZone.getDefault()

    @AfterTest fun reset() {
        ClockFormat.use24h = false
        TimeZone.setDefault(savedZone)
    }

    private fun legs(root: JSONObject): List<JSONObject> {
        val out = ArrayList<JSONObject>()
        val its = root.getJSONArray("itineraries")
        for (i in 0 until its.length()) {
            val legs = its.getJSONObject(i).getJSONArray("legs")
            for (k in 0 until legs.length()) out += legs.getJSONObject(k)
        }
        return out
    }

    private fun stops(leg: JSONObject): List<JSONObject> = buildList {
        leg.optJSONObject("from")?.let { add(it) }
        leg.optJSONObject("to")?.let { add(it) }
        leg.optJSONArray("intermediateStops")?.let { a -> for (i in 0 until a.length()) a.optJSONObject(i)?.let { add(it) } }
    }

    /** The fixture, and the same reply bent the ways a feed can differ: no zones, unknown zones,
     *  realtime moves, numbers as strings, missing fields, other modes and shapes. */
    private fun variants(): List<Pair<String, String>> {
        val r = Random(17)
        val out = mutableListOf("fixture" to fixture)
        fun variant(name: String, edit: (JSONObject) -> Unit) {
            val root = JSONObject(fixture)
            edit(root)
            out += name to root.toString()
        }
        variant("no zones") { root -> legs(root).forEach { l -> stops(l).forEach { it.remove("tz") } } }
        variant("unknown zone") { root -> legs(root).forEach { l -> stops(l).forEach { it.put("tz", "Mars/Base") } } }
        variant("other zones") { root -> legs(root).forEachIndexed { i, l -> stops(l).forEach { it.put("tz", listOf("Europe/Paris", "Asia/Kolkata", "Australia/Lord_Howe", "UTC")[i % 4]) } } }
        variant("late and early") { root ->
            legs(root).forEach { l ->
                l.put("realTime", true)
                l.put("scheduledStartTime", "2026-09-28T22:30:00Z")
                stops(l).forEach { s -> s.put("departure", "2026-09-28T22:3${r.nextInt(10)}:00Z"); s.put("arrival", "2026-09-28T23:1${r.nextInt(10)}:00Z") }
            }
        }
        variant("strings for numbers") { root ->
            root.getJSONArray("itineraries").let { its -> for (i in 0 until its.length()) its.getJSONObject(i).put("duration", "2580.7") }
            legs(root).forEach { l ->
                l.put("duration", l.optLong("duration").toString())
                l.put("realTime", "TRUE")
                l.optJSONObject("legGeometry")?.put("precision", "6.9")
                stops(l).forEach { s -> s.put("lat", s.optDouble("lat").toString()); s.put("cancelled", "true") }
            }
        }
        variant("fields missing") { root ->
            legs(root).forEach { l ->
                for (k in listOf("duration", "routeShortName", "headsign", "legGeometry", "startTime")) l.remove(k)
                l.optJSONObject("from")?.remove("lat")
            }
            root.getJSONArray("itineraries").getJSONObject(0).remove("endTime")
        }
        variant("other modes and colors") { root ->
            legs(root).forEachIndexed { i, l ->
                l.put("mode", listOf("BUS", "SUBWAY", "FERRY", "BIKE", "TRAM", "AIRPLANE")[i % 6])
                l.put("routeColor", if (i % 2 == 0) "#ff0000" else "00ff00")
                l.put("displayName", "D$i"); l.put("routeLongName", "Long $i"); l.put("routeShortName", if (i % 3 == 0) " " else "S$i")
                l.put("agencyName", if (i == 0) "" else "Agency $i")
            }
        }
        variant("shapes") { root ->
            legs(root).forEachIndexed { i, l ->
                val g = l.optJSONObject("legGeometry") ?: JSONObject().also { l.put("legGeometry", it) }
                when (i % 4) {
                    0 -> g.put("precision", 9)
                    1 -> g.put("points", "")
                    2 -> g.put("points", "not a polyline at all")
                    else -> g.put("precision", 5)
                }
            }
        }
        variant("not objects") { root ->
            val its = root.getJSONArray("itineraries")
            its.put(3)
            its.getJSONObject(0).getJSONArray("legs").getJSONObject(1).put("intermediateStops", JSONArray(listOf(1, JSONObject().put("name", "x"))))
        }
        variant("walk only") { root ->
            val its = root.getJSONArray("itineraries")
            for (i in 0 until its.length()) its.getJSONObject(i).put("legs", JSONArray().put(JSONObject().put("mode", "WALK").put("duration", 60)))
        }
        out += "no itineraries" to """{"itineraries":[]}"""
        out += "error" to """{"error":"x"}"""
        out += "array" to """[1,2]"""
        out += "broken" to """{"itineraries":[{"legs":["""
        return out
    }

    @Test fun planRepliesParseAsTheOracle() {
        var compared = 0
        for (zone in listOf("America/Los_Angeles", "Europe/Paris", "Asia/Kolkata", "Pacific/Chatham")) {
            TimeZone.setDefault(TimeZone.getTimeZone(zone))
            for (use24h in listOf(false, true)) {
                ClockFormat.use24h = use24h
                for ((name, json) in variants()) {
                    val old = runCatching { TransitousOracle.parsePlan(json, origin, dest) }
                    val new = runCatching { Transitous.parsePlan(json, origin, dest) }
                    assertEquals(old.isSuccess, new.isSuccess, "$name in $zone, 24h $use24h")
                    assertEquals(old.getOrNull().toString(), new.getOrNull().toString(), "$name in $zone, 24h $use24h")
                    compared++
                }
            }
        }
        assertTrue(compared > 100)
    }

    @Test fun legShapesPickAsTheOracle() {
        val root = JSONObject(fixture)
        val rides = legs(root).filter { it.optString("mode") != "WALK" }
        assertTrue(rides.isNotEmpty())
        for ((name, json) in variants()) {
            for (ride in rides + listOf(JSONObject().put("from", JSONObject().put("lat", 38.0).put("lon", -121.0)).put("to", JSONObject().put("lat", 38.1).put("lon", -121.1)))) {
                val a = LatLng(ride.getJSONObject("from").optDouble("lat"), ride.getJSONObject("from").optDouble("lon"))
                val b = LatLng(ride.getJSONObject("to").optDouble("lat"), ride.getJSONObject("to").optDouble("lon"))
                val old = runCatching { TransitousOracle.pickLegShape(json, a, b) }
                val new = runCatching { Transitous.pickLegShape(json, a, b) }
                assertEquals(old.isSuccess, new.isSuccess, name)
                assertEquals(old.getOrNull(), new.getOrNull(), name)
            }
        }
    }

    @Test fun isoTimesAndTheTimeParameterMatchJavaTime() {
        val r = Random(5)
        val epochs = List(20_000) { r.nextLong(-2_000_000_000L, 4_000_000_000L) } + listOf(0L, -1L, 1_790_634_840L, 253_402_300_799L)
        for (e in epochs) {
            val text = TransitousOracle.instantText(e)
            assertEquals(text, Transitous.instantText(e), "$e")
            assertEquals(TransitousOracle.parseIso(text), Transitous.parseIso(text), text)
            assertEquals(TransitousOracle.parseIso(text), portableIsoEpochSec(text), text)
            val fraction = text.dropLast(1) + "." + r.nextInt(1, 999).toString().padStart(3, '0') + "Z"
            assertEquals(TransitousOracle.parseIso(fraction), portableIsoEpochSec(fraction), fraction)
        }
        for (bad in listOf("", "not-a-time", "2026-07-13", "2026-07-13T20:26:00", "2026-13-01T00:00:00Z", "null")) {
            assertEquals(TransitousOracle.parseIso(bad), Transitous.parseIso(bad), bad)
            assertEquals(TransitousOracle.parseIso(bad), portableIsoEpochSec(bad), bad)
        }
    }

    /** Native's clock text agrees with `SimpleDateFormat` on every IANA zone, across DST changes,
     *  for an unknown zone (GMT) and for none (the process zone). */
    @Test fun portableClockTextMatchesSimpleDateFormat() {
        val r = Random(9)
        TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
        val zones: List<String?> = ZoneId.getAvailableZoneIds().sorted() + listOf(null, "Mars/Base", "")
        for (use24h in listOf(false, true)) {
            ClockFormat.use24h = use24h
            for (zone in zones) {
                repeat(40) {
                    val e = r.nextLong(1_000_000_000L, 2_500_000_000L)
                    assertEquals(TransitousOracle.clockText(e, zone), portableClockText(e, zone), "$e in $zone, 24h $use24h")
                    assertEquals(TransitousOracle.clockText(e, zone), Transitous.clockText(e, zone), "$e in $zone, 24h $use24h")
                }
            }
            // Around the 2026 changes in the US and Europe.
            for (start in listOf(1_772_953_200L, 1_793_512_800L, 1_774_746_000L, 1_792_890_000L)) {
                for (s in 0 until 4 * 3600 step 60) for (zone in listOf("America/Los_Angeles", "Europe/Paris", null)) {
                    assertEquals(TransitousOracle.clockText(start + s, zone), portableClockText(start + s, zone), "${start + s} in $zone")
                }
            }
        }
    }
}
