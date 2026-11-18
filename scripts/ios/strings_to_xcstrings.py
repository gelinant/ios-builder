#!/usr/bin/env python3
"""Convert Android string resources into an Apple String Catalog (Localizable.xcstrings).

Reads every values*/ folder under the Android res directory, keeps the ones whose qualifier is a
plain locale, and writes one Xcode 15+ String Catalog. Python 3 standard library only.

Rules (see scripts/ios/README-strings.md for the reasoning):
- values/ is the source language (en). values-xx, values-xx-rYY and values-b+... map to Apple
  locale codes (iw -> he, in -> id, zh -> zh-Hans, zh-rTW -> zh-Hant, pt -> pt-PT, ...).
  Folders with any non-locale qualifier (values-night, values-fr-land, values-v21) are skipped.
- Values are decoded the way aapt2 does: XML entities and CDATA, backslash escapes, double
  quotes that preserve whitespace, whitespace collapsing, trimming.
- Java format specifiers become Apple ones: %s -> %@, %1$s -> %1$@, %n -> newline; %d -> %ld
  for a 64-bit Swift Int, while %.1f and %% stay. formatted="false" values are copied verbatim.
- translatable="false" keys exist only in the source language (shouldTranslate = false).
- <plurals> become plural variations. When the count is not the first format argument, the
  plural is emitted as a substitution bound to the count argument.
- <string-array> items become indexed keys name[0], name[1], ...
- Inline tags (<b>, <i>, <u>, xliff:g, ...) are flattened to their text and counted.
"""

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter, OrderedDict

SOURCE_LANGUAGE = "en"
XLIFF_NS = "urn:oasis:names:tc:xliff:document:1.2"

# Android keeps the pre-ISO 639 codes for these three languages.
LEGACY_LANGUAGES = {"iw": "he", "in": "id", "ji": "yi"}

PLURAL_CATEGORIES = ("zero", "one", "two", "few", "many", "other")

# Languages whose CLDR rules have a "zero" category. Android ignores quantity="zero" elsewhere,
# while Apple applies "zero" to the number 0 in every language, so it is dropped for the others.
ZERO_CATEGORY_LANGUAGES = {"ar", "cy", "ksh", "lag", "lv", "prg"}

STRING_ARG_RE = re.compile(
    r"%(?:(?P<pos>\d+)\$)?(?P<flags>[-#+0,(<]*)(?P<width>\d+)?(?P<prec>\.\d+)?"
    r"(?P<conv>[tT][a-zA-Z]|[a-zA-Z%])"
)
INTEGER_CONVERSIONS = {"d", "o", "x", "X"}


class Report:
    """Collects counts, skipped items and warnings for --report."""

    def __init__(self):
        self.locales = OrderedDict()
        self.skipped = Counter()
        self.skipped_examples = {}
        self.warnings = Counter()
        self.warning_examples = {}
        self.notes = []

    def locale_counts(self, locale):
        return self.locales.setdefault(locale, Counter())

    def skip(self, reason, example):
        self.skipped[reason] += 1
        self.skipped_examples.setdefault(reason, []).append(example)

    def warn(self, kind, example):
        self.warnings[kind] += 1
        self.warning_examples.setdefault(kind, []).append(example)

    def render(self, max_examples=5):
        lines = ["Locales:"]
        width = max([len(k) for k in self.locales] + [6])
        for locale, counts in self.locales.items():
            lines.append(
                "  %-*s strings=%d plurals=%d array_items=%d" % (
                    width, locale, counts["strings"], counts["plurals"], counts["array_items"])
            )
        for title, counter, examples in (
            ("Skipped", self.skipped, self.skipped_examples),
            ("Warnings", self.warnings, self.warning_examples),
        ):
            lines.append("%s: %d" % (title, sum(counter.values())))
            for kind in sorted(counter):
                shown = examples[kind][:max_examples]
                more = len(examples[kind]) - len(shown)
                lines.append("  %s: %d" % (kind, counter[kind]))
                for ex in shown:
                    lines.append("    - %s" % ex)
                if more > 0:
                    lines.append("    ... %d more" % more)
        for note in self.notes:
            lines.append("Note: %s" % note)
        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Locale qualifiers

