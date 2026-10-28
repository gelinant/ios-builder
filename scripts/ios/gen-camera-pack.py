#!/usr/bin/env python3
"""Build the bundled iOS camera pack from the ALPR dataset already in the repository.

The repository ships one camera dataset: `app/src/main/assets/flock_cameras.bin`, the
community DeFlock ALPR nodes from OpenStreetMap, gzipped TSV `lat<TAB>lon<TAB>operator<TAB>
direction`. Android reads that file on device; iOS has no equivalent reader, so this script
writes the same points as a compact JSON resource.

    python3 scripts/ios/gen-camera-pack.py

Output: `iosApp/Vela/Resources/camera-pack.json`. Deterministic: points are rounded to five
decimals, sorted, and duplicates are dropped. Nothing is downloaded. Speed cameras are not in
this pack: the repository ships none, so the iOS app writes a region pack from Overpass when a
region is downloaded (see OfflineStore.kt).
"""

import gzip
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "app", "src", "main", "assets", "flock_cameras.bin")
VERSION = os.path.join(ROOT, "app", "src", "main", "assets", "flock_cameras_version.txt")
OUTPUT = os.path.join(ROOT, "iosApp", "Vela", "Resources", "camera-pack.json")

# Rough tallies for the documentation; the points themselves are worldwide.
AREAS = {
    "united_states": (24.0, -125.0, 50.0, -66.0),
    "united_kingdom": (49.8, -8.7, 61.0, 2.0),
    "germany": (47.2, 5.8, 55.1, 15.1),
    "france": (41.3, -5.2, 51.2, 9.6),
    "canada": (41.6, -141.1, 73.0, -52.6),
}


def date_from_version(text):
    text = text.strip()
    if len(text) >= 8 and text[:8].isdigit():
        return "%s-%s-%s" % (text[:4], text[4:6], text[6:8])
    return "unknown"


def main():
    with open(VERSION, encoding="utf-8") as f:
        version = f.read().strip()
    date = date_from_version(version)
    epoch_ms = 0
    if date != "unknown":
        import datetime
        epoch_ms = int(datetime.datetime.strptime(date, "%Y-%m-%d")
                       .replace(tzinfo=datetime.timezone.utc).timestamp() * 1000)

    seen = set()
    cameras = []
    areas = {name: 0 for name in AREAS}
    with gzip.open(SOURCE, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            try:
                lat = round(float(parts[0]), 5)
                lng = round(float(parts[1]), 5)
            except ValueError:
                continue
            if not (-90.0 <= lat <= 90.0 and -180.0 <= lng <= 180.0):
                continue
            key = (lat, lng)
            if key in seen:
                continue
            seen.add(key)
            cameras.append((lat, lng))
            for name, (s, w, n, e) in AREAS.items():
                if s <= lat <= n and w <= lng <= e:
                    areas[name] += 1

    cameras.sort()
    payload = {
        "id": "camera-pack",
        "name": "camera-pack-" + date,
        "kind": "alpr",
        "source": "DeFlock ALPR nodes in OpenStreetMap, app/src/main/assets/flock_cameras.bin",
        "licence": "OpenStreetMap contributors, ODbL 1.0",
        "version": version,
        "date": date,
        "generatedAtMs": epoch_ms,
        "coverage": "worldwide OSM DeFlock nodes, no speed cameras",
        "areas": areas,
        "s": -90.0,
        "w": -180.0,
        "n": 90.0,
        "e": 180.0,
        "cameras": [[lat, lng] for lat, lng in cameras],
    }
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, separators=(",", ":"), sort_keys=False)
        f.write("\n")
    print("%s: %d cameras, %d bytes, %s" % (
        os.path.relpath(OUTPUT, ROOT), len(cameras), os.path.getsize(OUTPUT), date))
    print("areas:", json.dumps(areas, sort_keys=True))


if __name__ == "__main__":
    main()
