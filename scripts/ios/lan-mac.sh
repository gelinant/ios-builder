#!/usr/bin/env bash
# Runs one of the iOS CI scripts on a Mac reachable over SSH on the LAN instead of the GitHub
# runner (docs/ios/HIVE.md, "Mac"). Same contract as mac-run.sh: prints STATUS and the log tail and
# exits 0 only when STATUS is ok. Artifacts come back under ~/.tmp/vela-mac/results/<tag>/.
#
# Usage: bash scripts/ios/lan-mac.sh <source checkout> <tag> <script> [args...]
#
# Environment (export it or put it in ~/.config/vela-mac.env):
#   VELA_MAC_HOST    hostname or IP of the Mac        (required)
#   VELA_MAC_USER    SSH user                         (default: local user)
#   VELA_MAC_PORT    SSH port                         (default: 22)
#   VELA_MAC_DIR     remote build directory           (default: $HOME/vela-build)
#   VELA_MAC_OUT     remote artifact directory        (default: $HOME/vela-build-out)
#   VELA_MAC_JOBS    builds at once on that Mac       (default: 2)
#   VELA_MAC_TIMEOUT seconds before giving up         (default: 5400)
#   VELA_MAC_DEVELOPER_DIR  /Applications/Xcode.app/Contents/Developer when xcode-select still
#                           points at the Command Line Tools (no sudo needed)
set -euo pipefail
[ -f "$HOME/.config/vela-mac.env" ] && . "$HOME/.config/vela-mac.env"

repo="${1:?source checkout}"; tag="${2:?tag}"; script="${3:?script}"; shift 3
: "${VELA_MAC_HOST:?set VELA_MAC_HOST (see the header of this script)}"
user="${VELA_MAC_USER:-$(id -un)}"
port="${VELA_MAC_PORT:-22}"
jobs="${VELA_MAC_JOBS:-2}"
timeout_s="${VELA_MAC_TIMEOUT:-5400}"
dest="$user@$VELA_MAC_HOST"
ssh=(ssh -p "$port" -o BatchMode=yes -o ServerAliveInterval=30 "$dest")

remote_home="$("${ssh[@]}" 'printf %s "$HOME"')"
expand() { # turn ~ and $HOME into the Mac's home, so the env file can stay portable
  local p="$1"
  p="${p/#\~/$remote_home}"
  p="${p/#\$HOME/$remote_home}"
  printf %s "${p:-$remote_home/vela-build}"
}
remote_dir="$(expand "${VELA_MAC_DIR:-}")"
remote_out="$(expand "${VELA_MAC_OUT:-}")"
[ "$remote_out" = "$remote_home/vela-build" ] && remote_out="$remote_home/vela-build-out"
work="$remote_dir/$tag"
out="$remote_out/$tag"
local_dir="${TMPDIR:-$HOME/.tmp}/vela-mac/results/$tag"
mkdir -p "$local_dir"
log="$local_dir/lan.log"

echo "lan-mac: $tag -> $dest:$work" >&2
"${ssh[@]}" "mkdir -p '$work' '$out' '$remote_dir/.slots'"

# Source, minus what the Mac rebuilds. local.properties is ignored by git but needed by Gradle on
# Android-only tasks; the iOS build does not need it, so it is not copied.
rsync -a --delete \
  --exclude '.git/' --exclude 'build/' --exclude '.gradle/' --exclude '.kotlin/' \
  --exclude 'iosApp/Vendor/' --exclude 'app/libs/' --exclude 'core/libs/' \
  --exclude '.tmp/' --exclude 'local.properties' --exclude 'node_modules/' \
  "$repo/" "$dest:$work/" >&2

args_quoted="$(printf '%q ' "$@")"

set +e
"${ssh[@]}" "VELA_WORK='$work' VELA_OUT='$out' VELA_SCRIPT='$script' VELA_ARGS='$args_quoted' \
  VELA_JOBS='$jobs' VELA_TIMEOUT='$timeout_s' VELA_DEVDIR='${VELA_MAC_DEVELOPER_DIR:-}' \
  bash -s" > "$log" 2>&1 <<'REMOTE'
set -uo pipefail
cd "$VELA_WORK" || exit 1
mkdir -p "$VELA_OUT" "$VELA_WORK/.slots"
rm -rf "$VELA_OUT"/*

# One build slot among VELA_JOBS, so several agents share the Mac without thrashing it.
slot=""
started=$(date +%s)
while [ -z "$slot" ]; do
  i=1
  while [ "$i" -le "$VELA_JOBS" ]; do
    if ( exec 9>"$VELA_WORK/.slots/$i.lock"; flock -n 9 ) 2>/dev/null; then
      slot="$i"; break
    fi
    i=$((i + 1))
  done
  [ -n "$slot" ] && break
  [ $(( $(date +%s) - started )) -lt "$VELA_TIMEOUT" ] || { echo "no build slot free"; exit 2; }
  sleep 10
done

# Hold the slot for the whole build, then run the requested script.
(
  exec 9>"$VELA_WORK/.slots/$slot.lock"
  flock 9
  export JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || echo "$HOME/opt/jdk-17/Contents/Home")"
  [ -n "${VELA_DEVDIR:-}" ] && export DEVELOPER_DIR="$VELA_DEVDIR"
  OUT="$VELA_OUT" bash "$VELA_SCRIPT" $VELA_ARGS
) 2>&1 | tail -c 2000000 | tee "$VELA_OUT/remote.log"
exit "${PIPESTATUS[0]}"
REMOTE
rc=$?
set -e

rsync -a "$dest:$out/" "$local_dir/" 2>/dev/null || true
status="$(cat "$local_dir/STATUS" 2>/dev/null || echo missing)"
echo "STATUS: $status"
echo "--- tail ($local_dir) ---"
tail -n 80 "$local_dir/log.txt" 2>/dev/null || tail -n 60 "$log"
echo "--- files ---"
ls -1 "$local_dir" 2>/dev/null | tr '\n' ' '; echo
echo "tag=$tag out=$local_dir"
[ "$status" = ok ] && [ "$rc" -eq 0 ]
