package app.vela.core.sat

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * SDP4: the deep-space half of SGP4 (Vallado, Crawford, Hujsak and Kelso, AIAA 2006-6753, WGS-72
 * constants). It adds the lunar-solar periodics and the secular rates of [dscom] and [dsinit], and
 * the half-day and one-day geopotential resonance integrator of [dspace], to the same near-Earth
 * mean elements [Sgp4] already propagates.
 *
 * The translation follows the reference implementation distributed with the paper. It is internal:
 * callers use [Sgp4.teme] and [Sgp4.fix], which route a TLE to SDP4 when its un-Kozai period is
 * 225 minutes or more. The state stays in TEME, so the ECEF and geodetic conversion is unchanged.
 */
internal object Sdp4 {
    private const val TWO_PI = 2.0 * PI
    private const val PI_LOCAL = PI
    private const val X2O3 = 2.0 / 3.0

    // WGS-72, identical to Sgp4 so both paths share one model.
    private const val MU = 398600.8
    private const val EARTH_RADIUS_KM = 6378.135
    private val XKE = 60.0 / sqrt(EARTH_RADIUS_KM * EARTH_RADIUS_KM * EARTH_RADIUS_KM / MU)
    private const val J2 = 0.001082616
    private const val J3 = -0.00000253881
    private val J3OJ2 = J3 / J2

    // Deep-space constants from the reference implementation.
    private const val ZNS = 1.19459e-5
    private const val ZES = 0.01675
    private const val ZNL = 1.5835218e-4
    private const val ZEL = 0.05490
    private const val C1SS = 2.9864797e-6
    private const val C1L = 4.7968065e-7
    private const val ZSINIS = 0.39785416
    private const val ZCOSIS = 0.91744867
    private const val ZCOSGS = 0.1945905
    private const val ZSINGS = -0.98088458

    private const val Q22 = 1.7891679e-6
    private const val Q31 = 2.1460748e-6
    private const val Q33 = 2.2123015e-7
    private const val ROOT22 = 1.7891679e-6
    private const val ROOT44 = 7.3636953e-9
    private const val ROOT54 = 2.1765803e-9
    private const val ROOT32 = 3.7393792e-7
    private const val ROOT52 = 1.1428639e-7
    private const val RPTIM = 4.37526908801129966e-3

    private const val FASX2 = 0.13130908
    private const val FASX4 = 2.8843198
    private const val FASX6 = 0.37448087
    private const val G22 = 5.7686396
    private const val G32 = 0.95240898
    private const val G44 = 1.8014998
    private const val G52 = 1.0508330
    private const val G54 = 4.4108898
    private const val STEPP = 720.0
    private const val STEPN = -720.0
    private const val STEP2 = 259200.0

    /** Lunar-solar common terms, produced once at initialization by [dscom]. */
    internal class Common {
        var sinim = 0.0
        var cosim = 0.0
        var sinomm = 0.0
        var cosomm = 0.0
        var day = 0.0
        var e3 = 0.0
        var ee2 = 0.0
        var em = 0.0
        var emsq = 0.0
        var gam = 0.0
        var rtemsq = 0.0
        var se2 = 0.0
        var se3 = 0.0
        var sgh2 = 0.0
        var sgh3 = 0.0
        var sgh4 = 0.0
        var sh2 = 0.0
        var sh3 = 0.0
        var si2 = 0.0
        var si3 = 0.0
        var sl2 = 0.0
        var sl3 = 0.0
        var sl4 = 0.0
        var s1 = 0.0
        var s2 = 0.0
        var s3 = 0.0
        var s4 = 0.0
        var s5 = 0.0
        var s6 = 0.0
        var s7 = 0.0
        var ss1 = 0.0
        var ss2 = 0.0
        var ss3 = 0.0
        var ss4 = 0.0
        var ss5 = 0.0
        var ss6 = 0.0
        var ss7 = 0.0
        var sz1 = 0.0
        var sz2 = 0.0
        var sz3 = 0.0
        var sz11 = 0.0
        var sz12 = 0.0
        var sz13 = 0.0
        var sz21 = 0.0
        var sz22 = 0.0
        var sz23 = 0.0
        var sz31 = 0.0
        var sz32 = 0.0
        var sz33 = 0.0
        var xgh2 = 0.0
        var xgh3 = 0.0
        var xgh4 = 0.0
        var xh2 = 0.0
        var xh3 = 0.0
        var xi2 = 0.0
        var xi3 = 0.0
        var xl2 = 0.0
        var xl3 = 0.0
        var xl4 = 0.0
        var nm = 0.0
        var z1 = 0.0
        var z2 = 0.0
        var z3 = 0.0
        var z11 = 0.0
        var z12 = 0.0
        var z13 = 0.0
        var z21 = 0.0
        var z22 = 0.0
        var z23 = 0.0
        var z31 = 0.0
        var z32 = 0.0
        var z33 = 0.0
        var zmol = 0.0
        var zmos = 0.0
    }

