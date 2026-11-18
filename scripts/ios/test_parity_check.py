#!/usr/bin/env python3
"""Unit tests for parity_check.py: python3 scripts/ios/test_parity_check.py"""

import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parity_check as pc  # noqa: E402


FEATURES = """# Features

## Map

- Vector map with buildings and
  house numbers.
- Tap a place.

## Search

- Search by name.
"""


def matrix(statuses=("✅", "🟡", "⚠️"), refs=((2, 3), (4, 4), (7, 7))):
    rows = [
        "# Matrix",
        "",
        pc.BEGIN,
        "stale",
        pc.END,
        "",
        "| Source | Feature | Status | Evidence | Next lot |",
        "|---|---|---|---|---|",
    ]
    for ref, status in zip(refs, statuses):
        source = f"L{ref[0]}" if ref[0] == ref[1] else f"L{ref[0]}-L{ref[1]}"
        rows.append(f"| [{source}](FEATURES.md) | Feature {ref[0]} | {status} | Test evidence | Next lot |")
    return "\n".join(rows) + "\n"


class FeatureTest(unittest.TestCase):
    def test_reads_wrapped_bullets(self):
        features = pc.feature_blocks(FEATURES)
        self.assertEqual([(f.start, f.end) for f in features], [(5, 6), (7, 7), (11, 11)])
        self.assertEqual(features[0].text, "Vector map with buildings and house numbers.")
        self.assertEqual(features[2].section, "Search")

    def test_matrix_requires_every_source_range_in_order(self):
        # Correct ranges for the compact fixture above.
        refs = ((5, 6), (7, 7), (11, 11))
        _, rows, errors = pc.validate(FEATURES, matrix(refs=refs))
        self.assertEqual(errors, [])
        self.assertEqual(len(rows), 3)
        _, _, errors = pc.validate(FEATURES, matrix(refs=((5, 5), (7, 7), (11, 11))))
        self.assertTrue(any("does not match" in error for error in errors))
        _, _, errors = pc.validate(FEATURES, matrix(refs=((5, 6), (7, 7))))
        self.assertTrue(any("2 rows" in error for error in errors))


class SummaryTest(unittest.TestCase):
    def test_counts_and_output_are_deterministic(self):
        text = matrix(statuses=("✅", "✅", "❌", "➖", "⚠️"),
                      refs=((5, 6), (7, 7), (11, 11), (11, 11), (11, 11)))
        rows, errors = pc.matrix_rows(text)
        self.assertEqual(errors, [])
        summary = pc.generated_summary(rows)
        self.assertEqual(summary, pc.generated_summary(rows))
        self.assertIn("| ✅ validé sur iPhone | 2 | 40,0 % |", summary)
        self.assertIn("| ❌ absent | 1 | 20,0 % |", summary)
        self.assertIn("| **Total** | **5** | **100,0 %** |", summary)

    def test_unknown_status_is_an_error(self):
        _, _, errors = pc.validate(FEATURES, matrix(statuses=("✅", "🔵", "⚠️"),
                                                         refs=((5, 6), (7, 7), (11, 11))))
        self.assertTrue(any("undocumented status" in error for error in errors))

    def test_md_replaces_only_generated_block(self):
        original = matrix(refs=((5, 6), (7, 7), (11, 11)))
        rows, errors = pc.matrix_rows(original)
        self.assertEqual(errors, [])
        updated = pc.replace_summary(original, rows)
        self.assertTrue(updated.startswith("# Matrix\n\n" + pc.BEGIN))
        self.assertIn("## Synthèse chiffrée", updated)
        self.assertIn("| [L5-L6](FEATURES.md)", updated)
        self.assertNotIn("stale", updated)
        self.assertTrue(updated.endswith("\n"))
        self.assertEqual(pc.replace_summary(updated, rows), updated)

    def test_cli_check_detects_stale_summary_and_md_repairs_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            features = Path(tmp) / "FEATURES.md"
            target = Path(tmp) / "FEATURES-IOS.md"
            features.write_text(FEATURES, encoding="utf-8")
            target.write_text(matrix(refs=((5, 6), (7, 7), (11, 11))), encoding="utf-8")
            args = ["--features", str(features), "--matrix", str(target)]
            self.assertEqual(pc.main(["--check"] + args), 1)
            self.assertEqual(pc.main(["--md", str(target), "--features", str(features)]), 0)
            self.assertEqual(pc.main(["--check"] + args), 0)
            self.assertEqual(target.read_text(encoding="utf-8").count(pc.BEGIN), 1)


class RepositoryTest(unittest.TestCase):
    def test_repository_matrix_is_complete_and_current(self):
        rows, errors = pc.check_files(pc.DEFAULT_FEATURES, pc.DEFAULT_MATRIX)
        self.assertEqual(errors, [])
        self.assertEqual(len(rows), len(pc.feature_blocks(pc.DEFAULT_FEATURES.read_text(encoding="utf-8"))))


if __name__ == "__main__":
    unittest.main()
