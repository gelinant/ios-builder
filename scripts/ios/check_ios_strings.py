#!/usr/bin/env python3
"""Check the generated iOS catalog, its Swift references and the 24-language picker."""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import strings_to_xcstrings as conv  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CATALOG = os.path.join(ROOT, "iosApp", "Vela", "Resources", "Localizable.xcstrings")
L10N = os.path.join(ROOT, "iosApp", "Vela", "Resources", "VelaL10n.swift")
KEY_RE = re.compile(r"\b(?:VelaL10n|L)\.text\(\s*\"([^\"]+)\"")
UI_CTORS = (
    "Text", "Label", "Button", "Toggle", "Picker", "Section", "TextField",
    "SecureField", "Link", "Menu", "Stepper", "navigationTitle", "accessibilityLabel",
    "accessibilityHint", "accessibilityValue", "help", "alert", "confirmationDialog",
    "badge", "ContentUnavailableView", "ProgressView",
)
UI_REGION_RE = re.compile(r"\.?\b(?:" + "|".join(UI_CTORS) + r")\s*\(")
# Keyword arguments inside a UI call that never carry user-visible text.
NON_TEXT_ARG_RE = re.compile(
    r"(?:systemImage|accessibilityIdentifier|identifier|role|image|for|action|placement|"
    r"value|selection|format|tableName|bundle|comment|of|in)\s*:\s*$")
# Literals that stay identical in every language: brands, licences, symbols, units, keys.
ALLOWED_LITERALS = {
    "Vela", "Google", "Transitous", "Wikidata", "Wikivoyage", "Piper", "OSM",
    "GPX", "KML", "KMZ", "MB", "GB", "GPS", "API", "ETA", "ASR", "URL", "JSON",
    "CSV", "PDF", "iOS", "Android", "Live", "LowDataMode", "LowRamMode",
    # The map credit is the licence's own text, identical in every language.
    "© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors",
}
ALLOWED_PREFIXES = ("https://", "http://", "mailto:")
# Stored string properties at type scope, indented four spaces. A name in this set is too generic
# to attribute to one declaration when it is read as a bare identifier.
CONSTANT_RE = re.compile(
    r"^(?: {4}|\t)(?:(?:private|fileprivate|internal|public)\s+)?(?:static\s+)?"
    r"(?:let|var)\s+(\w+)\s*(?::\s*String\s*)?=\s*\"((?:[^\"\\]|\\.)*)\"\s*$",
    re.MULTILINE)
CONSTANT_SKIP_NAMES = {
    "title", "label", "text", "detail", "source", "name", "kind", "identifier", "key",
}
# A local binding inside a function body: at least two indentation levels, so a stored
# property at type scope stays the job of CONSTANT_RE.
LOCAL_RE = re.compile(
    r"^(?P<indent>[ \t]+)(?:let|var)\s+(\w+)\s*(?::\s*String\s*)?=\s*\"((?:[^\"\\]|\\.)*)\"\s*$",
    re.MULTILINE)
ALLOWED_FILES = {
    # Developer diagnostics and fixture labels: these never ship in a release UI.
    "iosApp/Vela/Transit/TransitGoTestSupport.swift",
    "iosApp/Vela/Offline/OfflineTestSupport.swift",
}
LANGUAGE_RE = re.compile(r"VelaLanguage\(code: \"([^\"]+)\"")
INT_RE = re.compile(r"%(?:\d+\$)?[-#+0,(]*\d*(?:\.\d+)?d")


def fail(message):
    print("check_ios_strings: " + message, file=sys.stderr)
    raise SystemExit(1)


def _skip_string(source, index):
    r"""Return the index after a Swift string literal, including \(...) interpolation."""
    length = len(source)
    if source.startswith('"""', index):
        end = source.find('"""', index + 3)
        return length if end < 0 else end + 3
    i = index + 1
    while i < length:
        if source[i] == "\\":
            if i + 1 < length and source[i + 1] == "(":
                depth = 1
                i += 2
                while i < length and depth:
                    if source[i] == '"':
                        i = _skip_string(source, i)
                        continue
                    if source.startswith("//", i):
                        end = source.find("\n", i)
                        i = length if end < 0 else end
                        continue
                    if source.startswith("/*", i):
                        end = source.find("*/", i + 2)
                        i = length if end < 0 else end + 2
                        continue
                    if source[i] == "(":
                        depth += 1
                    elif source[i] == ")":
                        depth -= 1
                    i += 1
                continue
            i += 2
            continue
        if source[i] == '"':
            return i + 1
        i += 1
    return length


def _string_tokens(source):
    tokens = []
    i = 0
    length = len(source)
    while i < length:
        if source[i] == "/":
            if source.startswith("//", i):
                end = source.find("\n", i)
                i = length if end < 0 else end
                continue
            if source.startswith("/*", i):
                end = source.find("*/", i + 2)
                i = length if end < 0 else end + 2
                continue
        if source[i] == '"':
            end = _skip_string(source, i)
            tokens.append((i, end))
            i = end
            continue
        i += 1
    return tokens


