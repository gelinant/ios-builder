#!/usr/bin/env python3
"""Unit tests for core_deps.py: python3 scripts/ios/test_core_deps.py"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import core_deps as cd  # noqa: E402


def kfiles(tmp, sources):
    out = []
    for rel, text in sources.items():
        path = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        out.append(cd.KFile(tmp, rel, "main"))
    idx = cd.Index(out)
    for f in out:
        cd.resolve(f, [idx])
    return {f.rel: f for f in out}


class LexTest(unittest.TestCase):
    def test_comments_and_strings_are_blanked(self):
        src = 'val a = "Math.toRadians(1)" // Thread.sleep\n/* java.io.File /* nested */ */ val b = 1\n'
        code, strings = cd.lex(src)
        self.assertEqual(len(code), len(src))
        self.assertNotIn("Math", code)
        self.assertNotIn("Thread", code)
        self.assertNotIn("File", code)
        self.assertIn("val b = 1", code)
        self.assertEqual(strings[0][1], "Math.toRadians(1)")

    def test_templates_stay_code(self):
        code, _ = cd.lex('val s = "x ${Math.abs(y)} and $name"\n')
        self.assertIn("Math.abs(y)", code)
        self.assertIn("name", code)

    def test_raw_string_and_char_literals(self):
        code, strings = cd.lex('val r = """a "quoted" \\d ${q}"""\nval c = \'"\'\nval d = \'\\n\'\nval e = Foo\n')
        self.assertIn("q", code)
        self.assertIn("val e = Foo", code)
        self.assertIn('a "quoted" \\d ', strings[0][1])


class DeclTest(unittest.TestCase):
    def test_top_level_declarations(self):
        src = ("package p\n@Serializable(with = X::class) data class A(val x: Int) { fun inner() = 1 }\n"
               "fun <T : Comparable<T>> List<T>.best(): T? = null\nprivate fun hidden() = 0\n"
               "internal val JsonElement?.str: String? get() = null\nconst val K = 1\nenum class E { A, B }\n"
               "fun interface Cb { fun on() }\n")
        code, _ = cd.lex(src)
        decls = {d["name"]: d for d in cd.top_level_decls(code)}
        self.assertEqual(set(decls), {"A", "best", "hidden", "str", "K", "E", "Cb"})
        self.assertTrue(decls["best"]["ext"])
        self.assertTrue(decls["str"]["ext"])
        self.assertTrue(decls["hidden"]["private"])
        self.assertFalse(decls["A"]["private"])


class ResolveTest(unittest.TestCase):
    def test_imports_package_and_fully_qualified(self):
        with tempfile.TemporaryDirectory() as tmp:
            fs = kfiles(tmp, {
                "model/Geo.kt": "package app.vela.core.model\ndata class LatLng(val lat: Double)\n"
                                "fun LatLng.distanceTo(o: LatLng) = 0.0\n",
                "data/NoGoogle.kt": "package app.vela.core.data\nobject NoGoogle { var enabled = false }\n",
                "data/Helper.kt": "package app.vela.core.data\nfun helper() = 1\nprivate fun secret() = 2\n",
                "data/Use.kt": "package app.vela.core.data\nimport app.vela.core.model.LatLng\n"
                               "class Use { fun f(a: LatLng) = helper() + if (app.vela.core.data.NoGoogle.enabled) 1 else 0 }\n",
                "data/Other.kt": "package app.vela.core.data\nclass Other { fun helper() = 3; fun g() = helper() + secret() }\n",
                "nav/Star.kt": "package app.vela.core.nav\nimport app.vela.core.model.*\n"
                               "fun d(a: LatLng, b: LatLng) = a.distanceTo(b)\n",
            })
            use = fs["data/Use.kt"]
            self.assertEqual(sorted(k.split(":", 1)[1] for k in use.deps),
                             ["data/Helper.kt", "data/NoGoogle.kt", "model/Geo.kt"])
            self.assertEqual(use.deps["main:data/NoGoogle.kt"], {"fq"})
            # A member function shadows the same-package top-level one; private ones are not visible.
            self.assertEqual(fs["data/Other.kt"].deps, {})
            self.assertEqual(list(fs["nav/Star.kt"].deps), ["main:model/Geo.kt"])


class BlockerTest(unittest.TestCase):
    def blockers(self, src):
        code, _ = cd.lex(src)
        return set(cd.find_blockers(code, src.split("\n"), ""))

    def test_classification_examples(self):
        self.assertEqual(self.blockers("val x = Math.toRadians(1.0)\n"), {"math"})
        self.assertEqual(self.blockers('val s = "a".lowercase(java.util.Locale.ROOT)\n'), {"locale-case"})
        self.assertEqual(self.blockers("val l = java.util.Locale.getDefault().language\n"), {"locale-seam"})
        self.assertEqual(self.blockers("@Volatile var v = 0\nfun f() = synchronized(this) { }\n"),
                         {"volatile", "synchronized"})
        self.assertEqual(self.blockers('val s = String.format(java.util.Locale.US, "%d", 1)\n'),
                         {"format", "locale-case"})
        self.assertEqual(self.blockers("val n = Long.MAX_VALUE\nval m = Int.MIN_VALUE\n"), set())
        self.assertEqual(self.blockers("val n = java.lang.Long.parseUnsignedLong(h, 16)\n"), {"jvm-statics"})
        self.assertEqual(self.blockers("import okhttp3.OkHttpClient\n"), {"okhttp"})
        self.assertEqual(self.blockers("val r = Regex(p, RegexOption.DOT_MATCHES_ALL)\n"), {"jvm-regex"})
        self.assertEqual(self.blockers("val r = Regex(p, RegexOption.IGNORE_CASE)\n"), set())

    def test_message_first_asserts(self):
        code, _ = cd.lex('assertEquals("msg", 1, x)\nassertEquals("a", x)\nassertTrue("why", ok)\n'
                         'assertTrue(ok)\nassertEquals(1.0, d, 1e-6)\n')
        self.assertEqual(cd.message_first_asserts(code), 2)


class RepoTest(unittest.TestCase):
    def test_runs_on_the_repo(self):
        a = cd.analyze()
        self.assertGreater(len(a["main"]), 100)
        self.assertIn("main:model/Geo.kt", a["movable_a"])
        sections = cd.gen_sections(a)
        for name in ("summary", "blockers", "lots", "waves", "cycles", "v1", "cuts", "top", "tests", "c8"):
            self.assertIn(name, sections)


if __name__ == "__main__":
    unittest.main()
