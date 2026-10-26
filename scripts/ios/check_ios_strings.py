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
LANGUAGE_RE = re.compile(r"VelaLanguage\(code: \"([^\"]+)\"")
INT_RE = re.compile(r"%(?:\d+\$)?[-#+0,(]*\d*(?:\.\d+)?d")


def fail(message):
    print("check_ios_strings: " + message, file=sys.stderr)
    raise SystemExit(1)


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
