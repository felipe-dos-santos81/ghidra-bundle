#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHIDRA_SRC_DIR="$REPO_DIR/ghidra"

if [[ ! -d "$GHIDRA_SRC_DIR" ]]; then
  echo "ERROR: $GHIDRA_SRC_DIR does not exist. Run 'make checkout' first."
  exit 1
fi

cd "$GHIDRA_SRC_DIR"

if [[ -z "${JAVA_HOME:-}" ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -F -v 21 2>/dev/null)"
fi
export JAVA_HOME

if [[ -z "$JAVA_HOME" || ! -d "$JAVA_HOME" ]]; then
  echo "ERROR: JAVA_HOME for JDK 21 could not be resolved."
  exit 1
fi

echo "Using JAVA_HOME=$JAVA_HOME"
java -version

if [[ ! -x "./gradlew" ]]; then
  echo "ERROR: ./gradlew not executable in $GHIDRA_SRC_DIR"
  exit 1
fi

if [[ ! -d "dependencies" ]]; then
  echo "Fetching Ghidra build dependencies..."
  ./gradlew -I gradle/support/fetchDependencies.gradle
fi

echo "Building Ghidra distribution zip..."
./gradlew buildGhidra --console=plain

echo "Ghidra build complete. Output artifacts:"
ls -lh build/dist/ghidra_12.1.2_*.zip
