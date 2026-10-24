#!/usr/bin/env python3
"""Dependency and portability map of :core for the move to :core-common.

Reads core/src/main/java (and core/src/test/java, plus app/.../offline for lot C-8),
lexes every Kotlin file (comments and string literals removed, string templates kept),
resolves in-module references (explicit imports, star imports, same-package names,
fully qualified app.vela.core.* chains), detects JVM/Android blockers, classifies each
file PURE / MECHANICAL / SEAM / STAYS, and computes strongly connected components and
a wave-by-wave move order.

Usage:
  python3 scripts/ios/core_deps.py                       # short summary on stdout
  python3 scripts/ios/core_deps.py --md docs/ios/CORE-MIGRATION.md
  python3 scripts/ios/core_deps.py --json /tmp/opencode/core-graph.json
  python3 scripts/ios/core_deps.py --file data/google/parse/SearchParser.kt

--md only rewrites the blocks between <!-- BEGIN GENERATED: x --> and
<!-- END GENERATED: x --> markers; hand-written text outside them is kept. A missing
file is created from a skeleton.
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAIN_DIR = "core/src/main/java"
TEST_DIR = "core/src/test/java"
APP_OFFLINE_DIR = "app/src/main/java/app/vela/offline"
CORE_PREFIX = "app/vela/core/"
C8_APP_FILES = [
    "PmtilesReader.kt", "PmtilesCompact.kt", "PmtilesPatch.kt", "RegionCatalog.kt",
    "RegionPolys.kt", "PlacesArchiveSearch.kt",
]

PURE, MECH, SEAM, STAYS = "PURE", "MECHANICAL", "SEAM", "STAYS"
CLASS_RANK = {PURE: 0, MECH: 1, SEAM: 2, STAYS: 3}

# ---------------------------------------------------------------------------
# Lexer
# ---------------------------------------------------------------------------


def lex(src):
    """Returns (code, strings). `code` has the same length and line breaks as `src`, with
    comments and string-literal text blanked (template expressions kept as code). `strings`
    is a list of (offset, literal text)."""
    n = len(src)
    out = list(src)
    strings = []

    def blank(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    def block_comment(i):
        depth = 0
        while i < n:
            if src.startswith("/*", i):
                depth += 1
                i += 2
            elif src.startswith("*/", i):
                depth -= 1
                i += 2
                if depth == 0:
                    return i
            else:
                i += 1
        return n

    def char_lit(i):
        # 'a', '\n', '\u00e9', '\''
        j = i + 1
        if j < n and src[j] == "\\":
            j += 2
            while j < n and src[j] != "'" and src[j] != "\n":
                j += 1
        else:
            j += 1
        if j < n and src[j] == "'":
            blank(i + 1, j)
            return j + 1
        return i + 1  # not a char literal (should not happen in valid Kotlin)

    def string(i):
        raw = src.startswith('"""', i)
        i += 3 if raw else 1
        start = i
        buf = []
        while i < n:
            c = src[i]
            if raw and src.startswith('"""', i):
                j = i + 3
                while j < n and src[j] == '"':
                    j += 1
                # Extra quotes before the closing triple belong to the content.
                buf.append(src[i:j - 3])
                blank(i, j - 3)
                strings.append((start, "".join(buf)))
                return j
            if not raw and c == '"':
                strings.append((start, "".join(buf)))
                return i + 1
            if not raw and c == "\\":
                buf.append(src[i:i + 2])
                blank(i, i + 2)
                i += 2
                continue
            if not raw and c == "\n":  # unterminated, bail out
                strings.append((start, "".join(buf)))
                return i
            if c == "$" and i + 1 < n and src[i + 1] == "{":
                out[i] = " "
                out[i + 1] = " "
                buf.append("${}")
                j = code(i + 2, True)
                if j < n:
                    out[j] = " "
                i = j + 1
                continue
            if c == "$" and i + 1 < n and (src[i + 1].isalpha() or src[i + 1] == "_"):
                out[i] = " "
                j = i + 1
                while j < n and (src[j].isalnum() or src[j] == "_"):
                    j += 1
                buf.append("$")
                i = j  # identifier kept as code
                continue
            buf.append(c)
            if c != "\n":
                out[i] = " "
            i += 1
        strings.append((start, "".join(buf)))
        return n

    def code(i, in_template):
        depth = 0
        while i < n:
            c = src[i]
            if c == "/" and src.startswith("//", i):
                j = src.find("\n", i)
                j = n if j < 0 else j
                blank(i, j)
                i = j
                continue
            if c == "/" and src.startswith("/*", i):
                j = block_comment(i)
                blank(i, j)
                i = j
                continue
            if c == '"':
                i = string(i)
                continue
            if c == "'":
                i = char_lit(i)
                continue
            if c == "`":
                j = src.find("`", i + 1)
                if j > 0 and "\n" not in src[i:j]:
                    i = j + 1
                    continue
            if c == "{":
                depth += 1
            elif c == "}":
                if in_template and depth == 0:
                    return i
                depth -= 1
            i += 1
        return i

    code(0, False)
    return "".join(out), strings


def mask_depth0(code):
    """Keeps only text at bracket depth 0 (brackets themselves kept)."""
    out = []
    depth = 0
    for c in code:
        if c in "([{":
            out.append(c if depth == 0 else " ")
            depth += 1
        elif c in ")]}":
            depth = max(0, depth - 1)
            out.append(c if depth == 0 else " ")
        elif depth > 0 and c != "\n":
            out.append(" ")
        else:
            out.append(c)
    return "".join(out)


# ---------------------------------------------------------------------------
# Declarations and references
# ---------------------------------------------------------------------------

MODIFIERS = (r"(?:(?:public|internal|private|protected|data|sealed|enum|annotation|value|inline|"
             r"open|abstract|final|const|lateinit|suspend|infix|operator|tailrec|external|expect|"
             r"actual|fun(?=\s+interface)|@[\w.:]+(?:\([^)\n]*\))?)\s+)*")
GENERIC = r"<(?:[^<>]|<(?:[^<>]|<[^<>]*>)*>)*>"
DECL_RE = re.compile(r"(?m)^[ \t]*(" + MODIFIERS + r")(class|interface|object|typealias|fun|val|var)\b")
IDENT_RE = re.compile(r"`[^`\n]+`|[A-Za-z_][A-Za-z0-9_]*")
PACKAGE_RE = re.compile(r"(?m)^\s*package\s+([\w.]+)")
IMPORT_RE = re.compile(r"(?m)^\s*import\s+(\w+(?:\.\w+)*)(\.\*)?(?:\s+as\s+(\w+))?")
FQ_RE = re.compile(r"(?<![\w.])app\.vela\.(?:core|offline)(?:\s*\.\s*\w+)+")


def strip_generic_prefix(s):
    s = s.lstrip()
    if s.startswith("<"):
        m = re.match(GENERIC, s)
        if m:
            s = s[m.end():]
    return s.strip()


def split_receiver(segment):
    """'List<T>.foo' -> ('List<T>', 'foo'); 'foo' -> (None, 'foo')."""
    depth = 0
    last_dot = -1
    for k, c in enumerate(segment):
        if c == "<":
            depth += 1
        elif c == ">":
            depth -= 1
        elif c == "." and depth == 0:
            last_dot = k
    name = segment[last_dot + 1:] if last_dot >= 0 else segment
    recv = segment[:last_dot] if last_dot >= 0 else None
    m = IDENT_RE.match(name.strip())
    if not m:
        return recv, None
    return recv, m.group(0).strip("`")


def top_level_decls(code):
    d0 = mask_depth0(code)
    decls = []
    for m in DECL_RE.finditer(d0):
        kw = m.group(2)
        private = re.search(r"\bprivate\b", m.group(1)) is not None
        rest = d0[m.end():]
        line = code.count("\n", 0, m.start()) + 1
        before = len(decls)
        if kw in ("class", "interface", "object", "typealias"):
            mm = re.match(r"\s+(`[^`]+`|\w+)", rest)
            if mm:
                decls.append({"name": mm.group(1).strip("`"), "kind": "type", "ext": False, "line": line})
        elif kw == "fun":
            seg = rest.split("(", 1)[0]
            seg = strip_generic_prefix(seg)
            recv, name = split_receiver(seg)
            if name:
                decls.append({"name": name, "kind": "fun", "ext": recv is not None, "line": line})
        else:
            seg = re.split(r"[:=\n{]| by ", rest, maxsplit=1)[0]
            seg = strip_generic_prefix(seg)
            if seg.startswith("("):
                continue  # destructuring
            recv, name = split_receiver(seg)
            if name:
                decls.append({"name": name, "kind": "val", "ext": recv is not None, "line": line})
        for d in decls[before:]:
            d["private"] = private
    return decls


