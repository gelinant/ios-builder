#!/usr/bin/env bash
# Downloads the real Piper model used by the voice tests and the UI fixture. Pinned by archive
# SHA-256. Usage: fetch-voice-fixture.sh <destination-dir>, which receives <voice-id>/ with the
# model, tokens and espeak-ng-data exactly as the app stores it.
set -euo pipefail

ID=en_US-hfc_female-medium
NAME="vits-piper-$ID.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$NAME"
SHA256=3fffdceb0c65bd9415a085d09c3cb88cc82f9d74a6ca453f8ce7fc5eaee81ff8
BYTES=67228166

DEST="${1:?destination directory required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="${VELA_VOICE_CACHE:-$ROOT/.voice-cache}"
ARCHIVE="$CACHE/$NAME"
mkdir -p "$DEST" "$CACHE"

if [ ! -f "$ARCHIVE" ] || [ "$(wc -c < "$ARCHIVE" | tr -d ' ')" != "$BYTES" ]; then
  echo "voice fixture: downloading $NAME"
  curl -fL --retry 3 --connect-timeout 20 -o "$ARCHIVE.part" "$URL"
  SIZE="$(wc -c < "$ARCHIVE.part" | tr -d ' ')"
  [ "$SIZE" = "$BYTES" ] || { echo "voice fixture: wrong size $SIZE" >&2; rm -f "$ARCHIVE.part"; exit 1; }
  ACTUAL="$(shasum -a 256 "$ARCHIVE.part" | awk '{print $1}')"
  [ "$ACTUAL" = "$SHA256" ] || { echo "voice fixture: checksum $ACTUAL" >&2; rm -f "$ARCHIVE.part"; exit 1; }
  mv "$ARCHIVE.part" "$ARCHIVE"
fi

python3 - "$ARCHIVE" "$DEST" "$ID" <<'PY'
import os, sys, tarfile
archive, dest, voice_id = sys.argv[1], sys.argv[2], sys.argv[3]
out = os.path.join(dest, voice_id)
os.makedirs(out, exist_ok=True)
with tarfile.open(archive, "r:bz2") as tar:
    for member in tar.getmembers():
        parts = member.name.split("/")
        if len(parts) < 2 or parts[0] != "vits-piper-" + voice_id:
            continue
        rel = "/".join(parts[1:])
        if not rel or ".." in parts:
            continue
        target = os.path.join(out, rel)
        if member.isdir():
            os.makedirs(target, exist_ok=True)
        elif member.isfile():
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with tar.extractfile(member) as source, open(target, "wb") as sink:
                sink.write(source.read())
print(out)
PY
