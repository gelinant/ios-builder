package app.vela.core.util

import kotlin.math.abs

/**
 * Number formatting with the JVM's output, for code that used `String.format(Locale.US, ...)`.
 * `jvmTest` checks every formatter here against `String.format`.
 */
object Fmt {
    /**
     * `String.format(Locale.US, "%.${decimals}f", value)`. Like the JVM's `Formatter`, it rounds the
     * shortest decimal form of [value] (the digits of `toString`) half up, so `0.125` gives `0.13`
     * at two places. Negative zero keeps its sign; NaN and the infinities print as the JVM does.
     */
    fun fixed(value: Double, decimals: Int): String {
        require(decimals >= 0) { "decimals < 0" }
        if (value.isNaN()) return "NaN"
        val neg = value < 0.0 || (value == 0.0 && 1.0 / value < 0.0)
        val v = abs(value)
        val sign = if (neg) "-" else ""
        if (v.isInfinite()) return sign + "Infinity"
        if (v == 0.0) return sign + "0" + (if (decimals > 0) "." + "0".repeat(decimals) else "")

        // v = 0.DIGITS x 10^decExp, DIGITS without leading or trailing zeros.
        val s = v.toString()
        val e = s.indexOfAny(charArrayOf('E', 'e'))
        val mant = if (e >= 0) s.substring(0, e) else s
        val exp10 = if (e >= 0) s.substring(e + 1).toInt() else 0
        val dot = mant.indexOf('.')
        val intPart = if (dot >= 0) mant.substring(0, dot) else mant
        val all = intPart + (if (dot >= 0) mant.substring(dot + 1) else "")
        val lead = all.indexOfFirst { it != '0' }
        var decExp = intPart.length + exp10 - lead
        val digits = all.substring(lead).trimEnd('0').toCharArray()

        // FormattedFloatingDecimal.applyPrecision: keep decExp + decimals digits, half up.
        val n = digits.size
        val prec = decExp + decimals
        var kept = n
        if (prec in 0 until n) {
            kept = prec
            if (prec == 0) {
                if (digits[0] >= '5') {
                    digits[0] = '1'; kept = 1; decExp++
                } else {
                    kept = 0
                }
            } else if (digits[prec] >= '5') {
                var i = prec - 1
                while (i >= 0 && digits[i] == '9') i--
                if (i < 0) {
                    digits[0] = '1'; kept = 1; decExp++
                } else {
                    digits[i] = digits[i] + 1
                    kept = i + 1
                }
            }
        }

        fun digitAt(pos: Int): Char = if (pos in 0 until kept) digits[pos] else '0'
        val sb = StringBuilder(sign)
        if (decExp <= 0) sb.append('0') else for (p in 0 until decExp) sb.append(digitAt(p))
        if (decimals > 0) {
            sb.append('.')
            for (k in 0 until decimals) sb.append(digitAt(decExp + k))
        }
        return sb.toString()
    }
}
