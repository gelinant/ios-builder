package app.vela.core.sat

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.pow
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * One parsed two-line element set (TLE). [epochMs] is the element set's own epoch; a propagation
 * instant outside [Sgp4.MAX_EPOCH_AGE_DAYS] of it is refused rather than drawn as if it were
 * current.
 *
 * [catalogNumber] is the NORAD catalogue number. The name is the line above the pair, without the
 * optional `0 ` prefix; an unnamed element set keeps `OBJECT <number>`.
 */
data class Tle(
    val name: String,
    val catalogNumber: Int,
    val line1: String,
    val line2: String,
    val epochYear: Int,
    val epochDay: Double,
    val epochMs: Long,
    val inclinationDeg: Double,
    val eccentricity: Double,
    val meanMotionRevPerDay: Double,
    /** The drag term B* as a number, 0 when the field says so. */
    val bstar: Double,
) {
    /** Keplerian period in minutes, for the near-Earth limit and for the sheet. */
    val periodMinutes: Double get() = 1440.0 / meanMotionRevPerDay
}

/** A position and velocity in the true-equator mean-equinox frame, km and km/s. */
data class TemeState(
    val xKm: Double,
    val yKm: Double,
    val zKm: Double,
    val vxKmS: Double,
    val vyKmS: Double,
    val vzKmS: Double,
) {
    val speedKmS: Double get() = sqrt(vxKmS * vxKmS + vyKmS * vyKmS + vzKmS * vzKmS)
}

/**
 * A satellite as the map draws it: geodetic latitude and longitude, altitude, the ECEF state the
 * G-3 acceptance asks for, and the inertial speed the card shows.
 */
data class SatelliteFix(
    val latDeg: Double,
    val lonDeg: Double,
    val altitudeKm: Double,
    val ecefXKm: Double,
    val ecefYKm: Double,
    val ecefZKm: Double,
    val ecefVxKmS: Double,
    val ecefVyKmS: Double,
    val ecefVzKmS: Double,
    val speedKmS: Double,
)

/**
 * SGP4 for near-Earth element sets (Vallado, Crawford, Hujsak and Kelso, AIAA 2006-6753, WGS-72
 * constants), local and without a network. G-3 needs the sub-satellite point, the altitude and the
 * velocity of a cached TLE; it never needs a deep-space ephemeris.
 *
 * Refused on purpose, never approximated:
 * - an element set more than [MAX_EPOCH_AGE_DAYS] older than the propagation instant, or more than
 *   one day in the future;
 * - a deep-space orbit (period of 225 min or more: GPS, Molniya, geostationary). These need SDP4,
 *   which this lot does not carry, so the store drops them instead of drawing a wrong dot;
 * - a decayed object (SGP4 radius below one Earth radius), an eccentricity out of range and the
 *   other SGP4 error codes.
 *
 * The state is produced in TEME, then rotated to ECEF with GMST and the Earth rotation rate, then
 * converted to geodetic WGS-84 latitude, longitude and altitude.
 */
object Sgp4 {
    /** An element set is used at most this long after its epoch. */
    const val MAX_EPOCH_AGE_DAYS: Double = 30.0

    /** A propagation instant before the epoch by more than one day is not a forecast. */
    private const val MAX_FUTURE_AGE_DAYS = 1.0

    private const val MINUTES_PER_DAY = 1440.0
    private const val TWO_PI = 2.0 * PI
    private const val DEG = PI / 180.0

    // WGS-72, the constants SGP4 was fitted with.
    private const val MU = 398600.8
    private const val EARTH_RADIUS_KM = 6378.135
    private val XKE = 60.0 / sqrt(EARTH_RADIUS_KM * EARTH_RADIUS_KM * EARTH_RADIUS_KM / MU)
    private const val J2 = 0.001082616
    private const val J3 = -0.00000253881
    private const val J4 = -0.00000165597
    private val J3OJ2 = J3 / J2
    private val VKMPERSEC = EARTH_RADIUS_KM * XKE / 60.0
    private const val X2O3 = 2.0 / 3.0

    /** WGS-72 Earth rotation rate, rad/s, used for the ECEF velocity. */
    private const val OMEGA_EARTH = 7.29211514670698e-5

