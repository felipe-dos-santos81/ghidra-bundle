#!/bin/bash
# Builds the Ghidra distribution zip from the ghidra submodule into
# ghidra/build/dist/. Run it via `make build-ghidra`, which exports JAVA_HOME
# for JDK 21.
set -euo pipefail

GHIDRA_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ghidra"

if [[ ! -x "$GHIDRA_SRC_DIR/gradlew" ]]; then
  echo "ERROR: $GHIDRA_SRC_DIR/gradlew not found. Run 'make checkout' first." >&2
  exit 1
fi
if [[ -z "${JAVA_HOME:-}" ]] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "21'; then
  echo "ERROR: JAVA_HOME must point to a JDK 21 (got '${JAVA_HOME:-}'). Run 'make build-ghidra'." >&2
  exit 1
fi
export PATH="$JAVA_HOME/bin:$PATH"
echo "Using JAVA_HOME=$JAVA_HOME"

cd "$GHIDRA_SRC_DIR"

if [[ ! -d dependencies/flatRepo ]]; then
  echo "Fetching Ghidra build dependencies..."
  ./gradlew -I gradle/support/fetchDependencies.gradle
fi

echo "Building Ghidra distribution zip..."
./gradlew buildGhidra --console=plain

version="$(sed -n 's/^application\.version=//p' Ghidra/application.properties)"
ls -lh build/dist/ghidra_"${version}"_*.zip
