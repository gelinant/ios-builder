#!/usr/bin/env bash
# Fetches the four pinned z11 terrarium tiles over Mont Blanc and Chamonix, used by the terrain
# renderer spike (docs/ios/TERRAIN-SPIKE.md). The app also downloads them at run time; this script
# is the source check: a moved bucket, a renamed tile or a different size stops the run before the
# simulator starts. Tiles are not committed.
#
# Source: AWS Open Data elevation-tiles-prod (Mapzen terrain tiles). The composite has mixed
# open terms (public domain, CC BY 3.0/4.0, Open Government Licence, Copernicus) and attribution is
# mandatory. See https://github.com/tilezen/joerd/blob/master/docs/attribution.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/tools/ios-terrain-spike/DEM"
BASE=https://s3.amazonaws.com/elevation-tiles-prod/terrarium
ZOOM=11
# x y expected-bytes, measured on 2026-10-28.
TILES=(
  "1062 729 142987"
  "1063 729 147068"
  "1062 730 145412"
  "1063 730 146805"
)

total=0
for entry in "${TILES[@]}"; do
  read -r x y bytes <<< "$entry"
  dir="$DEST/$ZOOM/$x"
  file="$dir/$y.png"
  if [ ! -f "$file" ] || [ "$(wc -c < "$file" | tr -d ' ')" != "$bytes" ]; then
    mkdir -p "$dir"
    echo "terrain-dem: downloading $ZOOM/$x/$y ($bytes bytes)"
    if ! curl -fL --retry 3 --connect-timeout 20 -o "$file.part" "$BASE/$ZOOM/$x/$y.png"; then
      echo "terrain-dem: $BASE/$ZOOM/$x/$y.png is gone" >&2
      rm -f "$file.part"
      exit 1
    fi
    got="$(wc -c < "$file.part" | tr -d ' ')"
    if [ "$got" != "$bytes" ]; then
      echo "terrain-dem: $ZOOM/$x/$y sizes $got, expected $bytes" >&2
      rm -f "$file.part"
      exit 1
    fi
    mv "$file.part" "$file"
  fi
  magic="$(head -c 8 "$file" | od -An -tx1 | tr -d ' \n')"
  if [ "$magic" != "89504e470d0a1a0a" ]; then
    echo "terrain-dem: $file is not a PNG" >&2
    exit 1
  fi
  total=$((total + bytes))
done

echo "terrain-dem: 4 tiles, $total bytes, $ZOOM/1062..1063/729..730"
echo "terrain-dem: Mapzen terrain tiles / AWS Open Data elevation-tiles-prod, mixed open terms"
echo "terrain-dem: attribution required, see tilezen/joerd docs/attribution.md"
