#!/usr/bin/env python3
"""Tests for strings_to_xcstrings.py. Run: python3 -m unittest scripts/ios/test_strings_to_xcstrings.py"""

import json
import os
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import strings_to_xcstrings as conv  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REAL_RES = os.path.join(REPO, "app", "src", "main", "res")


def value_of(xml, report=None):
    """Decode the first child of <resources> as the tool would."""
    root = ET.fromstring(
        '<resources xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2">%s</resources>' % xml)
    return conv.element_value(root[0], report or conv.Report(), "test")[0]


class FixtureRes:
    """Builds a temporary res directory from {folder: {file: body}}."""

    def __init__(self, folders):
        self.tmp = tempfile.TemporaryDirectory()
        for folder, files in folders.items():
            os.makedirs(os.path.join(self.tmp.name, folder))
            for name, body in files.items():
                with open(os.path.join(self.tmp.name, folder, name), "w", encoding="utf-8") as f:
                    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                            '<resources xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2">'
                            '%s</resources>' % body)

    def __enter__(self):
        return self.tmp.name

    def __exit__(self, *exc):
        self.tmp.cleanup()


def convert(folders, allow=None):
    with FixtureRes(folders) as res:
        return conv.convert(res, allow)


class LocaleTests(unittest.TestCase):
    def check(self, folder, expected):
        self.assertEqual(conv.qualifier_to_locale(folder)[0], expected, folder)

    def test_source(self):
        self.check("values", "en")

    def test_plain_languages(self):
        self.check("values-fr", "fr")
        self.check("values-kmr", "kmr")

    def test_regions(self):
        self.check("values-pt-rBR", "pt-BR")
        self.check("values-en-rGB", "en-GB")
        self.check("values-es-r419", "es-419")

    def test_legacy_codes(self):
        self.check("values-iw", "he")
        self.check("values-in", "id")
        self.check("values-ji", "yi")

    def test_chinese(self):
        self.check("values-zh", "zh-Hans")
        self.check("values-zh-rCN", "zh-Hans")
        self.check("values-zh-rTW", "zh-Hant")
        self.check("values-zh-rHK", "zh-HK")
        self.check("values-b+zh+Hant+TW", "zh-Hant")
        self.check("values-b+zh+Hans", "zh-Hans")

    def test_portuguese(self):
        self.check("values-pt", "pt-PT")

    def test_bcp47(self):
        self.check("values-b+sr+Latn", "sr-Latn")
        self.check("values-b+es+419", "es-419")
        self.check("values-b+iw", "he")

    def test_non_locale_folders(self):
        for folder in ("values-night", "values-v21", "values-fr-night", "values-land",
                       "values-sw600dp", "values-mcc310"):
            self.assertIsNone(conv.qualifier_to_locale(folder)[0], folder)


