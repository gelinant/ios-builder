#!/usr/bin/env python3
"""Unit tests for check_notices.py: python3 scripts/ios/test_notices.py"""

from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

import check_notices as cn

ROOT = Path(__file__).resolve().parents[2]


class RealTreeTest(unittest.TestCase):
    def test_the_repository_passes(self):
        self.assertEqual(cn.check(ROOT), [])


class ParserTest(unittest.TestCase):
    def test_swift_packages_and_vendor_frameworks(self):
        text = (ROOT / cn.PROJECT_REL).read_text(encoding="utf-8")
        self.assertIn("MapLibre", cn.swift_packages(text))
        self.assertIn("SWCompression", cn.swift_packages(text))
        self.assertIn("SherpaOnnxC", cn.vendor_frameworks(text))

    def test_gradle_libraries_come_from_the_catalog(self):
        libraries = cn.catalog((ROOT / cn.CATALOG_REL).read_text(encoding="utf-8"))
        texts = {
            rel: (ROOT / rel).read_text(encoding="utf-8")
            for rel in cn.BUILD_FILES
        }
        aliases = cn.gradle_libraries(texts, libraries)
        self.assertIn("kotlinx-coroutines-core", aliases)
        self.assertIn("androidx-sqlite-bundled", aliases)
        self.assertNotIn("kotlinx-coroutines-test", aliases)


class CoverageTest(unittest.TestCase):
    def test_a_new_swift_package_is_reported(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / cn.NOTICES_REL).parent.mkdir(parents=True)
            (root / cn.PROJECT_REL).parent.mkdir(parents=True, exist_ok=True)
            (root / cn.CATALOG_REL).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / cn.NOTICES_REL, root / cn.NOTICES_REL)
            shutil.copy(ROOT / cn.CATALOG_REL, root / cn.CATALOG_REL)
            for rel in cn.BUILD_FILES:
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / rel, root / rel)
            project = (ROOT / cn.PROJECT_REL).read_text(encoding="utf-8")
            project = project.replace(
                "packages:\n",
                "packages:\n  NewMapKit:\n    url: https://example.invalid/NewMapKit\n",
            )
            (root / cn.PROJECT_REL).write_text(project, encoding="utf-8")
            errors = cn.check(root)
            self.assertTrue(any("NewMapKit" in error for error in errors), errors)

    def test_an_unknown_host_is_reported(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / cn.NOTICES_REL).parent.mkdir(parents=True)
            (root / cn.PROJECT_REL).parent.mkdir(parents=True, exist_ok=True)
            (root / cn.CATALOG_REL).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / cn.NOTICES_REL, root / cn.NOTICES_REL)
            shutil.copy(ROOT / cn.PROJECT_REL, root / cn.PROJECT_REL)
            shutil.copy(ROOT / cn.CATALOG_REL, root / cn.CATALOG_REL)
            for rel in cn.BUILD_FILES:
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / rel, root / rel)
            source = root / "iosApp/Vela/Probe.swift"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text('let url = "https://new-data.example.org/api"\n', encoding="utf-8")
            errors = cn.check(root)
            self.assertTrue(any("new-data.example.org" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
