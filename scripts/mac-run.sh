#!/usr/bin/env bash
# Runs a script from a Vela checkout on the macOS runner and waits for the result.
# Usage: scripts/mac-run.sh <vela checkout> <lot> <script path in checkout> [args...]
# Prints STATUS and the log tail; exit 0 if STATUS is ok. Result files: branch `results`, dir <tag>/.
# Large files (IPA): branch `builds`, dir <tag>/.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$1"; lot="$2"; script="$3"; shift 3
tag="${lot}-$(date +%Y%m%d-%H%M%S)-$RANDOM"
bash "$here/scripts/push-src.sh" "$repo" "$lot" HEAD >/dev/null

work=$(mktemp -d "${TMPDIR:-/tmp}/ios-builder.XXXXXX")
trap 'rm -rf "$work"' EXIT
git clone -q --depth 1 git@github.com:gelinant/ios-builder.git "$work/b"
cd "$work/b"
mkdir -p requests
printf 'src=src/%s\nscript=%s\nargs=%s\n' "$lot" "$script" "$*" > "requests/$tag.req"
git add "requests/$tag.req"
git -c user.name=hive -c user.email=hive@localhost commit -q -m "run $tag"
for i in 1 2 3 4 5 6; do git push -q origin HEAD:main && break; git pull -q --rebase origin main; sleep $((RANDOM % 5 + 1)); done
echo "requested $tag (src/$lot, $script)" >&2

# Wait up to 70 min for results/<tag>/STATUS.
for i in $(seq 1 280); do
  sleep 15
  if git fetch -q origin results 2>/dev/null && git cat-file -e "FETCH_HEAD:$tag/STATUS" 2>/dev/null; then
    status=$(git show "FETCH_HEAD:$tag/STATUS")
    echo "STATUS: $status"
    echo "--- log tail ($tag/log.txt on branch results) ---"
    git show "FETCH_HEAD:$tag/log.txt" 2>/dev/null | tail -n 120
    echo "--- files ---"
    git ls-tree --name-only "FETCH_HEAD:$tag" | tr '\n' ' '; echo
    echo "tag=$tag"
    [ "$status" = ok ]; exit $?
  fi
done
echo "timeout waiting for $tag"; exit 2
