#!/usr/bin/env python3
"""Write the synthetic offline fixtures the OfflineUITests scenario downloads.

    scripts/ios/offline_fixture.py iosApp/Vela/Resources

Two revisions of a Monaco place pack, places archive and basemap archive, a delta for each, a
world low-zoom archive and a map-fonts zip. The tiles are hand-built vector tiles with the layer
names the app probes (`transportation`, `water`, `poi`); they are not real map data and never
leave the Debug build. `OfflineFixtureSupport` serves these files from a fixture host through a
DEBUG-only URLProtocol and points OfflineStore's catalogs at them.
"""
import gzip
import json
import sqlite3
import struct
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "scripts"))
from velapmtiles import HEADER_LEN, write_dir  # noqa: E402


def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        b = value & 0x7F
        value >>= 7
        out.append(b | (0x80 if value else 0))
        if not value:
            return bytes(out)


def key(field: int, wire: int) -> bytes:
    return varint((field << 3) | wire)


def text_field(field: int, value: str) -> bytes:
    body = value.encode()
    return key(field, 2) + varint(len(body)) + body


def packed(field: int, values: list[int]) -> bytes:
    body = b"".join(varint(v) for v in values)
    return key(field, 2) + varint(len(body)) + body


def feature(kind: int, geometry: list[int]) -> bytes:
    return packed(3, [kind]) + packed(4, geometry)


def zigzag(value: int) -> int:
    return (value << 1) ^ (value >> 31)


def layer(name: str, features: list[bytes]) -> bytes:
    body = text_field(1, name)
    for f in features:
        body += key(2, 2) + varint(len(f)) + f
    body += key(5, 0) + varint(4096)
    body += key(15, 0) + varint(2)
    return key(3, 2) + varint(len(body)) + body


def mvt_water(opacity: int) -> bytes:
    ring = [9, zigzag(0), zigzag(0), 26, zigzag(4096), zigzag(0),
            zigzag(0), zigzag(4096), zigzag(-4096), zigzag(0)]
    return layer("water", [feature(3, ring)])


def mvt_roads(offset: int) -> bytes:
    line = [9, zigzag(0), zigzag(2048 + offset), 10, zigzag(4096), zigzag(0)]
    feats = [feature(2, line)]
    return layer("transportation", feats) + layer("water", [feature(3, [
        9, zigzag(0), zigzag(0), 26, zigzag(4096), zigzag(0),
        zigzag(0), zigzag(4096), zigzag(-4096), zigzag(0)])])


def mvt_place(offset: int) -> bytes:
    return layer("poi", [feature(1, [9, zigzag(2048), zigzag(2048 + offset)])])


def hilbert_tile_id(z: int, x: int, y: int) -> int:
    acc = sum((1 << t) * (1 << t) for t in range(z))
    n, xx, yy, d = 1 << z, x, y, 0
    s = n // 2
    while s > 0:
        rx = 1 if xx & s else 0
        ry = 1 if yy & s else 0
        d += s * s * ((3 * rx) ^ ry)
        if ry == 0:
            if rx == 1:
                xx, yy = s - 1 - xx, s - 1 - yy
            xx, yy = yy, xx
        s //= 2
    return acc + d