def _match_paren(source, start):
    depth = 0
    i = start
    while i < len(source):
        if source[i] == '"':
            i = _skip_string(source, i)
            continue
        if source.startswith("//", i):
            end = source.find("\n", i)
            i = len(source) if end < 0 else end
            continue
        if source.startswith("/*", i):
            end = source.find("*/", i + 2)
            i = len(source) if end < 0 else end + 2
            continue
        if source[i] == "(":
            depth += 1
        elif source[i] == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(source) - 1


def _debug_ranges(source):
    ranges = []
    stack = []
    for match in re.finditer(r"#if\s+DEBUG|#endif", source):
        if match.group(0).startswith("#if"):
            stack.append(match.start())
        elif stack:
            ranges.append((stack.pop(), match.end()))
    return ranges


def _visible_text(literal):
    """Drop Swift interpolations so only text that reaches the screen is checked."""
    out = []
    i = 0
    while i < len(literal):
        if literal[i] == "\\" and i + 1 < len(literal) and literal[i + 1] == "(":
            depth = 1
            i += 2
            while i < len(literal) and depth:
                if literal[i] == '"':
                    i = _skip_string(literal, i)
                    continue
                if literal[i] == "(":
                    depth += 1
                elif literal[i] == ")":
                    depth -= 1
                i += 1
            continue
        out.append(literal[i])
        i += 1
    return "".join(out)


def hardcoded_literals(path, source):
    """Yield (line, literal) for English UI literals that never reach VelaL10n."""
    tokens = _string_tokens(source)
    debug = _debug_ranges(source)
    regions = []
    for match in UI_REGION_RE.finditer(source):
        if re.search(r"\bfunc\s+$", source[max(0, match.start() - 20):match.start()]):
            continue
        start = match.end() - 1
        regions.append((match.start(), _match_paren(source, start)))
    for start, end in tokens:
        literal = source[start + 1:end - 1]
        inside = [r for r in regions if r[0] < start and end <= r[1]]
        if not inside:
            continue
        region = min(inside, key=lambda r: r[1] - r[0])
        before = source[region[0]:start]
        if NON_TEXT_ARG_RE.search(before[-90:]):
            continue
        if re.search(r"(?:VelaL10n|L|text)\.text\(\s*$", before):
            continue
        if any(lo <= start < hi for lo, hi in debug):
            continue
        if literal in ALLOWED_LITERALS or literal.startswith(ALLOWED_PREFIXES):
            continue
        visible = _visible_text(literal)
        if "=" in visible:
            continue
        if "\\(" in literal:
            # A number or a name inside a sentence still leaves the words around it in English,
            # as in Text("\(count) results"). Pure data strings carry no letters outside the
            # interpolation, so they stay quiet.
            if not re.search(r"[A-Za-z]", visible):
                continue
        elif not re.search(r"[A-Z]", visible):
            continue
        line = source.count("\n", 0, start) + 1
        yield line, literal


def stored_constants(source, debug):
    """Yield (line, name, literal) for named string properties that hold UI copy."""
    for match in CONSTANT_RE.finditer(source):
        name = match.group(1)
        literal = match.group(2)
        if name in CONSTANT_SKIP_NAMES:
            continue
        if any(lo <= match.start() < hi for lo, hi in debug):
            continue
        if literal in ALLOWED_LITERALS or literal.startswith(ALLOWED_PREFIXES):
            continue
        visible = _visible_text(literal)
        # A stored literal is only copy when it reads like a phrase: a capital letter and a
        # space, and no debug key=value shape.
        if "=" in visible or " " not in visible or not re.search(r"[A-Z]", visible):
            continue
        line = source.count("\n", 0, match.start()) + 1
        yield line, name, literal


def local_literals(source, debug):
    """Yield (line, name, literal) for a local string that a view later shows.

    The literal must read like copy: a phrase or a capitalised word, never an identifier such
    as a symbol name. The reference check happens in main, once every UI call is known.
    """
    for match in LOCAL_RE.finditer(source):
        if len(match.group("indent").expandtabs(4)) < 8:
            continue
        if any(lo <= match.start() < hi for lo, hi in debug):
            continue
        name = match.group(2)
        literal = match.group(3)
        if literal in ALLOWED_LITERALS or literal.startswith(ALLOWED_PREFIXES):
            continue
        if "\\(" in literal or "=" in literal or "." in literal:
            continue
        if not re.search(r"[A-Za-z]", literal):
            continue
        if " " not in literal and not literal[:1].isupper():
            continue
        line = source.count("\n", 0, match.start()) + 1
        yield line, name, literal


def ui_regions(source):
    """Yield the source span of every UI call that can show a string."""
    for match in UI_REGION_RE.finditer(source):
        if re.search(r"\bfunc\s+$", source[max(0, match.start() - 20):match.start()]):
            continue
        yield match.start(), _match_paren(source, match.end() - 1)


