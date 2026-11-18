#!/usr/bin/env bash
# Builds and tests :core-common for iOS on the macOS runner (PORTAGE_IOS.md section 4), with no
# Android SDK: -Pvela.iosOnly=true leaves the Android modules out of the build. Runs from the
# source root; writes the Gradle log and the test reports to $OUT.
set -uo pipefail
: "${OUT:?OUT is not set}"
export JAVA_HOME="${JAVA_HOME_17_arm64:-${JAVA_HOME:-}}"
echo "JAVA_HOME=$JAVA_HOME"
java -version 2>&1 | head -1

start=$(date +%s)
./gradlew --no-daemon --stacktrace -Pvela.iosOnly=true \
    :core-common:jvmTest \
    :core-common:iosSimulatorArm64Test \
    :core-common:compileKotlinIosArm64 \
    2>&1 | tee "$OUT/gradle.log"
status=${PIPESTATUS[0]}
echo "gradle exit $status in $(( $(date +%s) - start )) s" | tee "$OUT/summary.txt"

results=core-common/build/test-results
if [ -d "$results" ]; then
    cp -R "$results" "$OUT/test-results"
    for dir in "$results"/*/; do
        name=$(basename "$dir")
        tests=0 failures=0 errors=0 skipped=0
        for f in "$dir"*.xml; do
            [ -f "$f" ] || continue
            line=$(grep -m1 -o '<testsuite [^>]*>' "$f")
            for k in tests failures errors skipped; do
                v=$(printf '%s' "$line" | sed -n "s/.* $k=\"\([0-9]*\)\".*/\1/p")
                eval "$k=\$(( $k + ${v:-0} ))"
            done
        done
        echo "$name: tests=$tests failures=$failures errors=$errors skipped=$skipped" | tee -a "$OUT/summary.txt"
    done
fi
[ -d core-common/build/reports/tests ] && cp -R core-common/build/reports/tests "$OUT/test-reports"
exit "$status"