def qualifier_to_locale(folder):
    """Map an Android values folder name to an Apple locale code.

    Returns (locale, None) on success, or (None, reason) when the folder is not a plain locale
    folder. values maps to the source language.
    """
    if folder == "values":
        return SOURCE_LANGUAGE, None
    if not folder.startswith("values-"):
        return None, "not a values folder"
    parts = folder[len("values-"):].split("-")
    head = parts[0]
    if head.startswith("b+"):
        sub = head[2:].split("+")
        rest = parts[1:]
        language = sub[0].lower()
        script = None
        region = None
        for tag in sub[1:]:
            if re.fullmatch(r"[A-Za-z]{4}", tag):
                script = tag.title()
            elif re.fullmatch(r"[A-Za-z]{2}|\d{3}", tag):
                region = tag.upper()
            else:
                return None, "unsupported BCP 47 subtag %r" % tag
    else:
        if not re.fullmatch(r"[a-z]{2,3}", head):
            return None, "no locale qualifier"
        language = head
        script = None
        region = None
        rest = parts[1:]
        if rest and re.fullmatch(r"r(?:[A-Z]{2}|\d{3})", rest[0]):
            region = rest[0][1:]
            rest = rest[1:]
    if not re.fullmatch(r"[a-z]{2,3}", language):
        return None, "no locale qualifier"
    if rest:
        return None, "extra qualifiers %r" % "-".join(rest)
    return apple_locale(language, script, region), None


def apple_locale(language, script=None, region=None):
    """Build the locale code Xcode uses for a language, script and region."""
    language = LEGACY_LANGUAGES.get(language, language)
    if language == "zh":
        if script is None:
            # Xcode only offers zh-Hans, zh-Hant and zh-HK. Android zh and zh-rCN/rSG are
            # Simplified; zh-rTW and zh-rMO are Traditional.
            if region in ("TW", "MO"):
                script = "Hant"
            elif region == "HK":
                return "zh-HK"
            else:
                script = "Hans"
        if region in ("CN", "SG", "TW", "MO"):
            region = None
    if language == "pt" and script is None and region is None:
        # Android values-pt is European Portuguese when values-pt-rBR exists; Xcode names it pt-PT.
        region = "PT"
    code = language
    if script:
        code += "-" + script
    if region:
        code += "-" + region
    return code


# ---------------------------------------------------------------------------
# Value decoding

def flatten_element(element, report, where):
    """Return the raw text of an element with inline child tags removed."""
    out = [element.text or ""]
    for child in element:
        tag = child.tag
        if isinstance(tag, str) and tag.startswith("{" + XLIFF_NS + "}"):
            name = "xliff:" + tag.split("}", 1)[1]
        elif isinstance(tag, str):
            name = tag
        else:
            name = None
        if name is not None:
            report.warn("inline tag <%s> flattened" % name, where)
            out.append(flatten_element(child, report, where))
        out.append(child.tail or "")
    return "".join(out)


def decode_android(raw, report=None, where=""):
    """Apply aapt2 string processing: escapes, quotes, whitespace collapsing and trimming."""
    # Each item is (char, collapsible) where collapsible marks an unquoted, unescaped space.
    chars = []
    quoted = False
    i = 0
    n = len(raw)
    while i < n:
        c = raw[i]
        if c == "\\":
            i += 1
            if i >= n:
                break
            e = raw[i]
            if e == "n":
                chars.append(("\n", False))
            elif e == "t":
                chars.append(("\t", False))
            elif e == "u":
                digits = raw[i + 1:i + 5]
                if re.fullmatch(r"[0-9a-fA-F]{4}", digits):
                    chars.append((chr(int(digits, 16)), False))
                    i += 4
                else:
                    if report:
                        report.warn("bad \\u escape", where)
                    chars.append(("u", False))
            else:
                # \' \" \\ \@ \? \# and any other escaped char stand for themselves.
                chars.append((e, False))
            i += 1
            continue
        if c == '"':
            quoted = not quoted
            i += 1
            continue
        if not quoted and c in " \t\n\r\f\v":
            if not (chars and chars[-1][1]):
                chars.append((" ", True))
            i += 1
            continue
        if not quoted and c == "'" and report:
            report.warn("unescaped apostrophe", where)
        chars.append((c, False))
        i += 1
    if quoted and report:
        report.warn("unbalanced double quote", where)
    start = 0
    end = len(chars)
    while start < end and chars[start][1]:
        start += 1
    while end > start and chars[end - 1][1]:
        end -= 1
    return "".join(ch for ch, _ in chars[start:end])


