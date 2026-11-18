#!/usr/bin/env bash
# Fetches the MapLibre Native iOS xcframework built with MLN_WITH_GLOBE. The release is a
# pre-release and is pinned by tag, size and SHA-256; it is never committed. Idempotent: a second
# run with the same version does nothing.
#
#   scripts/ios/fetch-maplibre-globe.sh        # G-1 spike: tools/ios-globe-spike/Vendor
#   scripts/ios/fetch-maplibre-globe.sh app    # Vela: iosApp/Vendor, used by project.yml
#
# The archive is the dynamic xcframework. The app embeds it; the spike app measured the size delta.
# Fail loudly if the release or the asset disappears.
set -euo pipefail

VERSION=ios-v2026.10.19-globe
ASSET=MapLibre.dynamic.xcframework.zip
URL="https://github.com/maplibre/maplibre-native/releases/download/$VERSION/$ASSET"
SHA256=ae9c967acf220111d8fb1c8f066d23cff0d91c5ec827c8f68770d4cd55f799e8
BYTES=169968107

MODE="${1:-spike}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
case "$MODE" in
  app) DEST="$ROOT/iosApp/Vendor" ;;
  spike) DEST="$ROOT/tools/ios-globe-spike/Vendor" ;;
  *) echo "maplibre-globe: unknown destination '$MODE' (use app or spike)" >&2; exit 2 ;;
esac
FRAMEWORK="$DEST/MapLibre.xcframework"

if [ -f "$FRAMEWORK/Info.plist" ]; then
  echo "maplibre-globe: present at $FRAMEWORK ($(du -sh "$FRAMEWORK" | cut -f1) on disk)"
  exit 0
fi

mkdir -p "$DEST"
ZIP="$DEST/$ASSET"

echo "maplibre-globe: downloading $ASSET ($BYTES bytes) from $VERSION"
# -f turns the 404 of a deleted release into an immediate, readable failure.
if ! curl -fL --retry 3 --connect-timeout 20 -o "$ZIP.part" "$URL"; then
  echo "maplibre-globe: download failed for $URL" >&2
  echo "maplibre-globe: the pre-release $VERSION is gone or its asset was renamed" >&2
  rm -f "$ZIP.part"
  exit 1
fi
SIZE="$(wc -c < "$ZIP.part" | tr -d ' ')"
if [ "$SIZE" != "$BYTES" ]; then
  echo "maplibre-globe: wrong size $SIZE, expected $BYTES" >&2
  rm -f "$ZIP.part"
  exit 1
fi
ACTUAL="$(python3 - "$ZIP.part" <<'PY'
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for block in iter(lambda: f.read(1 << 20), b""):
        h.update(block)
print(h.hexdigest())
PY
)"
if [ "$ACTUAL" != "$SHA256" ]; then
  echo "maplibre-globe: checksum $ACTUAL, expected $SHA256" >&2
  rm -f "$ZIP.part"
  exit 1
fi
mv "$ZIP.part" "$ZIP"

# python3's zipfile works on the macOS runner and on Linux. Check the archive shape rather than
# trusting it: a renamed or repackaged asset must not silently produce a half-installed vendor.
python3 - "$ZIP" "$DEST" <<'PY'
import sys, zipfile
archive, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as z:
    names = z.namelist()
    if not any(n.startswith("MapLibre.xcframework/") for n in names):
        raise SystemExit("unexpected archive members, no MapLibre.xcframework/ prefix: " + ", ".join(names[:5]))
    for info in z.infolist():
        name = info.filename
        if name.startswith("MapLibre.xcframework/"):
            z.extract(info, dest)
PY
rm -f "$ZIP"
test -f "$FRAMEWORK/Info.plist"

# The globe build is recognisable by the projection render tests and by isCoordinateOccluded:.
# A plain Mercator xcframework would make the spike prove nothing, so stop here instead.
if ! grep -rq "isCoordinateOccluded" "$FRAMEWORK" 2>/dev/null; then
  echo "maplibre-globe: $FRAMEWORK has no isCoordinateOccluded symbol; not the globe build" >&2
  exit 1
fi
echo "maplibre-globe $VERSION: ready at $FRAMEWORK ($(du -sh "$FRAMEWORK" | cut -f1) on disk)"
