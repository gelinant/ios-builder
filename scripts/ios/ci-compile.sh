#!/usr/bin/env bash
# Compile-only check for the iOS app: generate the project and build it for the simulator, no tests
# and no archive. Used to validate a merge before spending a full run (docs/ios/HIVE.md):
# 5 to 8 minutes when the Gradle and SPM caches are warm.
# Run from the source root with OUT set.
set -euo pipefail
: "${OUT:?OUT must be set}"
mkdir -p "$OUT"
ROOT="$(pwd)"
note() { echo "$*" | tee -a "$OUT/summary.txt"; }
step() { echo; echo "== $*"; }

WORK="$(mktemp -d "${TMPDIR:-$HOME/.tmp}/ios-compile.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
DD="$HOME/Library/Developer/Xcode/DerivedData/Vela-ci"
SPM="$DD/SourcePackages"
XCODEGEN_VERSION=2.46.0

export JAVA_HOME="${JAVA_HOME_17_arm64:-$JAVA_HOME}"
VELA_BUILD_ID="${VELA_BUILD_ID:-$(date -u +%Y%m%d%H%M)}"

step "Voice framework"
bash "$ROOT/scripts/ios/fetch-sherpa.sh" >> "$OUT/sherpa.log" 2>&1 || {
  echo "sherpa-onnx fetch failed; tail:"; tail -n 20 "$OUT/sherpa.log"; exit 1; }

step "String catalog"
mkdir -p "$ROOT/iosApp/Vela/Resources"
python3 "$ROOT/scripts/ios/strings_to_xcstrings.py" --res "$ROOT/app/src/main/res" \
  --out "$ROOT/iosApp/Vela/Resources/Localizable.xcstrings" \
  > /dev/null 2> "$OUT/strings-report.txt" || note "catalog generation failed (continuing)"

step "XcodeGen"
if ! command -v xcodegen > /dev/null; then
  curl -fsSL -o "$WORK/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
  unzip -q "$WORK/xcodegen.zip" -d "$WORK/xcodegen"
  XCODEGEN="$(find "$WORK/xcodegen" -type f -name xcodegen -perm -u+x | head -n 1)"
else
  XCODEGEN="$(command -v xcodegen)"
fi
note "xcodegen: $("$XCODEGEN" --version 2>&1 | tail -n 1)"

step "Generate and build"
cd "$ROOT/iosApp"
"$XCODEGEN" generate --spec project.yml --quiet
UDID="$(xcrun simctl list devices available | sed -n 's/^ *iPhone [^(]*(\([0-9A-F-]\{36\}\)) (Shutdown).*/\1/p' | head -n 1)"
[ -n "$UDID" ] || { note "no iPhone simulator available"; exit 1; }
note "simulator: $UDID"
xcodebuild build \
  -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$SPM" \
  MARKETING_VERSION="0.1.$VELA_BUILD_ID" CURRENT_PROJECT_VERSION="$(date -u +%s)" \
  CODE_SIGNING_ALLOWED=NO > "$OUT/xcodebuild-compile.log" 2>&1 || {
    echo "compile failed; errors:"
    grep -E "error:" "$OUT/xcodebuild-compile.log" | head -n 40
    tail -n 40 "$OUT/xcodebuild-compile.log"
    exit 1; }
note "simulator build: ok"

gzip -9f "$OUT/xcodebuild-compile.log" 2> /dev/null || true
echo ok > "$OUT/STATUS"
echo "compile check green"
