#!/usr/bin/env bash
# Prints the macOS runner's toolchain, for the iOS port (PORTAGE_IOS.md section 4).
set -u
echo "OUT=$OUT"
xcodebuild -version
xcrun simctl list runtimes | head -20
xcrun simctl list devices available | grep -E 'iPhone' | head -5
ls /Applications | grep -i xcode
for t in xcodegen brew java swift ruby; do printf '%s: ' "$t"; command -v "$t" || echo missing; done
/usr/libexec/java_home -V 2>&1 | head -10
echo "JAVA_HOME_17_arm64=${JAVA_HOME_17_arm64:-unset} JAVA_HOME_17_X64=${JAVA_HOME_17_X64:-unset}"
sysctl -n machdep.cpu.brand_string; sysctl -n hw.ncpu; echo "$(($(sysctl -n hw.memsize) / 1073741824)) GB"
df -h / | tail -1
echo hello > "$OUT/hello.txt"