def convert_format(text, report=None, where=""):
    """Convert Java format specifiers to Apple ones."""

    def repl(match):
        conv = match.group("conv")
        spec = match.group(0)
        if conv == "%":
            return spec
        if conv == "n":
            return "\n"
        pos = match.group("pos")
        prefix = "%" + (pos + "$" if pos else "")
        flags = match.group("flags") or ""
        width = match.group("width") or ""
        prec = match.group("prec") or ""
        if "," in flags or "<" in flags or "(" in flags:
            if report:
                report.warn("unsupported format flag in %s" % spec, where)
        if conv in ("s", "S"):
            if conv == "S" and report:
                report.warn("%S upper-casing dropped", where)
            if (width or prec or flags) and report:
                report.warn("width or precision on %s" % spec, where)
            return prefix + "@"
        if conv in ("c", "b", "B", "h", "H"):
            if report:
                report.warn("%%%s converted to %%@" % conv, where)
            return prefix + "@"
        if conv[0] in "tT":
            if report:
                report.warn("date conversion %s kept" % spec, where)
            return spec
        if conv == "d":
            # Swift's Int is a 64-bit CLong on every iOS target Vela builds.
            return prefix + flags + width + prec + "ld"
        if conv in "oxXeEfgGaA":
            return spec
        if report:
            report.warn("unknown format conversion %s kept" % spec, where)
        return spec

    return STRING_ARG_RE.sub(repl, text)


def element_value(element, report, where):
    """Decode one <string> or <item> element into its Apple value."""
    raw = flatten_element(element, report, where)
    text = decode_android(raw, report, where)
    if element.get("formatted") == "false":
        return text, False
    return convert_format(text, report, where), True


# Matches converted specifiers, including %@.
APPLE_ARG_RE = re.compile(
    r"%(?:(?P<pos>\d+)\$)?[-#+0,(]*\d*(?:\.\d+)?(?:ll|l|h)?(?P<conv>[@a-zA-Z])"
)


def apple_args(text):
    args = []
    implicit = 0
    for m in APPLE_ARG_RE.finditer(text.replace("%%", "")):
        if m.group("pos"):
            pos = int(m.group("pos"))
        else:
            implicit += 1
            pos = implicit
        args.append((pos, m.group("conv"), m))
    return args


def count_argument(values):
    """Pick the plural count argument: the lowest-position integer argument of the plural."""
    positions = set()
    for value in values:
        for pos, conv, _ in apple_args(value):
            if conv in INTEGER_CONVERSIONS:
                positions.add((pos, conv))
    if not positions:
        return None
    return min(positions)


def replace_count_arg(text, position):
    """Replace the specifier for argument `position` with %arg (String Catalog substitution)."""
    out = []
    last = 0
    implicit = 0
    stripped = text
    i = 0
    while i < len(stripped):
        if stripped.startswith("%%", i):
            i += 2
            continue
        m = APPLE_ARG_RE.match(stripped, i)
        if m and stripped[i] == "%":
            if m.group("pos"):
                pos = int(m.group("pos"))
            else:
                implicit += 1
                pos = implicit
            if pos == position:
                out.append(stripped[last:i])
                out.append("%arg")
                last = m.end()
            i = m.end()
            continue
        i += 1
    out.append(stripped[last:])
    return "".join(out)


# ---------------------------------------------------------------------------
# Loading

