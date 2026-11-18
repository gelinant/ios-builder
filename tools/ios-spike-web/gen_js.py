#!/usr/bin/env python3
"""Extracts the JavaScript the Android hidden WebViews inject, byte for byte, for the W-2 spike.

Reads the Kotlin sources (read-only), evaluates the raw-string templates the way Kotlin does
(`${'$'}`, `$name`, `${expr}`, then trimIndent), and writes:
  js/*.js                    the scripts, for review (the request id is the token @@ID@@)
  Sources/GeneratedJS.swift  the same bytes in base64, plus their SHA-256 and the details URL

The bridge names stay `VelaBridge` / `VelaPanel`: the app swaps in per-process random names at
run time, as JsNames.of does on Android.

Usage: python3 tools/ios-spike-web/gen_js.py   (from the repository root)
"""
import base64
import hashlib
import json
import os
import random
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(ROOT, "app/src/main/java/app/vela/web")
ID_TOKEN = "@@ID@@"

# The fixture place (GoogleHealthProbeTest): Davis Food Co-op.
FIXTURE_FID = "0x8085299fd6f41a23:0x10d37b4cae550f0"
FIXTURE_NAME = "Davis Food Co-op"
FIXTURE_ADDRESS = "620 G St, Davis, CA 95616"
FIXTURE_LAT, FIXTURE_LNG = 38.5449, -121.7405  # the Davis fixture point of GoogleHealthProbeTest
VIEWPORT = (1920, 945)  # BrowserViewport.CHOICES[0], the most common pick


def read(path):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    assert "\r" not in s, path
    return s


def kotlin_unescape(lit):
    out, i = [], 0
    while i < len(lit):
        c = lit[i]
        if c == "\\":
            n = lit[i + 1]
            if n == "u":
                out.append(chr(int(lit[i + 2:i + 6], 16)))
                i += 6
                continue
            out.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "$": "$", "'": "'", "b": "\b"}[n])
            i += 2
            continue
        assert c != "$", "template in a regular string: " + lit
        out.append(c)
        i += 1
    return "".join(out)


def const_string(src, name):
    """A `const val NAME = "a" + "b"` built from regular string literals."""
    m = re.search(r"const val " + name + r"\s*=\s*((?:\"(?:[^\"\\]|\\.)*\"\s*\+?\s*)+)", src)
    assert m, name
    return "".join(kotlin_unescape(x) for x in re.findall(r"\"((?:[^\"\\]|\\.)*)\"", m.group(1)))


def raw_const(src, name):
    """A `const val NAME = \"\"\"...\"\"\"` raw string, no trimIndent."""
    m = re.search(r"const val " + name + r' = """(.*?)"""', src, re.S)
    assert m, name
    assert "$" not in m.group(1), name
    return m.group(1)


def raw_after(src, marker):
    """The first `return \"\"\"...\"\"\".trimIndent()` after [marker], unevaluated."""
    start = src.index(marker)
    a = src.index('"""', start) + 3
    b = src.index('"""', a)
    assert src[b:b + 16] == '""".trimIndent()', "expected trimIndent after " + marker
    return src[a:b]


def evaluate(raw, env):
    """Kotlin raw-string templates: ${'$'}, ${expr} and $ident, looked up in [env]."""
    out, i = [], 0
    while i < len(raw):
        c = raw[i]
        if c != "$":
            out.append(c)
            i += 1
            continue
        if raw.startswith("${'$'}", i):
            out.append("$")
            i += 6
            continue
        if raw.startswith("${", i):
            j = raw.index("}", i)
            expr = raw[i + 2:j]
            assert expr in env, "unknown template expression: " + expr
            out.append(env[expr])
            i = j + 1
            continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", raw[i + 1:])
        if m:
            assert m.group(0) in env, "unknown template name: " + m.group(0)
            out.append(env[m.group(0)])
            i += 1 + len(m.group(0))
            continue
        out.append("$")
        i += 1
    return "".join(out)


def indent_width(line):
    n = 0
    while n < len(line) and line[n].isspace():
        n += 1
    return n


def trim_indent(s):
    """kotlin.text.trimIndent."""
    lines = s.split("\n")
    widths = [indent_width(l) for l in lines if l.strip()]
    m = min(widths) if widths else 0
    last = len(lines) - 1
    kept = []
    for idx, l in enumerate(lines):
        if (idx == 0 or idx == last) and not l.strip():
            continue
        kept.append(l[m:])
    return "\n".join(kept)


def js_string(v):
    """WebReviewsFetcher.jsString."""
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


def js_str(v):
    """WebPopularTimesFetcher.jsStr."""
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'


