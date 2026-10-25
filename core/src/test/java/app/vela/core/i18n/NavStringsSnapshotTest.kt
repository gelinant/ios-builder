package app.vela.core.i18n

import app.vela.core.model.LaneSide
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.Route
import app.vela.core.model.RouteLeg
import app.vela.core.model.distanceTo
import app.vela.core.nav.NavReplay
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.util.Locale

/**
 * Every spoken and banner string Vela builds, for every language, against a stored snapshot
 * (`nav_strings_snapshot.txt`): a sample of maneuvers, distances, stops, lanes and a replayed drive.
 * It pins the text while the navigation core moves between modules. A deliberate wording change
 * regenerates the file: the test writes the new text to `build/nav_strings_snapshot.txt`.
 */
class NavStringsSnapshotTest {

    private val languages = listOf(
        "en", "fr", "de", "es", "it", "pt", "pt-br", "nl", "ru", "pl", "sv", "uk", "hu", "ro",
        "zh", "zh-tw", "ja", "he",
    )

    private val types = listOf(
        "turn", "new name", "depart", "arrive", "merge", "on ramp", "off ramp", "fork", "end of road",
        "continue", "roundabout", "rotary", "roundabout turn", "exit roundabout", "exit rotary",
        "notification", "uturn",
    )
    private val mods = listOf(null, "left", "right", "slight left", "slight right", "sharp left", "sharp right", "straight", "uturn")

    private fun dump(ns: NavStrings): String = buildString {
        fun line(k: String, v: String) { append(k).append(" = ").append(v).append('\n') }
        for (t in types) for (m in mods) {
            line("phrase $t/$m road", ns.phrase(t, m, "Main Street", null, null, null))
            line("phrase $t/$m none", ns.phrase(t, m, null, null, null, null))
            line("phrase $t/$m sign", ns.phrase(t, m, "I 80", "Sacramento: Reno", "72A", 2))
            line("phrase $t/$m rb", ns.phrase(t, m, "Covell Boulevard", null, null, 3))
        }
        val inst = ns.phrase("turn", "left", "Russell Boulevard", null, null, null)
        val sign = ns.phrase("off ramp", "right", null, "Sacramento: Reno", "72A", null)
        for (n in 0..3) line("passLights $n", ns.passLights(n))
        line("lightThen", ns.lightThen(ns.passLights(1), inst))
        line("spokenSign", ns.spokenSign(sign))
        line("repeatShort", ns.repeatShort(sign))
        for (d in listOf(0.0, 8.0, 30.0, 95.0, 150.0, 160.9, 304.8, 402.3, 500.0, 804.7, 999.0, 1000.0, 1609.3, 2414.0, 4500.0, 12_874.8, 32_186.9)) {
            line("spokenDistance $d imperial", ns.spokenDistance(d, true))
            line("spokenDistance $d metric", ns.spokenDistance(d, false))
        }
        line("inThen", ns.inThen(ns.spokenDistance(400.0, false), inst))
        line("arrived", ns.arrived())
        line("destinationSide left", ns.destinationSide(true))
        line("destinationSide right", ns.destinationSide(false))
        line("startNav", ns.startNav(inst))
        line("reachedStop label", ns.reachedStop("Davis Food Co-op"))
        line("reachedStop blank", ns.reachedStop(""))
        for (left in listOf(true, false, null)) {
            line("stopAhead $left", ns.stopAhead("Davis Food Co-op", left))
            line("stopAhead blank $left", ns.stopAhead("", left))
            line("thenStop $left", ns.thenStop(inst, "Davis Food Co-op", left))
            line("intoLotThen L $left", ns.intoLotThen(true, "Davis Food Co-op", left))
            line("intoLotThen R $left", ns.intoLotThen(false, "", left))
        }
        line("thenNext", ns.thenNext(inst, ns.phrase("turn", "right", "B Street", null, null, null)))
        line("intoLot L", ns.intoLot(true))
        line("intoLot R", ns.intoLot(false))
        line("fasterRoute", ns.fasterRoute(inst))
        line("voiceTest", ns.voiceTest())
        line("rerouting", ns.rerouting())
        line("fasterRouteAvailable 1", ns.fasterRouteAvailable(1))
        line("fasterRouteAvailable 7", ns.fasterRouteAvailable(7))
        line("stopsNotIncluded", ns.stopsNotIncluded())
        line("leftYourRoute", ns.leftYourRoute())
        line("destinationAhead", ns.destinationAhead())
        for (side in LaneSide.entries) for (c in 1..3) {
            line("useLanes $side $c", ns.useLanes(side, c))
            line("useLanesToDo $side $c", ns.useLanesToDo(side, c, sign))
        }
        line("expandForSpeech", ns.expandForSpeech("Turn left onto W 128th St toward I-80 E, then Dr. King Blvd 2nd Ave"))
    }