def local_names(code):
    """Names declared anywhere in the file (shadowing guard for same-package lookup)."""
    types = set(re.findall(r"\b(?:class|interface|object|typealias)\s+(\w+)", code))
    funs = set()
    for m in re.finditer(r"\bfun\s+(" + GENERIC + r"\s*)?([^(=\n{]*)\(", code):
        _, name = split_receiver(m.group(2).strip())
        if name:
            funs.add(name)
    vals = set(re.findall(r"\b(?:val|var)\s+(\w+)", code))
    vals |= set(re.findall(r"[(,]\s*(?:vararg\s+|crossinline\s+|noinline\s+)?(?:(?:val|var)\s+)?(\w+)\s*:(?!:)", code))
    for m in re.finditer(r"\{\s*(\w+(?:\s*,\s*\w+)*)\s*->", code):
        for part in m.group(1).split(","):
            vals.add(part.strip())
    vals |= set(re.findall(r"\bfor\s*\(\s*(\w+)\s+in\b", code))
    vals |= set(re.findall(r"\bcatch\s*\(\s*(\w+)\s*:", code))
    return types, funs, vals


def identifier_uses(code):
    """name -> set of usage flags: 'bare', 'dot', 'call', 'ref'."""
    uses = defaultdict(set)
    n = len(code)
    for m in IDENT_RE.finditer(code):
        name = m.group(0).strip("`")
        a = m.start()
        b = m.end()
        p = a - 1
        while p >= 0 and code[p] in " \t\n":
            p -= 1
        prev = code[p] if p >= 0 else ""
        prev2 = code[p - 1:p + 1] if p >= 1 else ""
        q = b
        while q < n and code[q] in " \t":
            q += 1
        nxt = code[q] if q < n else ""
        flags = uses[name]
        if prev2 == "::":
            flags.add("ref")
        elif prev == ".":
            flags.add("dot")
        else:
            flags.add("bare")
        if nxt in "({" or (nxt == "<" and re.match(GENERIC + r"\s*\(", code[q:q + 120] or "")):
            if prev == ".":
                flags.add("dotcall")
            elif prev2 != "::":
                flags.add("call")
    return uses


# ---------------------------------------------------------------------------
# Blockers
# ---------------------------------------------------------------------------