    // WGS-84 for the geodetic point; SGP4 itself stays on WGS-72.
    private const val WGS84_A = 6378.137
    private const val WGS84_F = 1.0 / 298.257223563
    private val WGS84_E2 = WGS84_F * (2.0 - WGS84_F)

    /**
     * Parses a CelesTrak TLE answer: three-line groups of a name, line 1 and line 2. A group whose
     * checksum or fields do not parse is skipped, never repaired; an element set with an unknown
     * catalogue number or a degenerate mean motion is skipped too.
     */
    fun parseTles(text: String): List<Tle> {
        val raw = text.split('\n').map { it.removeSuffix("\r") }
        val out = ArrayList<Tle>()
        var i = 0
        while (i < raw.size) {
            val line1 = raw[i]
            val line2 = if (i + 1 < raw.size) raw[i + 1] else ""
            if (!line1.startsWith("1 ") || !line2.startsWith("2 ")) {
                i += 1
                continue
            }
            val nameLine = if (i > 0) raw[i - 1] else ""
            val hasName = nameLine.isNotBlank() && !nameLine.startsWith("1 ") &&
                !nameLine.startsWith("2 ")
            val parsed = parseOne(if (hasName) nameLine else "", line1, line2)
            if (parsed != null) out += parsed
            i += 2
        }
        return out
    }

    /** One group, or null when the pair is invalid. Used by [parseTles] and by the store. */
    fun parseTle(nameLine: String, line1: String, line2: String): Tle? = parseOne(nameLine, line1, line2)

    /**
     * The TEME state at [atMs], or null when the element set cannot be used: bad epoch age, deep
     * space, decay, or any SGP4 error.
     */
    fun teme(tle: Tle, atMs: Long): TemeState? {
        val minutes = (atMs - tle.epochMs) / 60_000.0
        if (minutes > MAX_EPOCH_AGE_DAYS * MINUTES_PER_DAY) return null
        if (minutes < -MAX_FUTURE_AGE_DAYS * MINUTES_PER_DAY) return null
        val satrec = Satrec(tle)
        return satrec.propagate(minutes)
    }

    /**
     * The map and card view of [tle] at [atMs]: geodetic point, altitude, ECEF position and
     * velocity, and the inertial speed. Null under the same rules as [teme].
     */
    fun fix(tle: Tle, atMs: Long): SatelliteFix? {
        val teme = teme(tle, atMs) ?: return null
        val jd = 2_440_587.5 + atMs / 86_400_000.0
        val gmst = gstime(jd)
        val cosg = cos(gmst)
        val sing = sin(gmst)
        val ecefX = cosg * teme.xKm + sing * teme.yKm
        val ecefY = -sing * teme.xKm + cosg * teme.yKm
        val ecefZ = teme.zKm
        // v_ecef = Rz(gmst) * v_teme - omega x r_ecef
        val ecefVx = cosg * teme.vxKmS + sing * teme.vyKmS + OMEGA_EARTH * ecefY
        val ecefVy = -sing * teme.vxKmS + cosg * teme.vyKmS - OMEGA_EARTH * ecefX
        val ecefVz = teme.vzKmS
        val (lat, lon, alt) = geodetic(ecefX, ecefY, ecefZ)
        return SatelliteFix(
            latDeg = lat,
            lonDeg = lon,
            altitudeKm = alt,
            ecefXKm = ecefX,
            ecefYKm = ecefY,
            ecefZKm = ecefZ,
            ecefVxKmS = ecefVx,
            ecefVyKmS = ecefVy,
            ecefVzKmS = ecefVz,
            speedKmS = teme.speedKmS,
        )
    }