    private fun lRoute(): Route {
        val a = LatLng(38.5400, -121.7600)
        val c1 = LatLng(38.5500, -121.7600)
        val c2 = LatLng(38.5500, -121.7500)
        val end = LatLng(38.5600, -121.7500)
        val ns = NavStringsRegistry.current()
        return Route(
            polyline = listOf(a, c1, c2, end),
            legs = listOf(
                RouteLeg(
                    distanceMeters = 3100.0, durationSeconds = 240.0, durationInTrafficSeconds = null,
                    maneuvers = listOf(
                        Maneuver(ManeuverType.DEPART, ns.phrase("depart", null, "A Street", null, null, null), a, 1113.0, 86.0),
                        Maneuver(ManeuverType.TURN_RIGHT, ns.phrase("turn", "right", "B Street", null, null, null), c1, 870.0, 70.0),
                        Maneuver(ManeuverType.TURN_LEFT, ns.phrase("turn", "left", "C Avenue", null, null, null), c2, 1113.0, 84.0),
                        Maneuver(ManeuverType.ARRIVE, ns.arrived(), end, 0.0, 0.0),
                    ),
                ),
            ),
            distanceMeters = 3100.0, durationSeconds = 240.0, durationInTrafficSeconds = null,
        )
    }

    private fun densify(poly: List<LatLng>, stepM: Double = 15.0): List<LatLng> {
        val out = ArrayList<LatLng>()
        for (i in 0 until poly.size - 1) {
            val a = poly[i]; val b = poly[i + 1]
            val steps = maxOf(1, (a.distanceTo(b) / stepM).toInt())
            for (s in 0 until steps) {
                val t = s.toDouble() / steps
                out += LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t)
            }
        }
        out += poly.last()
        return out
    }

    private fun replay(imperial: Boolean): String = buildString {
        val route = lRoute()
        val report = NavReplay.analyze(route, densify(route.polyline), imperial)
        for (c in report.cards) for (s in c.spoke) append("spoke ${c.fixIndex} ${c.stepIndex}: ").append(s).append('\n')
    }

    @Test fun `every language matches the snapshot`() {
        val text = buildString {
            for (code in languages) {
                val ns = NavStringsRegistry.forLanguage(code)
                append("## ").append(code).append(' ').append(ns.javaClass.simpleName).append('\n')
                append(dump(ns))
                NavStringsRegistry.setLocale(Locale.forLanguageTag(code))
                try {
                    append("# replay imperial\n").append(replay(true))
                    append("# replay metric\n").append(replay(false))
                } finally {
                    NavStringsRegistry.setLocale(Locale.forLanguageTag("en"))
                }
            }
        }
        val expected = javaClass.getResourceAsStream("/nav_strings_snapshot.txt")?.bufferedReader()?.readText()
        if (expected != text) {
            File("build").mkdirs()
            File("build/nav_strings_snapshot.txt").writeText(text)
        }
        assertEquals("nav strings changed; new text in core/build/nav_strings_snapshot.txt", expected, text)
    }
}