    /** Deep-space secular rates and resonance coefficients, produced once by [dsinit]. */
    internal class Secular {
        var irez = 0
        var atime = 0.0
        var d2201 = 0.0
        var d2211 = 0.0
        var d3210 = 0.0
        var d3222 = 0.0
        var d4410 = 0.0
        var d4422 = 0.0
        var d5220 = 0.0
        var d5232 = 0.0
        var d5421 = 0.0
        var d5433 = 0.0
        var dedt = 0.0
        var didt = 0.0
        var dmdt = 0.0
        var dndt = 0.0
        var dnodt = 0.0
        var domdt = 0.0
        var del1 = 0.0
        var del2 = 0.0
        var del3 = 0.0
        var xfact = 0.0
        var xlamo = 0.0
        var xli = 0.0
        var xni = 0.0
    }

    /** Everything one deep-space element set needs after initialization. */
    internal class Deep(
        val common: Common,
        val secular: Secular,
        val gsto: Double,
        val argpo: Double,
        val argpdot: Double,
        val no: Double,
    )

    /** The lunar-solar perturbed elements returned by [dpper]. */
    internal class Perturbed(
        val ep: Double,
        val inclp: Double,
        val nodep: Double,
        val argpp: Double,
        val mp: Double,
    )

    /** The mean elements after [dspace]. */
    internal class Space(
        val em: Double,
        val argpm: Double,
        val inclm: Double,
        val mm: Double,
        val nodem: Double,
        val nm: Double,
        val dndt: Double,
    )

    private fun mod2pi(value: Double): Double {
        var r = value % TWO_PI
        if (r < 0.0) r += TWO_PI
        return r
    }

    /**
     * Initializes the deep-space terms for one element set. [epochDays1950] is the TLE epoch in
     * days since 1949-12-31 00:00; [ecco], [inclo], [nodeo], [argpo] and [mo] are the un-Kozai
     * mean elements; [noUnkozai] is the mean motion after un-Kozai, in rad/min.
     */
    fun init(
        epochDays1950: Double,
        ecco: Double,
        inclo: Double,
        nodeo: Double,
        argpo: Double,
        mo: Double,
        noUnkozai: Double,
        mdot: Double,
        argpdot: Double,
        nodedot: Double,
    ): Deep {
        val gsto = Sgp4.gstime(epochDays1950 + 2433281.5)
        val common = dscom(epochDays1950, ecco, argpo, inclo, nodeo, noUnkozai)
        val xpidot = argpdot + nodedot
        val secular = dsinit(common, ecco, inclo, nodeo, argpo, mo, noUnkozai, mdot, nodedot,
            xpidot, gsto)
        return Deep(common, secular, gsto, argpo, argpdot, noUnkozai)
    }

