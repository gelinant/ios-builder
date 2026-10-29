package app.vela.core.data

import app.vela.core.util.UrlCodec
import kotlin.math.roundToLong

/**
 * A ready share: the sheet's subject, the text that names the place or trip, and the link item
 * when one exists.
 */
data class ShareContent(val subject: String, val text: String, val link: String?)

/**
 * Outgoing share links and text, the counterpart of Android's share menu (L53, L115).
 *
 * A place link is Google's canonical URL when Google is allowed: the exact listing by unsigned
 * cid, else a name and point query, as `SavedStore.sharePlaceUrl` and Android's `sharePlaceUrl`
 * already build. With Google off nothing Google-shaped is produced: the share falls back to the
 * place's own OpenStreetMap object when its id carries one, else to a Photon search on the name
 * and address, and the text carries the keyless `geo:` pin Android shares when no link exists.
 *
 * [ShortLinks] resolves incoming short links only; neither Android nor iOS has an API that creates
 * a `maps.app.goo.gl` link. No short link is therefore ever claimed here, and the "Open shared
 * Google Maps links" setting changes nothing in an outgoing share.
 */
object ShareLinks {
    private const val GOOGLE_MAPS = "https://www.google.com/maps"

    /** Android's place link: the exact listing by cid, else a name and point query. */
    fun googlePlaceUrl(name: String, latitude: Double, longitude: Double, featureId: String?): String {
        val cid = featureId?.substringAfter(':', "")?.removePrefix("0x")
            ?.takeIf { it.isNotBlank() }
            ?.let { hex -> runCatching { hex.toULong(16).toString() }.getOrNull() }
        if (cid != null) return "$GOOGLE_MAPS?cid=$cid"
        val point = "${coordinate(latitude)}%2C${coordinate(longitude)}"
        val query = name.trim().takeIf { it.isNotEmpty() }?.let { "${encode(it)}%20$point" } ?: point
        return "$GOOGLE_MAPS/search/?api=1&query=$query"
    }

    /**
     * The place's own OpenStreetMap object when its id names one (`osm:n123`, `osm:node/123`, or
     * the same behind `overture:`). The map's places bake keeps that ref in the row id; a Google
     * listing, a Photon row and a dropped pin have none.
     */
    fun osmUrl(sourceId: String?): String? {
        val id = sourceId?.removePrefix("overture:")?.trim().orEmpty()
        if (!id.startsWith("osm:")) return null
        val ref = id.removePrefix("osm:")
        val short = Regex("""^([nwr])(\d+)$""").find(ref)
        if (short != null) {
            val type = when (short.groupValues[1]) {
                "n" -> "node"
                "w" -> "way"
                else -> "relation"
            }
            return "https://www.openstreetmap.org/" + type + "/" + short.groupValues[2]
        }
        val long = Regex("""^(node|way|relation)/(\d+)$""").find(ref) ?: return null
        return "https://www.openstreetmap.org/${long.groupValues[1]}/${long.groupValues[2]}"
    }

    /** A Photon search over the same name and address the geocoder answers, as a clickable page. */
    fun photonSearchUrl(name: String, address: String?): String? {
        val query = listOf(name.trim(), address?.trim().orEmpty())
            .filter { it.isNotEmpty() }
            .joinToString(" ")
        if (query.isEmpty()) return null
        return "https://photon.komoot.io/?q=${encode(query)}"
    }

    /** The OpenStreetMap object or, failing that, a Photon search, for a share with no Google. */
    fun openPlaceUrl(sourceId: String?, name: String, address: String?): String? =
        osmUrl(sourceId) ?: photonSearchUrl(name, address)

    /**
     * The place text: its name, its address when it adds something to the name, and, when no link
     * could be resolved, Android's keyless `geo:` pin. The name is never repeated by an address
     * that already starts with it, as Android's address item does.
     */
    fun placeText(
        name: String,
        address: String?,
        latitude: Double,
        longitude: Double,
        hasLink: Boolean,
    ): String {
        val shown = name.trim()
        val street = address?.trim().orEmpty()
        val lines = mutableListOf<String>()
        // Android shares the address alone when it already begins with the name, so the name is
        // not printed twice and no part of the street is dropped.
        if (shown.isNotEmpty() && street.startsWith(shown, ignoreCase = true)) {
            lines += street
        } else {
            lines += shown.ifEmpty { coordinate(latitude) }
            if (street.isNotEmpty()) lines += street
        }
        if (!hasLink) {
            val point = "${coordinate(latitude)},${coordinate(longitude)}"
            val label = if (shown.isEmpty()) "" else "(${encode(shown)})"
            lines += "geo:$point?q=$point$label"
        }
        return lines.joinToString("\n")
    }

