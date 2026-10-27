#!/usr/bin/env bash
# Fetches the prebuilt sherpa-onnx iOS xcframework used by the neural voice. The archive is pinned
# by version, size and SHA-256 and is never committed (docs/ios/VOICE.md). Idempotent: a second run
# with the same version does nothing.
set -euo pipefail

VERSION=1.13.8
NAME="sherpa-onnx-v${VERSION}-ios-shared-onnxruntime-static.xcframework.zip"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/${NAME}"
SHA256=e259a7d3b38ad7dec49bb078252a30bb42ede8355e2bb130cf8c1c78ed131f75
BYTES=31858229

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/iosApp/Vendor"
FRAMEWORK="$DEST/SherpaOnnxC.xcframework"

if [ -f "$FRAMEWORK/Info.plist" ]; then
  echo "sherpa-onnx: present at $FRAMEWORK"
  exit 0
fi

mkdir -p "$DEST"
ZIP="$DEST/$NAME"

echo "sherpa-onnx: downloading $NAME"
curl -fL --retry 3 --connect-timeout 20 -o "$ZIP.part" "$URL"
SIZE="$(wc -c < "$ZIP.part" | tr -d ' ')"
if [ "$SIZE" != "$BYTES" ]; then
  echo "sherpa-onnx: wrong size $SIZE, expected $BYTES" >&2
  rm -f "$ZIP.part"
  exit 1
fi
ACTUAL="$(shasum -a 256 "$ZIP.part" | awk '{print $1}')"
if [ "$ACTUAL" != "$SHA256" ]; then
  echo "sherpa-onnx: checksum $ACTUAL, expected $SHA256" >&2
  rm -f "$ZIP.part"
  exit 1
fi
mv "$ZIP.part" "$ZIP"

# python3's zipfile works on both the macOS runner and Linux (no unzip on some hosts).
python3 - "$ZIP" "$DEST" <<'PY'
import os, sys, zipfile
archive, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as z:
    for info in z.infolist():
        name = info.filename
        if not name.startswith("SherpaOnnxC.xcframework/"):
            raise SystemExit("unexpected archive member " + name)
        z.extract(info, dest)
PY
rm -f "$ZIP"
test -f "$FRAMEWORK/Info.plist"
echo "sherpa-onnx $VERSION: ready at $FRAMEWORK"