    /** The lunar-solar periodics at [t] minutes after epoch, applied to the mean elements. */
    fun dpper(deep: Deep, t: Double, epIn: Double, inclpIn: Double, nodepIn: Double,
        argppIn: Double, mpIn: Double): Perturbed {
        val c = deep.common
        var ep = epIn
        var inclp = inclpIn
        var nodep = nodepIn
        var argpp = argppIn
        var mp = mpIn

        var zm = c.zmos + ZNS * t
        var zf = zm + 2.0 * ZES * sin(zm)
        var sinzf = sin(zf)
        var f2 = 0.5 * sinzf * sinzf - 0.25
        var f3 = -0.5 * sinzf * cos(zf)
        val ses = c.se2 * f2 + c.se3 * f3
        val sis = c.si2 * f2 + c.si3 * f3
        val sls = c.sl2 * f2 + c.sl3 * f3 + c.sl4 * sinzf
        val sghs = c.sgh2 * f2 + c.sgh3 * f3 + c.sgh4 * sinzf
        val shs = c.sh2 * f2 + c.sh3 * f3
        zm = c.zmol + ZNL * t
        zf = zm + 2.0 * ZEL * sin(zm)
        sinzf = sin(zf)
        f2 = 0.5 * sinzf * sinzf - 0.25
        f3 = -0.5 * sinzf * cos(zf)
        val sel = c.ee2 * f2 + c.e3 * f3
        val sil = c.xi2 * f2 + c.xi3 * f3
        val sll = c.xl2 * f2 + c.xl3 * f3 + c.xl4 * sinzf
        val sghl = c.xgh2 * f2 + c.xgh3 * f3 + c.xgh4 * sinzf
        val shll = c.xh2 * f2 + c.xh3 * f3
        val pe = ses + sel
        val pinc = sis + sil
        var pl = sls + sll
        var pgh = sghs + sghl
        var ph = shs + shll

        // The reference subtracts the epoch values here; dscom sets them to zero.
        inclp += pinc
        ep += pe
        val sinip = sin(inclp)
        val cosip = cos(inclp)

        if (inclp >= 0.2) {
            ph /= sinip
            pgh -= cosip * ph
            argpp += pgh
            nodep += ph
            mp += pl
        } else {
            val sinop = sin(nodep)
            val cosop = cos(nodep)
            var alfdp = sinip * sinop
            var betdp = sinip * cosop
            val dalf = ph * cosop + pinc * cosip * sinop
            val dbet = -ph * sinop + pinc * cosip * cosop
            alfdp += dalf
            betdp += dbet
            nodep = mod2pi(nodep)
            val xls = mp + argpp + pl + pgh + (cosip - pinc * sinip) * nodep
            val xnoh = nodep
            nodep = atan2(alfdp, betdp)
            if (abs(xnoh - nodep) > PI_LOCAL) {
                nodep = if (nodep < xnoh) nodep + TWO_PI else nodep - TWO_PI
            }
            mp += pl
            argpp = xls - mp - cosip * nodep
        }
        return Perturbed(ep, inclp, nodep, argpp, mp)
    }