# (id, class, seam or fix, regex on code, label). Code has comments and strings blanked.
NOT_DOT = r"(?<![\w.])"
RULES = [
    # STAYS
    ("osmand", STAYS, "OsmAnd", NOT_DOT + r"net\.osmand\.", "net.osmand (OsmAnd)"),
    ("hilt-module", STAYS, "Hilt", r"@(?:Module|InstallIn|Provides)\b", "@Module/@Provides Hilt"),
    ("cronet", STAYS, "Cronet", NOT_DOT + r"org\.chromium\.", "Cronet"),
    # SEAM: Android
    ("android-log", SEAM, "Log", NOT_DOT + r"android\.util\.Log\b", "android.util.Log"),
    ("android-prefs", SEAM, "KeyValueStore", r"\bSharedPreferences\b|getSharedPreferences|" + NOT_DOT + r"androidx\.core\.content\.edit\b", "SharedPreferences"),
    ("android-sqlite", SEAM, "SqlDb", NOT_DOT + r"android\.database\b|\bSQLiteOpenHelper\b|\bSQLiteDatabase\b", "SQLite Android"),
    ("android-location", SEAM, "LocationSource", NOT_DOT + r"android\.location\.", "android.location"),
    ("android-sensors", SEAM, "HeadingSource", NOT_DOT + r"android\.hardware\.", "capteurs android.hardware"),
    ("android-speech", SEAM, "SpeechSynth", NOT_DOT + r"android\.(?:speech|media)\.", "TTS / audio Android"),
    ("android-icu", SEAM, "PlatformLocale/TextNormalizer", NOT_DOT + r"android\.icu\.", "android.icu"),
    ("android-context", SEAM, "PlatformFiles/CoreGraph", NOT_DOT + r"android\.content\.Context\b|@ApplicationContext\b", "Context Android"),
    ("android-clock", MECH, "Clock", NOT_DOT + r"android\.os\.SystemClock\b|\bSystemClock\.", "SystemClock"),
    ("android-other", SEAM, "Android", NOT_DOT + r"androidx?\.(?!util\.Log\b|database\b|location\.|hardware\.|speech\.|media\.|icu\.|content\.Context\b|content\.SharedPreferences\b|os\.SystemClock\b|core\.content\.edit\b)\w+", "autre API android/androidx"),
    # SEAM: network, JS, files, crypto
    ("okhttp", SEAM, "VelaHttp", NOT_DOT + r"okhttp3\.", "okhttp3"),
    ("rhino", SEAM, "JsEngine", NOT_DOT + r"org\.mozilla\.", "Rhino"),
    ("file", SEAM, "PlatformFiles", NOT_DOT + r"java\.io\.(?:File|FileInputStream|FileOutputStream|RandomAccessFile|FileReader|FileWriter|FileNotFoundException)\b|" + NOT_DOT + r"java\.nio\.(?:file|channels)\.", "java.io.File / java.nio.file"),
    ("stream", SEAM, "PlatformFiles/VelaHttp (flux)", NOT_DOT + r"java\.io\.(?:InputStream|OutputStream|Reader|Writer|BufferedReader|BufferedWriter|InputStreamReader|OutputStreamWriter|BufferedInputStream|BufferedOutputStream|DataInputStream|DataOutputStream|ByteArrayInputStream|PushbackInputStream|Closeable|PrintWriter|StringReader|StringWriter|FilterInputStream)\b|\b(?:decodeFromStream|encodeToStream)\b", "flux java.io"),
    ("zip", SEAM, "Unzip", NOT_DOT + r"java\.util\.zip\.(?!CRC32\b)\w+", "java.util.zip"),
    ("crypto", SEAM, "SignatureVerifier", NOT_DOT + r"java\.security\.|" + NOT_DOT + r"javax\.crypto\.", "java.security / javax.crypto"),
    ("net-conn", SEAM, "VelaHttp", NOT_DOT + r"java\.net\.(?:URL|HttpURLConnection|InetAddress|Socket|InetSocketAddress|UnknownHostException|SocketTimeoutException|ConnectException|SocketException)\b", "java.net connexion"),
    ("normalizer", SEAM, "TextNormalizer", NOT_DOT + r"java\.text\.Normalizer\b|\bNormalizer\.", "java.text.Normalizer"),
    ("threads", SEAM, "threads (hors liste)", r"(?<![\w.])Thread\b|" + NOT_DOT + r"java\.util\.concurrent\.(?:Executor\w*|CountDownLatch|Future|CompletableFuture|ThreadPoolExecutor|Semaphore|locks\.\w+)\b|\bkotlin\.concurrent\.thread\b|(?<![\w.])thread\s*\(|\bLooper\b|\bHandler\s*\(", "Thread / Executor"),
    ("xml", SEAM, "XML (hors liste)", NOT_DOT + r"org\.(?:xmlpull|kxml2|w3c|xml)\.|" + NOT_DOT + r"javax\.xml\.", "parseur XML"),
    ("unicode", SEAM, "TextNormalizer (scripts)", r"\bCharacter\.(?:UnicodeScript|UnicodeBlock|getType)\b|\bUnicodeScript\b", "Character.UnicodeScript"),
    ("platform-info", SEAM, "plateforme", r"\bSystem\.(?:getProperty|getenv|lineSeparator|gc|exit)\b|\bRuntime\.getRuntime\b", "System.getProperty / Runtime"),
    # MECHANICAL
    ("hilt-inject", MECH, "retirer @Inject (D3)", NOT_DOT + r"javax\.inject\.|" + NOT_DOT + r"dagger\.|@Inject\b|@Singleton\b", "@Inject / @Singleton"),
    ("math", MECH, "kotlin.math", r"(?<![\w.])(?:Math|StrictMath)\.\w+|" + NOT_DOT + r"java\.lang\.Math\b", "Math.*"),
    ("synchronized", MECH, "atomicfu synchronized", r"(?<![\w.])synchronized\s*\(|@Synchronized\b", "synchronized"),
    ("volatile", MECH, "kotlin.concurrent.Volatile", r"@(?:field:)?Volatile\b", "@Volatile"),
    ("time", MECH, "kotlinx-datetime", NOT_DOT + r"java\.time\.|" + NOT_DOT + r"java\.util\.(?:Calendar|Date|TimeZone|GregorianCalendar)\b|\bSimpleDateFormat\b", "java.time / Calendar"),
    ("systime", MECH, "Clock", r"\bSystem\.(?:currentTimeMillis|nanoTime)\b", "System.currentTimeMillis / nanoTime"),
    ("bigint", MECH, "toULong(16)", r"\bBig(?:Integer|Decimal)\b", "BigInteger / BigDecimal"),
    ("format", MECH, "util/Fmt", r"\bString\.format\s*\(|\.format\s*\(|" + NOT_DOT + r"java\.text\.(?:DecimalFormat|NumberFormat|MessageFormat)\b", "String.format / .format("),
    ("atomic", MECH, "atomicfu", NOT_DOT + r"java\.util\.concurrent\.atomic\.|\bAtomic(?:Integer|Long|Boolean|Reference)\b", "java.util.concurrent.atomic"),
    ("concurrent-coll", MECH, "Map + verrou atomicfu", r"\b(?:ConcurrentHashMap|CopyOnWriteArrayList|CopyOnWriteArraySet|ConcurrentLinkedQueue|ConcurrentLinkedDeque|ConcurrentSkipListMap|LinkedBlockingQueue)\b", "collections concurrentes"),
    ("timeunit", MECH, "kotlin.time.Duration", r"\bTimeUnit\.", "TimeUnit"),
    ("net-codec", MECH, "util/UrlCodec", r"\bURLEncoder\b|\bURLDecoder\b|" + NOT_DOT + r"java\.net\.URI\b|(?<![\w.])URI\s*\(|\bURI\.create\b", "URLEncoder / URI"),
    ("jvm-statics", MECH, "équivalent Kotlin", r"(?<![\w.])Integer\.\w+|(?<![\w.])Character\.(?!UnicodeScript|UnicodeBlock|getType)\w+|(?<![\w.])Long\.(?!MAX_VALUE\b|MIN_VALUE\b|SIZE_BITS\b|SIZE_BYTES\b)[a-z]\w*|(?<![\w.])(?:Double|Float)\.(?:doubleToLongBits|doubleToRawLongBits|longBitsToDouble|floatToIntBits|floatToRawIntBits|intBitsToFloat|compare|parseDouble|parseFloat|toHexString)\b|" + NOT_DOT + r"java\.lang\.|\bSystem\.(?:arraycopy|identityHashCode)\b|(?<![\w.])Object\s*\(\s*\)|\bInterruptedException\b|\bStringBuffer\b|\bString\.valueOf\b|\.intern\(\)", "statiques JVM (Integer., Character., ...)"),
    ("charset", MECH, "encodeToByteArray / decodeToString", r"\bCharsets\.|" + NOT_DOT + r"java\.nio\.charset\.|\bStandardCharsets\b", "Charsets"),
    ("bytebuffer", MECH, "lecture d'octets à la main", r"\bByteBuffer\b|\bByteOrder\b", "ByteBuffer"),
    ("io-exception", MECH, "kotlinx-io IOException ou exception maison", r"\bIOException\b|\bEOFException\b|\bUncheckedIOException\b|" + NOT_DOT + r"java\.io\.ByteArrayOutputStream\b", "IOException / ByteArrayOutputStream"),
    ("crc32", MECH, "CRC32 en Kotlin", r"\bCRC32\b", "CRC32"),
    ("java-util", MECH, "kotlin.random / kotlin.uuid / Base64 / collections", NOT_DOT + r"java\.util\.(?!Locale\b|concurrent\b|zip\b|regex\b|Calendar\b|Date\b|TimeZone\b|GregorianCalendar\b)\w+", "autre java.util (UUID, Base64, Random, TreeMap...)"),
    ("jvm-regex", MECH, "Regex Kotlin", NOT_DOT + r"java\.util\.regex\.|\bPattern\.compile\b|\bRegexOption\.(?!IGNORE_CASE\b|MULTILINE\b)\w+|\.toPattern\(\)", "java.util.regex / RegexOption JVM"),
    ("lru-map", MECH, "LRU maison", r"\bremoveEldestEntry\b|LinkedHashMap\s*(?:<[^>]*>)?\s*\(\s*\d+\s*,\s*[\d.]+f?\s*,\s*true", "LinkedHashMap accessOrder / removeEldestEntry"),
    ("reflection", MECH, "sans réflexion JVM", r"::class\.java\b|\.javaClass\b|\bClass\.forName\b|\bkotlin\.reflect\.full\b|\bKClass\b.*\.java\b", "réflexion JVM"),
    ("org-json", MECH, "kotlinx.serialization (réécriture)", NOT_DOT + r"org\.json\.|\bJSON(?:Object|Array|Exception)\b", "org.json"),
    ("dispatchers-io", MECH, "import kotlinx.coroutines.IO", r"\bDispatchers\.IO\b", "Dispatchers.IO"),
]
RULE_INFO = {r[0]: {"class": r[1], "fix": r[2], "label": r[4]} for r in RULES}
RULE_INFO["locale-seam"] = {"class": SEAM, "fix": "PlatformLocale", "label": "Locale.getDefault / Locale(...)"}
RULE_INFO["locale-case"] = {"class": MECH, "fix": "appels sans Locale", "label": "Locale.ROOT / Locale.US"}
COMPILED_RULES = [(r[0], re.compile(r[3])) for r in RULES]

NOTE_RULES = [
    ("jvm-annotations", r"@Jvm(?:Static|Field|Overloads|Name|Inline)\b|@Throws\b",
     "@JvmStatic/@JvmField/@JvmOverloads/@JvmName/@JvmInline/@Throws : acceptés en common (OptionalExpectation)"),
    ("jvm-wildcards", r"@JvmSuppressWildcards\b|@JvmWildcard\b", "@JvmSuppressWildcards : JVM seul (Dagger)"),
    ("to-bytearray", r"\.toByteArray\(\s*\)", ".toByteArray() : JVM seul si le receveur est un String"),
    ("string-from-bytes", r"(?<![\w.])String\s*\(\s*\w+\s*\)", "String(x) : JVM seul si x est un ByteArray"),
    ("run-blocking", r"\brunBlocking\b", "runBlocking : présent sur JVM et natif, pas en JS"),
]
COMPILED_NOTES = [(r[0], re.compile(r[1]), r[2]) for r in NOTE_RULES]
REGEX_NATIVE_RE = re.compile(r"\\p\{(?:Is|In|java|script|sc=|Script)|\(\?U\)|\\G|[*+?]\+|\{\d+(?:,\d*)?\}\+")

LOCALE_CONST = r"Locale\.(?:ROOT|US|ENGLISH|UK|FRANCE|FRENCH|GERMANY|GERMAN|ITALY|ITALIAN|JAPAN|JAPANESE|CANADA|CANADA_FRENCH|KOREA|CHINA|SIMPLIFIED_CHINESE|TRADITIONAL_CHINESE)\b"

STAYS_OVERRIDES = {
    "location/LocationProvider.kt": "implémentation Android de LocationSource",
    "location/HeadingProvider.kt": "implémentation Android de HeadingSource",
    "location/MotionProvider.kt": "capteurs Android (accéléromètre)",
    "feedback/Haptics.kt": "Vibrator Android",
    "net/GoogleTransport.kt": "hook Cronet (Interceptor OkHttp)",
    "di/CoreModule.kt": "module Hilt",
}


