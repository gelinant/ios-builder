#!/usr/bin/env python3
"""Build the bundled Vela POI pack from a vector-tile fixture already in the repository.

The only POI data the repository ships is the OpenMapTiles fixture
`core/src/test/resources/tiles/davis-14-2651-6288.pbf` (z14 x2651 y6288). It is the tile the
core tests decode, and it carries 956 OSM POIs of which 337 are named. This script extracts the
named point features into `iosApp/Vela/Resources/poi-davis.json`, with the Android sheet group
(food, fuel, transit, parking, other) so the app can filter and size them like its tile layers.

Run from the repository root:

    python3 scripts/ios/gen-poi-pack.py

The output is deterministic: places are sorted by name, then coordinates. Nothing is downloaded.
"""

import json
import math
import struct
from collections import Counter

SOURCE = "core/src/test/resources/tiles/davis-14-2651-6288.pbf"
OUTPUT = "iosApp/Vela/Resources/poi-davis.json"
ZOOM = 14
TX = 2651
TY = 6288
LAYER = "poi"

# The OSM class sets behind the sheet's five categories, copied from PoiClasses in
# ios-shared/src/commonMain/kotlin/app/vela/ios/map/LayersStore.kt.
GROUPS = {
    "food": {
        "restaurant", "fast_food", "cafe", "bar", "pub", "biergarten",
        "food_and_drink", "ice_cream", "drinking_water",
    },
    "fuel": {"fuel", "charging_station", "gas"},
    "transit": {
        "bus", "rail", "railway", "tram", "airport", "ferry_terminal",
        "subway", "station", "halt", "bus_station",
    },
    "parking": {"parking", "parking_garage", "parking_lot", "bicycle_parking"},
}


def read_varint(buf, offset):
    value = 0
    shift = 0
    while True:
        byte = buf[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, offset
        shift += 7


def fields(buf):
    offset = 0
    while offset < len(buf):
        key, offset = read_varint(buf, offset)
        field, wire = key >> 3, key & 7
        if wire == 0:
            value, offset = read_varint(buf, offset)
            yield field, wire, value
        elif wire == 2:
            length, offset = read_varint(buf, offset)
            yield field, wire, buf[offset:offset + length]
            offset += length
        elif wire == 5:
            yield field, wire, buf[offset:offset + 4]
            offset += 4
        elif wire == 1:
            yield field, wire, buf[offset:offset + 8]
            offset += 8
        else:
            raise ValueError("unsupported wire type %d at %d" % (wire, offset))


def packed(buf):
    values = []
    offset = 0
    while offset < len(buf):
        value, offset = read_varint(buf, offset)
        values.append(value)
    return values


def zigzag(value):
    return (value >> 1) ^ -(value & 1)


def decode_value(buf):
    for field, wire, value in fields(buf):
        if field == 1 and wire == 2:
            return value.decode("utf-8")
        if field == 2 and wire == 5:
            return struct.unpack("<f", value)[0]
        if field == 3 and wire == 1:
            return struct.unpack("<d", value)[0]
        if field in (4, 5) and wire == 0:
            return value
        if field == 6 and wire == 0:
            return zigzag(value)
        if field == 7 and wire == 0:
            return bool(value)
    return None


def layer(buf):
    name = None
    keys, values, features = [], [], []
    extent = 4096
    for field, wire, value in fields(buf):
        if field == 1 and wire == 2:
            name = value.decode("utf-8")
        elif field == 2 and wire == 2:
            features.append(value)
        elif field == 3 and wire == 2:
            keys.append(value.decode("utf-8"))
        elif field == 4 and wire == 2:
            values.append(decode_value(value))
        elif field == 5 and wire == 0:
            extent = value
    return name, keys, values, features, extent


def features(tile, keys, values, raw, extent):
    tags, geometry, kind = [], None, 0
    for field, wire, value in fields(raw):
        if field == 2:
            tags += packed(value)
        elif field == 3 and wire == 0:
            kind = value
        elif field == 4:
            geometry = packed(value)
    if kind != 1 or not geometry:
        return None
    props = {keys[k]: values[v] for k, v in zip(tags[0::2], tags[1::2])}
    name = props.get("name")
    if not name:
        return None
    x = zigzag(geometry[1])
    y = zigzag(geometry[2])
    n = 1 << ZOOM
    lng = (TX + x / extent) / n * 360 - 180
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (TY + y / extent) / n))))
    cls = props.get("class") or ""
    group = next((g for g, classes in GROUPS.items() if cls in classes), "other")
    return {
        "name": name,
        "class": cls,
        "group": group,
        "lat": round(lat, 6),
        "lng": round(lng, 6),
    }


def main():
    tile = open(SOURCE, "rb").read()
    places = []
    for field, wire, value in fields(tile):
        if field != 3 or wire != 2:
            continue
        name, keys, values, raw, extent = layer(value)
        if name != LAYER:
            continue
        places = [p for p in (features(tile, keys, values, f, extent) for f in raw) if p]
        break
    unique = {}
    for place in places:
        unique[(place["name"], place["lat"], place["lng"])] = place
    places = sorted(unique.values(), key=lambda p: (p["name"], p["lat"], p["lng"]))
    payload = {
        "source": SOURCE,
        "zoom": ZOOM,
        "tile": [TX, TY],
        "count": len(places),
        "places": places,
    }
    with open(OUTPUT, "w", encoding="utf-8") as out:
        json.dump(payload, out, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        out.write("\n")
    print("%d named places, %d after deduplication" % (len(places), len(unique)))
    print(Counter(p["group"] for p in places))


if __name__ == "__main__":
    main()