def java_url_encode(s):
    """java.net.URLEncoder.encode(s, "UTF-8")."""
    safe = set(b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*_")
    out = []
    for b in s.encode("utf-8"):
        if b in safe:
            out.append(chr(b))
        elif b == 0x20:
            out.append("+")
        else:
            out.append("%%%02X" % b)
    return "".join(out)


def kotlin_double(d):
    s = repr(float(d))
    assert "e" not in s
    return s


def reviews_js(cap):
    src = read(os.path.join(WEB, "WebReviewsFetcher.kt"))
    words = read(os.path.join(ROOT, "core/src/main/java/app/vela/core/data/ReviewWords.kt"))
    strip = raw_const(read(os.path.join(WEB, "ReviewTabJs.kt")), "STRIP_PLACE_NAME_JS")
    sel = lambda k, const: '"%s":' % k + js_string(const_string(src, const))
    selectors = "{" + ",".join([
        sel("card", "DEFAULT_CARD_SEL"), sel("id", "DEFAULT_ID_SEL"), sel("moreToggle", "DEFAULT_MORE_TOGGLE_SEL"),
        sel("author", "DEFAULT_AUTHOR_SEL"), sel("text", "DEFAULT_TEXT_SEL"), sel("date", "DEFAULT_DATE_SEL"),
    ]) + "}"
    env = {
        "idj": js_string(ID_TOKEN),
        "cap": str(cap),
        "reviewPatternJs()": js_string(const_string(words, "REVIEW_PATTERN")),
        "morePatternJs()": js_string(const_string(words, "MORE_PATTERN")),
        "STRIP_PLACE_NAME_JS": strip,
        "selectorsJs()": selectors,
    }
    return trim_indent(evaluate(raw_after(src, "private fun extractScript("), env))


def photos_js(cap, early):
    src = read(os.path.join(WEB, "WebPhotoFetcher.kt"))
    env = {
        "idj": js_string(ID_TOKEN),
        "cap": str(cap),
        'if (early) "true" else "false"': "true" if early else "false",
    }
    return trim_indent(evaluate(raw_after(src, "private fun extractScript("), env))


def details_url():
    """WebPopularTimesFetcher.fetch: searchEndpoint + q + pb (SearchPb.build, BrowserViewport.apply)."""
    cal = json.loads(read(os.path.join(ROOT, "calibration.json")))
    addr = re.sub(r"\s+", " ", FIXTURE_ADDRESS.replace(",", " ")).strip()
    query = FIXTURE_NAME + " " + addr
    pb = cal["searchPb"].replace("{QUERY}", query.replace("!", " ").strip()) \
        .replace("{LNG}", kotlin_double(FIXTURE_LNG)).replace("{LAT}", kotlin_double(FIXTURE_LAT))
    m = re.search(r"!1d([0-9.]+)", pb)
    if m:  # RequestShape.span: the template's span, jittered by up to 0.2%
        span = float(m.group(1)) * (1 + (random.random() - 0.5) * 0.004)
        pb = pb[:m.start()] + "!1d" + kotlin_double(span) + pb[m.end():]
    w, h = VIEWPORT
    captured_size = "!3m2!1i1024!2i768"
    captured_rects = ("m28!1m6!1m2!1i0!2i0!2m2!1i530!2i768!1m6!1m2!1i974!2i0!2m2!1i1024!2i768"
                      "!1m6!1m2!1i0!2i0!2m2!1i1024!2i20!1m6!1m2!1i0!2i748!2m2!1i1024!2i768")
    rects = ("m28!1m6!1m2!1i0!2i0!2m2!1i530!2i%d!1m6!1m2!1i%d!2i0!2m2!1i%d!2i%d"
             "!1m6!1m2!1i0!2i0!2m2!1i%d!2i20!1m6!1m2!1i0!2i%d!2m2!1i%d!2i%d") % (h, w - 50, w, h, w, h - 20, w, h)
    pb = pb.replace(captured_size, "!3m2!1i%d!2i%d" % (w, h)).replace(captured_rects, rects)
    return cal["searchEndpoint"] + "&q=" + java_url_encode(query) + "&pb=" + java_url_encode(pb), cal["sessionWarmUrl"]


def popular_js(url):
    src = read(os.path.join(WEB, "WebPopularTimesFetcher.kt"))
    env = {"u": js_str(url), "idj": js_str(ID_TOKEN)}
    return trim_indent(evaluate(raw_after(src, "private fun script("), env))


def main():
    random.seed(20261024)
    url, warm = details_url()
    scripts = {
        "reviews": reviews_js(50),
        "photos": photos_js(80, False),
        "popular": popular_js(url),
    }
    os.makedirs(os.path.join(HERE, "js"), exist_ok=True)
    swift = [
        "// Generated by tools/ios-spike-web/gen_js.py from the Android sources. Do not edit.",
        "import Foundation",
        "",
        "enum GeneratedJS {",
    ]
    for name, js in scripts.items():
        assert js.count(ID_TOKEN) >= 1, name
        data = js.encode("utf-8")
        with open(os.path.join(HERE, "js", name + ".js"), "wb") as f:
            f.write(data)
        swift.append('    static let %sB64 = "%s"' % (name, base64.b64encode(data).decode()))
        swift.append('    static let %sSha256 = "%s"' % (name, hashlib.sha256(data).hexdigest()))
        print("%-8s %6d bytes sha256 %s" % (name, len(data), hashlib.sha256(data).hexdigest()))
    swift.append('    static let detailsUrl = %s' % json.dumps(url))
    swift.append('    static let sessionWarmUrl = %s' % json.dumps(warm))
    swift.append('    static let featureId = %s' % json.dumps(FIXTURE_FID))
    swift.append("}")
    with open(os.path.join(HERE, "Sources", "GeneratedJS.swift"), "w", encoding="utf-8") as f:
        f.write("\n".join(swift) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