def find_blockers(code, src_lines, imports_text):
    found = {}

    def add(rid, pos, count):
        line = code.count("\n", 0, pos) + 1
        found[rid] = {"count": count, "line": line, "text": src_lines[line - 1].strip()[:140]}

    for rid, rx in COMPILED_RULES:
        ms = list(rx.finditer(code))
        if ms:
            add(rid, ms[0].start(), len(ms))
    # Locale: constants only (mechanical) vs real locale use (seam).
    locs = [m for m in re.finditer(r"(?<![\w])Locale\b", code)
            if not re.match(r"\s*import\b", code[code.rfind("\n", 0, m.start()) + 1:m.start()])]
    if locs:
        bad = [m for m in locs if not re.match(LOCALE_CONST, code[m.start():])]
        if bad:
            add("locale-seam", bad[0].start(), len(bad))
        else:
            add("locale-case", locs[0].start(), len(locs))
    return found


def find_notes(code, strings):
    notes = {}
    for nid, rx, label in COMPILED_NOTES:
        c = len(rx.findall(code))
        if c:
            notes[nid] = c
    rx_hits = [s for _, s in strings if REGEX_NATIVE_RE.search(s) and ("\\" in s or "(?" in s)]
    if rx_hits:
        notes["regex-native"] = len(rx_hits)
    return notes


# ---------------------------------------------------------------------------
# Test framework usage
# ---------------------------------------------------------------------------

TEST_RULES = [
    ("org.junit", r"\borg\.junit\."),
    ("@Test", r"@Test\b"),
    ("@Before/@After", r"@(?:Before|After|BeforeClass|AfterClass)\b"),
    ("@Ignore", r"@Ignore\b"),
    ("@Test(expected)", r"@Test\s*\(\s*expected"),
    ("@Rule", r"@(?:get:)?Rule\b"),
    ("@RunWith", r"@RunWith\b"),
    ("Assume", r"\bAssume\b|\bassume\w+\("),
    ("assertThat", r"\bassertThat\s*\("),
    ("assertArrayEquals", r"\bassertArrayEquals\b"),
    ("kotlin.test", r"\bkotlin\.test\b"),
    ("runTest", r"\brunTest\b"),
    ("ressources", r"getResource(?:AsStream)?\b|\bClassLoader\b|src/test/resources"),
    ("mockwebserver", r"\bMockWebServer\b|mockwebserver"),
    ("robolectric", r"\brobolectric\b|Robolectric"),
    ("mockk/mockito", r"\bmockk\b|\bmockito\b|Mockito"),
]
COMPILED_TEST_RULES = [(r[0], re.compile(r[1])) for r in TEST_RULES]
ASSERT_RE = re.compile(r"\b(assert(?:Equals|NotEquals|Same|NotSame|ArrayEquals|True|False|Null|NotNull))\s*\(")


def message_first_asserts(code):
    """JUnit puts the message first, kotlin.test last: count the calls that must be reordered."""
    count = 0
    for m in ASSERT_RE.finditer(code):
        i = m.end()
        depth = 0
        args = [[]]
        while i < len(code):
            ch = code[i]
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif ch == "," and depth == 0:
                args.append([])
                i += 1
                continue
            args[-1].append(ch)
            i += 1
        first = "".join(args[0]).strip()
        if not re.fullmatch(r'"[^"]*"|"""[^"]*"""', first):
            continue
        name = m.group(1)
        two_arg = name in ("assertTrue", "assertFalse", "assertNull", "assertNotNull")
        if (two_arg and len(args) == 2) or (not two_arg and len(args) >= 3):
            count += 1
    return count


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------


class KFile:
    def __init__(self, root, rel, group):
        self.root = root
        self.rel = rel  # path relative to root
        self.group = group  # main / test / app
        path = os.path.join(REPO, root, rel)
        with open(path, encoding="utf-8") as fh:
            self.src = fh.read()
        self.lines = self.src.count("\n") + (0 if self.src.endswith("\n") else 1)
        self.code, self.strings = lex(self.src)
        m = PACKAGE_RE.search(self.code)
        self.package = m.group(1) if m else ""
        self.imports = []
        for im in IMPORT_RE.finditer(self.code):
            self.imports.append((im.group(1), bool(im.group(2)), im.group(3)))
        # Body without package/import lines, for usage scanning.
        body = PACKAGE_RE.sub(lambda mm: " " * len(mm.group(0)), self.code)
        body = re.sub(r"(?m)^\s*import\s+[^\n]*", lambda mm: " " * len(mm.group(0)), body)
        self.body = body
        self.decls = top_level_decls(self.code)
        self.local_types, self.local_funs, self.local_vals = local_names(re.sub(r"[ \t]+", " ", body))
        self.uses = identifier_uses(re.sub(FQ_RE, lambda mm: " " * len(mm.group(0)), body))
        self.fq = [re.sub(r"\s+", "", mm.group(0)) for mm in FQ_RE.finditer(body)]
        src_lines = self.src.split("\n")
        squeezed = re.sub(r"[ \t]+", " ", self.code)  # same lines, much shorter
        self.blockers = find_blockers(squeezed, src_lines, "")
        self.notes = find_notes(squeezed, self.strings)
        self.test_usage = {}
        if group == "test":
            for tid, rx in COMPILED_TEST_RULES:
                c = len(rx.findall(self.code))
                if c:
                    self.test_usage[tid] = c
            c = message_first_asserts(self.code)
            if c:
                self.test_usage["assert(message, ...)"] = c
        self.deps = {}  # file id -> set of reasons
        self.dep_syms = {}  # file id -> set of referenced top-level names
        self.key = f"{group}:{rel}"

    @property
    def short(self):
        if self.group == "app":
            return "app/offline/" + self.rel
        if self.group == "test":
            return "test/" + self.rel
        return self.rel


def collect(root, group, only=None):
    base = os.path.join(REPO, root)
    out = []
    if not os.path.isdir(base):
        return out
    for dp, _, fns in os.walk(base):
        for fn in fns:
            if not fn.endswith(".kt"):
                continue
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, base)
            if group in ("main", "test"):
                if not rel.startswith(CORE_PREFIX):
                    continue
                rel = rel[len(CORE_PREFIX):]
            if only is not None and rel not in only:
                continue
            out.append(KFile(root if group == "app" else os.path.join(root, CORE_PREFIX), rel, group))
    out.sort(key=lambda f: f.rel)
    return out


class Index:
    def __init__(self, files):
        self.by_pkg = defaultdict(lambda: defaultdict(list))
        self.packages = set()
        for f in files:
            self.packages.add(f.package)
            for d in f.decls:
                if not d["private"]:  # file-private, invisible to other files
                    self.by_pkg[f.package][d["name"]].append((f, d))

    def lookup(self, pkg, name):
        return self.by_pkg.get(pkg, {}).get(name, [])

    def split_fq(self, dotted):
        """'app.vela.core.data.NoGoogle.enabled' -> ('app.vela.core.data', 'NoGoogle')."""
        parts = dotted.split(".")
        for k in range(len(parts) - 1, 0, -1):
            pkg = ".".join(parts[:k])
            if pkg in self.packages:
                return pkg, parts[k]
        return None, None