def tile_of(lat: float, lng: float, z: int) -> tuple[int, int]:
    import math
    n = 1 << z
    x = int((lng + 180.0) / 360.0 * n)
    rad = math.radians(lat)
    y = int((1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0 * n)
    return x, y


def build_pmtiles(path: Path, tiles: dict[int, bytes], z: int) -> None:
    blobs = [gzip.compress(tiles[k], mtime=0) for k in sorted(tiles)]
    entries, payload = [], bytearray()
    for tid, blob in zip(sorted(tiles), blobs):
        entries.append((tid, len(payload), len(blob), 1))
        payload += blob
    directory = write_dir(entries, 2)
    meta = gzip.compress(b'{"vela":"fixture"}', mtime=0)
    tile_off = HEADER_LEN + len(directory) + len(meta)
    head = bytearray(HEADER_LEN)
    head[0:7] = b"PMTiles"
    head[7] = 3
    for at, value in ((8, HEADER_LEN), (16, len(directory)),
                      (24, HEADER_LEN + len(directory)), (32, len(meta)),
                      (40, 0), (48, 0), (56, tile_off), (64, len(payload)),
                      (72, len(entries)), (80, len(entries)), (88, len(entries))):
        struct.pack_into("<Q", head, at, value)
    head[96] = 1
    head[97] = 2
    head[98] = 2
    head[99] = 1
    head[100] = z
    head[101] = z
    path.write_bytes(bytes(head) + directory + meta + bytes(payload))


def build_pack(path: Path, rows_v2: bool) -> tuple[dict[str, int], Path]:
    work = path.with_suffix(".db")
    if work.exists():
        work.unlink()
    db = sqlite3.connect(work)
    db.executescript("""
        CREATE TABLE poi(id TEXT, name TEXT, lat REAL, lng REAL, category TEXT,
                         address TEXT, phone TEXT, website TEXT, hours TEXT);
        CREATE TABLE streetname(sid INTEGER PRIMARY KEY, street TEXT, street_norm TEXT);
        CREATE TABLE addr(hn TEXT, sid INTEGER, city TEXT, lat REAL, lng REAL);
        CREATE TABLE streetpt(sid INTEGER, lat REAL, lng REAL);
    """)
    db.execute("INSERT INTO poi VALUES('n1','Casino de Monte Carlo',43.7391,7.4280,'casino','',NULL,NULL,NULL)")
    db.execute("INSERT INTO streetname VALUES(1,'Avenue de Monte Carlo','avenue de monte carlo')")
    db.execute("INSERT INTO addr VALUES('1',1,'Monaco',43.7390,7.4279)")
    db.execute("INSERT INTO streetpt VALUES(1,43.7391,7.4280)")
    if rows_v2:
        db.execute("INSERT INTO poi VALUES('n2','Cafe de Paris',43.7395,7.4285,'cafe','',NULL,NULL,NULL)")
        db.execute("INSERT INTO poi VALUES('n3','Monte Carlo Bay',43.7400,7.4290,'hotel','',NULL,NULL,NULL)")
        db.execute("INSERT INTO streetpt VALUES(1,43.7401,7.4282)")
    db.commit()
    counts = {t: db.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
              for t in ("poi", "streetname", "addr", "streetpt")}
    db.close()
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(work, "pack.db")
    return counts, work


def build_pack_delta(old_db: Path, new_db: Path, out: Path) -> None:
    work = out.with_suffix(".db")
    if work.exists():
        work.unlink()
    db = sqlite3.connect(work)
    db.execute(f"ATTACH DATABASE '{old_db}' AS old")
    db.execute(f"ATTACH DATABASE '{new_db}' AS new")
    columns = {
        "poi": "id,name,lat,lng,category,address,phone,website,hours",
        "streetname": "sid,street,street_norm",
        "addr": "hn,sid,city,lat,lng",
        "streetpt": "sid,lat,lng",
    }
    for table, cols in columns.items():
        db.execute(f"CREATE TABLE del_{table} AS SELECT {cols} FROM old.{table} "
                   f"EXCEPT SELECT {cols} FROM new.{table}")
        db.execute(f"CREATE TABLE ins_{table} AS SELECT {cols} FROM new.{table} "
                   f"EXCEPT SELECT {cols} FROM old.{table}")
    db.commit()
    db.close()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(work, "delta.db")
    work.unlink()


def write_patch(old_path: Path, new_path: Path, out: Path, rev_from: int, rev_to: int) -> None:
    import subprocess
    subprocess.run([sys.executable, str(HERE.parent / "pmtiles-make-patch.py"),
                    str(old_path), str(new_path), str(out),
                    "--rev-from", str(rev_from), "--rev-to", str(rev_to)], check=True)


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "iosApp/Vela/Resources")
    out.mkdir(parents=True, exist_ok=True)
    x12, y12 = tile_of(43.7391, 7.4280, 12)
    x14, y14 = tile_of(43.7391, 7.4280, 14)

    basemap_v1 = {hilbert_tile_id(12, x12, y12): mvt_roads(1)}
    basemap_v2 = {hilbert_tile_id(12, x12, y12): mvt_roads(2)}
    places_v1 = {hilbert_tile_id(14, x14, y14): mvt_place(1)}
    places_v2 = {hilbert_tile_id(14, x14, y14): mvt_place(2)}
    paths = {
        "basemap-v1.pmtiles": (basemap_v1, 12),
        "basemap-v2.pmtiles": (basemap_v2, 12),
        "places-v1.pmtiles": (places_v1, 14),
        "places-v2.pmtiles": (places_v2, 14),
        "world.pmtiles": ({hilbert_tile_id(0, 0, 0): mvt_water(1)}, 0),
    }
    made = {}
    for name, (tiles, z) in paths.items():
        path = out / f"offline-fixture-{name}"
        build_pmtiles(path, tiles, z)
        made[name] = path
    for prefix, rev_from, rev_to in (("basemap", 1, 2), ("places", 1, 2)):
        write_patch(made[f"{prefix}-v1.pmtiles"], made[f"{prefix}-v2.pmtiles"],
                    out / f"offline-fixture-{prefix}-v1-to-v2.vpatch", rev_from, rev_to)

    v1 = out / "offline-fixture-pack-v1.zip"
    v2 = out / "offline-fixture-pack-v2.zip"
    counts1, db1 = build_pack(v1, rows_v2=False)
    counts2, db2 = build_pack(v2, rows_v2=True)
    build_pack_delta(db1, db2, out / "offline-fixture-pack-delta.zip")
    db1.unlink()
    db2.unlink()

    with zipfile.ZipFile(out / "offline-fixture-map-fonts.zip", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("Noto Sans Regular/0-255.pbf", b"fixture-glyphs")

    print(json.dumps({"countsV1": counts1, "countsV2": counts2}, indent=2))
    for f in sorted(out.glob("offline-fixture-*")):
        print(f"{f.name}: {f.stat().st_size} bytes")


if __name__ == "__main__":
    main()
