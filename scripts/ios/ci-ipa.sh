#!/usr/bin/env bash
# Builds, tests and packages the Vela iOS app on the macOS runner (docs/ios/BUILD-IOS.md,
# docs/ios/TESTING-IOS.md). Run from the source root with OUT set. Writes to $OUT: summary.txt,
# screenshot.png, one PNG per UI scenario screenshot (launch-*.png, search-*.png, place-*.png,
# directions-*.png, nav-*.png, calibration.png), route-*.png (a simulated drive), Vela-unsigned.ipa,
# app-log.txt, velacore-log.txt, search-coffee-sf.txt.gz and directions-{drive,walk}-sf.txt.gz
# (raw replies, test fixtures), gradle.log and
# one xcodebuild-<step>.log per xcodebuild call. Test, screenshot, launch, Kotlin call, UI scenario
# and calibration failures are reported and the script goes on to the archive; it exits non-zero
# at the end if any step failed.
set -euo pipefail

# mac-run.sh passes these as script arguments, so a focused run does not need environment
# variables on the runner: VELA_ONLY_UI=PlaceUITests VELA_SKIP_ARCHIVE=1.
for arg in "$@"; do
  case "$arg" in
    VELA_ONLY_UI=*|VELA_SKIP_ARCHIVE=*) export "$arg" ;;
  esac
done

: "${OUT:?OUT must be set}"
mkdir -p "$OUT"
ROOT="$(pwd)"
# shellcheck source=scripts/ios/sim-helpers.sh
source "$ROOT/scripts/ios/sim-helpers.sh"
WORK="$(mktemp -d)"
XCODEGEN_VERSION=2.46.0
BUNDLE_ID=app.vela.ios
# Development versions must increase for SideStore to offer an update. Override with VELA_VERSION
# and VELA_BUILD_NUMBER for a named release.
VELA_BUILD_ID="${VELA_BUILD_ID:-$(date -u +%Y%m%d%H%M)}"
VELA_VERSION="${VELA_VERSION:-0.1.$VELA_BUILD_ID}"
VELA_BUILD_NUMBER="${VELA_BUILD_NUMBER:-$(date -u +%s)}"
# Under DerivedData so the runner's cache (~/Library/Developer/Xcode/DerivedData/**/SourcePackages)
# keeps the MapLibre download between runs.
DD="$HOME/Library/Developer/Xcode/DerivedData/Vela-ci"
SPM="$DD/SourcePackages"
SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"
failures=()
trap 'gzip -9f "$OUT"/xcodebuild-*.log "$OUT"/gradle.log 2> /dev/null || true' EXIT

note() { echo "$*" | tee -a "$SUMMARY"; }
step() { echo; echo "== $* ($(date +%H:%M:%S))"; }

# Runs xcodebuild with the full log in $OUT/xcodebuild-<name>.log. Prints the last lines on
# success, the error lines and the tail on failure.
xb() {
  local name="$1"; shift
  local log="$OUT/xcodebuild-$name.log"
  local start=$SECONDS
  if xcodebuild "$@" MARKETING_VERSION="$VELA_VERSION" CURRENT_PROJECT_VERSION="$VELA_BUILD_NUMBER" > "$log" 2>&1; then
    tail -n 3 "$log"
    echo "($name: $((SECONDS - start)) s)"
    return 0
  fi
  echo "xcodebuild $name failed after $((SECONDS - start)) s. Error lines:"
  grep -E "error:|\*\* .* FAILED \*\*|Test Case .* failed|: failed|Failing tests" "$log" | head -n 100 || true
  echo "--- tail of $name log ---"
  tail -n 60 "$log"
  return 1
}

install_xcodegen() {
  if command -v xcodegen > /dev/null; then
    XCODEGEN="$(command -v xcodegen)"
    return
  fi
  if curl -fsSL -o "$WORK/xcodegen.zip" \
      "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"; then
    unzip -q "$WORK/xcodegen.zip" -d "$WORK/xcodegen"
    XCODEGEN="$(find "$WORK/xcodegen" -type f -name xcodegen -perm -u+x | head -n 1)"
  fi
  if [ -z "${XCODEGEN:-}" ]; then
    brew install xcodegen
    XCODEGEN="$(command -v xcodegen)"
  fi
}