    /** The secular and resonance contributions to the mean elements at [t] minutes. */
    fun dspace(
        deep: Deep,
        t: Double,
        emIn: Double,
        argpmIn: Double,
        inclmIn: Double,
        mmIn: Double,
        nodemIn: Double,
    ): Space {
        val s = deep.secular
        val theta = mod2pi(deep.gsto + t * RPTIM)
        var em = emIn + s.dedt * t
        var inclm = inclmIn + s.didt * t
        var argpm = argpmIn + s.domdt * t
        var nodem = nodemIn + s.dnodt * t
        var mm = mmIn + s.dmdt * t
        val no = deep.no
        var nm = no

        if (s.irez != 0) {
            var atime = 0.0
            var xni = no
            var xli = s.xlamo
            val delt = if (t > 0.0) STEPP else STEPN
            var xndt: Double
            var xldot: Double
            var xnddt: Double
            while (abs(t - atime) >= STEPP) {
                if (s.irez != 2) {
                    xndt = s.del1 * sin(xli - FASX2) +
                        s.del2 * sin(2.0 * (xli - FASX4)) +
                        s.del3 * sin(3.0 * (xli - FASX6))
                    xldot = xni + s.xfact
                    xnddt = s.del1 * cos(xli - FASX2) +
                        2.0 * s.del2 * cos(2.0 * (xli - FASX4)) +
                        3.0 * s.del3 * cos(3.0 * (xli - FASX6))
                    xnddt *= xldot
                } else {
                    val xomi = deep.argpo + deep.argpdot * atime
                    val x2omi = xomi + xomi
                    val x2li = xli + xli
                    xndt = (s.d2201 * sin(x2omi + xli - G22) +
                        s.d2211 * sin(xli - G22) +
                        s.d3210 * sin(xomi + xli - G32) +
                        s.d3222 * sin(-xomi + xli - G32) +
                        s.d4410 * sin(x2omi + x2li - G44) +
                        s.d4422 * sin(x2li - G44) +
                        s.d5220 * sin(xomi + xli - G52) +
                        s.d5232 * sin(-xomi + xli - G52) +
                        s.d5421 * sin(xomi + x2li - G54) +
                        s.d5433 * sin(-xomi + x2li - G54))
                    xldot = xni + s.xfact
                    xnddt = (s.d2201 * cos(x2omi + xli - G22) +
                        s.d2211 * cos(xli - G22) +
                        s.d3210 * cos(xomi + xli - G32) +
                        s.d3222 * cos(-xomi + xli - G32) +
                        s.d5220 * cos(xomi + xli - G52) +
                        s.d5232 * cos(-xomi + xli - G52) +
                        2.0 * (s.d4410 * cos(x2omi + x2li - G44) +
                            s.d4422 * cos(x2li - G44) +
                            s.d5421 * cos(xomi + x2li - G54) +
                            s.d5433 * cos(-xomi + x2li - G54)))
                    xnddt *= xldot
                }
                xli += xldot * delt + xndt * STEP2
                xni += xndt * delt + xnddt * STEP2
                atime += delt
            }
            // The loop above stops inside one step of t, so ft is always in [-720, 720].
            val ft = t - atime
            // Recompute the dot terms at the stopping point, as the reference does.
            if (s.irez != 2) {
                xndt = s.del1 * sin(xli - FASX2) +
                    s.del2 * sin(2.0 * (xli - FASX4)) +
                    s.del3 * sin(3.0 * (xli - FASX6))
                xldot = xni + s.xfact
                xnddt = (s.del1 * cos(xli - FASX2) +
                    2.0 * s.del2 * cos(2.0 * (xli - FASX4)) +
                    3.0 * s.del3 * cos(3.0 * (xli - FASX6))) * xldot
            } else {
                val xomi = deep.argpo + deep.argpdot * atime
                val x2omi = xomi + xomi
                val x2li = xli + xli
                xndt = (s.d2201 * sin(x2omi + xli - G22) +
                    s.d2211 * sin(xli - G22) +
                    s.d3210 * sin(xomi + xli - G32) +
                    s.d3222 * sin(-xomi + xli - G32) +
                    s.d4410 * sin(x2omi + x2li - G44) +
                    s.d4422 * sin(x2li - G44) +
                    s.d5220 * sin(xomi + xli - G52) +
                    s.d5232 * sin(-xomi + xli - G52) +
                    s.d5421 * sin(xomi + x2li - G54) +
                    s.d5433 * sin(-xomi + x2li - G54))
                xldot = xni + s.xfact
                xnddt = (s.d2201 * cos(x2omi + xli - G22) +
                    s.d2211 * cos(xli - G22) +
                    s.d3210 * cos(xomi + xli - G32) +
                    s.d3222 * cos(-xomi + xli - G32) +
                    s.d5220 * cos(xomi + xli - G52) +
                    s.d5232 * cos(-xomi + xli - G52) +
                    2.0 * (s.d4410 * cos(x2omi + x2li - G44) +
                        s.d4422 * cos(x2li - G44) +
                        s.d5421 * cos(xomi + x2li - G54) +
                        s.d5433 * cos(-xomi + x2li - G54))) * xldot
            }
            nm = xni + xndt * ft + xnddt * ft * ft * 0.5
            val xl = xli + xldot * ft + xndt * ft * ft * 0.5
            mm = if (s.irez != 1) xl - 2.0 * nodem + 2.0 * theta else xl - nodem - argpm + theta
            val dndt = nm - no
            nm = no + dndt
        }
        return Space(em, argpm, inclm, mm, nodem, nm, 0.0)
    }

