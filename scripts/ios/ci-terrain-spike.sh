#!/usr/bin/env bash
# Terrain renderer spike on the macOS runner (docs/ios/TERRAIN-SPIKE.md). Checks the pinned DEM
# tiles, builds the throwaway app against the app's MapLibre pin, drives the autopilot in the iOS
# Simulator and captures three screenshots. Writes STATUS, log.txt and summary.txt into $OUT like
# the other CI scripts.
set -uo pipefail
OUT="${OUT:?OUT must be set}"
SRC="$(pwd)"
ROOT="$SRC/tools/ios-terrain-spike"
DD=/tmp/terrain-spike-dd
mkdir -p "$OUT/screens"
log() { echo "[terrain] $(date +%H:%M:%S) $*"; }
note() { echo "$*" | tee -a "$OUT/summary.txt"; }
fail() { note "FAILED: $*"; echo "failed" > "$OUT/STATUS"; exit 1; }

: > "$OUT/summary.txt"
note "terrain spike, MapLibre Native 6.31.0, MLNCustomStyleLayer + Metal"

step_dem() {
  log "checking the pinned terrarium tiles"
  bash "$SRC/scripts/ios/fetch-terrain-dem.sh" 2>&1 | tee "$OUT/dem.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail "the DEM source is not reachable or changed size"
  du -sk "$ROOT/DEM" > "$OUT/dem-size.txt"
  note "DEM: 4 tiles z11 over Mont Blanc, $(du -sk "$ROOT/DEM" | cut -f1) KiB on disk"
}

step_xcodegen() {
  local version=2.46.0
  if ! command -v xcodegen > /dev/null; then
    log "installing XcodeGen $version"
    curl -fsSL -o /tmp/terrain-xcodegen.zip \
      "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" || fail "XcodeGen download failed"
    unzip -q -o /tmp/terrain-xcodegen.zip -d /tmp/terrain-xcodegen || fail "XcodeGen unzip failed"
    XCODEGEN="$(find /tmp/terrain-xcodegen -type f -name xcodegen -perm -u+x | head -n 1)"
  else
    XCODEGEN="$(command -v xcodegen)"
  fi
  [ -x "$XCODEGEN" ] || fail "no usable xcodegen"
  note "xcodegen: $("$XCODEGEN" --version 2>&1 | tail -n 1)"
  ( cd "$ROOT" && "$XCODEGEN" generate --spec project.yml ) > "$OUT/xcodegen.log" 2>&1 \
    || fail "XcodeGen failed (see xcodegen.log)"
}