# Sums tests= and failures= over the JUnit XML files of one Gradle test task.
junit_counts() {
  cat "$1"/*.xml 2> /dev/null | python3 -c '
import re, sys
suites = re.findall(r"<testsuite [^>]*>", sys.stdin.read())
def count(key):
    return sum(int(re.search(key + "=.([0-9]+)", s).group(1)) for s in suites)
if suites:
    print(count("tests"), "tests,", count("failures") + count("errors"), "failures")
else:
    print("no results")
'
}

pick_simulator() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
ios = [(rt, d) for rt, ds in devices.items() if ".iOS-" in rt for d in ds]
pick = ([d for rt, d in ios if d["name"] == "iPhone 17" and rt.endswith("iOS-26-5")]
        or [d for rt, d in ios if d["name"] == "iPhone 17"]
        or [d for rt, d in ios if d["name"].startswith("iPhone")])
print(pick[0]["udid"] if pick else "")
'
}

note "commit: $(git -C "$ROOT" log -1 --format='%h %s')"
note "xcode: $(xcodebuild -version | tr '\n' ' ')"
note "version: $VELA_VERSION ($VELA_BUILD_NUMBER)"

# Gradle runs here and again from the Xcode build phase (iosApp/scripts/build-velacore.sh), which
# inherits JAVA_HOME and VELA_GRADLE_FLAGS from this environment.
export JAVA_HOME="${JAVA_HOME_17_arm64:-${JAVA_HOME:-}}"
export VELA_GRADLE_FLAGS="--no-daemon"
note "java: $("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1)"

step "Kotlin: tests and the VelaCore framework"
# Links both frameworks the Xcode builds below need, so their build phase only copies them, and
# runs the shared Kotlin tests on the JVM and in the simulator. --continue: a failing test still
# leaves the frameworks for the app build.
gradle_start=$SECONDS
FW_SIM="$ROOT/ios-shared/build/bin/iosSimulatorArm64/debugFramework/VelaCore.framework"
FW_DEV="$ROOT/ios-shared/build/bin/iosArm64/releaseFramework/VelaCore.framework"
if ./gradlew --no-daemon --continue -Pvela.iosOnly=true \
    :ios-shared:linkDebugFrameworkIosSimulatorArm64 :ios-shared:linkReleaseFrameworkIosArm64 \
    :ios-shared:jvmTest :ios-shared:iosSimulatorArm64Test > "$OUT/gradle.log" 2>&1; then
  note "gradle: ok in $((SECONDS - gradle_start)) s"
else
  note "gradle: FAILED after $((SECONDS - gradle_start)) s"
  grep -E "^e: |FAILED|What went wrong" -A 3 "$OUT/gradle.log" | head -n 60 || true
  tail -n 40 "$OUT/gradle.log"
  failures+=(gradle)
  [ -d "$FW_SIM" ] && [ -d "$FW_DEV" ] || { note "VelaCore framework missing, stopping"; exit 1; }
fi
for t in jvmTest iosSimulatorArm64Test; do
  note "kotlin $t: $(junit_counts "$ROOT/ios-shared/build/test-results/$t")"
done
for fw in "$FW_SIM" "$FW_DEV"; do
  note "VelaCore.framework $(basename "$(dirname "$(dirname "$fw")")")/$(basename "$(dirname "$fw")"): $(du -sh "$fw" | cut -f1), static library $(stat -f%z "$fw/VelaCore") bytes, SKIE Swift module: $([ -d "$fw/Modules/VelaCore.swiftmodule" ] && echo yes || echo no)"
done

step "String Catalog"
python3 "$ROOT/scripts/ios/strings_to_xcstrings.py" \
  --out "$ROOT/iosApp/Vela/Resources/Localizable.xcstrings" --report \
  > /dev/null 2> "$OUT/strings-report.txt"
catalog_summary="$(python3 "$ROOT/scripts/ios/check_ios_strings.py")"
note "$catalog_summary"

step "XcodeGen"
install_xcodegen
note "xcodegen: $("$XCODEGEN" --version 2>&1 | tail -n 1)"

step "Generate the project"
cd "$ROOT/iosApp"
"$XCODEGEN" generate --spec project.yml --quiet
ls -d Vela.xcodeproj Vela/Info.plist

step "Resolve packages"
xb resolve -resolvePackageDependencies -project Vela.xcodeproj -scheme Vela \
  -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$SPM"
resolved="$(find Vela.xcodeproj -name Package.resolved | head -n 1)"
[ -n "$resolved" ] && note "packages: $(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(" ".join(x["identity"]+"@"+x["state"].get("version","?") for x in p["pins"]))' "$resolved")"

step "Pick a simulator"
UDID="$(pick_simulator)"
[ -n "$UDID" ] || { note "no iPhone simulator available"; exit 1; }
note "simulator: $(xcrun simctl list devices available | grep "$UDID" | sed 's/^ *//') runtime $(xcrun simctl list devices available | awk -v u="$UDID" '/^-- /{rt=$0} index($0,u){print rt}')"
DEST="platform=iOS Simulator,id=$UDID"
SIM_FLAGS=(-project Vela.xcodeproj -scheme Vela -configuration Debug -destination "$DEST"
  -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$SPM" CODE_SIGNING_ALLOWED=NO)

step "Build for the simulator"
xb build-sim build-for-testing "${SIM_FLAGS[@]}"
note "simulator build: ok"

step "Boot the simulator"
# Booted before the unit tests so the app's info lines (the calibration version) persist in the
# simulator's log from its first launch on.
xcrun simctl boot "$UDID" 2> /dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null || note "simulator boot status failed"
sim_log_persist "$UDID" || note "log persistence not set"

step "Unit tests"
if xb test test-without-building "${SIM_FLAGS[@]}" -only-testing:VelaTests; then
  note "tests: ok, $(grep -oE 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$OUT/xcodebuild-test.log" | tail -n 1 || echo 'count not found')"
else
  note "tests: FAILED"
  failures+=(tests)
fi
grep -oE "SEAM_TEST .*" "$OUT/xcodebuild-test.log" | sort -u | while read -r line; do note "${line#SEAM_TEST }"; done || true

step "Launch and screenshot"
APP="$DD/Build/Products/Debug-iphonesimulator/Vela.app"
launch_and_shoot() {
  xcrun simctl boot "$UDID" 2> /dev/null || true
  xcrun simctl bootstatus "$UDID" -b > /dev/null || return 1
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 || true
  xcrun simctl install "$UDID" "$APP" || return 1
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -VelaDeterministic YES || return 1
  sleep 20
  xcrun simctl io "$UDID" screenshot "$OUT/screenshot.png" || return 1
}
if launch_and_shoot; then
  note "screenshot: saved 20 s after launch"
else
  note "screenshot: FAILED"
  failures+=(screenshot)
fi
running="$(xcrun simctl spawn "$UDID" launchctl list 2> /dev/null || true)"
if grep -q "$BUNDLE_ID" <<< "$running"; then
  note "app running after 20 s: yes"
else
  note "app running after 20 s: NO"
  failures+=(launch)
fi

step "UI scenarios"
# Every class in VelaUITests (docs/ios/TESTING-IOS.md): launch over the fixture cameras, search
# "coffee" over San Francisco, live calibration. Screenshots go to SHOT_DIR (TEST_RUNNER_
# variables reach the test runner); UITEST key=value lines go to the summary.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2> /dev/null || true
sim_location_grant "$UDID" "$BUNDLE_ID" || note "location grant failed"
sim_location_set "$UDID" sf || note "simulated location failed"
SHOTS="$WORK/shots"
mkdir -p "$SHOTS"
export TEST_RUNNER_SHOT_DIR="$SHOTS"
# The iOS UI-test target cannot launch simctl itself. This host watcher starts Market Street when
# NavModel reports that guidance began, then restores the fixed point after End.
sim_route_arm "$UDID" sf-market 20 1
NAV_REPLAY_PID="$SIM_ROUTE_ARM_PID"
ui_only=(-only-testing:VelaUITests)
if [ -n "${VELA_ONLY_UI:-}" ]; then
  ui_only=(-only-testing:"VelaUITests/$VELA_ONLY_UI")
fi
if xb uitest test-without-building "${SIM_FLAGS[@]}" "${ui_only[@]}" \
    -resultBundlePath "$WORK/uitest.xcresult"; then
  note "ui scenarios: ok"
else
  note "ui scenarios: FAILED"
  failures+=(ui-scenarios)
fi
sim_route_disarm "$NAV_REPLAY_PID"
unset TEST_RUNNER_SHOT_DIR
grep -oE "Test Case '-\[VelaUITests\.[A-Za-z]+ [A-Za-z]+\]' (passed|failed) \([0-9.]+ seconds\)" "$OUT/xcodebuild-uitest.log" \
  | sed -E "s/Test Case '-\[VelaUITests\.([A-Za-z]+) ([A-Za-z]+)\]' /ui \1.\2: /" | while read -r line; do note "$line"; done || true
grep -oE "UITEST [a-z0-9_]+=[^ ]+" "$OUT/xcodebuild-uitest.log" | sort -u | while read -r line; do note "ui ${line#UITEST }"; done || true
if ! ls "$SHOTS"/*.png > /dev/null 2>&1 && [ -d "$WORK/uitest.xcresult" ]; then
  xcrun xcresulttool export attachments --path "$WORK/uitest.xcresult" --output-path "$SHOTS" > /dev/null 2>&1 || true
fi
for shot in "$SHOTS"/*.png; do
  [ -e "$shot" ] && cp "$shot" "$OUT/"
done
note "ui screenshots: $(cd "$OUT" && ls launch-*.png search-*.png place-*.png directions-*.png nav-*.png suggest.png category.png map-poi.png settings-*.png calibration.png 2> /dev/null | tr '\n' ' ')"

step "Route replay"
# A simulated drive down Market Street with the map following the user: prepares the navigation
# scenarios (docs/ios/TESTING-IOS.md). Two screenshots, the second after the puck has moved.
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" \
  -VelaStartCamera sf -VelaDeterministic YES -VelaFollowUser YES > /dev/null || note "route replay launch failed"
sleep 8
if sim_route_start "$UDID" sf-market 20 1; then
  sleep 4
  sim_shot "$UDID" "$OUT/route-1.png" || true
  sleep 40
  sim_shot "$UDID" "$OUT/route-2.png" || true
  note "route replay: sf-market at 20 m/s, route-1.png and route-2.png"
else
  note "route replay: FAILED to start"
  failures+=(route-replay)
fi
sim_location_clear "$UDID" || true

sim_collect_logs "$UDID" "$OUT" 20
cal_start="$(grep -m1 -oE "calibration at startup: version [0-9]+" "$OUT/velacore-log.txt" || true)"
cal_live="$(grep -oE "calibration after refresh: version [0-9]+" "$OUT/velacore-log.txt" | awk '{print $NF}' | sort -n | tail -n 1 || true)"
note "calibration log: ${cal_start:-no startup line}; highest after refresh: ${cal_live:-none}"
# The place sheet's loads (PlaceStore, PlaceLoad tag) and the hidden page (Web category).
grep -oE "(details|photos|reviews): [^\"]*" "$OUT/velacore-log.txt" | head -n 12 | while read -r line; do note "place load: $line"; done || true
grep -oE "reviews: (page asked for|answered|given up|injecting)[^\"]*|web content process terminated|blocked hosts: [^\"]*" "$OUT/velacore-log.txt" \
  | head -n 8 | while read -r line; do note "web: $line"; done || true
ui_cal="$(grep -m1 -oE "UITEST calibration_version=[0-9]+" "$OUT/xcodebuild-uitest.log" | cut -d= -f2 || true)"
if [ "${ui_cal:-0}" -ge 27 ] 2> /dev/null; then
  note "live calibration: version $ui_cal"
else
  note "live calibration: NOT LOADED (${ui_cal:-no value})"
  failures+=(calibration)
fi
kotlin_line="$(grep -m1 -E "Kotlin call (ok|failed)" "$OUT/velacore-log.txt" || true)"
if grep -q "Kotlin call ok" <<< "$kotlin_line"; then
  note "kotlin call at launch: ${kotlin_line#*Kotlin call ok: }"
else
  note "kotlin call at launch: NOT FOUND ${kotlin_line:+($kotlin_line)}"
  failures+=(kotlin-call)
fi
xcrun simctl shutdown "$UDID" || true

step "Record a search reply"
# One raw "coffee" reply for San Francisco from this runner, with the iOS identity, kept as a
# parser fixture. Python's HTTP stack, not Apple's: only the reply's shape matters here.
python3 - "$ROOT/calibration.json" "$OUT/search-coffee-sf.txt" << 'PY' || note "search reply: not recorded"
import http.cookiejar, json, sys, urllib.parse, urllib.request
cal = json.load(open(sys.argv[1]))
ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
jar = http.cookiejar.CookieJar()
for name, value in (("SOCS", "CAESHAgBEhIaAB"), ("CONSENT", "YES+")):
    jar.set_cookie(http.cookiejar.Cookie(0, name, value, None, False, ".google.com", True, True, "/", True,
                                         True, None, False, None, None, {}))
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
base = {"User-Agent": ua, "Accept-Language": "en-US,en;q=0.9"}
opener.open(urllib.request.Request(cal["sessionWarmUrl"], headers=dict(base, **{
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Sec-Fetch-Dest": "document", "Sec-Fetch-Mode": "navigate", "Sec-Fetch-Site": "none"})), timeout=30).read()
pb = cal["searchPb"].replace("{QUERY}", "coffee").replace("{LAT}", "37.7749").replace("{LNG}", "-122.4194")
url = cal["searchEndpoint"] + "&q=coffee&pb=" + urllib.parse.quote_plus(pb, safe="*")
body = opener.open(urllib.request.Request(url, headers=dict(base, **{
    "Accept": "*/*", "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin",
    "Referer": "https://www.google.com/maps"})), timeout=30).read()