def constant_references(source, names):
    """Yield (line, name) when a UI call reads one of the stored constants."""
    for start, end in ui_regions(source):
        region = source[start:end + 1]
        for name in names:
            hit = re.search(r"\b" + re.escape(name) + r"\b", region)
            if hit:
                yield source.count("\n", 0, start + hit.start()) + 1, name


def walk_strings(value):
    if isinstance(value, dict):
        for child in value.values():
            yield from walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_strings(child)
    elif isinstance(value, str):
        yield value


def main():
    resources = os.path.join(ROOT, "app", "src", "main", "res")
    catalog, report = conv.convert(resources)
    expected = conv.dump_catalog(catalog)
    if not os.path.isfile(CATALOG):
        fail("Localizable.xcstrings is missing; run strings_to_xcstrings.py first")
    with open(CATALOG, encoding="utf-8") as f:
        actual = f.read()
    if actual != expected:
        fail("Localizable.xcstrings is stale; regenerate it")
    on_disk = json.loads(actual)

    used = set()
    for folder, _, files in os.walk(os.path.join(ROOT, "iosApp", "Vela")):
        for filename in files:
            if not filename.endswith(".swift"):
                continue
            with open(os.path.join(folder, filename), encoding="utf-8") as f:
                used.update(KEY_RE.findall(f.read()))
    missing = sorted(key for key in used if key not in on_disk["strings"])
    if missing:
        fail("Swift references missing catalog keys: " + ", ".join(missing))
    no_english = sorted(key for key in used if "en" not in on_disk["strings"][key]["localizations"])
    if no_english:
        fail("Swift keys without English fallback: " + ", ".join(no_english))
    for key, record in on_disk["strings"].items():
        for value in walk_strings(record):
            if INT_RE.search(value.replace("%%", "")):
                fail("%s retains a 32-bit %%d specifier" % key)

    offenders = []
    constants = []
    locals_ = []
    sources = {}
    for folder, _, files in os.walk(os.path.join(ROOT, "iosApp", "Vela")):
        for filename in sorted(files):
            if not filename.endswith(".swift"):
                continue
            path = os.path.join(folder, filename)
            rel = os.path.relpath(path, ROOT)
            if rel in ALLOWED_FILES:
                continue
            with open(path, encoding="utf-8") as f:
                source = f.read()
            sources[rel] = source
            debug = _debug_ranges(source)
            for line, name, literal in stored_constants(source, debug):
                constants.append((rel, line, name, literal))
            for line, name, literal in local_literals(source, debug):
                locals_.append((rel, line, name, literal))
            for line, literal in hardcoded_literals(rel, source):
                offenders.append("%s:%d %r" % (rel, line, literal))
    if offenders:
        fail("user-visible literals bypass VelaL10n: " + "; ".join(offenders[:12]) +
             (" (+%d more)" % (len(offenders) - 12) if len(offenders) > 12 else ""))
    for rel, line, name, literal in constants:
        for ref_line, _ in constant_references(sources[rel], {name}):
            offenders.append("%s:%d stored constant %s = %r (used at line %d)" % (
                rel, line, name, literal, ref_line))
    # A stored constant can be read from another file, so scan every file for each name.
    for rel, line, name, literal in constants:
        for other, source in sources.items():
            if other == rel:
                continue
            for ref_line, _ in constant_references(source, {name}):
                offenders.append("%s:%d stored constant %s = %r (used in %s:%d)" % (
                    rel, line, name, literal, other, ref_line))
    for rel, line, name, literal in locals_:
        for ref_line, _ in constant_references(sources[rel], {name}):
            offenders.append("%s:%d local %s = %r (used in a view at line %d)" % (
                rel, line, name, literal, ref_line))
    if offenders:
        fail("user-visible literals bypass VelaL10n: " + "; ".join(offenders[:12]) +
             (" (+%d more)" % (len(offenders) - 12) if len(offenders) > 12 else ""))

    with open(L10N, encoding="utf-8") as f:
        picker = set(LANGUAGE_RE.findall(f.read()))
    resource_locales = set(report.locales)
    picker_as_locales = {"pt-PT" if x == "pt" else "zh-Hans" if x == "zh"
                         else "zh-Hant" if x == "zh-TW" else x for x in picker}
    if picker_as_locales != resource_locales:
        fail("language picker does not match Android locales: picker=%s resources=%s" % (
            sorted(picker_as_locales), sorted(resource_locales)))
    if len(picker) != 24:
        fail("language picker has %d entries, expected 24" % len(picker))

    translated_locales = {locale for record in on_disk["strings"].values()
                          for locale in record["localizations"]}
    localized_values = sum(len(record["localizations"]) for record in on_disk["strings"].values())
    print("string catalog: %d keys, %d resource locales (%d with translations), "
          "%d localized values, %d Swift references, 24 picker languages" % (
              len(on_disk["strings"]), len(resource_locales), len(translated_locales),
              localized_values, len(used)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