    /** Geodetic WGS-84 latitude, longitude and altitude from an ECEF point in km. */
    fun geodetic(xKm: Double, yKm: Double, zKm: Double): Triple<Double, Double, Double> {
        val p = hypot(xKm, yKm)
        var lat = atan2(zKm, p * (1.0 - WGS84_E2))
        var sinLat = sin(lat)
        var n = WGS84_A / sqrt(1.0 - WGS84_E2 * sinLat * sinLat)
        repeat(5) {
            lat = atan2(zKm + WGS84_E2 * n * sinLat, p)
            sinLat = sin(lat)
            n = WGS84_A / sqrt(1.0 - WGS84_E2 * sinLat * sinLat)
        }
        val alt = if (abs(cos(lat)) > 1e-9) p / cos(lat) - n else abs(zKm) - WGS84_A * (1.0 - WGS84_F)
        var lon = atan2(yKm, xKm) / DEG
        if (lon > 180.0) lon -= 360.0
        if (lon < -180.0) lon += 360.0
        return Triple(lat / DEG, lon, alt)
    }

    /** Greenwich mean sidereal time in radians for a Julian date (Vallado). */
    fun gstime(jdUt1: Double): Double {
        val tut1 = (jdUt1 - 2_451_545.0) / 36_525.0
        var temp = -6.2e-6 * tut1 * tut1 * tut1 + 0.093104 * tut1 * tut1 +
            (876_600.0 * 3600.0 + 8_640_184.812866) * tut1 + 67_310.54841
        temp *= DEG / 240.0
        temp %= TWO_PI
        if (temp < 0.0) temp += TWO_PI
        return temp
    }

    private fun parseOne(nameLine: String, line1: String, line2: String): Tle? {
        if (line1.length < 69 || line2.length < 69) return null
        if (!line1.startsWith("1 ") || !line2.startsWith("2 ")) return null
        if (!checksumOk(line1) || !checksumOk(line2)) return null
        val cat1 = line1.substring(2, 7).trim().toIntOrNull()
        val cat2 = line2.substring(2, 7).trim().toIntOrNull()
        val catalog = cat2 ?: cat1 ?: return null
        if (cat1 != null && cat2 != null && cat1 != cat2) return null

        val yy = line1.substring(18, 20).trim().toIntOrNull() ?: return null
        val day = line1.substring(20, 32).trim().toDoubleOrNull() ?: return null
        if (day < 1.0 || day >= 367.0) return null
        val year = if (yy < 57) 2000 + yy else 1900 + yy

        val inclination = line2.substring(8, 16).trim().toDoubleOrNull() ?: return null
        val eccentricity = ("0." + line2.substring(26, 33).trim()).toDoubleOrNull() ?: return null
        val meanMotion = line2.substring(52, 63).trim().toDoubleOrNull() ?: return null
        val bstarTerm = bstar(line1) ?: return null
        if (inclination < 0.0 || inclination > 180.0) return null
        if (eccentricity < 0.0 || eccentricity >= 1.0) return null
        if (meanMotion <= 0.0 || meanMotion > 20.0) return null

        val name = if (nameLine.isBlank()) "OBJECT $catalog" else nameLine.trim()
            .removePrefix("0 ").trim().ifBlank { "OBJECT $catalog" }
        return Tle(
            name = name,
            catalogNumber = catalog,
            line1 = line1,
            line2 = line2,
            epochYear = year,
            epochDay = day,
            epochMs = epochMillis(year, day),
            inclinationDeg = inclination,
            eccentricity = eccentricity,
            meanMotionRevPerDay = meanMotion,
            bstar = bstarTerm,
        )
    }

    private fun checksumOk(line: String): Boolean {
        if (line.length < 69) return false
        val expected = line[68]
        if (!expected.isDigit()) return false
        var sum = 0
        for (index in 0 until 68) {
            val c = line[index]
            when {
                c.isDigit() -> sum += c - '0'
                c == '-' -> sum += 1
            }
        }
        return sum % 10 == expected - '0'
    }

    /** ` 28098-4` means 0.28098e-4; the field carries the exponential notation of a TLE. */
    private fun bstar(line1: String): Double? {
        val field = line1.substring(53, 61)
        val text = field.trim()
        if (text.isEmpty()) return 0.0
        var sign = 1.0
        var body = text
        if (body.startsWith("-")) {
            sign = -1.0
            body = body.substring(1)
        } else if (body.startsWith("+")) {
            body = body.substring(1)
        }
        val exponentAt = body.indexOfLast { it == '-' || it == '+' }
        val mantissaText: String
        val exponent: Int
        if (exponentAt <= 0) {
            mantissaText = body
            exponent = 0
        } else {
            mantissaText = body.substring(0, exponentAt)
            exponent = body.substring(exponentAt).toIntOrNull() ?: return null
        }
        val digits = mantissaText.filter { it.isDigit() }
        if (digits.isEmpty()) return 0.0
        val mantissa = ("0." + digits).toDoubleOrNull() ?: return null
        return sign * mantissa * 10.0.pow(exponent)
    }