def resolve(f, indexes):
    """Fills f.deps with (target file key -> reasons)."""
    def add(target, reason, name):
        if target is f:
            return
        f.deps.setdefault(target.key, set()).add(reason)
        f.dep_syms.setdefault(target.key, set()).add(name)

    explicit = set()
    star_pkgs = []
    for path, star, alias in f.imports:
        if star:
            star_pkgs.append(path)
            continue
        for idx in indexes:
            pkg, name = idx.split_fq(path)
            if pkg is None:
                continue
            hits = idx.lookup(pkg, name)
            for tf, _ in hits:
                add(tf, "import", name)
            if hits:
                explicit.add(alias or path.split(".")[-1])
    for dotted in f.fq:
        for idx in indexes:
            pkg, name = idx.split_fq(dotted)
            if pkg is None:
                continue
            for tf, _ in idx.lookup(pkg, name):
                add(tf, "fq", name)

    def used(name, d):
        flags = f.uses.get(name)
        if not flags:
            return False
        kind, ext = d["kind"], d["ext"]
        if kind == "type":
            return ("bare" in flags or "ref" in flags) and name not in f.local_types
        if kind == "fun":
            if "ref" in flags:
                return True
            if ext and "dotcall" in flags:
                return True
            return "call" in flags and name not in f.local_funs and name not in f.local_types
        # val / var
        if ext and "dot" in flags:
            return True
        return "bare" in flags and name not in f.local_vals and name not in f.local_funs

    for reason, pkgs in (("package", [f.package]), ("star", star_pkgs)):
        for pkg in pkgs:
            for idx in indexes:
                for name, hits in idx.by_pkg.get(pkg, {}).items():
                    if name in explicit:
                        continue
                    for tf, d in hits:
                        if tf is f:
                            continue
                        if used(name, d):
                            add(tf, reason, name)


