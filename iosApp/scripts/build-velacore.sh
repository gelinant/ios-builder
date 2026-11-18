#!/usr/bin/env bash
# Pre-build phase of the Vela target (iosApp/project.yml): builds the Kotlin framework VelaCore
# (module :ios-shared) for the SDK, architecture and configuration Xcode is building, into
# ios-shared/build/xcode-frameworks/$CONFIGURATION/$SDK_NAME, where FRAMEWORK_SEARCH_PATHS points.
# JDK: $JAVA_HOME if it holds a java, else the JDK 17 that /usr/libexec/java_home finds.
# VELA_GRADLE_FLAGS adds Gradle flags (CI sets --no-daemon).
set -euo pipefail

if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 17 2> /dev/null || /usr/libexec/java_home -v 17+ 2> /dev/null || true)"
fi
if [ -z "$JAVA_HOME" ]; then
  echo "error: building VelaCore needs a JDK 17 or newer (brew install openjdk@17, or set JAVA_HOME)"
  exit 1
fi
export JAVA_HOME

cd "$SRCROOT/.."
# shellcheck disable=SC2086 # VELA_GRADLE_FLAGS is a list of flags.
./gradlew ${VELA_GRADLE_FLAGS:-} -Pvela.iosOnly=true :ios-shared:embedAndSignAppleFrameworkForXcode