    /**
     * Google's directions link for the selected route, or null without a destination. A start that
     * is merely the device's position or the map's center is left out, which is what Google means
     * by an absent origin; the stops keep the route's order.
     */
    fun googleDirectionsUrl(
        origin: String,
        destination: String,
        waypoints: List<String>,
        modeName: String,
    ): String? {
        val to = destination.trim()
        if (to.isEmpty()) return null
        val params = mutableListOf("api=1", "destination=${encode(to)}", "travelmode=${travelMode(modeName)}")
        val from = origin.trim()
        if (from.isNotEmpty() && !from.equals(HERE, ignoreCase = true) && !from.equals(MAP_CENTER, ignoreCase = true)) {
            params.add("origin=${encode(from)}")
        }
        val stops = waypoints.map { it.trim() }.filter { it.isNotEmpty() }
        if (stops.isNotEmpty()) params.add("waypoints=${encode(stops.joinToString("|"))}")
        return "$GOOGLE_MAPS/dir/?${params.joinToString("&")}"
    }

    /**
     * The route text: start and destination, stops in order, travel mode and, only when the model
     * really has one, the ETA. The link is a separate share item, as the place link is.
     */
    fun routeText(
        origin: String,
        destination: String,
        waypoints: List<String>,
        modeName: String,
        etaText: String?,
    ): String {
        val to = destination.trim().ifEmpty { "the destination" }
        val from = origin.trim()
        val lines = mutableListOf(
            if (from.isEmpty()) "Directions to $to" else "Directions from $from to $to",
        )
        val stops = waypoints.map { it.trim() }.filter { it.isNotEmpty() }
        if (stops.isNotEmpty()) lines += "Stops: ${stops.joinToString(", ")}"
        lines += "Mode: ${modeLabel(modeName)}"
        etaText?.trim()?.takeIf { it.isNotEmpty() }?.let { lines += "ETA: $it" }
        return lines.joinToString("\n")
    }

    /**
     * A place share with Google on or off. With Google off no Google link is built at all; the
     * OpenStreetMap or Photon link is used when the app can build one, else the text carries
     * Android's `geo:` pin.
     */
    fun placeShare(
        name: String,
        address: String?,
        latitude: Double,
        longitude: Double,
        featureId: String?,
        sourceId: String?,
        google: Boolean,
    ): ShareContent {
        val link = if (google) googlePlaceUrl(name, latitude, longitude, featureId)
        else openPlaceUrl(sourceId, name, address)
        return ShareContent(
            subject = name.trim(),
            text = placeText(name, address, latitude, longitude, hasLink = link != null),
            link = link,
        )
    }

    /**
     * A route share. The ETA is whatever the model provided and is omitted when it provided none;
     * Google's directions link is only built when Google is allowed.
     */
    fun routeShare(
        origin: String,
        destination: String,
        waypoints: List<String>,
        modeName: String,
        etaText: String?,
        google: Boolean,
    ): ShareContent {
        val to = destination.trim()
        return ShareContent(
            subject = if (to.isEmpty()) "Route" else "Route to $to",
            text = routeText(origin, destination, waypoints, modeName, etaText),
            link = if (google) googleDirectionsUrl(origin, destination, waypoints, modeName) else null,
        )
    }

    /** Google's `travelmode` value for a Kotlin `TravelMode` name. */
    fun travelMode(modeName: String): String = when (modeName.uppercase()) {
        "WALK" -> "walking"
        "BICYCLE" -> "bicycling"
        "TRANSIT" -> "transit"
        else -> "driving"
    }

    /** The English word Android's chooser would label the mode with. */
    fun modeLabel(modeName: String): String = when (modeName.uppercase()) {
        "WALK" -> "Walking"
        "BICYCLE" -> "Cycling"
        "TRANSIT" -> "Transit"
        else -> "Driving"
    }

    private const val HERE = "your location"
    private const val MAP_CENTER = "the map's center"

    /** Six decimals at most, so a shared point is readable and still within a metre. */
    fun coordinate(value: Double): String {
        val scaled = (value * 1_000_000).roundToLong().toDouble() / 1_000_000
        return scaled.toString()
    }

    private fun encode(text: String): String = UrlCodec.encode(text).replace("+", "%20")
}
