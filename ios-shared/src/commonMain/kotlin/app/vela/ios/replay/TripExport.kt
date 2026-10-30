package app.vela.ios.replay

import app.vela.core.replay.TripLog

/**
 * Writes a scrubbed Vela trip as GPX 1.1. Only the fixes are exported: the label and destination
 * are already gone from a scrubbed CSV, and this writer never adds a name or a time of day, so a
 * published file says where the public middle of the drive went and nothing else. Timestamps are
 * deliberately left out because a trim rebased them onto zero, which is not a wall-clock date.
 */
object TripExport {

    fun gpx(csv: String): String {
        val points = TripLog.parsePoints(csv.split('\n').filter { it.isNotBlank() })
        val out = StringBuilder()
        out.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        out.append("<gpx version=\"1.1\" creator=\"Vela\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n")
        out.append("  <trk>\n    <name>Shared trip</name>\n    <trkseg>\n")
        for (p in points) {
            out.append("      <trkpt lat=\"").append(p.lat).append("\" lon=\"").append(p.lng).append("\">")
            if (p.speed.isFinite() && p.speed > 0f) {
                out.append("<extensions><speed>").append(p.speed).append("</speed></extensions>")
            }
            out.append("</trkpt>\n")
        }
        out.append("    </trkseg>\n  </trk>\n</gpx>\n")
        return out.toString()
    }
}