open(sys.argv[2], "wb").write(body)
print(len(body))
# Directions from the San Francisco point to the Ferry Building (the sf-market fixture's ends),
# driving (1e0) and walking (1e2), kept as RouteStore parser fixtures.
for mode, name in (("0", "drive"), ("2", "walk")):
    pb = (cal["directionsPb"].replace("{OLAT}", "37.7749").replace("{OLNG}", "-122.4194")
          .replace("{DLAT}", "37.7942").replace("{DLNG}", "-122.3946").replace("{MODE}", mode))
    url = cal["directionsEndpoint"] + "&pb=" + urllib.parse.quote_plus(pb, safe="*")
    try:
        body = opener.open(urllib.request.Request(url, headers=dict(base, **{
            "Accept": "*/*", "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin",
            "Referer": "https://www.google.com/maps"})), timeout=30).read()
        open(sys.argv[2].replace("search-coffee-sf", "directions-%s-sf" % name), "wb").write(body)
    except Exception as e:
        print("directions %s: %s" % (name, e))
# The open router's answers for the same trip (the hybrid's steps) and the transit planner's.
vela = {"User-Agent": "VelaMaps/0.4"}
for backend, name in (("routed-car", "osrm-car"), ("routed-foot", "osrm-foot")):
    url = ("https://routing.openstreetmap.de/%s/route/v1/driving/-122.4194,37.7749;-122.3946,37.7942"
           "?overview=full&geometries=polyline6&steps=true&alternatives=3" % backend)
    try:
        body = urllib.request.urlopen(urllib.request.Request(url, headers=vela), timeout=30).read()
        open(sys.argv[2].replace("search-coffee-sf", "%s-sf" % name), "wb").write(body)
    except Exception as e:
        print("%s: %s" % (name, e))
