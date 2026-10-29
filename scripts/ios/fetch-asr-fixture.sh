#!/usr/bin/env bash
# Downloads the real speech model used by the voice-search tests (Whisper tiny int8, the same
# archive Android downloads for English). Pinned by size and SHA-256. Usage:
# fetch-asr-fixture.sh <destination-dir>, which receives <engine-id>/ with the model and tokens
# exactly as the app stores them.
set -euo pipefail

ID=whisper-tiny
NAME="vela-asr-$ID.tar.gz"
URL="https://github.com/PimpinPumpkin/Vela/releases/download/asr-models/$NAME"
SHA256=ae93a93e04b6b4d86753f123e5539d216fe5a52dcf441d0e7fc97d05b3568d2e
BYTES=61255404

DEST="${1:?destination directory required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="${VELA_ASR_CACHE:-$ROOT/.asr-cache}"
ARCHIVE="$CACHE/$NAME"
mkdir -p "$DEST" "$CACHE"

if [ ! -f "$ARCHIVE" ] || [ "$(wc -c < "$ARCHIVE" | tr -d ' ')" != "$BYTES" ]; then
  echo "asr fixture: downloading $NAME"
  curl -fL --retry 3 --connect-timeout 20 -o "$ARCHIVE.part" "$URL"
  SIZE="$(wc -c < "$ARCHIVE.part" | tr -d ' ')"
  [ "$SIZE" = "$BYTES" ] || { echo "asr fixture: wrong size $SIZE" >&2; rm -f "$ARCHIVE.part"; exit 1; }
  ACTUAL="$(shasum -a 256 "$ARCHIVE.part" | awk '{print $1}')"
  [ "$ACTUAL" = "$SHA256" ] || { echo "asr fixture: checksum $ACTUAL" >&2; rm -f "$ARCHIVE.part"; exit 1; }
  mv "$ARCHIVE.part" "$ARCHIVE"
fi

python3 - "$ARCHIVE" "$DEST" "$ID" <<'PY'
import os, sys, tarfile
archive, dest, engine_id = sys.argv[1], sys.argv[2], sys.argv[3]
out = os.path.join(dest, engine_id)
os.makedirs(out, exist_ok=True)
with tarfile.open(archive, "r:gz") as tar:
    for member in tar.getmembers():
        parts = member.name.split("/")
        if len(parts) < 2:
            continue
        # Strip the archive's single top-level folder, the same rule the app applies.
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
