#!/usr/bin/env bash
# W-2 WKWebView spike (docs/ios/spike-webview-ios.md) on the macOS runner, from the source root,
# with $OUT for outputs. Builds tools/ios-spike-web, runs it in the iOS Simulator and copies its
# report, log, snapshots and screenshots to $OUT.
# Args: variant letters for the app (A B C D), default all.
set -u
OUT="${OUT:?OUT must be set}"
SRC="$(pwd)"
mkdir -p "$OUT/app" "$OUT/screens"
log() { echo "[webspike] $(date +%H:%M:%S) $*"; }

cd "$SRC/tools/ios-spike-web" || exit 1

# Boot first, in the background: a first boot of the runtime took 7 minutes on run 1.
UDID=$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
c = sorted((k, x["udid"]) for k, v in d.items() if "iOS" in k for x in v if x["name"] == "iPhone 17")
c = c or sorted((k, x["udid"]) for k, v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone"))
print(c[-1][1] if c else "")')
[ -n "$UDID" ] || { log "no iPhone simulator"; exit 1; }
log "booting simulator $UDID"
(xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1) &
BOOTPID=$!

XG="$(command -v xcodegen || true)"
if [ -z "$XG" ]; then
  log "installing XcodeGen"
  if curl -fsSL -o /tmp/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip \
     && unzip -q -o /tmp/xcodegen.zip -d /tmp/xg; then
    XG=/tmp/xg/xcodegen/bin/xcodegen
  else
    brew install xcodegen >/dev/null 2>&1 && XG="$(command -v xcodegen)"
  fi
fi
[ -x "$XG" ] || { log "no xcodegen"; exit 1; }
"$XG" --version
"$XG" generate --spec project.yml || exit 1

log "building"
xcodebuild -project SpikeWeb.xcodeproj -scheme SpikeWeb -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/spikeweb-dd CODE_SIGNING_ALLOWED=NO build > "$OUT/build.log" 2>&1
rc=$?
grep -E "(error|warning): " "$OUT/build.log" | sort -u | head -80 > "$OUT/build-diag.txt"
if [ $rc -ne 0 ]; then
  log "build failed ($rc)"
  cat "$OUT/build-diag.txt"
  tail -30 "$OUT/build.log"
  exit 1
fi
APP=/tmp/spikeweb-dd/Build/Products/Debug-iphonesimulator/SpikeWeb.app
[ -d "$APP" ] || { log "no app at $APP"; exit 1; }
log "built; warnings: $(grep -c 'warning: ' "$OUT/build-diag.txt")"

log "waiting for simulator $UDID"
wait "$BOOTPID" 2>/dev/null
log "booted"
xcrun simctl install "$UDID" "$APP" || exit 1

DATA=$(xcrun simctl get_app_container "$UDID" app.vela.spikeweb data 2>/dev/null)
log "data container $DATA"

log "launching"
start=$(date +%s)
xcrun simctl launch --console --terminate-running-process "$UDID" app.vela.spikeweb "$@" > "$OUT/console.txt" 2>&1 < /dev/null &
LPID=$!
shot=0
deadline=$((start + 1500))
while :; do
  now=$(date +%s)
  if [ -n "$DATA" ] && [ -f "$DATA/Documents/spike-done" ]; then
    sleep 3
    break
  fi
  if [ "$now" -ge "$deadline" ]; then
    log "hard timeout, terminating the app"
    xcrun simctl terminate "$UDID" app.vela.spikeweb 2>/dev/null
    break
  fi
  if ! kill -0 "$LPID" 2>/dev/null; then
    # simctl returned: the app exited, or the console attach ended early. Wait while the log moves.
    lastmod=$(stat -f %m "$DATA/Documents/spike-log.txt" 2>/dev/null || echo "$start")
    if [ $((now - lastmod)) -gt 90 ]; then
      log "app gone (log idle for $((now - lastmod)) s)"
      break
    fi
  fi
  if [ $(((now - start) % 20)) -lt 5 ] && [ "$shot" -lt 45 ]; then
    shot=$((shot + 1))
    xcrun simctl io "$UDID" screenshot --type=jpeg "$OUT/screens/$(printf '%03d' $((now - start)))s.jpg" >/dev/null 2>&1
  fi
  sleep 5
done
kill "$LPID" 2>/dev/null
wait "$LPID" 2>/dev/null
log "app ended after $(($(date +%s) - start)) s"

[ -n "$DATA" ] || DATA=$(xcrun simctl get_app_container "$UDID" app.vela.spikeweb data 2>/dev/null)
if [ -n "$DATA" ] && [ -d "$DATA/Documents" ]; then
  cp -R "$DATA/Documents/." "$OUT/app/"
fi
ls -la "$OUT/app"
# Why a WebContent process ended (memory limit, crash, watchdog), from the simulator's log.
xcrun simctl spawn "$UDID" log show --last 30m --style compact \
  --predicate 'process BEGINSWITH "com.apple.WebKit" OR subsystem == "com.apple.WebKit"' 2>/dev/null \
  | grep -iE "terminat|jetsam|memory|crash|unresponsive|limit|kill|exceed" | head -300 > "$OUT/webkit-log.txt"
echo "--- WebKit log (process ends) ---"
head -40 "$OUT/webkit-log.txt" | cut -c1-300
echo "--- SPIKE lines (status, results) ---"
grep -E "SPIKE\|(start|status|result|rules|snapshot)" "$OUT/app/spike-log.txt" 2>/dev/null | cut -c1-300
echo "--- report ---"
/usr/bin/python3 - "$OUT/app/spike-result.json" <<'EOF'
import json, sys
try:
    r = json.load(open(sys.argv[1]))
except Exception as e:
    print("no report:", e); sys.exit(0)
print("done", r.get("done"), "ios", r.get("ios"), "rules", r.get("contentRules"), "scripts", r.get("scripts"))
skip = {"events", "infos"}
for v in r.get("variants", []):
    print("==", v.get("variant"), "cookies", v.get("cookies"))
    for k in ("reviews", "popular", "photos"):
        if k in v:
            print(" ", k, json.dumps({a: b for a, b in v[k].items() if a not in skip}, sort_keys=True)[:900])
EOF
[ -f "$OUT/app/spike-result.json" ]