try:
    url = ("https://api.transitous.org/api/v1/plan?fromPlace=37.7749,-122.4194&toPlace=37.7942,-122.3946"
           "&numItineraries=5&language=en")
    body = urllib.request.urlopen(urllib.request.Request(url, headers=vela), timeout=30).read()
    open(sys.argv[2].replace("search-coffee-sf", "transit-plan-sf"), "wb").write(body)
except Exception as e:
    print("transit plan: %s" % e)
PY
for f in osrm-car-sf osrm-foot-sf transit-plan-sf; do
  if [ -s "$OUT/$f.txt" ]; then
    note "open reply: $f $(stat -f%z "$OUT/$f.txt") bytes"
    gzip -9f "$OUT/$f.txt"
  else
    note "open reply: $f not recorded"
  fi
done
for f in directions-drive-sf directions-walk-sf; do
  if [ -s "$OUT/$f.txt" ]; then
    note "directions reply: $f $(stat -f%z "$OUT/$f.txt") bytes"
    gzip -9f "$OUT/$f.txt"
  else
    note "directions reply: $f not recorded"
  fi
done
if [ -s "$OUT/search-coffee-sf.txt" ]; then
  note "search reply: $(stat -f%z "$OUT/search-coffee-sf.txt") bytes, $(grep -oE '0x[0-9a-f]+:0x[0-9a-f]+' "$OUT/search-coffee-sf.txt" | sort -u | wc -l | tr -d ' ') feature ids"
  gzip -9f "$OUT/search-coffee-sf.txt"