class DecodeTests(unittest.TestCase):
    def test_escapes(self):
        self.assertEqual(value_of(r"<string name='a'>It\'s \"x\" \\ \@ \? \#</string>"),
                         "It's \"x\" \\ @ ? #")

    def test_newline_and_tab(self):
        self.assertEqual(value_of(r"<string name='a'>a\nb\tc</string>"), "a\nb\tc")

    def test_unicode_escape(self):
        self.assertEqual(value_of(r"<string name='a'>A \u2192 B</string>"), "A \u2192 B")

    def test_bad_unicode_escape_warns(self):
        report = conv.Report()
        self.assertEqual(value_of(r"<string name='a'>\u12</string>", report), "u12")
        self.assertEqual(report.warnings["bad \\u escape"], 1)

    def test_xml_entities(self):
        self.assertEqual(value_of("<string name='a'>a &amp; b &lt;c&gt; &#8594; &#x41;</string>"),
                         "a & b <c> \u2192 A")

    def test_cdata(self):
        self.assertEqual(value_of("<string name='a'><![CDATA[<b>bold</b> & co]]></string>"),
                         "<b>bold</b> & co")

    def test_whitespace_collapses_and_trims(self):
        self.assertEqual(value_of("<string name='a'>\n   one   two\n\tthree  \n</string>"),
                         "one two three")

    def test_quotes_preserve_whitespace(self):
        self.assertEqual(value_of("<string name='a'>\"  two  spaces \"</string>"),
                         "  two  spaces ")

    def test_quotes_allow_apostrophe(self):
        self.assertEqual(value_of("<string name='a'>\"It's fine\"</string>"), "It's fine")

    def test_partial_quotes(self):
        self.assertEqual(value_of("<string name='a'>a  \"b  c\"  d</string>"), "a b  c d")

    def test_escaped_whitespace_is_kept_at_ends(self):
        self.assertEqual(value_of(r"<string name='a'>  \n x \t </string>"), "\n x \t")

    def test_unescaped_apostrophe_warns(self):
        report = conv.Report()
        self.assertEqual(value_of("<string name='a'>It's</string>", report), "It's")
        self.assertEqual(report.warnings["unescaped apostrophe"], 1)

    def test_inline_tags_flattened(self):
        report = conv.Report()
        self.assertEqual(
            value_of("<string name='a'>A <b>bold</b>, <i>it</i> and <u>u</u> end</string>", report),
            "A bold, it and u end")
        self.assertEqual(report.warnings["inline tag <b> flattened"], 1)
        self.assertEqual(report.warnings["inline tag <i> flattened"], 1)
        self.assertEqual(report.warnings["inline tag <u> flattened"], 1)

    def test_xliff_flattened(self):
        report = conv.Report()
        self.assertEqual(
            value_of('<string name="a">Hi <xliff:g id="name" example="Bo">%1$s</xliff:g>!</string>',
                     report),
            "Hi %1$@!")
        self.assertEqual(report.warnings["inline tag <xliff:g> flattened"], 1)


class FormatTests(unittest.TestCase):
    def fmt(self, text):
        return conv.convert_format(text)

    def test_strings(self):
        self.assertEqual(self.fmt("%s and %1$s and %2$s"), "%@ and %1$@ and %2$@")

    def test_integers_become_long_for_swift(self):
        self.assertEqual(self.fmt("%d %1$d %.1f %2$.2f %05d %x"), "%ld %1$ld %.1f %2$.2f %05ld %x")

    def test_percent_stays(self):
        self.assertEqual(self.fmt("50%% of %1$d"), "50%% of %1$ld")

    def test_newline_conversion(self):
        self.assertEqual(self.fmt("a%nb"), "a\nb")

    def test_plain_percent_text_untouched(self):
        self.assertEqual(self.fmt("100% sure"), "100% sure")

    def test_upper_s_warns(self):
        report = conv.Report()
        self.assertEqual(conv.convert_format("%S", report), "%@")
        self.assertEqual(report.warnings["%S upper-casing dropped"], 1)

    def test_formatted_false_is_verbatim(self):
        self.assertEqual(value_of("<string name='a' formatted='false'>%s 100%</string>"),
                         "%s 100%")

    def test_converted_in_element(self):
        self.assertEqual(value_of("<string name='a'>Could not find \\\"%1$s\\\"</string>"),
                         'Could not find "%1$@"')


