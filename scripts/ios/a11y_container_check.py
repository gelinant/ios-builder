#!/usr/bin/env python3
"""Catch the SwiftUI container that swallows its controls.

An identifier or a label/value set on a stack is normally harmless. Combined on the same view,
they can make the stack a single accessibility element: VoiceOver then reads one node and no
button, field or row is reachable (`unified-settings-sheet` was the case). This script reports a
container whose modifier chain sets `.accessibilityValue` or `.accessibilityLabel` on the container
itself and whose body holds an interactive control, unless the chain already declares
`.accessibilityElement(children: .contain)`.

Deliberately narrow, so it has no false positives: status rows made only of Text (a value with no
control), Form, List, ScrollView and NavigationStack without a value, and leaf identifiers
(Text, Button, Image, Link, Label) are never reported. Run it from the repository root:

    python3 scripts/ios/a11y_container_check.py iosApp

Exit code 1 means at least one container needs `.accessibilityElement(children: .contain)` before
its identifier.
"""
import re
import sys
from pathlib import Path

CONTAINERS = {
    "VStack", "HStack", "ZStack", "NavigationStack", "NavigationView", "TabView", "Section",
    "Group", "LazyVStack", "LazyHStack", "LazyVGrid", "LazyHGrid", "OutlineGroup",
    "DisclosureGroup", "GeometryReader", "ScrollViewReader", "ViewThatFits", "TimelineView",
}
CONTROL_RE = re.compile(r"\b(Button|Menu|Link|NavigationLink|Toggle|TextField|Picker|Stepper|Slider)\b")
OPEN_RE = re.compile(r"^\s*(" + "|".join(sorted(CONTAINERS)) + r")\b")
ID_RE = re.compile(r'\.accessibilityIdentifier\("([^"]+)"\)')
MOD_RE = re.compile(r"^\s*\.")


def stripped(lines):
    """Drop comments so a commented identifier cannot be reported."""
    out = []
    in_comment = False
    for raw in lines:
        line = raw
        if in_comment:
            if "*/" in line:
                line = line.split("*/", 1)[1]
                in_comment = False
            else:
                out.append("")
                continue
        while "/*" in line:
            before, rest = line.split("/*", 1)
            if "*/" in rest:
                line = before + rest.split("*/", 1)[1]
            else:
                line = before
                in_comment = True
                break
        if "//" in line:
            line = line.split("//", 1)[0]
        out.append(line)
    return out


def depths(lines):
    out = []
    depth = 0
    for line in lines:
        out.append(depth)
        depth += line.count("{") - line.count("}")
    return out


def scan(path):
    lines = stripped(path.read_text(encoding="utf-8").splitlines())
    db = depths(lines)
    for i, line in enumerate(lines):
        match = ID_RE.search(line)
        if not match:
            continue
        depth = db[i]
        # Walk back over the modifier chain and any closure bodies it contains to the view the
        # chain starts from. Container bodies sit one level deeper, so they are skipped.
        j = i - 1
        while j >= 0:
            text = lines[j].strip()
            if not text or db[j] > depth:
                j -= 1
                continue
            if db[j] == depth and MOD_RE.match(text):
                j -= 1
                continue
            break
        if j < 0:
            continue
        opener = OPEN_RE.match(lines[j].strip())
        if not opener:
            continue
        # End of the chain: the next non-modifier line at the same depth.
        k = i + 1
        while k < len(lines):
            text = lines[k].strip()
            if not text or db[k] > depth:
                k += 1
                continue
            if db[k] == depth and MOD_RE.match(text):
                k += 1
                continue
            break
        chain = " ".join(lines[t].strip() for t in range(j + 1, k) if db[t] == depth)
        if "accessibilityElement(children: .contain)" in chain:
            continue
        if "accessibilityValue" not in chain and "accessibilityLabel" not in chain:
            continue
        # Body of the container: skip when it has no control to lose.
        end = None
        for l in range(j + 1, len(lines)):
            if lines[l].strip() == "}" and db[l] == depth + 1:
                end = l
                break
        if end is None:
            continue
        if not CONTROL_RE.search(" ".join(lines[j + 1:end])):
            continue
        yield i + 1, match.group(1), opener.group(1)


def main(argv):
    root = Path(argv[1]) if len(argv) > 1 else Path("iosApp")
    files = [root] if root.is_file() else sorted(root.rglob("*.swift"))
    total = 0
    for path in files:
        for line, ident, kind in scan(path):
            print(f"{path}:{line}: {kind} '{ident}' becomes one element; "
                  f"add .accessibilityElement(children: .contain) before the identifier")
            total += 1
    print(f"{total} container identifier(s) hide their controls")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
