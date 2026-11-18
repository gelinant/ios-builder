#!/usr/bin/env python3
"""Validate the iOS feature matrix and regenerate its numeric summary.

The matrix has one row for every feature bullet in FEATURES.md. Source ranges, row order,
status markers, evidence and follow-up lots are checked. Only the generated summary block is
rewritten; all analysis and matrix rows remain hand-written.

Usage:
  python3 scripts/ios/parity_check.py --check
  python3 scripts/ios/parity_check.py --md
  python3 scripts/ios/parity_check.py --md docs/ios/FEATURES-IOS.md
"""

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[2]
DEFAULT_FEATURES = REPO / "FEATURES.md"
DEFAULT_MATRIX = REPO / "docs/ios/FEATURES-IOS.md"
BEGIN = "<!-- BEGIN GENERATED: parity-summary -->"
END = "<!-- END GENERATED: parity-summary -->"
STATUSES = ("✅", "🟡", "⚠️", "❌", "➖")
STATUS_LABELS = {
    "✅": "validé sur iPhone",
    "🟡": "testé sur simulateur",
    "⚠️": "partiel",
    "❌": "absent",
    "➖": "sans équivalent iOS",
}
ROW_REF = re.compile(r"\bL(\d+)(?:-L(\d+))?\b")


@dataclass(frozen=True)
class Feature:
    section: str
    start: int
    end: int
    text: str


@dataclass(frozen=True)
class MatrixRow:
    start: int
    end: int
    feature: str
    status: str
    evidence: str
    next_lot: str
    line: int


def feature_blocks(text):
    """Return every top-level feature bullet, including its wrapped lines."""
    lines = text.splitlines()
    features = []
    section = ""
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("## "):
            section = line[3:].strip()
        if not line.startswith("- "):
            index += 1
            continue
        start = index + 1
        parts = [line[2:].strip()]
        index += 1
        while index < len(lines) and lines[index].startswith("  ") and lines[index].strip():
            parts.append(lines[index].strip())
            index += 1
        features.append(Feature(section, start, index, " ".join(parts)))
    return features


def matrix_rows(text):
    """Read matrix rows and reject malformed tables or undocumented status markers."""
    rows = []
    errors = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.startswith("|") or not ROW_REF.search(line.split("|", 2)[1] if "|" in line else ""):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 5:
            errors.append(f"line {number}: expected 5 table columns, got {len(cells)}")
            continue
        match = ROW_REF.search(cells[0])
        if not match:
            errors.append(f"line {number}: missing FEATURES.md source range")
            continue
        start = int(match.group(1))
        end = int(match.group(2) or start)
        status = cells[2]
        if status not in STATUSES:
            errors.append(f"line {number}: undocumented status marker {status!r}")
        if not cells[1] or not cells[3] or not cells[4]:
            errors.append(f"line {number}: feature, evidence and next lot are required")
        rows.append(MatrixRow(start, end, cells[1], status, cells[3], cells[4], number))
    return rows, errors


def validate(features_text, matrix_text):
    features = feature_blocks(features_text)
    rows, errors = matrix_rows(matrix_text)
    if not features:
        errors.append("FEATURES.md contains no feature bullets")
    if len(rows) != len(features):
        errors.append(f"matrix has {len(rows)} rows but FEATURES.md has {len(features)} feature bullets")
    for index in range(max(len(rows), len(features))):
        if index >= len(rows) or index >= len(features):
            break
        row, feature = rows[index], features[index]
        if (row.start, row.end) != (feature.start, feature.end):
            errors.append(
                f"matrix line {row.line}: L{row.start}-L{row.end} does not match "
                f"FEATURES.md L{feature.start}-L{feature.end} ({feature.text[:60]})"
            )
    return features, rows, errors


def generated_summary(rows):
    counts = {status: 0 for status in STATUSES}
    for row in rows:
        if row.status in counts:
            counts[row.status] += 1
    total = len(rows)
    lines = [
        BEGIN,
        "## Synthèse chiffrée",
        "",
        "Cette table est régénérée par `python3 scripts/ios/parity_check.py --md`. Les pourcentages",
        "comptent des lignes de fonctions, pas leur complexité ni leur importance quotidienne.",
        "",
        "| Statut | Lignes | Part du total |",
        "|---|---:|---:|",
    ]
    for status in STATUSES:
        share = (100.0 * counts[status] / total) if total else 0.0
        lines.append(f"| {status} {STATUS_LABELS[status]} | {counts[status]} | {share:.1f} % |".replace(".", ","))
    lines.append(f"| **Total** | **{total}** | **100,0 %** |")
    lines.append(END)
    return "\n".join(lines)


def replace_summary(matrix_text, rows):
    summary = generated_summary(rows)
    pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.DOTALL)
    matches = list(pattern.finditer(matrix_text))
    if len(matches) != 1:
        raise ValueError(f"expected exactly one generated summary block, found {len(matches)}")
    return matrix_text[:matches[0].start()] + summary + matrix_text[matches[0].end():]


def check_files(features_path, matrix_path):
    features_text = features_path.read_text(encoding="utf-8")
    matrix_text = matrix_path.read_text(encoding="utf-8")
    _, rows, errors = validate(features_text, matrix_text)
    if not errors:
        expected = replace_summary(matrix_text, rows)
        if expected != matrix_text:
            errors.append("generated summary is stale; run python3 scripts/ios/parity_check.py --md")
    return rows, errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--md", nargs="?", const=str(DEFAULT_MATRIX), metavar="PATH",
                        help="regenerate the summary in PATH, or docs/ios/FEATURES-IOS.md")
    action.add_argument("--check", action="store_true", help="validate without modifying files")
    parser.add_argument("--features", type=Path, default=DEFAULT_FEATURES, help=argparse.SUPPRESS)
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    matrix_path = Path(args.md) if args.md is not None else args.matrix
    try:
        features_text = args.features.read_text(encoding="utf-8")
        matrix_text = matrix_path.read_text(encoding="utf-8")
        _, rows, errors = validate(features_text, matrix_text)
        if errors:
            for error in errors:
                print(f"ERROR: {error}", file=sys.stderr)
            return 1
        updated = replace_summary(matrix_text, rows)
        if args.check:
            if updated != matrix_text:
                print("ERROR: generated summary is stale; run python3 scripts/ios/parity_check.py --md",
                      file=sys.stderr)
                return 1
            print(f"OK: {len(rows)} feature rows; summary is current")
            return 0
        if updated != matrix_text:
            matrix_path.write_text(updated, encoding="utf-8")
            print(f"Updated {matrix_path}: {len(rows)} feature rows")
        else:
            print(f"Unchanged {matrix_path}: {len(rows)} feature rows")
        return 0
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
