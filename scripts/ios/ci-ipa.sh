#!/usr/bin/env bash
# Builds, tests and packages the Vela iOS app on the macOS runner (docs/ios/BUILD-IOS.md).
# Run from the source root with OUT set. Writes to $OUT: summary.txt, screenshot.png,
# Vela-unsigned.ipa, app-log.txt, velacore-log.txt, gradle.log and one xcodebuild-<step>.log per
# xcodebuild call. Test, screenshot, launch and Kotlin call failures are reported and the script
# goes on to the archive; it exits non-zero at the end if any step failed.
set -euo pipefail

: "${OUT:?OUT must be set}"
mkdir -p "$OUT"
ROOT="$(pwd)"
WORK="$(mktemp -d)"
XCODEGEN_VERSION=2.46.0
BUNDLE_ID=app.vela.ios
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
  if xcodebuild "$@" > "$log" 2>&1; then
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

step "Unit tests"
if xb test test-without-building "${SIM_FLAGS[@]}"; then
  note "tests: ok, $(grep -m1 -oE 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$OUT/xcodebuild-test.log" || echo 'count not found')"
else
  note "tests: FAILED"
  failures+=(tests)
fi

step "Launch and screenshot"
APP="$DD/Build/Products/Debug-iphonesimulator/Vela.app"
launch_and_shoot() {
  xcrun simctl boot "$UDID" 2> /dev/null || true
  xcrun simctl bootstatus "$UDID" -b > /dev/null || return 1
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 || true
  xcrun simctl install "$UDID" "$APP" || return 1
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" || return 1
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
xcrun simctl spawn "$UDID" log show --last 2m --style compact --predicate 'process == "Vela"' 2> /dev/null \
  | tail -n 300 > "$OUT/app-log.txt" || true
xcrun simctl spawn "$UDID" log show --last 2m --style compact --predicate 'subsystem == "app.vela.ios"' 2> /dev/null \
  > "$OUT/velacore-log.txt" || true
kotlin_line="$(grep -m1 -E "Kotlin call (ok|failed)" "$OUT/velacore-log.txt" || true)"
if grep -q "Kotlin call ok" <<< "$kotlin_line"; then
  note "kotlin call at launch: ${kotlin_line#*Kotlin call ok: }"
else
  note "kotlin call at launch: NOT FOUND ${kotlin_line:+($kotlin_line)}"
  failures+=(kotlin-call)
fi
xcrun simctl shutdown "$UDID" || true

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
# The Objective-C name of IosGraph survives stripping: present only if the Kotlin code is linked.
note "kotlin code in the device binary: $(grep -q -a "VelaCoreIosGraph" "$APP_DEVICE/Vela" && echo yes || echo NO)"
for key in CFBundleIdentifier CFBundleDisplayName CFBundleShortVersionString MinimumOSVersion UIBackgroundModes; do
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