    private fun epochMillis(year: Int, dayOfYear: Double): Long {
        val daysSinceEpoch = daysFromCivil(year, 1, 1) + (dayOfYear - 1.0)
        return (daysSinceEpoch * 86_400_000.0).roundToLong()
    }

    /** Days since 1970-01-01 for a civil date (proleptic Gregorian). */
    private fun daysFromCivil(year: Int, month: Int, day: Int): Long {
        val y = if (month <= 2) year - 1 else year
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val doy = (153 * (if (month > 2) month - 3 else month + 9) + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era.toLong() * 146_097L + doe.toLong() - 719_468L
    }

    /**
     * The initialized SGP4 coefficients for one near-Earth element set. A null [Satrec] means the
     * orbit is deep space or degenerate, which G-3 refuses.
     */
    private class Satrec(tle: Tle) {
        private val noKozai = tle.meanMotionRevPerDay * TWO_PI / MINUTES_PER_DAY
        private val ecco = tle.eccentricity
        private val inclo = tle.inclinationDeg * DEG
        private val nodeo = tle.line2.substring(17, 25).trim().toDouble() * DEG
        private val argpo = tle.line2.substring(34, 42).trim().toDouble() * DEG
        private val mo = tle.line2.substring(43, 51).trim().toDouble() * DEG
        private val bstarValue = tle.bstar

        private val noUnkozai: Double
        private val ao: Double
        private val con41: Double
        private val x1mth2: Double
        private val x7thm1: Double
        private val cc1: Double
        private val cc4: Double
        private val cc5: Double
        private val omgcof: Double
        private val xmcof: Double
        private val nodecf: Double
        private val t2cof: Double
        private val xlcof: Double
        private val aycof: Double
        private val eta: Double
        private val delmo: Double
        private val sinmao: Double
        private val mdot: Double
        private val argpdot: Double
        private val nodedot: Double
        private val isimp: Int

        init {
            val eccsq = ecco * ecco
            val omeosq = 1.0 - eccsq
            val rteosq = sqrt(omeosq)
            val cosio = cos(inclo)
            val cosio2 = cosio * cosio
            val sinio = sin(inclo)

            var ak = (XKE / noKozai).pow(X2O3)
            var d1 = 0.75 * J2 * (3.0 * cosio2 - 1.0) / (rteosq * omeosq)
            var del = d1 / (ak * ak)
            val adel = ak * (1.0 - del * del - del * (1.0 / 3.0 + 134.0 * del * del / 81.0))
            del = d1 / (adel * adel)
            noUnkozai = noKozai / (1.0 + del)

            ao = (XKE / noUnkozai).pow(X2O3)
            val po = ao * omeosq
            val con42 = 1.0 - 5.0 * cosio2
            con41 = -con42 - cosio2 - cosio2
            val posq = po * po
            val rp = ao * (1.0 - ecco)
            val perige = (rp - 1.0) * EARTH_RADIUS_KM

            isimp = if (rp < (220.0 / EARTH_RADIUS_KM + 1.0)) 1 else 0
            var sfour = 1.0 + 78.0 / EARTH_RADIUS_KM
            var qzms24 = ((120.0 - 78.0) / EARTH_RADIUS_KM).pow(4.0)
            if (perige < 156.0) {
                sfour = perige - 78.0
                if (perige < 98.0) sfour = 20.0
                qzms24 = ((120.0 - sfour) / EARTH_RADIUS_KM).pow(4.0)
                sfour = sfour / EARTH_RADIUS_KM + 1.0
            }
            val pinvsq = 1.0 / posq
            val tsi = 1.0 / (ao - sfour)
            eta = ao * ecco * tsi
            val etasq = eta * eta
            val eeta = ecco * eta
            val psisq = abs(1.0 - etasq)
            val coef = qzms24 * tsi.pow(4.0)
            val coef1 = coef / psisq.pow(3.5)
            val cc2 = coef1 * noUnkozai * (ao * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq)) +
                0.375 * J2 * tsi / psisq * con41 * (8.0 + 3.0 * etasq * (8.0 + etasq)))
            cc1 = bstarValue * cc2
            var cc3 = 0.0
            if (ecco > 1.0e-4) cc3 = -2.0 * coef * tsi * J3OJ2 * noUnkozai * sinio / ecco
            x1mth2 = 1.0 - cosio2
            cc4 = 2.0 * noUnkozai * coef1 * ao * omeosq *
                (eta * (2.0 + 0.5 * etasq) + ecco * (0.5 + 2.0 * etasq) -
                    J2 * tsi / (ao * psisq) *
                    (-3.0 * con41 * (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta)) +
                        0.75 * x1mth2 * (2.0 * etasq - eeta * (1.0 + etasq)) *
                        cos(2.0 * argpo)))
            cc5 = 2.0 * coef1 * ao * omeosq * (1.0 + 2.75 * (etasq + eeta) + eeta * etasq)