fi

if [ "${VELA_SKIP_ARCHIVE:-0}" = 1 ]; then
  if ((${#failures[@]})); then
    printf 'failed steps: %s\n' "${failures[*]}" | tee -a "$SUMMARY"
    exit 1
  fi
  exit 0
fi

step "Archive for iOS devices, unsigned"
ARCHIVE="$WORK/Vela.xcarchive"
xb archive archive -project Vela.xcodeproj -scheme Vela -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
  -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$SPM" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

step "Package the IPA"
mkdir -p "$WORK/ipa/Payload"
cp -R "$ARCHIVE/Products/Applications/Vela.app" "$WORK/ipa/Payload/"
rm -f "$OUT/Vela-unsigned.ipa"
(cd "$WORK/ipa" && zip -qry "$OUT/Vela-unsigned.ipa" Payload)
APP_DEVICE="$WORK/ipa/Payload/Vela.app"
ipa_bytes="$(stat -f%z "$OUT/Vela-unsigned.ipa")"
note "ipa: Vela-unsigned.ipa $ipa_bytes bytes ($(du -h "$OUT/Vela-unsigned.ipa" | cut -f1))"
note "app frameworks: $(ls "$APP_DEVICE/Frameworks" 2> /dev/null | tr '\n' ' ')"
note "app binary: $(lipo -archs "$APP_DEVICE/Vela"), $(stat -f%z "$APP_DEVICE/Vela") bytes"
APPEX="$APP_DEVICE/PlugIns/NavActivityExtension.appex"
if [ -f "$APPEX/NavActivityExtension" ] \
    && unzip -l "$OUT/Vela-unsigned.ipa" \
    | grep -q "Payload/Vela.app/PlugIns/NavActivityExtension.appex/NavActivityExtension"; then
  note "live activity extension: PlugIns/NavActivityExtension.appex present in IPA, $(stat -f%z "$APPEX/NavActivityExtension") bytes"
else
  note "live activity extension: MISSING from IPA"
  failures+=(live-activity-extension)
fi
if [ -f "$APPEX/NavActivityExtension" ]; then
  note "extension plist CFBundleIdentifier: $(plutil -extract CFBundleIdentifier raw -o - "$APPEX/Info.plist")"
  note "extension plist NSExtensionPointIdentifier: $(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$APPEX/Info.plist")"
  if codesign -dv "$APPEX" > /dev/null 2>&1; then
    note "extension signing: PRESENT in unsigned archive"
    failures+=(live-activity-signing)
  else
    note "extension signing: none"
  fi
fi
# The Objective-C name of IosGraph survives stripping: present only if the Kotlin code is linked.
note "kotlin code in the device binary: $(grep -q -a "VelaCoreIosGraph" "$APP_DEVICE/Vela" && echo yes || echo NO)"
for key in CFBundleIdentifier CFBundleDisplayName CFBundleShortVersionString MinimumOSVersion UIBackgroundModes NSSupportsLiveActivities; do
  # json handles arrays and fails on bare scalars, which raw prints.
  value="$(plutil -extract "$key" json -o - "$APP_DEVICE/Info.plist" 2> /dev/null \
    || plutil -extract "$key" raw -o - "$APP_DEVICE/Info.plist" 2> /dev/null || echo missing)"
  note "plist $key: $value"
done

echo
echo "== Summary"
cat "$SUMMARY"
if [ "${#failures[@]}" -gt 0 ]; then
  echo "failed steps: ${failures[*]}" | tee -a "$SUMMARY"
  exit 1
fi
