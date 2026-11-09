#!/usr/bin/env python3
"""Build the bundled iOS camera pack from the ALPR dataset already in the repository.

The repository ships one camera dataset: `app/src/main/assets/flock_cameras.bin`, the
community DeFlock ALPR nodes from OpenStreetMap, gzipped TSV `lat<TAB>lon<TAB>operator<TAB>
direction`. Android reads that file on device; iOS has no equivalent reader, so this script
writes the same points as a compact JSON resource.

    python3 scripts/ios/gen-camera-pack.py

Output: `iosApp/Vela/Resources/camera-pack.json`. Deterministic: points are rounded to five
decimals, sorted, and duplicates are dropped. One camera per coordinate is kept, with the first
non-empty direction tag among its duplicates. A camera element is `[lat, lng]` when the facing
is unknown and `[lat, lng, degrees]` when it is known, so the map draws a direction wedge only
for a real tag. Nothing is downloaded. Speed cameras are not in this pack: the repository ships
none, so the iOS app writes a region pack from Overpass when a region is downloaded (see
OfflineStore.kt).
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


def normalize_direction(raw):
    """OSM `direction` as a whole number of degrees clockwise from north.

    The Android build script already normalizes the asset to integer degrees. The fallback
    still accepts a decimal or a negative value so a hand-edited source cannot put an
    unreadable angle in the pack. An empty or unreadable tag means "facing unknown" and
    returns None: the map must not guess a bearing.
    """
    text = (raw or "").strip()
    if not text:
        return None
    try:
        degrees = round(float(text)) % 360
    except ValueError:
        return None
    return int(degrees)


def main():
    with open(VERSION, encoding="utf-8") as f:
        version = f.read().strip()
    date = date_from_version(version)
    epoch_ms = 0
    if date != "unknown":
        import datetime
        epoch_ms = int(datetime.datetime.strptime(date, "%Y-%m-%d")
                       .replace(tzinfo=datetime.timezone.utc).timestamp() * 1000)

    # One camera per rounded coordinate. A duplicate may carry the only direction tag, so
    # remember the first non-empty bearing instead of dropping it with the later row.
    seen = {}
    for_order = []
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
            direction = normalize_direction(parts[3] if len(parts) > 3 else "")
            if key not in seen:
                seen[key] = direction
                for_order.append((lat, lng))
            elif seen[key] is None and direction is not None:
                seen[key] = direction

    for_order.sort()
    cameras = []
    for lat, lng in for_order:
        direction = seen[(lat, lng)]
        cameras.append([lat, lng, direction] if direction is not None else [lat, lng])
        for name, (s, w, n, e) in AREAS.items():
            if s <= lat <= n and w <= lng <= e:
                areas[name] += 1
    oriented = sum(1 for camera in cameras if len(camera) == 3)

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
        # Five decimals is 1.1 m of latitude per step; the direction tag is whole degrees.
        # The map uses both numbers to keep its wedge an indicator, not a measured field of view.
        "precisionM": 1.1,
        "bearingPrecisionDeg": 1,
        "oriented": oriented,
        "unoriented": len(cameras) - oriented,
        "areas": areas,
        "s": -90.0,
        "w": -180.0,
        "n": 90.0,
        "e": 180.0,
        "cameras": cameras,
    }
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, separators=(",", ":"), sort_keys=False)
        f.write("\n")
    print("%s: %d cameras, %d oriented, %d bytes, %s" % (
        os.path.relpath(OUTPUT, ROOT), len(cameras), oriented,
        os.path.getsize(OUTPUT), date))
    print("areas:", json.dumps(areas, sort_keys=True))


if __name__ == "__main__":
    main()
