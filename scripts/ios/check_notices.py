#!/usr/bin/env python3
"""Check that the bundled notices cover every dependency and every data source.

The About page reads `iosApp/Vela/Settings/Notices.json`. This script is the guard that keeps a
new Swift package, vendor framework, shared Kotlin library or network host from shipping without
its license row:

  * Swift packages are read from the `packages:` block of `iosApp/project.yml`;
  * vendor frameworks are read from `Vendor/*.xcframework` references in that file;
  * third-party Gradle libraries are read from the `implementation` / `api` lines of
    `core-common/build.gradle.kts` and `ios-shared/build.gradle.kts`, resolved through
    `gradle/libs.versions.toml`;
  * hosts are collected from the source and style files, and every host must be listed by a notice
    or be one of the project addresses (repository, releases, website, donation).

Run from the repository root:

    python3 scripts/ios/check_notices.py

Exit code 0 means the notices cover the tree. A non-zero exit prints one line per gap.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NOTICES_REL = "iosApp/Vela/Settings/Notices.json"
PROJECT_REL = "iosApp/project.yml"
CATALOG_REL = "gradle/libs.versions.toml"
BUILD_FILES = ["core-common/build.gradle.kts", "ios-shared/build.gradle.kts"]
SCAN_DIRS = ["core-common/src/commonMain/kotlin", "ios-shared/src/commonMain", "iosApp/Vela"]
SCAN_SUFFIXES = {".swift", ".kt", ".json", ".c", ".h"}
SKIP_FILES = {"Notices.json"}

# Swift package name -> notice id. Add a line here and a notice entry when a package arrives.
SWIFT_PACKAGES = {"MapLibre": "maplibre", "SWCompression": "swcompression"}
# Vendor xcframework name -> notice id.
VENDOR_FRAMEWORKS = {"SherpaOnnxC": "sherpa-onnx", "MapLibre": "maplibre"}
# Gradle group -> notice id. The Kotlin standard library is always linked and has its own entry.
GRADLE_GROUPS = {"org.jetbrains.kotlinx": "kotlinx", "androidx.sqlite": "androidx-sqlite"}
ALWAYS_REQUIRED = {"vela", "kotlin"}
REQUIRED = {
    "vela", "maplibre", "swcompression", "sherpa-onnx", "kotlin", "kotlinx",
    "androidx-sqlite", "skie", "osm", "esri", "google", "transitous", "photon",
    "overpass", "piper-voices",
}
# Hosts owned by the project itself or used only as fixtures and XML namespaces. None of them
# serves map or place data, so none needs a license row.
EXEMPT_HOSTS = {
    "api.github.com", "github.com", "raw.githubusercontent.com",
    "pimpinpumpkin.github.io", "velamaps.org", "buymeacoffee.com",
    "www.opengis.net", "www.topografix.com", "example.invalid", "davisfood.coop",
    "www.w3.org",
}
ALLOWED_KINDS = {"app", "library", "data"}


def load_notices(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("entries"), list):
        raise ValueError("the file must contain an entries array")
    return data["entries"]


def swift_packages(text: str) -> list[str]:
    found: list[str] = []
    inside = False
    for line in text.splitlines():
        if line.rstrip() == "packages:":
            inside = True
            continue
        if inside:
            if line and not line.startswith(" "):
                break
            match = re.match(r"^  ([A-Za-z0-9_.-]+):\s*$", line)
            if match:
                found.append(match.group(1))
    return found


def vendor_frameworks(text: str) -> list[str]:
    return re.findall(r"framework:\s+Vendor/([A-Za-z0-9_.-]+)\.xcframework", text)


def catalog(text: str) -> dict[str, tuple[str, str]]:
    found: dict[str, tuple[str, str]] = {}
    for line in text.splitlines():
        match = re.match(
            r"^([A-Za-z0-9_.-]+)\s*=\s*\{\s*group\s*=\s*\"([^\"]+)\"\s*,\s*name\s*=\s*\"([^\"]+)\"",
            line,
        )
        if match:
            found[match.group(1)] = (match.group(2), match.group(3))
    return found


def gradle_libraries(build_texts: dict[str, str], libraries: dict[str, tuple[str, str]]) -> list[str]:
    refs: set[str] = set()
    for text in build_texts.values():
        for alias in re.findall(r"(?:implementation|api)\(\s*libs\.([A-Za-z0-9_.]+)", text):
            if alias.startswith(("plugins.", "versions.")) or "test" in alias:
                continue
            refs.add(alias.replace(".", "-"))
    return sorted(refs)


def hosts_in(root: Path) -> set[str]:
    hosts: set[str] = set()
    for rel in SCAN_DIRS:
        base = root / rel
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in SCAN_SUFFIXES:
                continue
            if path.name in SKIP_FILES:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            hosts.update(re.findall(r"https?://([A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,})", text))
    return {host.lower() for host in hosts}


def check(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    notices_path = root / NOTICES_REL
    project_path = root / PROJECT_REL
    catalog_path = root / CATALOG_REL
    for path in [notices_path, project_path, catalog_path]:
        if not path.exists():
            return [f"missing file: {path.relative_to(root)}"]

    try:
        entries = load_notices(notices_path)
    except (ValueError, json.JSONDecodeError) as exc:
        return [f"{NOTICES_REL}: {exc}"]

    by_id: dict[str, dict] = {}
    host_to_id: dict[str, str] = {}
    for entry in entries:
        missing = [key for key in ("id", "title", "kind", "license", "url", "note") if not entry.get(key)]
        if missing:
            errors.append(f"notice {entry.get('id', '?')}: missing {', '.join(missing)}")
            continue
        notice_id = entry["id"]
        if notice_id in by_id:
            errors.append(f"notice {notice_id}: duplicate id")
        by_id[notice_id] = entry
        if entry["kind"] not in ALLOWED_KINDS:
            errors.append(f"notice {notice_id}: kind must be one of {sorted(ALLOWED_KINDS)}")
        if not entry["url"].startswith("https://"):
            errors.append(f"notice {notice_id}: the url must use https")
        for host in entry.get("hosts", []):
            if host in host_to_id and host_to_id[host] != notice_id:
                errors.append(f"host {host}: listed by {host_to_id[host]} and {notice_id}")
            host_to_id[host] = notice_id

    for required in sorted(REQUIRED):
        if required not in by_id:
            errors.append(f"notice {required}: required entry is missing")

    project = project_path.read_text(encoding="utf-8")
    for package in swift_packages(project):
        notice_id = SWIFT_PACKAGES.get(package)
        if not notice_id:
            errors.append(
                f"Swift package {package}: no notice mapping. Add an entry and a line in "
                "scripts/ios/check_notices.py SWIFT_PACKAGES.")
        elif notice_id not in by_id:
            errors.append(f"Swift package {package}: notice {notice_id} is missing")
    for framework in vendor_frameworks(project):
        notice_id = VENDOR_FRAMEWORKS.get(framework)
        if not notice_id:
            errors.append(
                f"vendor framework {framework}: no notice mapping. Add an entry and a line in "
                "scripts/ios/check_notices.py VENDOR_FRAMEWORKS.")
        elif notice_id not in by_id:
            errors.append(f"vendor framework {framework}: notice {notice_id} is missing")

    libraries = catalog(catalog_path.read_text(encoding="utf-8"))
    build_texts = {
        rel: (root / rel).read_text(encoding="utf-8")
        for rel in BUILD_FILES if (root / rel).exists()
    }
    if len(build_texts) != len(BUILD_FILES):
        errors.append("one of the shared Gradle build files is missing")
    for alias in gradle_libraries(build_texts, libraries):
        if alias not in libraries:
            errors.append(f"Gradle library {alias}: not found in {CATALOG_REL}")
            continue
        group, _ = libraries[alias]
        notice_id = GRADLE_GROUPS.get(group)
        if not notice_id:
            errors.append(
                f"Gradle library {group}:{alias}: no notice mapping. Add an entry and a line in "
                "scripts/ios/check_notices.py GRADLE_GROUPS.")
        elif notice_id not in by_id:
            errors.append(f"Gradle library {group}:{alias}: notice {notice_id} is missing")
    if any("libs.plugins.skie" in text for text in build_texts.values()) and "skie" not in by_id:
        errors.append("SKIE plugin: notice skie is missing")

    for required in ALWAYS_REQUIRED:
        if required not in by_id:
            errors.append(f"notice {required}: required entry is missing")

    hosts = hosts_in(root)
    for host in sorted(hosts):
        if host in EXEMPT_HOSTS:
            continue
        if host not in host_to_id:
            errors.append(
                f"host {host}: no notice covers it. Add the host to a data notice's hosts array "
                "or to EXEMPT_HOSTS in scripts/ios/check_notices.py.")

    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check the bundled notices against the tree.")
    parser.add_argument("--root", default=str(ROOT), help="repository root")
    args = parser.parse_args(argv)
    root = Path(args.root)
    errors = check(root)
    if errors:
        for error in errors:
            print(f"NOTICES {error}", file=sys.stderr)
        print(f"notices: {len(errors)} gap(s)", file=sys.stderr)
        return 1
    entries = load_notices(root / NOTICES_REL)
    libraries = sum(1 for entry in entries if entry["kind"] == "library")
    data = sum(1 for entry in entries if entry["kind"] == "data")
    print(f"notices: ok, {len(entries)} entries ({libraries} libraries, {data} data sources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
