#!/bin/bash
# Builds the Ghidra distribution zip from the ghidra submodule into
# ghidra/build/dist/. Run it via `make build-ghidra`, which exports JAVA_HOME
# for JDK 25.
set -euo pipefail

GHIDRA_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ghidra"

if [[ ! -x "$GHIDRA_SRC_DIR/gradlew" ]]; then
  echo "ERROR: $GHIDRA_SRC_DIR/gradlew not found. Run 'make checkout' first." >&2
  exit 1
fi
# Require a full JDK: both binaries must exist and report major 25, so a JRE-only
# or wrong-major JAVA_HOME fails here even when invoked without the Makefile.
if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/java" || ! -x "$JAVA_HOME/bin/javac" ]] || \
   ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "25' || \
   ! "$JAVA_HOME/bin/javac" -version 2>&1 | grep -q ' 25'; then
  echo "ERROR: JAVA_HOME must point to a full JDK 25 with bin/java and bin/javac (got '${JAVA_HOME:-}'). Run 'make build-ghidra'." >&2
  exit 1
fi
export PATH="$JAVA_HOME/bin:$PATH"
echo "Using JAVA_HOME=$JAVA_HOME"

cd "$GHIDRA_SRC_DIR"

# Keep the dependency cache in sync with this source checkout: fetch when flatRepo
# is missing or its marker differs from the submodule's HEAD (marker included).
# The marker is written only after a successful fetch and is git-ignored
# (flatRepo/ is in the ghidra submodule's .gitignore), so it never dirties the
# checkout. Without this, an upgraded checkout could silently reuse a stale cache.
SRC_COMMIT="$(git rev-parse HEAD)"
MARKER="dependencies/flatRepo/.bundle-source"
FETCH_REASON=""
if [[ ! -d dependencies/flatRepo ]]; then
  FETCH_REASON="dependency cache is missing"
elif [[ "$(cat "$MARKER" 2>/dev/null)" != "$SRC_COMMIT" ]]; then
  FETCH_REASON="source commit changed or marker missing"
fi
if [[ -n "$FETCH_REASON" ]]; then
  echo "Fetching Ghidra build dependencies ($FETCH_REASON)..."
  ./gradlew -I gradle/support/fetchDependencies.gradle
  echo "$SRC_COMMIT" > "$MARKER"
fi

echo "Building Ghidra distribution zip..."
./gradlew buildGhidra --console=plain

version="$(sed -n 's/^application\.version=//p' Ghidra/application.properties)"
ls -lh build/dist/ghidra_"${version}"_*.zip