    /** CelesTrak / AIAA dscom: lunar-solar common terms. */
    private fun dscom(
        epochDays1950: Double,
        ep: Double,
        argpp: Double,
        inclp: Double,
        nodep: Double,
        np: Double,
    ): Common {
        val c = Common()
        val em = ep
        val snodm = sin(nodep)
        val cnodm = cos(nodep)
        val sinomm = sin(argpp)
        val cosomm = cos(argpp)
        val sinim = sin(inclp)
        val cosim = cos(inclp)
        val emsq = em * em
        val betasq = 1.0 - emsq
        val rtemsq = sqrt(betasq)

        c.sinim = sinim
        c.cosim = cosim
        c.sinomm = sinomm
        c.cosomm = cosomm
        c.em = em
        c.emsq = emsq
        c.rtemsq = rtemsq
        val day = epochDays1950 + 18261.5
        c.day = day
        val xnodce = mod2pi(4.5236020 - 9.2422029e-4 * day)
        val stem = sin(xnodce)
        val ctem = cos(xnodce)
        val zcosil = 0.91375164 - 0.03568096 * ctem
        val zsinil = sqrt(1.0 - zcosil * zcosil)
        val zsinhl = 0.089683511 * stem / zsinil
        val zcoshl = sqrt(1.0 - zsinhl * zsinhl)
        val gam = 5.8351514 + 0.0019443680 * day
        var zx = 0.39785416 * stem / zsinil
        val zy = zcoshl * ctem + 0.91744867 * zsinhl * stem
        zx = atan2(zx, zy)
        zx = gam + zx - xnodce
        val zcosgl = cos(zx)
        val zsingl = sin(zx)
        c.gam = gam

        var zcosg = ZCOSGS
        var zsing = ZSINGS
        var zcosi = ZCOSIS
        var zsini = ZSINIS
        var zcosh = cnodm
        var zsinh = snodm
        var cc = C1SS
        val xnoi = 1.0 / np

        var ss1 = 0.0
        var ss2 = 0.0
        var ss3 = 0.0
        var ss4 = 0.0
        var ss5 = 0.0
        var ss6 = 0.0
        var ss7 = 0.0
        var sz1 = 0.0
        var sz2 = 0.0
        var sz3 = 0.0
        var sz11 = 0.0
        var sz12 = 0.0
        var sz13 = 0.0
        var sz21 = 0.0
        var sz22 = 0.0
        var sz23 = 0.0
        var sz31 = 0.0
        var sz32 = 0.0
        var sz33 = 0.0
        var s1 = 0.0
        var s2 = 0.0
        var s3 = 0.0
        var s4 = 0.0
        var s5 = 0.0
        var s6 = 0.0
        var s7 = 0.0
        var z1 = 0.0
        var z2 = 0.0
        var z3 = 0.0
        var z11 = 0.0
        var z12 = 0.0
        var z13 = 0.0
        var z21 = 0.0
        var z22 = 0.0
        var z23 = 0.0
        var z31 = 0.0
        var z32 = 0.0
        var z33 = 0.0

        for (lsflg in 1..2) {
            val a1 = zcosg * zcosh + zsing * zcosi * zsinh
            val a3 = -zsing * zcosh + zcosg * zcosi * zsinh
            val a7 = -zcosg * zsinh + zsing * zcosi * zcosh
            val a8 = zsing * zsini
            val a9 = zsing * zsinh + zcosg * zcosi * zcosh
            val a10 = zcosg * zsini
            val a2 = cosim * a7 + sinim * a8
            val a4 = cosim * a9 + sinim * a10
            val a5 = -sinim * a7 + cosim * a8
            val a6 = -sinim * a9 + cosim * a10

            val x1 = a1 * cosomm + a2 * sinomm
            val x2 = a3 * cosomm + a4 * sinomm
            val x3 = -a1 * sinomm + a2 * cosomm
            val x4 = -a3 * sinomm + a4 * cosomm
            val x5 = a5 * sinomm
            val x6 = a6 * sinomm
            val x7 = a5 * cosomm
            val x8 = a6 * cosomm

            z31 = 12.0 * x1 * x1 - 3.0 * x3 * x3
            z32 = 24.0 * x1 * x2 - 6.0 * x3 * x4
            z33 = 12.0 * x2 * x2 - 3.0 * x4 * x4
            z1 = 3.0 * (a1 * a1 + a2 * a2) + z31 * emsq
            z2 = 6.0 * (a1 * a3 + a2 * a4) + z32 * emsq
            z3 = 3.0 * (a3 * a3 + a4 * a4) + z33 * emsq
            z11 = -6.0 * a1 * a5 + emsq * (-24.0 * x1 * x7 - 6.0 * x3 * x5)
            z12 = -6.0 * (a1 * a6 + a3 * a5) +
                emsq * (-24.0 * (x2 * x7 + x1 * x8) - 6.0 * (x3 * x6 + x4 * x5))
            z13 = -6.0 * a3 * a6 + emsq * (-24.0 * x2 * x8 - 6.0 * x4 * x6)
            z21 = 6.0 * a2 * a5 + emsq * (24.0 * x1 * x5 - 6.0 * x3 * x7)
            z22 = 6.0 * (a4 * a5 + a2 * a6) +
                emsq * (24.0 * (x2 * x5 + x1 * x6) - 6.0 * (x4 * x7 + x3 * x8))
            z23 = 6.0 * a4 * a6 + emsq * (24.0 * x2 * x6 - 6.0 * x4 * x8)
            z1 = z1 + z1 + betasq * z31
            z2 = z2 + z2 + betasq * z32
            z3 = z3 + z3 + betasq * z33
            s3 = cc * xnoi
            s2 = -0.5 * s3 / rtemsq
            s4 = s3 * rtemsq
            s1 = -15.0 * em * s4
            s5 = x1 * x3 + x2 * x4
            s6 = x2 * x3 + x1 * x4
            s7 = x2 * x4 - x1 * x3

            if (lsflg == 1) {
                ss1 = s1
                ss2 = s2
                ss3 = s3
                ss4 = s4
                ss5 = s5
                ss6 = s6
                ss7 = s7
                sz1 = z1
                sz2 = z2
                sz3 = z3
                sz11 = z11
                sz12 = z12
                sz13 = z13
                sz21 = z21
                sz22 = z22
                sz23 = z23
                sz31 = z31
                sz32 = z32
                sz33 = z33
                zcosg = zcosgl
                zsing = zsingl
                zcosi = zcosil
                zsini = zsinil
                zcosh = zcoshl * cnodm + zsinhl * snodm
                zsinh = snodm * zcoshl - cnodm * zsinhl
                cc = C1L
            }
        }

        c.zmol = mod2pi(4.7199672 + 0.22997150 * day - gam)
        c.zmos = mod2pi(6.2565837 + 0.017201977 * day)

        c.se2 = 2.0 * ss1 * ss6
        c.se3 = 2.0 * ss1 * ss7
        c.si2 = 2.0 * ss2 * sz12
        c.si3 = 2.0 * ss2 * (sz13 - sz11)
        c.sl2 = -2.0 * ss3 * sz2
        c.sl3 = -2.0 * ss3 * (sz3 - sz1)
        c.sl4 = -2.0 * ss3 * (-21.0 - 9.0 * emsq) * ZES
        c.sgh2 = 2.0 * ss4 * sz32
        c.sgh3 = 2.0 * ss4 * (sz33 - sz31)
        c.sgh4 = -18.0 * ss4 * ZES
        c.sh2 = -2.0 * ss2 * sz22
        c.sh3 = -2.0 * ss2 * (sz23 - sz21)

        c.ee2 = 2.0 * s1 * s6
        c.e3 = 2.0 * s1 * s7
        c.xi2 = 2.0 * s2 * z12
        c.xi3 = 2.0 * s2 * (z13 - z11)
        c.xl2 = -2.0 * s3 * z2
        c.xl3 = -2.0 * s3 * (z3 - z1)
        c.xl4 = -2.0 * s3 * (-21.0 - 9.0 * emsq) * ZEL
        c.xgh2 = 2.0 * s4 * z32
        c.xgh3 = 2.0 * s4 * (z33 - z31)
        c.xgh4 = -18.0 * s4 * ZEL
        c.xh2 = -2.0 * s2 * z22
        c.xh3 = -2.0 * s2 * (z23 - z21)

        c.s1 = s1
        c.s2 = s2
        c.s3 = s3
        c.s4 = s4
        c.s5 = s5
        c.s6 = s6
        c.s7 = s7
        c.ss1 = ss1
        c.ss2 = ss2
        c.ss3 = ss3
        c.ss4 = ss4
        c.ss5 = ss5
        c.ss6 = ss6
        c.ss7 = ss7
        c.sz1 = sz1
        c.sz2 = sz2
        c.sz3 = sz3
        c.sz11 = sz11
        c.sz12 = sz12
        c.sz13 = sz13
        c.sz21 = sz21
        c.sz22 = sz22
        c.sz23 = sz23
        c.sz31 = sz31
        c.sz32 = sz32
        c.sz33 = sz33
        c.z1 = z1
        c.z2 = z2
        c.z3 = z3
        c.z11 = z11
        c.z12 = z12
        c.z13 = z13
        c.z21 = z21
        c.z22 = z22
        c.z23 = z23
        c.z31 = z31
        c.z32 = z32
        c.z33 = z33
        c.nm = np
        return c
    }