def tarjan(nodes, edges):
    index = {}
    low = {}
    on = set()
    stack = []
    sccs = []
    counter = [0]
    sys.setrecursionlimit(10000)

    def strong(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on.add(v)
        for w in edges.get(v, ()):
            if w not in index:
                strong(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            sccs.append(sorted(comp))

    for v in nodes:
        if v not in index:
            strong(v)
    return sccs


def own_class(f):
    if f.group == "main" and f.rel in STAYS_OVERRIDES:
        return STAYS
    cls = PURE
    for rid in f.blockers:
        c = RULE_INFO[rid]["class"]
        if CLASS_RANK[c] > CLASS_RANK[cls]:
            cls = c
    return cls


def waves(nodes, edges, ok):
    """Waves over the SCC condensation, restricted to nodes in `ok` whose whole dependency
    cone is in `ok`. Returns (wave per node, sccs, movable set)."""
    sccs = tarjan(nodes, edges)
    comp_of = {}
    for i, c in enumerate(sccs):
        for v in c:
            comp_of[v] = i
    # Tarjan yields components in reverse topological order (deps first).
    wave = {}
    movable_comp = {}
    for i, comp in enumerate(sccs):
        deps = set()
        for v in comp:
            for w in edges.get(v, ()):
                if comp_of[w] != i:
                    deps.add(comp_of[w])
        good = all(v in ok for v in comp) and all(movable_comp.get(d, False) for d in deps)
        movable_comp[i] = good
        if good:
            wv = 1 + max([wave[sccs[d][0]] for d in deps], default=0)
            for v in comp:
                wave[v] = wv
    movable = {v for v in nodes if v in wave}
    return wave, sccs, movable


# ---------------------------------------------------------------------------
# Lots
# ---------------------------------------------------------------------------

V1_ROOTS = [
    "data/google/parse/SearchParser.kt", "data/google/GoogleResponse.kt", "data/google/SearchPb.kt",
    "data/google/RequestShape.kt", "data/google/BrowserViewport.kt", "util/Jitter.kt",
    "config/Calibration.kt",
]

LOT_RULES = [
    ("RESTE", r"^(di/|feedback/|location/(Location|Heading|Motion)Provider\.kt|net/GoogleTransport\.kt|data/ObfRouteEngine\.kt|util/AtomicFiles\.kt)"),
    ("C-4", r"^(config/|VelaConfig\.kt)"),
    ("C-3", r"^data/(ValhallaRouter|RouteGeometry|PhotonGeocoder|Overpass\w*|transit/Transitous|transit/TransitOrder|NdwBridgeOpenings|ShortLinks|FuelGb\w*|PaintedRoads|OsmMaxspeed|RouteEngine|RouteBudget|tiles/MapStyle)\.kt$"),
    ("C-6", r"^data/(\w*Store|OfflinePacks|PlaceCache|StreetViewCache|transit/TransitLineCache|OfflineRoot|AmbientDiskCache|PlaceImport|TakeoutCsv|ImportResult)\.kt$"),
    ("C-2", r"^(data/google/|data/(MapDataSource|MockMapDataSource|CategoryFilter|ReviewWords|ClosingTime|NoGoogle|OtherLocations|MapLinkParser|MyMapKml)\.kt$|net/)"),
    ("C-5", r"^(nav/|replay/|i18n/|data/naming/|location/|data/(RouteCorridor|RoutingPrefs|OfflinePhrases)\.kt$)"),
    ("C-7", r"^voice/"),
    ("C-8", r"^data/OfflineRank\.kt$"),
    ("V-1 (model/util)", r"^(model/|util/)"),
]


def plan_lot(rel):
    for lot, rx in LOT_RULES:
        if re.search(rx, rel):
            return lot
    return "hors lot"


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------


def analyze():
    main = collect(MAIN_DIR, "main")
    test = collect(TEST_DIR, "test")
    app = collect(APP_OFFLINE_DIR, "app")
    main_idx = Index(main)
    test_idx = Index(test)
    app_idx = Index(app)
    for f in main:
        resolve(f, [main_idx])
    for f in test:
        resolve(f, [main_idx, test_idx])
    for f in app:
        resolve(f, [main_idx, app_idx])
    files = {f.key: f for f in main + test + app}

    cls = {k: own_class(f) for k, f in files.items()}
    main_keys = [f.key for f in main]
    main_edges = {f.key: sorted(d for d in f.deps if d.startswith("main:")) for f in main}

    ok_a = {k for k in main_keys if cls[k] in (PURE, MECH)}
    wave_a, sccs, movable_a = waves(main_keys, main_edges, ok_a)
    ok_b = {k for k in main_keys if cls[k] != STAYS}
    wave_b, _, movable_b = waves(main_keys, main_edges, ok_b)

    reach = {}

    def closure(k):
        if k in reach:
            return reach[k]
        seen = set()
        todo = [k]
        while todo:
            v = todo.pop()
            for w in main_edges.get(v, ()):
                if w not in seen:
                    seen.add(w)
                    todo.append(w)
        seen.discard(k)
        reach[k] = seen
        return seen

    rdeps = defaultdict(set)
    for k, ds in main_edges.items():
        for d in ds:
            rdeps[d].add(k)

    # Root causes for files that are fine themselves but blocked through deps.
    blocked_by = {}
    for k in main_keys:
        if cls[k] in (PURE, MECH) and k not in movable_a:
            roots = sorted(d for d in closure(k) if cls[d] in (SEAM, STAYS))
            blocked_by[k] = roots

    v1_keys = set("main:" + r for r in V1_ROOTS if "main:" + r in files)
    v1 = set(v1_keys)
    for r in list(v1_keys):
        v1 |= closure(r)
    v1_ext_roots = {k for k in main_keys if re.match(r"^main:(model|util)/", k) and k != "main:util/AtomicFiles.kt"} | v1_keys
    v1_ext = set(v1_ext_roots)
    for r in list(v1_ext_roots):
        v1_ext |= closure(r)

    lots = {}
    for k in main_keys:
        rel = files[k].rel
        lots[k] = "V-1" if k in v1 else plan_lot(rel)

    # Tests: subjects are the main files they reference.
    tests = {}
    for f in test:
        subj = sorted(d for d in f.deps if d.startswith("main:"))
        helpers = sorted(d for d in f.deps if d.startswith("test:"))
        tests[f.key] = {"subjects": subj, "helpers": helpers}

    def test_ready(k, seen=None):
        seen = seen or set()
        if k in seen:
            return True
        seen.add(k)
        f = files[k]
        if cls[k] not in (PURE, MECH):
            return False
        if any(s not in movable_a for s in tests[k]["subjects"]):
            return False
        return all(test_ready(h, seen) for h in tests[k]["helpers"])

    test_status = {}
    for f in test:
        k = f.key
        if test_ready(k):
            test_status[k] = "commonTest (après C-1)"
        elif cls[k] in (PURE, MECH):
            test_status[k] = "bloqué par ses sujets"
        else:
            test_status[k] = "bloqué par le test lui-même"
    test_wave = {}
    for f in test:
        k = f.key
        if test_status[k].startswith("commonTest"):
            test_wave[k] = max([wave_a[s] for s in tests[k]["subjects"]], default=0)

    return {
        "main": main, "test": test, "app": app, "files": files, "cls": cls,
        "edges": main_edges, "rdeps": rdeps, "wave_a": wave_a, "wave_b": wave_b,
        "movable_a": movable_a, "movable_b": movable_b, "sccs": sccs, "blocked_by": blocked_by,
        "closure": closure, "v1": v1, "v1_ext": v1_ext, "lots": lots, "tests": tests,
        "test_status": test_status, "test_wave": test_wave,
    }


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------


def short(key):
    g, rel = key.split(":", 1)
    if g == "test":
        return "test/" + rel
    if g == "app":
        return "app/offline/" + rel
    return rel


def blocker_ids(f):
    return sorted(f.blockers, key=lambda r: (-CLASS_RANK[RULE_INFO[r]["class"]], r))


def fmt_blockers(f, with_mech=True):
    parts = []
    for rid in blocker_ids(f):
        if not with_mech and RULE_INFO[rid]["class"] == MECH:
            continue
        parts.append(f"`{rid}`×{f.blockers[rid]['count']}")
    return ", ".join(parts) or "-"


def seams_of(f):
    out = []
    for rid in blocker_ids(f):
        info = RULE_INFO[rid]
        if info["class"] in (SEAM, STAYS) and info["fix"] not in out:
            out.append(info["fix"])
    return out


def to_json(a):
    files = a["files"]
    out = {"files": {}, "sccs": [c for c in a["sccs"] if len(c) > 1]}
    for k, f in files.items():
        out["files"][k] = {
            "path": os.path.join(f.root, f.rel),
            "package": f.package,
            "lines": f.lines,
            "declarations": f.decls,
            "deps": {d: sorted(r) for d, r in sorted(f.deps.items())},
            "blockers": f.blockers,
            "notes": f.notes,
            "class": a["cls"][k],
            "wave": a["wave_a"].get(k),
            "wave_after_seams": a["wave_b"].get(k),
            "lot": a["lots"].get(k),
            "in_v1": k in a["v1"],
            "blocked_by": a["blocked_by"].get(k),
            "test_usage": f.test_usage or None,
            "test_status": a["test_status"].get(k),
        }
    return out


def table(rows, header):
    out = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


def gen_sections(a):
    main, files, cls = a["main"], a["files"], a["cls"]
    S = {}
    counts = defaultdict(int)
    lines_by = defaultdict(int)
    for f in main:
        counts[cls[f.key]] += 1
        lines_by[cls[f.key]] += f.lines
    total = len(main)
    total_lines = sum(f.lines for f in main)
    movable = a["movable_a"]
    multi = [c for c in a["sccs"] if len(c) > 1]
    max_wave = max(a["wave_a"].values(), default=0)
    max_wave_b = max(a["wave_b"].values(), default=0)
    edges_n = sum(len(v) for v in a["edges"].values())

    # --- summary
    rows = []
    for c in (PURE, MECH, SEAM, STAYS):
        rows.append([c, counts[c], f"{lines_by[c]:,}".replace(",", " ")])
    rows.append(["**total**", total, f"{total_lines:,}".replace(",", " ")])
    s = [table(rows, ["Classe", "Fichiers", "Lignes"]), ""]
    s.append(f"- Arêtes internes (fichier → fichier de `:core`) : **{edges_n}**.")
    s.append(f"- Déplaçables sans couture, une fois C-1 fait (PURE ou MECHANICAL, et toutes les dépendances aussi) : "
             f"**{len(movable)}** fichiers, en **{max_wave}** vagues.")
    s.append(f"- PURE ou MECHANICAL mais bloqués par une dépendance SEAM ou STAYS : **{len(a['blocked_by'])}**.")
    s.append(f"- Déplaçables une fois les coutures F-2 posées (tout sauf STAYS et ce qui en dépend) : "
             f"**{len(a['movable_b'])}**, en **{max_wave_b}** vagues.")
    s.append(f"- Composantes fortement connexes de plus d'un fichier (cycles) : **{len(multi)}**"
             + (f" ({', '.join(str(len(c)) for c in multi)} fichiers)" if multi else "") + ".")
    s.append(f"- Clôture V-1 : **{len(a['v1'])}** fichiers.")
    s.append("")
    pk = defaultdict(lambda: defaultdict(int))
    for f in main:
        p = f.rel.split("/")[0] if "/" in f.rel else "(racine)"
        if f.rel.startswith("data/") and f.rel.count("/") >= 2:
            p = "/".join(f.rel.split("/")[:2])
        pk[p]["n"] += 1
        pk[p]["lines"] += f.lines
        pk[p][cls[f.key]] += 1
        if f.key in movable:
            pk[p]["mov"] += 1
    rows = [[f"`{p}`", v["n"], v["lines"], v[PURE], v[MECH], v[SEAM], v[STAYS], v["mov"]]
            for p, v in sorted(pk.items())]
    s.append(table(rows, ["Paquet", "Fichiers", "Lignes", "PURE", "MECH.", "SEAM", "STAYS", "déplaçables (A)"]))
    S["summary"] = "\n".join(s)

    # --- blockers
    rows = []
    for rid, info in sorted(RULE_INFO.items(), key=lambda kv: (-CLASS_RANK[kv[1]["class"]], kv[0])):
        fs = [f for f in main if rid in f.blockers]
        if not fs:
            continue
        occ = sum(f.blockers[rid]["count"] for f in fs)
        only = sum(1 for f in fs if len(f.blockers) == 1)
        rows.append([f"`{rid}`", info["label"], info["class"], info["fix"], len(fs), occ, only])
    s = [table(rows, ["Id", "Détecte", "Classe", "Couture ou remplacement", "Fichiers", "Occurrences",
                      "seul bloqueur"])]
    notes = defaultdict(lambda: [0, 0])
    for f in main:
        for nid, c in f.notes.items():
            notes[nid][0] += 1
            notes[nid][1] += c
    labels = {r[0]: r[2] for r in NOTE_RULES}
    labels["regex-native"] = "littéral avec une syntaxe de regex à vérifier sur natif (\\p{Is..}, quantificateur possessif, \\G)"
    if notes:
        s.append("")
        s.append("Notes (sans effet sur la classe) :")
        s.append("")
        for nid, (nf, occ) in sorted(notes.items()):
            s.append(f"- `{nid}` : {nf} fichiers, {occ} occurrences. {labels.get(nid, '')}")
    S["blockers"] = "\n".join(s)

    # --- lots
    lot_order = ["V-1", "V-1 (model/util)", "C-2", "C-3", "C-4", "C-5", "C-6", "C-7", "C-8", "hors lot", "RESTE"]
    s = []
    by_lot = defaultdict(list)
    for f in main:
        by_lot[a["lots"][f.key]].append(f)
    for lot in lot_order:
        fs = by_lot.get(lot, [])
        if not fs:
            continue
        c = defaultdict(int)
        for f in fs:
            c[cls[f.key]] += 1
        s.append(f"#### {lot} ({len(fs)} fichiers, {sum(f.lines for f in fs)} lignes ; "
                 f"PURE {c[PURE]}, MECH. {c[MECH]}, SEAM {c[SEAM]}, STAYS {c[STAYS]})")
        s.append("")
        rows = []
        for f in sorted(fs, key=lambda f: (a["wave_a"].get(f.key, 99), a["wave_b"].get(f.key, 99), f.rel)):
            k = f.key
            deps = a["edges"][k]
            wa = a["wave_a"].get(k, "-")
            wb = a["wave_b"].get(k, "-")
            extra = ""
            if k in a["blocked_by"]:
                roots = a["blocked_by"][k]
                extra = "via " + ", ".join(short(r).rsplit("/", 1)[-1].removesuffix(".kt") for r in roots[:4])
                if len(roots) > 4:
                    extra += f" (+{len(roots) - 4})"
            elif cls[k] in (SEAM, STAYS):
                extra = " / ".join(seams_of(f))
                if f.rel in STAYS_OVERRIDES:
                    extra = STAYS_OVERRIDES[f.rel]
            rows.append([f"`{f.rel}`", f.lines, cls[k], fmt_blockers(f), len(deps), len(a["rdeps"][k]), wa, wb, extra])
        s.append(table(rows, ["Fichier", "Lignes", "Classe", "Bloqueurs", "Dép.", "Dépendants", "Vague A",
                              "Vague B", "Couture / bloqué par"]))
        s.append("")
    # C-1
    s.append("#### C-1 (transversal : fichiers qui ont au moins un remplacement mécanique)")
    s.append("")
    c1 = defaultdict(lambda: defaultdict(int))
    for f in main:
        if cls[f.key] == STAYS:
            continue
        for rid in f.blockers:
            if RULE_INFO[rid]["class"] == MECH:
                p = f.rel.split("/")[0] if "/" in f.rel else "(racine)"
                c1[rid][p] += 1
    rows = []
    for rid in sorted(c1, key=lambda r: -sum(c1[r].values())):
        rows.append([f"`{rid}`", RULE_INFO[rid]["fix"], sum(c1[rid].values()),
                     ", ".join(f"{p} {n}" for p, n in sorted(c1[rid].items(), key=lambda kv: -kv[1]))])
    s.append(table(rows, ["Remplacement", "Vers", "Fichiers", "Par paquet"]))
    S["lots"] = "\n".join(s)

    # --- waves
    s = ["Vague A : seulement PURE et MECHANICAL (après C-1, avant toute couture).", ""]
    by_wave = defaultdict(list)
    for k, w in a["wave_a"].items():
        by_wave[w].append(k)
    for w in sorted(by_wave):
        names = sorted(short(k) for k in by_wave[w])
        s.append(f"- **Vague {w}** ({len(names)}) : " + ", ".join(f"`{n}`" for n in names))
    s.append("")
    s.append("Vague B : en plus, les fichiers SEAM une fois leurs coutures posées (rien de STAYS). "
             "Seuls les fichiers qui ne sont pas déjà dans la vague A sont listés.")
    s.append("")
    by_wave = defaultdict(list)
    for k, w in a["wave_b"].items():
        if k not in a["movable_a"]:
            by_wave[w].append(k)
    for w in sorted(by_wave):
        names = sorted(short(k) for k in by_wave[w])
        s.append(f"- **B{w}** ({len(names)}) : " + ", ".join(f"`{n}`" for n in names))
    never = [f.rel for f in main if f.key not in a["movable_b"]]
    s.append("")
    s.append(f"Jamais déplaçables sans couper un fichier ({len(never)}) : STAYS, et ce qui en dépend : "
             + ", ".join(f"`{n}`" for n in sorted(never)))
    S["waves"] = "\n".join(s)

    # --- cycles
    s = []
    if not multi:
        s.append("Aucun cycle.")
    for c in sorted(multi, key=len, reverse=True):
        cl = defaultdict(int)
        for k in c:
            cl[cls[k]] += 1
        s.append(f"- **{len(c)} fichiers** (PURE {cl[PURE]}, MECH. {cl[MECH]}, SEAM {cl[SEAM]}, STAYS {cl[STAYS]}) : "
                 + ", ".join(f"`{short(k)}`" for k in c))
        cs = set(c)
        inner = []
        for k in c:
            for d in a["edges"][k]:
                if d in cs:
                    reasons = "/".join(sorted(files[k].deps[d]))
                    inner.append(f"{short(k).rsplit('/', 1)[-1].removesuffix('.kt')} → "
                                 f"{short(d).rsplit('/', 1)[-1].removesuffix('.kt')} ({reasons})")
        if len(c) <= 12:
            s.append("  - arêtes : " + " ; ".join(inner))
    S["cycles"] = "\n".join(s)

    # --- v1
    v1 = sorted(a["v1"], key=lambda k: (a["wave_a"].get(k, 99), k))
    s = [f"Racines : " + ", ".join(f"`{r}`" for r in V1_ROOTS) + ".", "",
         f"Clôture transitive : **{len(v1)} fichiers**, {sum(files[k].lines for k in v1)} lignes.", ""]
    c = defaultdict(int)
    for k in v1:
        c[cls[k]] += 1
    s.append(f"Classes : PURE {c[PURE]}, MECHANICAL {c[MECH]}, SEAM {c[SEAM]}, STAYS {c[STAYS]}. "
             f"Déplaçables en vague A : {sum(1 for k in v1 if k in a['movable_a'])}.")
    s.append("")
    rows = []
    for k in v1:
        f = files[k]
        via = sorted(r for r in a["v1"] if k in a["edges"].get(r, ()) )
        rows.append([f"`{f.rel}`", f.lines, cls[k], fmt_blockers(f), a["wave_a"].get(k, "-"),
                     ", ".join(short(v).rsplit("/", 1)[-1].removesuffix(".kt") for v in via[:5])
                     + (f" (+{len(via) - 5})" if len(via) > 5 else "")])
    s.append(table(rows, ["Fichier", "Lignes", "Classe", "Bloqueurs", "Vague A", "Tiré par"]))
    agg = defaultdict(int)
    for k in v1:
        for rid, b in files[k].blockers.items():
            agg[rid] += b["count"]
    s.append("")
    s.append("Bloqueurs cumulés de la clôture : " + ", ".join(f"`{r}`×{n}" for r, n in sorted(agg.items(), key=lambda kv: -kv[1])) + ".")
    ext = sorted(a["v1_ext"] - a["v1"])
    s.append("")
    s.append(f"V-1 tel qu'écrit dans le plan (ajoute tout `model/` et `util/` sauf `AtomicFiles`) : "
             f"**{len(a['v1_ext'])} fichiers**, soit {len(ext)} de plus : " + ", ".join(f"`{short(k)}`" for k in ext) + ".")
    S["v1"] = "\n".join(s)

    # --- cuts: SEAM/STAYS files that keep PURE/MECHANICAL files out of wave A
    s = ["Fichiers SEAM ou STAYS qui bloquent des fichiers PURE ou MECHANICAL (par leur cône de dépendances). "
         "« Seul » = le fichier est la seule racine bloquante : le couper suffit.", ""]
    hits = defaultdict(lambda: [0, 0])
    for k, roots in a["blocked_by"].items():
        for r in roots:
            hits[r][0] += 1
            if len(roots) == 1:
                hits[r][1] += 1
    rows = []
    for r, (nb, alone) in sorted(hits.items(), key=lambda kv: (-kv[1][0], kv[0])):
        users = sorted(a["rdeps"][r])
        syms = sorted({sym for k in users for sym in files[k].dep_syms.get(r, ())})
        rows.append([f"`{short(r)}`", cls[r], ", ".join(seams_of(files[r])), nb, alone,
                     ", ".join(f"`{x}`" for x in syms[:6]) + (" ..." if len(syms) > 6 else "")])
    s.append(table(rows, ["Racine", "Classe", "Couture", "Fichiers bloqués", "Seul", "Symboles utilisés par les dépendants"]))
    s.append("")
    s.append("Arêtes vers un fichier STAYS (à couper par une couture ou en déplaçant le symbole) :")
    s.append("")
    for f in main:
        if cls[f.key] == STAYS:
            continue
        for d in sorted(a["edges"][f.key]):
            if cls[d] == STAYS:
                s.append(f"- `{f.rel}` → `{short(d)}` : " + ", ".join(f"`{x}`" for x in sorted(f.dep_syms.get(d, ()))))
    S["cuts"] = "\n".join(s)

    # --- top
    rows = []
    top = sorted(main, key=lambda f: (-len(a["rdeps"][f.key]), f.rel))[:15]
    for f in top:
        k = f.key
        trans = sum(1 for g in main if k in a["closure"](g.key))
        rows.append([f"`{f.rel}`", len(a["rdeps"][k]), trans, cls[k], a["wave_a"].get(k, "-"), fmt_blockers(f)])
    S["top"] = table(rows, ["Fichier", "Dépendants directs", "Dépendants transitifs", "Classe", "Vague A", "Bloqueurs"])

    # --- tests
    test = a["test"]
    st = defaultdict(int)
    for f in test:
        st[a["test_status"][f.key]] += 1
    tc = defaultdict(int)
    for f in test:
        tc[cls[f.key]] += 1
    usage = defaultdict(lambda: [0, 0])
    for f in test:
        for tid, n in f.test_usage.items():
            usage[tid][0] += 1
            usage[tid][1] += n
    s = [f"{len(test)} fichiers de test, {sum(f.lines for f in test)} lignes.", "",
         f"Classe propre des tests (mêmes règles que le main) : PURE {tc[PURE]}, MECHANICAL {tc[MECH]}, "
         f"SEAM {tc[SEAM]}, STAYS {tc[STAYS]}.", ""]
    s.append(table([[k, v] for k, v in sorted(st.items())], ["Statut", "Tests"]))
    s.append("")
    s.append("Usage du framework de test :")
    s.append("")
    s.append(table([[f"`{t}`", n, o] for t, (n, o) in sorted(usage.items(), key=lambda kv: -kv[1][0])],
                   ["Motif", "Fichiers", "Occurrences"]))
    s.append("")
    tb = defaultdict(lambda: [0, 0])
    for f in test:
        for rid, b in f.blockers.items():
            tb[rid][0] += 1
            tb[rid][1] += b["count"]
    s.append("Bloqueurs dans les tests eux-mêmes : " + ", ".join(
        f"`{r}` {n} fichiers" for r, (n, o) in sorted(tb.items(), key=lambda kv: -kv[1][0])) + ".")
    s.append("")
    ready = [f for f in test if a["test_status"][f.key].startswith("commonTest")]
    by_w = defaultdict(list)
    for f in ready:
        by_w[a["test_wave"][f.key]].append(f.rel)
    s.append(f"Tests prêts pour `commonTest` dès que leurs sujets ont bougé ({len(ready)}), par vague du sujet le plus tardif :")
    s.append("")
    for w in sorted(by_w):
        s.append(f"- après la vague {w} ({len(by_w[w])}) : " + ", ".join(f"`{n}`" for n in sorted(by_w[w])))
    blocked_self = [f for f in test if a["test_status"][f.key] == "bloqué par le test lui-même"]
    s.append("")
    s.append(f"Tests bloqués par leur propre code ({len(blocked_self)}) :")
    s.append("")
    rows = [[f"`{f.rel}`", cls[f.key], fmt_blockers(f)] for f in blocked_self]
    s.append(table(rows, ["Test", "Classe", "Bloqueurs"]))
    S["tests"] = "\n".join(s)

    # --- c8 app/offline
    s = []
    app = a["app"]
    rows = []
    for f in app:
        core_deps = sorted(d for d in f.deps if d.startswith("main:"))
        app_deps = sorted(d for d in f.deps if d.startswith("app:"))
        blocked = [d for d in core_deps if d not in a["movable_a"]]
        mark = "**C-8**" if f.rel in C8_APP_FILES else ""
        rows.append([f"`{f.rel}`", mark, f.lines, cls[f.key], fmt_blockers(f),
                     ", ".join(short(d).removesuffix(".kt") for d in core_deps) or "-",
                     ", ".join(short(d).rsplit("/", 1)[-1].removesuffix(".kt") for d in app_deps) or "-",
                     ", ".join(short(d).rsplit("/", 1)[-1].removesuffix(".kt") for d in blocked) or "-"])
    s.append(table(rows, ["Fichier (app/offline)", "Plan", "Lignes", "Classe", "Bloqueurs", "Dép. :core",
                          "Dép. app/offline", "Dép. :core non déplaçables (A)"]))
    S["c8"] = "\n".join(s)
    return S


SKELETON = """# Carte de migration de `:core` vers `:core-common` (lot C-0)

Généré en partie par `python3 scripts/ios/core_deps.py --md docs/ios/CORE-MIGRATION.md`.

## Résumé

<!-- BEGIN GENERATED: summary -->
<!-- END GENERATED: summary -->

## Bloqueurs

<!-- BEGIN GENERATED: blockers -->
<!-- END GENERATED: blockers -->

## Lots

<!-- BEGIN GENERATED: lots -->
<!-- END GENERATED: lots -->

## Vagues

<!-- BEGIN GENERATED: waves -->
<!-- END GENERATED: waves -->

## Cycles

<!-- BEGIN GENERATED: cycles -->
<!-- END GENERATED: cycles -->

## Clôture V-1

<!-- BEGIN GENERATED: v1 -->
<!-- END GENERATED: v1 -->

## Points de coupe

<!-- BEGIN GENERATED: cuts -->
<!-- END GENERATED: cuts -->

## Les 15 fichiers les plus dépendus

<!-- BEGIN GENERATED: top -->
<!-- END GENERATED: top -->

## Tests

<!-- BEGIN GENERATED: tests -->
<!-- END GENERATED: tests -->

## C-8 : `app/offline`

<!-- BEGIN GENERATED: c8 -->
<!-- END GENERATED: c8 -->
"""


def write_md(path, sections):
    text = open(path, encoding="utf-8").read() if os.path.exists(path) else SKELETON
    for name, body in sections.items():
        rx = re.compile(r"(<!-- BEGIN GENERATED: " + re.escape(name) + r" -->\n)(.*?)(<!-- END GENERATED: "
                        + re.escape(name) + r" -->)", re.S)
        if not rx.search(text):
            text += f"\n<!-- BEGIN GENERATED: {name} -->\n<!-- END GENERATED: {name} -->\n"
        text = rx.sub(lambda m: m.group(1) + body.rstrip() + "\n" + m.group(3), text)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def describe(a, rel):
    key = rel if ":" in rel else "main:" + rel
    f = a["files"].get(key)
    if not f:
        print(f"unknown file {rel}", file=sys.stderr)
        return 1
    print(f"{f.short}  package {f.package}  {f.lines} lines  class {a['cls'][key]}")
    print("declarations:", ", ".join(f"{d['name']}({d['kind']}{',ext' if d['ext'] else ''})" for d in f.decls))
    print("deps:")
    for d, r in sorted(f.deps.items()):
        print(f"  {short(d)}  [{', '.join(sorted(r))}] {', '.join(sorted(f.dep_syms.get(d, ())))}")
    print("dependents:", ", ".join(short(k) for k in sorted(a["rdeps"].get(key, ()))))
    print("blockers:")
    for rid in blocker_ids(f):
        b = f.blockers[rid]
        print(f"  {rid} x{b['count']} ({RULE_INFO[rid]['class']}) L{b['line']}: {b['text']}")
    if f.notes:
        print("notes:", f.notes)
    if f.test_usage:
        print("test usage:", f.test_usage)
    print("wave A:", a["wave_a"].get(key), " wave B:", a["wave_b"].get(key), " lot:", a["lots"].get(key))
    if key in a["blocked_by"]:
        print("blocked by:", ", ".join(short(k) for k in a["blocked_by"][key]))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--md", help="regenerate the generated sections of this Markdown file")
    ap.add_argument("--json", help="dump the graph as JSON to this path ('-' for stdout)")
    ap.add_argument("--file", action="append", help="describe one file (path under app/vela/core/)")
    args = ap.parse_args(argv)
    a = analyze()
    if args.json:
        data = json.dumps(to_json(a), indent=1, ensure_ascii=False, default=sorted)
        if args.json == "-":
            print(data)
        else:
            with open(args.json, "w", encoding="utf-8") as fh:
                fh.write(data)
    if args.md:
        write_md(args.md, gen_sections(a))
    if args.file:
        rc = 0
        for rel in args.file:
            rc |= describe(a, rel)
        return rc
    if not args.md and not args.json:
        c = defaultdict(int)
        for f in a["main"]:
            c[a["cls"][f.key]] += 1
        multi = [x for x in a["sccs"] if len(x) > 1]
        print(f"main files {len(a['main'])}: " + ", ".join(f"{k} {c[k]}" for k in (PURE, MECH, SEAM, STAYS)))
        print(f"movable (A) {len(a['movable_a'])} in {max(a['wave_a'].values(), default=0)} waves; "
              f"after seams (B) {len(a['movable_b'])} in {max(a['wave_b'].values(), default=0)} waves")
        print(f"cycles: {[len(x) for x in multi]}")
        print(f"V-1 closure: {len(a['v1'])} files")
        print(f"tests {len(a['test'])}, app/offline {len(a['app'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