class Entry:
    """One resource: kind is string, plurals or array."""

    def __init__(self, kind, name, value, translatable=True, formatted=True):
        self.kind = kind
        self.name = name
        self.value = value  # str, {category: str}, or [str]
        self.translatable = translatable
        self.formatted = formatted


def load_folder(path, locale, report):
    """Load all string resources of one values folder, keyed by resource name."""
    entries = OrderedDict()
    for filename in sorted(os.listdir(path)):
        if not filename.endswith(".xml"):
            continue
        file_path = os.path.join(path, filename)
        rel = os.path.join(os.path.basename(path), filename)
        root = ET.parse(file_path).getroot()
        if root.tag != "resources":
            continue
        for element in root:
            if not isinstance(element.tag, str):
                continue
            name = element.get("name")
            tag = element.tag
            if tag not in ("string", "plurals", "string-array"):
                continue
            where = "%s %s" % (rel, name)
            if name is None:
                report.skip("element without name", rel)
                continue
            if name in entries:
                report.skip("duplicate name", where)
                continue
            translatable = element.get("translatable") != "false"
            if tag == "string":
                value, formatted = element_value(element, report, where)
                entries[name] = Entry("string", name, value, translatable, formatted)
            elif tag == "plurals":
                forms = {}
                formatted = True
                for item in element.findall("item"):
                    quantity = item.get("quantity")
                    if quantity not in PLURAL_CATEGORIES:
                        report.skip("unknown plural quantity", "%s %r" % (where, quantity))
                        continue
                    value, formatted = element_value(item, report, where)
                    forms[quantity] = value
                if "zero" in forms and locale.split("-")[0] not in ZERO_CATEGORY_LANGUAGES:
                    report.warn("quantity zero dropped (not a CLDR category here)", where)
                    del forms["zero"]
                if "other" not in forms:
                    report.warn("plural without other", where)
                if not forms:
                    report.skip("empty plurals", where)
                    continue
                entries[name] = Entry("plurals", name, forms, translatable, formatted)
            else:
                items = []
                for item in element.findall("item"):
                    value, _ = element_value(item, report, where)
                    items.append(value)
                entries[name] = Entry("array", name, items, translatable)
    return entries


def load_resources(res_dir, report):
    """Return {locale: {name: Entry}} with the source language first."""
    folders = sorted(
        d for d in os.listdir(res_dir)
        if d.startswith("values") and os.path.isdir(os.path.join(res_dir, d))
    )
    if "values" not in folders:
        raise SystemExit("no values/ folder in %s" % res_dir)
    result = OrderedDict()
    for folder in ["values"] + [f for f in folders if f != "values"]:
        locale, reason = qualifier_to_locale(folder)
        path = os.path.join(res_dir, folder)
        if locale is None:
            # Only report folders that actually hold strings.
            probe = load_folder(path, "und", Report())
            if probe:
                report.skip("non-locale folder (%s)" % reason, folder)
            continue
        if locale in result:
            report.skip("folder maps to an existing locale", "%s -> %s" % (folder, locale))
            continue
        result[locale] = load_folder(path, locale, report)
    return result


def resolve_reference(value, locale, resources, report, where):
    """Resolve a whole-value @string/name reference, falling back to the source language."""
    m = re.fullmatch(r"@string/([A-Za-z0-9_.]+)", value)
    if not m:
        if value.startswith("@") or value.startswith("?"):
            if re.fullmatch(r"[@?][A-Za-z0-9_.:+]+/[A-Za-z0-9_.]+", value):
                report.warn("unresolved resource reference kept", where)
        return value
    target = m.group(1)
    for loc in (locale, SOURCE_LANGUAGE):
        entry = resources.get(loc, {}).get(target)
        if entry is not None and entry.kind == "string":
            return entry.value
    report.warn("unresolved resource reference kept", where)
    return value


# ---------------------------------------------------------------------------
# Catalog