    /** CelesTrak / AIAA dsinit: secular rates and resonance coefficients. */
    private fun dsinit(
        c: Common,
        ecco: Double,
        inclm: Double,
        nodeo: Double,
        argpo: Double,
        mo: Double,
        no: Double,
        mdot: Double,
        nodedot: Double,
        xpidot: Double,
        gsto: Double,
    ): Secular {
        val s = Secular()
        val cosim = c.cosim
        val sinim = c.sinim
        val emsq = c.emsq
        val em = c.em
        val eccsq = ecco * ecco

        var irez = 0
        if (0.0034906585 < no && no < 0.0052359877) irez = 1
        if (no >= 8.26e-3 && no <= 9.24e-3 && em >= 0.5) irez = 2
        s.irez = irez

        val ses = c.ss1 * ZNS * c.ss5
        val sis = c.ss2 * ZNS * (c.sz11 + c.sz13)
        val sls = -ZNS * c.ss3 * (c.sz1 + c.sz3 - 14.0 - 6.0 * emsq)
        val sghs = c.ss4 * ZNS * (c.sz31 + c.sz33 - 6.0)
        var shs = -ZNS * c.ss2 * (c.sz21 + c.sz23)
        if (inclm < 5.2359877e-2 || inclm > PI_LOCAL - 5.2359877e-2) shs = 0.0
        if (sinim != 0.0) shs /= sinim
        val sgs = sghs - cosim * shs

        s.dedt = ses + c.s1 * ZNL * c.s5
        s.didt = sis + c.s2 * ZNL * (c.z11 + c.z13)
        s.dmdt = sls - ZNL * c.s3 * (c.z1 + c.z3 - 14.0 - 6.0 * emsq)
        val sghl = c.s4 * ZNL * (c.z31 + c.z33 - 6.0)
        var shll = -ZNL * c.s2 * (c.z21 + c.z23)
        if (inclm < 5.2359877e-2 || inclm > PI_LOCAL - 5.2359877e-2) shll = 0.0
        s.domdt = sgs + sghl
        s.dnodt = shs
        if (sinim != 0.0) {
            s.domdt -= cosim / sinim * shll
            s.dnodt += shll / sinim
        }
        s.dndt = 0.0

        if (irez != 0) {
            val aonv = (no / XKE).pow(X2O3)
            if (irez == 2) {
                val cosisq = cosim * cosim
                val emo = em
                var emr = ecco
                val emsqo = emsq
                var emsqr = eccsq
                var eoc = emr * emsqr
                val g201 = -0.306 - (emr - 0.64) * 0.440
                var g211: Double
                var g310: Double
                var g322: Double
                var g410: Double
                var g422: Double
                var g520: Double
                if (emr <= 0.65) {
                    g211 = 3.616 - 13.2470 * emr + 16.2900 * emsqr
                    g310 = -19.302 + 117.3900 * emr - 228.4190 * emsqr + 156.5910 * eoc
                    g322 = -18.9068 + 109.7927 * emr - 214.6334 * emsqr + 146.5816 * eoc
                    g410 = -41.122 + 242.6940 * emr - 471.0940 * emsqr + 313.9530 * eoc
                    g422 = -146.407 + 841.8800 * emr - 1629.014 * emsqr + 1083.4350 * eoc
                    g520 = -532.114 + 3017.977 * emr - 5740.032 * emsqr + 3708.2760 * eoc
                } else {
                    g211 = -72.099 + 331.819 * emr - 508.738 * emsqr + 266.724 * eoc
                    g310 = -346.844 + 1582.851 * emr - 2415.925 * emsqr + 1246.113 * eoc
                    g322 = -342.585 + 1554.908 * emr - 2366.899 * emsqr + 1215.972 * eoc
                    g410 = -1052.797 + 4758.686 * emr - 7193.992 * emsqr + 3651.957 * eoc
                    g422 = -3581.690 + 16178.110 * emr - 24462.770 * emsqr + 12422.520 * eoc
                    g520 = if (emr > 0.715) {
                        -5149.66 + 29936.92 * emr - 54087.36 * emsqr + 31324.56 * eoc
                    } else {
                        1464.74 - 4664.75 * emr + 3763.64 * emsqr
                    }
                }
                var g533: Double
                var g521: Double
                var g532: Double
                if (emr < 0.7) {
                    g533 = -919.22770 + 4988.6100 * emr - 9064.7700 * emsqr + 5542.21 * eoc
                    g521 = -822.71072 + 4568.6173 * emr - 8491.4146 * emsqr + 5337.524 * eoc
                    g532 = -853.66600 + 4690.2500 * emr - 8624.7700 * emsqr + 5341.4 * eoc
                } else {
                    g533 = -37995.780 + 161616.52 * emr - 229838.20 * emsqr + 109377.94 * eoc
                    g521 = -51752.104 + 218913.95 * emr - 309468.16 * emsqr + 146349.42 * eoc
                    g532 = -40023.880 + 170470.89 * emr - 242699.48 * emsqr + 115605.82 * eoc
                }
                val sini2 = sinim * sinim
                val f220 = 0.75 * (1.0 + 2.0 * cosim + cosisq)
                val f221 = 1.5 * sini2
                val f321 = 1.875 * sinim * (1.0 - 2.0 * cosim - 3.0 * cosisq)
                val f322 = -1.875 * sinim * (1.0 + 2.0 * cosim - 3.0 * cosisq)
                val f441 = 35.0 * sini2 * f220
                val f442 = 39.3750 * sini2 * sini2
                val f522 = 9.84375 * sinim * (sini2 * (1.0 - 2.0 * cosim - 5.0 * cosisq) +
                    0.33333333 * (-2.0 + 4.0 * cosim + 6.0 * cosisq))
                val f523 = sinim * (4.92187512 * sini2 * (-2.0 - 4.0 * cosim +
                    10.0 * cosisq) + 6.56250012 * (1.0 + 2.0 * cosim - 3.0 * cosisq))
                val f542 = 29.53125 * sinim * (2.0 - 8.0 * cosim +
                    cosisq * (-12.0 + 8.0 * cosim + 10.0 * cosisq))
                val f543 = 29.53125 * sinim * (-2.0 - 8.0 * cosim +
                    cosisq * (12.0 + 8.0 * cosim - 10.0 * cosisq))
                val xno2 = no * no
                val ainv2 = aonv * aonv
                var temp1 = 3.0 * xno2 * ainv2
                var temp = temp1 * ROOT22
                s.d2201 = temp * f220 * g201
                s.d2211 = temp * f221 * g211
                temp1 *= aonv
                temp = temp1 * ROOT32
                s.d3210 = temp * f321 * g310
                s.d3222 = temp * f322 * g322
                temp1 *= aonv
                temp = 2.0 * temp1 * ROOT44
                s.d4410 = temp * f441 * g410
                s.d4422 = temp * f442 * g422
                temp1 *= aonv
                temp = temp1 * ROOT52
                s.d5220 = temp * f522 * g520
                s.d5232 = temp * f523 * g532
                temp = 2.0 * temp1 * ROOT54
                s.d5421 = temp * f542 * g521
                s.d5433 = temp * f543 * g533
                // theta at epoch is gsto, so the reference's mo + 2 nodeo - 2 theta applies.
                s.xlamo = mod2pi(mo + 2.0 * nodeo - 2.0 * gsto)
                s.xfact = mdot + s.dmdt + 2.0 * (nodedot + s.dnodt - RPTIM) - no
                emr = emo
                emsqr = emsqo
            }
            if (irez == 1) {
                val g200 = 1.0 + emsq * (-2.5 + 0.8125 * emsq)
                val g310 = 1.0 + 2.0 * emsq
                val g300 = 1.0 + emsq * (-6.0 + 6.60937 * emsq)
                val f220 = 0.75 * (1.0 + cosim) * (1.0 + cosim)
                val f311 = 0.9375 * sinim * sinim * (1.0 + 3.0 * cosim) -
                    0.75 * (1.0 + cosim)
                var f330 = 1.0 + cosim
                f330 = 1.875 * f330 * f330 * f330
                var del1 = 3.0 * no * no * aonv * aonv
                s.del2 = 2.0 * del1 * f220 * g200 * Q22
                s.del3 = 3.0 * del1 * f330 * g300 * Q33 * aonv
                s.del1 = del1 * f311 * g310 * Q31 * aonv
                s.xlamo = mod2pi(mo + nodeo + argpo - gsto)
                s.xfact = mdot + xpidot - RPTIM + s.dmdt + s.domdt + s.dnodt - no
            }
            s.xli = s.xlamo
            s.xni = no
            s.atime = 0.0
        }
        return s
    }
}