class CatalogTests(unittest.TestCase):
    def test_basic_structure(self):
        catalog, _ = convert({
            "values": {"strings.xml": "<string name='hello'>Hello</string>"},
            "values-fr": {"strings.xml": "<string name='hello'>Bonjour</string>"},
        })
        self.assertEqual(catalog["sourceLanguage"], "en")
        self.assertEqual(catalog["version"], "1.0")
        locs = catalog["strings"]["hello"]["localizations"]
        self.assertEqual(locs["en"], {"stringUnit": {"state": "translated", "value": "Hello"}})
        self.assertEqual(locs["fr"]["stringUnit"]["value"], "Bonjour")
        self.assertEqual(catalog["strings"]["hello"]["extractionState"], "manual")

    def test_translatable_false_source_only(self):
        catalog, report = convert({
            "values": {"strings.xml": "<string name='app' translatable='false'>Vela</string>"},
            "values-ja": {"strings.xml": "<string name='app'>Vela JA</string>"},
        })
        record = catalog["strings"]["app"]
        self.assertFalse(record["shouldTranslate"])
        self.assertEqual(list(record["localizations"]), ["en"])
        self.assertEqual(report.skipped["translatable=false outside source"], 1)

    def test_orphan_translation_skipped(self):
        catalog, report = convert({
            "values": {"strings.xml": "<string name='a'>A</string>"},
            "values-de": {"strings.xml": "<string name='b'>B</string>"},
        })
        self.assertNotIn("b", catalog["strings"])
        self.assertEqual(report.skipped["not in source language"], 1)

    def test_non_locale_folder_skipped(self):
        catalog, report = convert({
            "values": {"strings.xml": "<string name='a'>A</string>"},
            "values-night": {"strings.xml": "<string name='a'>Night</string>"},
            "values-v21": {"themes.xml": "<style name='x'/>"},
        })
        self.assertEqual(list(catalog["strings"]["a"]["localizations"]), ["en"])
        self.assertEqual(sum(report.skipped.values()), 1)

    def test_plurals_top_level(self):
        catalog, _ = convert({
            "values": {"plurals.xml": "<plurals name='n'><item quantity='one'>%d stop</item>"
                                      "<item quantity='other'>%d stops</item></plurals>"},
            "values-pl": {"strings.xml": "<plurals name='n'>"
                                         "<item quantity='one'>%d przystanek</item>"
                                         "<item quantity='few'>%d przystanki</item>"
                                         "<item quantity='many'>%d przystanków</item>"
                                         "<item quantity='other'>%d przystanku</item></plurals>"},
        })
        en = catalog["strings"]["n"]["localizations"]["en"]
        self.assertEqual(en["variations"]["plural"]["one"]["stringUnit"]["value"], "%ld stop")
        self.assertEqual(en["variations"]["plural"]["other"]["stringUnit"]["value"], "%ld stops")
        pl = catalog["strings"]["n"]["localizations"]["pl"]["variations"]["plural"]
        self.assertEqual(sorted(pl), ["few", "many", "one", "other"])

    def test_plural_count_not_first_uses_substitution(self):
        catalog, report = convert({
            "values": {"strings.xml": "<plurals name='cells'>"
                                      "<item quantity='one'>About %1$s (%2$d part)</item>"
                                      "<item quantity='other'>About %1$s (%2$d parts)</item>"
                                      "</plurals>"},
        })
        en = catalog["strings"]["cells"]["localizations"]["en"]
        self.assertEqual(en["stringUnit"]["value"], "%#@count@")
        sub = en["substitutions"]["count"]
        self.assertEqual(sub["argNum"], 2)
        self.assertEqual(sub["formatSpecifier"], "ld")
        self.assertEqual(sub["variations"]["plural"]["other"]["stringUnit"]["value"],
                         "About %1$@ (%arg parts)")
        self.assertEqual(report.warnings["plural count is argument 2 (substitution)"], 1)

    def test_plural_count_first_of_several(self):
        catalog, _ = convert({
            "values": {"strings.xml": "<plurals name='p'>"
                                      "<item quantity='one'>%1$d place into %2$s</item>"
                                      "<item quantity='other'>%1$d places into %2$s</item>"
                                      "</plurals>"},
        })
        en = catalog["strings"]["p"]["localizations"]["en"]
        self.assertEqual(en["variations"]["plural"]["other"]["stringUnit"]["value"],
                         "%1$ld places into %2$@")

    def test_zero_dropped_where_not_cldr(self):
        catalog, report = convert({
            "values": {"strings.xml": "<plurals name='p'><item quantity='zero'>None</item>"
                                      "<item quantity='one'>%d</item>"
                                      "<item quantity='other'>%d</item></plurals>"},
            "values-ar": {"strings.xml": "<plurals name='p'><item quantity='zero'>Z %d</item>"
                                         "<item quantity='other'>%d</item></plurals>"},
        })
        locs = catalog["strings"]["p"]["localizations"]
        self.assertNotIn("zero", locs["en"]["variations"]["plural"])
        self.assertIn("zero", locs["ar"]["variations"]["plural"])
        self.assertEqual(report.warnings["quantity zero dropped (not a CLDR category here)"], 1)

    def test_string_array_indexed(self):
        catalog, report = convert({
            "values": {"arrays.xml": "<string name='red'>Red</string>"
                                     "<string-array name='colors'><item>@string/red</item>"
                                     "<item>Blue</item></string-array>"},
            "values-fr": {"strings.xml": "<string name='red'>Rouge</string>"
                                         "<string-array name='colors'><item>@string/red</item>"
                                         "<item>Bleu</item><item>Vert</item></string-array>"},
        })
        s = catalog["strings"]
        self.assertEqual(s["colors[0]"]["localizations"]["en"]["stringUnit"]["value"], "Red")
        self.assertEqual(s["colors[0]"]["localizations"]["fr"]["stringUnit"]["value"], "Rouge")
        self.assertEqual(s["colors[1]"]["localizations"]["fr"]["stringUnit"]["value"], "Bleu")
        self.assertNotIn("colors[2]", s)
        self.assertEqual(report.skipped["array item beyond source length"], 1)

    def test_allow_list(self):
        catalog, report = convert({
            "values": {"strings.xml": "<string name='a'>A</string><string name='b'>B</string>"
                                      "<string-array name='arr'><item>X</item></string-array>"},
        }, allow={"a", "arr", "missing"})
        self.assertEqual(sorted(catalog["strings"]), ["a", "arr[0]"])
        self.assertEqual(report.skipped["allow-listed key not found"], 1)

    def test_allow_list_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            f.write("# keys used on iOS\na\n\n  b  # trailing comment\n")
        try:
            self.assertEqual(conv.read_allow_list(f.name), {"a", "b"})
        finally:
            os.unlink(f.name)

    def test_deterministic_output(self):
        folders = {
            "values": {"strings.xml": "<string name='z'>Z</string><string name='a'>A</string>"},
            "values-fr": {"strings.xml": "<string name='a'>A fr</string>"},
            "values-de": {"strings.xml": "<string name='z'>Z de</string>"},
        }
        first = conv.dump_catalog(convert(folders)[0])
        second = conv.dump_catalog(convert(folders)[0])
        self.assertEqual(first, second)
        self.assertLess(first.index('"a"'), first.index('"z"'))
        self.assertIn('"sourceLanguage" : "en"', first)
        self.assertTrue(first.endswith("}\n"))

    def test_cli_writes_file(self):
        with FixtureRes({"values": {"strings.xml": "<string name='a'>A</string>"}}) as res:
            out = os.path.join(res, "out.xcstrings")
            conv.main(["--res", res, "--out", out])
            with open(out, encoding="utf-8") as f:
                self.assertEqual(json.load(f)["strings"]["a"]["localizations"]["en"]
                                 ["stringUnit"]["value"], "A")