choose_simulator() {
  UDID=$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
c = sorted((k, x["udid"]) for k, v in d.items() if "iOS" in k for x in v if x["name"] == "iPhone 17")
c = c or sorted((k, x["udid"]) for k, v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone"))
print(c[-1][1] if c else "")')
  [ -n "$UDID" ] || fail "no iPhone simulator"
  note "simulator: $UDID ($(xcrun simctl list devices | grep "$UDID" | sed -e 's/^ *//'))"
}

step_build() {
  log "building the spike app"
  xcodebuild build -project "$ROOT/TerrainSpike.xcodeproj" -scheme TerrainSpike \
    -configuration Debug -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO \
    > "$OUT/build.log" 2>&1
  local rc=$?
  grep -E "error: " "$OUT/build.log" | head -60 > "$OUT/build-errors.txt"
  if [ $rc -ne 0 ]; then
    cat "$OUT/build-errors.txt"
    fail "build failed"
  fi
  local app="$DD/Build/Products/Debug-iphonesimulator/TerrainSpike.app"
  [ -d "$app" ] || fail "no app at $app"
  note "app built: $(du -sh "$app" | cut -f1)"
}

step_run() {
  local app="$DD/Build/Products/Debug-iphonesimulator/TerrainSpike.app"
  log "booting simulator $UDID"
  xcrun simctl boot "$UDID" 2>/dev/null
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1
  xcrun simctl install "$UDID" "$app" || fail "install failed"
  local data
  data=$(xcrun simctl get_app_container "$UDID" app.vela.terrainspike data 2>/dev/null)
  [ -n "$data" ] || fail "no data container"

  log "launching the autopilot"
  xcrun simctl launch --console --terminate-running-process "$UDID" app.vela.terrainspike --autopilot \
    > "$OUT/console.txt" 2>&1 < /dev/null &
  local lpid=$!
  local deadline=$(( $(date +%s) + 420 ))
  while :; do
    for m in valley tilted overlay; do
      if [ -f "$data/Documents/terrain-state-$m" ] && [ ! -f "$OUT/terrain-$m.png" ]; then
        sleep 1
        xcrun simctl io "$UDID" screenshot --type=png "$OUT/terrain-$m.png" > /dev/null 2>&1 \
          && log "screenshot terrain-$m.png"
      fi
    done
    [ -f "$data/Documents/terrain-done" ] && break
    if [ "$(date +%s)" -ge "$deadline" ]; then
      log "autopilot timeout"
      break
    fi
    sleep 1
  done
  kill "$lpid" 2>/dev/null
  wait "$lpid" 2>/dev/null
  mkdir -p "$OUT/app"
  [ -d "$data/Documents" ] && cp -R "$data/Documents/." "$OUT/app/"
  ls -la "$OUT/app" > "$OUT/app-files.txt" 2>&1
  xcrun simctl terminate "$UDID" app.vela.terrainspike 2>/dev/null
  [ -f "$OUT/app/terrain-report.json" ] || fail "the autopilot wrote no report"
  grep "TERRAIN " "$OUT/console.txt" | tail -n 200 > "$OUT/console-tail.txt" 2>/dev/null || true
}

step_report() {
  /usr/bin/python3 - "$OUT" <<'PY' | tee -a "$OUT/summary.txt"
import json, os, sys
out = sys.argv[1]
r = json.load(open(os.path.join(out, "app", "terrain-report.json")))
if r.get("error"):
    print("ERROR:", r["error"])
d = r.get("dem") or {}
print("dem: %s z%s %sx%s tiles, %s bytes, %.0f ms download+decode" % (
    d.get("sourceClass"), d.get("zoom"), d.get("tilesPerSide"), d.get("tilesPerSide"),
    d.get("downloadedBytes"), d.get("downloadAndDecodeMs", 0)))
p = r.get("pass") or {}
print("pass: depth=%s format=%s color=%s, projection matrix=%s" % (
    p.get("depthAttachment"), p.get("depthFormat"), p.get("colorFormat"),
    p.get("providesProjectionMatrix")))
for name in ("128", "256", "512"):
    m = (r.get("meshes") or {}).get(name)
    if not m:
        continue
    f = (r.get("fps") or {}).get(name) or {}
    i = (r.get("idle") or {}).get(name) or {}
    print("mesh %s: %d tris, build %.1f ms, upload %.1f ms, arrays %d bytes, footprint +%d bytes; "
          "fps %.1f, cpu %.2f ms/frame, encode %.3f ms; idle %d frames in %.1f s" % (
              name, m.get("triangles"), m.get("buildMs", 0), m.get("uploadMs", 0),
              m.get("arrayBytes"), m.get("footprintDeltaBytes", 0),
              f.get("fps", 0), f.get("cpuMsPerFrame", 0), f.get("encodeMsPerFrame", 0),
              i.get("frames", 0), i.get("seconds", 0)))
for pr in r.get("probes") or []:
    print("probe %s: %d pts, max %.2f px, mean %.2f px, horizon lift %.2f px" % (
        pr.get("state"), pr.get("points", 0), pr.get("maxErrorPx", 0),
        pr.get("meanErrorPx", 0), pr.get("horizonLiftPx", 0)))
o = r.get("overlay") or {}
print("overlay: %.1f fps, cpu %.2f ms/frame, %s frames" % (
    o.get("fps", 0), o.get("cpuMsPerFrame", 0), o.get("frames", 0)))
print("footprint: %d MiB" % (r.get("footprintBytes", 0) / 1048576))
PY
}

step_dem
step_xcodegen
choose_simulator
step_build
step_run
step_report
note "screenshots: terrain-valley.png terrain-tilted.png terrain-overlay.png"
echo ok > "$OUT/STATUS"
