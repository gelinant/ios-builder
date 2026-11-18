#!/usr/bin/env bash
# G-1 globe spike on the macOS runner (docs/ios/GLOBE-SPIKE.md). Run from the source root with
# OUT set. Fetches the pinned MapLibre globe xcframework, builds the throwaway app and its size
# baseline, drives the autopilot in the iOS Simulator for fps and screenshots, then runs the
# gesture UI test. Writes STATUS, log.txt and summary.txt into $OUT like the other CI scripts.
set -uo pipefail
OUT="${OUT:?OUT must be set}"
SRC="$(pwd)"
ROOT="$SRC/tools/ios-globe-spike"
DD=/tmp/globe-spike-dd
mkdir -p "$OUT/screens"
log() { echo "[globe] $(date +%H:%M:%S) $*"; }
note() { echo "$*" | tee -a "$OUT/summary.txt"; }
fail() { note "FAILED: $*"; echo "failed" > "$OUT/STATUS"; exit 1; }

: > "$OUT/summary.txt"
note "G-1 globe spike, MapLibre Native ios-v2026.10.19-globe (MLN_WITH_GLOBE)"

step_fetch() {
  log "fetching the pinned globe xcframework"
  local started
  started=$(date +%s)
  bash "$SRC/scripts/ios/fetch-maplibre-globe.sh" 2>&1 | tee "$OUT/fetch.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail "the pre-release xcframework could not be fetched"
  local elapsed=$(( $(date +%s) - started ))
  local fw="$ROOT/Vendor/MapLibre.xcframework"
  local kib
  kib=$(du -sk "$fw" | cut -f1)
  {
    echo "release=ios-v2026.10.19-globe"
    echo "download_seconds=$elapsed"
    echo "archive_bytes=169968107"
    echo "xcframework_kib=$kib"
    du -sh "$fw"
    du -sh "$fw"/* 2>/dev/null
    ls "$fw"
  } > "$OUT/xcframework-size.txt"
  note "xcframework: $((kib / 1024)) MiB on disk ($(du -sh "$fw" | cut -f1)), fetched in ${elapsed}s"
}

step_xcodegen() {
  local version=2.46.0
  if ! command -v xcodegen > /dev/null; then
    log "installing XcodeGen $version"
    curl -fsSL -o /tmp/globe-xcodegen.zip \
      "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" || fail "XcodeGen download failed"
    unzip -q -o /tmp/globe-xcodegen.zip -d /tmp/globe-xcodegen || fail "XcodeGen unzip failed"
    XCODEGEN="$(find /tmp/globe-xcodegen -type f -name xcodegen -perm -u+x | head -n 1)"
  else
    XCODEGEN="$(command -v xcodegen)"
  fi
  [ -x "$XCODEGEN" ] || fail "no usable xcodegen"
  note "xcodegen: $("$XCODEGEN" --version 2>&1 | tail -n 1)"
  ( cd "$ROOT" && "$XCODEGEN" generate --spec project.yml ) > "$OUT/xcodegen.log" 2>&1 \
    || fail "XcodeGen failed (see xcodegen.log)"
}

step_build() {
  log "building the size baseline"
  xcodebuild build -project "$ROOT/GlobeSpike.xcodeproj" -scheme GlobeBaseline -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO \
    > "$OUT/build-baseline.log" 2>&1 \
    || { grep -E "error: " "$OUT/build-baseline.log" | head -40; fail "baseline build failed"; }

  log "building the spike app and its UI test"
  xcodebuild build-for-testing -project "$ROOT/GlobeSpike.xcodeproj" -scheme GlobeSpike \
    -configuration Debug -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO \
    > "$OUT/build.log" 2>&1
  local rc=$?
  grep -E "error: " "$OUT/build.log" | head -40 > "$OUT/build-errors.txt"
  if [ $rc -ne 0 ]; then
    cat "$OUT/build-errors.txt"
    fail "the pre-release did not build the spike app"
  fi
  local app="$DD/Build/Products/Debug-iphonesimulator/GlobeSpike.app"
  local base="$DD/Build/Products/Debug-iphonesimulator/GlobeBaseline.app"
  [ -d "$app" ] || fail "no app at $app"
  [ -d "$base" ] || fail "no baseline at $base"
  local app_kib base_kib fw_kib exe_bytes
  app_kib=$(du -sk "$app" | cut -f1)
  base_kib=$(du -sk "$base" | cut -f1)
  fw_kib=$(du -sk "$app/Frameworks/MapLibre.framework" 2>/dev/null | cut -f1 || echo 0)
  exe_bytes=$(stat -f%z "$app/GlobeSpike" 2>/dev/null || echo 0)
  {
    echo "app_kib=$app_kib"
    echo "baseline_kib=$base_kib"
    echo "delta_kib=$((app_kib - base_kib))"
    echo "embedded_framework_kib=$fw_kib"
    echo "app_executable_bytes=$exe_bytes"
    du -sh "$app" "$base" "$app/Frameworks/MapLibre.framework" 2>/dev/null
  } > "$OUT/app-size.txt"
  note "app size: $((app_kib / 1024)) MiB spike, $((base_kib / 1024)) MiB baseline, delta $(((app_kib - base_kib) / 1024)) MiB; embedded MapLibre.framework $((fw_kib / 1024)) MiB"
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

step_autopilot() {
  local app="$DD/Build/Products/Debug-iphonesimulator/GlobeSpike.app"
  log "booting simulator $UDID"
  ( xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 ) &
  local bootpid=$!
  wait "$bootpid" 2>/dev/null
  xcrun simctl install "$UDID" "$app" || fail "install failed"
  local data
  data=$(xcrun simctl get_app_container "$UDID" app.vela.globespike data 2>/dev/null)
  [ -n "$data" ] || fail "no data container"

  log "launching the autopilot"
  xcrun simctl launch --console --terminate-running-process "$UDID" app.vela.globespike --autopilot \
    > "$OUT/console.txt" 2>&1 < /dev/null &
  local lpid=$!
  local deadline=$(( $(date +%s) + 300 ))
  while :; do
    for m in z3 z0 tilted; do
      if [ -f "$data/Documents/globe-state-$m" ] && [ ! -f "$OUT/globe-$m.png" ]; then
        sleep 0.8
        xcrun simctl io "$UDID" screenshot --type=png "$OUT/globe-$m.png" > /dev/null 2>&1 \
          && log "screenshot globe-$m.png"
      fi
    done
    [ -f "$data/Documents/globe-done" ] && break
    [ "$(date +%s)" -ge "$deadline" ] && { log "autopilot timeout"; break; }
    sleep 1
  done
  kill "$lpid" 2>/dev/null
  wait "$lpid" 2>/dev/null
  mkdir -p "$OUT/app"
  [ -d "$data/Documents" ] && cp -R "$data/Documents/." "$OUT/app/"
  ls -la "$OUT/app" > "$OUT/app-files.txt" 2>&1
  xcrun simctl terminate "$UDID" app.vela.globespike 2>/dev/null
  [ -f "$OUT/app/globe-report.json" ] || fail "the autopilot wrote no report"
}

step_gestures() {
  log "running the gesture UI test"
  xcodebuild test-without-building -project "$ROOT/GlobeSpike.xcodeproj" -scheme GlobeSpike \
    -configuration Debug -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DD" -only-testing:GlobeSpikeUITests \
    CODE_SIGNING_ALLOWED=NO > "$OUT/gestures.log" 2>&1
  local rc=$?
  grep "GESTURE " "$OUT/gestures.log" | sed -e 's/^.*GESTURE /GESTURE /' > "$OUT/gestures.txt"
  cat "$OUT/gestures.txt"
  if [ $rc -ne 0 ]; then
    tail -40 "$OUT/gestures.log"
    note "gesture UI test failed (see gestures.log); autopilot measurements are still valid"
  else
    note "gesture UI test: passed"
  fi
}

step_report() {
  /usr/bin/python3 - "$OUT" <<'PY' | tee -a "$OUT/summary.txt"
import json, os, sys
out = sys.argv[1]
try:
    r = json.load(open(os.path.join(out, "app", "globe-report.json")))
except Exception as e:
    print("no autopilot report:", e)
    raise SystemExit(0)
def fps(key):
    d = r.get(key) or {}
    return "%s: %.1f fps (%s frames / %.1f s, avg render %.2f ms)" % (
        key, d.get("fps", 0), d.get("frames", 0), d.get("seconds", 0), d.get("avgRenderMs", 0))
print(fps("rotate"))
print(fps("zoomOut"))
c = r.get("camera") or {}
l = r.get("limits") or {}
o = r.get("occlusion") or {}
print("camera: min zoom %s, max zoom %s, max pitch %s" % (
    c.get("minimumZoomLevel"), c.get("maximumZoomLevel"), c.get("maximumPitch")))
print("limits: zoom -3 kept %s, zoom 30 kept %s, pitch 80 kept %s" % (
    l.get("zoomKeptAfterBelow"), l.get("zoomKeptAfterAbove"), l.get("pitchKept")))
print("occlusion at z%s: centre %s, antipode %s" % (
    o.get("atZoom"), o.get("center"), o.get("antipode")))
print("projection switch: %s in %.2f s" % (r.get("projection"), r.get("styleLoadSeconds") or 0))
PY
}

step_fetch
step_xcodegen
choose_simulator
step_build
step_autopilot
step_gestures
step_report
note "screenshots: globe-z3.png globe-z0.png globe-tilted.png"
echo ok > "$OUT/STATUS"