@unittest.skipUnless(os.path.isdir(REAL_RES), "Android res directory not found")
class RealResourcesTest(unittest.TestCase):
    def test_real_resources(self):
        catalog, report = conv.convert(REAL_RES)
        strings = catalog["strings"]
        self.assertGreater(len(strings), 1000)
        per_locale = {}
        for record in strings.values():
            for locale in record["localizations"]:
                per_locale[locale] = per_locale.get(locale, 0) + 1
        for folder in sorted(os.listdir(REAL_RES)):
            locale, _ = conv.qualifier_to_locale(folder)
            if locale is None:
                continue
            path = os.path.join(REAL_RES, folder)
            names = set()
            for name in os.listdir(path):
                if name.endswith(".xml"):
                    root = ET.parse(os.path.join(path, name)).getroot()
                    names.update(e.get("name") for e in root
                                 if e.tag in ("string", "plurals", "string-array")
                                 and e.get("translatable") != "false")
            if not names:
                continue
            # Every locale folder with content yields strings, and at least 90% of its
            # entries survive (the rest are reported skips).
            self.assertGreaterEqual(per_locale.get(locale, 0), max(1, int(len(names) * 0.9)),
                                    "%s (%s)" % (folder, locale))
        self.assertGreater(per_locale["en"], 1000)
        # No Java string specifier may survive outside formatted="false" strings.
        dump = conv.dump_catalog(catalog)
        self.assertNotRegex(dump, r"%\d+\$s")


if __name__ == "__main__":
    unittest.main()
