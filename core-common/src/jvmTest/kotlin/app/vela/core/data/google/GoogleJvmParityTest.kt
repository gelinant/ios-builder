package app.vela.core.data.google

import app.vela.core.data.ClockFormat
import java.math.BigDecimal
import java.math.BigInteger
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.random.Random
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals

/** The common code of lot C-2 against the JDK calls it replaced, so Android prints what it did. */
class GoogleJvmParityTest {

    @AfterTest fun reset() {
        ClockFormat.use24h = false
    }

    @Test fun downlinkAndRttHintsMatchTheJdk() {
        val r = Random(7)
        repeat(20_000) {
            val kbps = r.nextInt(0, 20_000)
            val noise = r.nextDouble(0.8, 1.2)
            val k = Math.round((kbps * noise).coerceIn(0.0, 10_000.0) / 50.0) * 50
            assertEquals(BigDecimal(k).movePointLeft(3).stripTrailingZeros().toPlainString(), BrowserHeaders.downlinkHint(kbps, noise), "$kbps x $noise")
            val ms = r.nextInt(0, 4_000)
            assertEquals((Math.round((ms * noise).coerceIn(0.0, 3000.0) / 50.0) * 50).toString(), BrowserHeaders.rttHint(ms, noise), "$ms x $noise")
        }
    }

    @Test fun clockTimesMatchDateTimeFormatter() {
        val zones = listOf("America/Los_Angeles", "Europe/Paris", "Asia/Kolkata", "Australia/Lord_Howe", "UTC")
        val r = Random(3)
        for (use24h in listOf(false, true)) {
            ClockFormat.use24h = use24h
            val f = DateTimeFormatter.ofPattern(if (use24h) "HH:mm" else "h:mm a", Locale.US)
            repeat(5_000) {
                val epoch = r.nextLong(1_000_000_000L, 2_500_000_000L)
                val zone = zones[it % zones.size]
                assertEquals(
                    f.format(Instant.ofEpochSecond(epoch).atZone(ZoneId.of(zone))),
                    ClockFormat.at(epoch, kotlinx.datetime.TimeZone.of(zone)),
                    "$epoch in $zone, 24h $use24h",
                )
            }
        }
    }

    @Test fun featureIdHalvesMatchBigInteger() {
        val r = Random(11)
        val hex = (List(2_000) { r.nextLong().toULong().toString(16) } + listOf("0", "ffffffffffffffff", "8000000000000000", "00ab"))
        for (h in hex) assertEquals(BigInteger(h, 16).toString(), h.toULong(16).toString(), h)
    }

    @Test fun twoComplementHexMatchesStringFormat() {
        val r = Random(5)
        repeat(2_000) {
            val h = r.nextLong()
            val l = r.nextLong()
            assertEquals(
                String.format("0x%016x:0x%016x", h, l),
                "0x${h.toULong().toString(16).padStart(16, '0')}:0x${l.toULong().toString(16).padStart(16, '0')}",
            )
        }
    }
}