def string_unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural_localization(forms, count_arg):
    """Build a localization for a plural, top-level or as a substitution."""
    if count_arg is None or count_arg[0] == 1:
        return {"variations": {"plural": {q: string_unit(v) for q, v in forms.items()}}}
    position, conv = count_arg
    variants = {q: string_unit(replace_count_arg(v, position)) for q, v in forms.items()}
    return {
        "stringUnit": {"state": "translated", "value": "%#@count@"},
        "substitutions": {
            "count": {
                "argNum": position,
                "formatSpecifier": "ld" if conv == "d" else conv,
                "variations": {"plural": variants},
            }
        },
    }


def build_catalog(resources, report, allow=None):
    """Build the String Catalog dictionary."""
    source = resources[SOURCE_LANGUAGE]
    strings = {}
    found = set()

    def wanted(name):
        return allow is None or name in allow

    count_args = {}
    for locale, entries in resources.items():
        counts = report.locale_counts(locale)
        for name, entry in entries.items():
            where = "%s %s" % (locale, name)
            src = source.get(name)
            if locale != SOURCE_LANGUAGE:
                if src is None:
                    report.skip("not in source language", where)
                    continue
                if src.kind != entry.kind:
                    report.skip("kind differs from source", where)
                    continue
                if not src.translatable or not entry.translatable:
                    report.skip("translatable=false outside source", where)
                    continue
            if entry.kind == "array":
                for index, item in enumerate(entry.value):
                    key = "%s[%d]" % (name, index)
                    if not (wanted(name) or wanted(key)):
                        continue
                    if locale != SOURCE_LANGUAGE and index >= len(src.value):
                        report.skip("array item beyond source length", "%s[%d]" % (where, index))
                        continue
                    found.update((name, key))
                    item = resolve_reference(item, locale, resources, report, where)
                    record = strings.setdefault(key, new_record(src or entry))
                    record["localizations"][locale] = string_unit(item)
                    counts["array_items"] += 1
                continue
            if not wanted(name):
                continue
            found.add(name)
            record = strings.setdefault(name, new_record(src or entry))
            if entry.kind == "string":
                value = resolve_reference(entry.value, locale, resources, report, where)
                record["localizations"][locale] = string_unit(value)
                counts["strings"] += 1
            else:
                if name not in count_args:
                    count_args[name] = count_argument(source[name].value.values())
                    if count_args[name] is None:
                        report.warn("plural without integer argument", name)
                count_arg = count_args[name]
                if locale == SOURCE_LANGUAGE and count_arg and count_arg[0] != 1:
                    report.warn("plural count is argument %d (substitution)" % count_arg[0], name)
                record["localizations"][locale] = plural_localization(entry.value, count_arg)
                counts["plurals"] += 1
    if allow is not None:
        for key in sorted(allow - found):
            report.skip("allow-listed key not found", key)
    return {"sourceLanguage": SOURCE_LANGUAGE, "strings": strings, "version": "1.0"}


def new_record(entry):
    record = {"extractionState": "manual", "localizations": {}}
    if not entry.translatable:
        record["shouldTranslate"] = False
    return record


def dump_catalog(catalog):
    """Serialize like Xcode does: sorted keys, two-space indent, ' : ' separators."""
    return json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True,
                      separators=(",", " : ")) + "\n"


def read_allow_list(path):
    keys = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                keys.add(line)
    return keys


def convert(res_dir, allow=None):
    report = Report()
    resources = load_resources(res_dir, report)
    catalog = build_catalog(resources, report, allow)
    return catalog, report


def main(argv=None):
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--res", default=os.path.join(root, "app", "src", "main", "res"),
                        help="Android res directory (default: app/src/main/res)")
    parser.add_argument("--out", default="Localizable.xcstrings",
                        help="output file, '-' for stdout (default: Localizable.xcstrings)")
    parser.add_argument("--keys", help="allow-list file: one key per line, # comments")
    parser.add_argument("--report", action="store_true",
                        help="print per-locale counts, skipped items and warnings to stderr")
    args = parser.parse_args(argv)

    allow = read_allow_list(args.keys) if args.keys else None
    catalog, report = convert(args.res, allow)
    text = dump_catalog(catalog)
    if args.out == "-":
        sys.stdout.write(text)
    else:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
    if args.report:
        print(report.render(), file=sys.stderr)
        print("Keys: %d" % len(catalog["strings"]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