            val cosio4 = cosio2 * cosio2
            val temp1 = 1.5 * J2 * pinvsq * noUnkozai
            val temp2 = 0.5 * temp1 * J2 * pinvsq
            val temp3 = -0.46875 * J4 * pinvsq * pinvsq * noUnkozai
            mdot = noUnkozai + 0.5 * temp1 * rteosq * con41 +
                0.0625 * temp2 * rteosq * (13.0 - 78.0 * cosio2 + 137.0 * cosio4)
            argpdot = -0.5 * temp1 * con42 +
                0.0625 * temp2 * (7.0 - 114.0 * cosio2 + 395.0 * cosio4) +
                temp3 * (3.0 - 36.0 * cosio2 + 49.0 * cosio4)
            val xhdot1 = -temp1 * cosio
            nodedot = xhdot1 + (0.5 * temp2 * (4.0 - 19.0 * cosio2) +
                2.0 * temp3 * (3.0 - 7.0 * cosio2)) * cosio

            omgcof = bstarValue * cc3 * cos(argpo)
            xmcof = if (ecco > 1.0e-4) -X2O3 * coef * bstarValue / eeta else 0.0
            nodecf = 3.5 * omeosq * xhdot1 * cc1
            t2cof = 1.5 * cc1
            xlcof = if (abs(cosio + 1.0) > 1.5e-12) {
                -0.25 * J3OJ2 * sinio * (3.0 + 5.0 * cosio) / (1.0 + cosio)
            } else {
                -0.25 * J3OJ2 * sinio * (3.0 + 5.0 * cosio) / 1.5e-12
            }
            aycof = -0.5 * J3OJ2 * sinio
            val delmotemp = 1.0 + eta * cos(mo)
            delmo = delmotemp * delmotemp * delmotemp
            sinmao = sin(mo)
            x7thm1 = 7.0 * cosio2 - 1.0
        }

        private var rejected = false

        init {
            rejected = ecco >= 1.0 || ecco < 0.0 || noUnkozai <= 0.0 ||
                TWO_PI / noUnkozai >= 225.0
        }

        fun propagate(t: Double): TemeState? {
            if (rejected) return null
            var xmdf = mo + mdot * t
            var argpdf = argpo + argpdot * t
            var nodedf = nodeo + nodedot * t
            var argpm = argpdf
            var mm = xmdf
            val t2 = t * t
            var nodem = nodedf + nodecf * t2
            var tempa = 1.0 - cc1 * t
            var tempe = bstarValue * cc4 * t
            var templ = t2cof * t2
            if (isimp != 1) {
                val delomg = omgcof * t
                val delmtemp = 1.0 + eta * cos(xmdf)
                val delm = xmcof * (delmtemp * delmtemp * delmtemp - delmo)
                val temp = delomg + delm
                mm = xmdf + temp
                argpm = argpdf - temp
                tempe += bstarValue * cc5 * (sin(mm) - sinmao)
            }
            var nm = noUnkozai
            var em = ecco - tempe
            if (em >= 1.0 || em < -0.001) return null
            if (em < 1.0e-6) em = 1.0e-6

            var am = (XKE / nm).pow(X2O3) * tempa * tempa
            nm = XKE / (am * am * am).pow(0.5)
            if (nm <= 0.0) return null
            mm += noUnkozai * templ
            val xlm = mm + argpm + nodem
            nodem %= TWO_PI
            argpm %= TWO_PI

            val sinim = sin(inclo)
            val cosim = cos(inclo)
            val ep = em
            val xincp = inclo
            val argpp = argpm
            val nodep = nodem
            val mp = (xlm - argpm - nodem) % TWO_PI

            val axnl = ep * cos(argpp)
            val temp = 1.0 / (am * (1.0 - ep * ep))
            val aynl = ep * sin(argpp) + temp * aycof
            val xl = mp + argpp + nodep + temp * xlcof * axnl

            var u = (xl - nodep) % TWO_PI
            if (u < 0.0) u += TWO_PI
            var eo1 = u
            var tem5 = 9999.9
            var ktr = 1
            var sineo1 = sin(eo1)
            var coseo1 = cos(eo1)
            while (abs(tem5) >= 1e-12 && ktr <= 10) {
                sineo1 = sin(eo1)
                coseo1 = cos(eo1)
                tem5 = 1.0 - coseo1 * axnl - sineo1 * aynl
                tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
                if (abs(tem5) >= 0.95) tem5 = if (tem5 > 0.0) 0.95 else -0.95
                eo1 += tem5
                ktr += 1
            }

            val ecose = axnl * coseo1 + aynl * sineo1
            val esine = axnl * sineo1 - aynl * coseo1
            val el2 = axnl * axnl + aynl * aynl
            val pl = am * (1.0 - el2)
            if (pl < 0.0) return null
            val rl = am * (1.0 - ecose)
            val rdotl = sqrt(am) * esine / rl
            val rvdotl = sqrt(pl) / rl
            val betal = sqrt(1.0 - el2)
            val temp2 = esine / (1.0 + betal)
            val sinu = am / rl * (sineo1 - aynl - axnl * temp2)
            val cosu = am / rl * (coseo1 - axnl + aynl * temp2)
            var su = atan2(sinu, cosu)
            val sin2u = (cosu + cosu) * sinu
            val cos2u = 1.0 - 2.0 * sinu * sinu
            val tempP = 1.0 / pl
            val temp1 = 0.5 * J2 * tempP
            val temp2P = temp1 * tempP
            val mrt = rl * (1.0 - 1.5 * temp2P * betal * con41) +
                0.5 * temp1 * x1mth2 * cos2u
            su -= 0.25 * temp2P * x7thm1 * sin2u
            val xnode = nodep + 1.5 * temp2P * cosim * sin2u
            val xinc = xincp + 1.5 * temp2P * cosim * sinim * cos2u
            val mvt = rdotl - nm * temp1 * x1mth2 * sin2u / XKE
            val rvdot = rvdotl + nm * temp1 * (x1mth2 * cos2u + 1.5 * con41) / XKE

            val sinsu = sin(su)
            val cossu = cos(su)
            val snod = sin(xnode)
            val cnod = cos(xnode)
            val sini = sin(xinc)
            val cosi = cos(xinc)
            val xmx = -snod * cosi
            val xmy = cnod * cosi
            val ux = xmx * sinsu + cnod * cossu
            val uy = xmy * sinsu + snod * cossu
            val uz = sini * sinsu
            val vx = xmx * cossu - cnod * sinsu
            val vy = xmy * cossu - snod * sinsu
            val vz = sini * cossu
            if (mrt < 1.0) return null
            return TemeState(
                xKm = mrt * EARTH_RADIUS_KM * ux,
                yKm = mrt * EARTH_RADIUS_KM * uy,
                zKm = mrt * EARTH_RADIUS_KM * uz,
                vxKmS = (mvt * ux + rvdot * vx) * VKMPERSEC,
                vyKmS = (mvt * uy + rvdot * vy) * VKMPERSEC,
                vzKmS = (mvt * uz + rvdot * vz) * VKMPERSEC,
            )
        }
    }
}
