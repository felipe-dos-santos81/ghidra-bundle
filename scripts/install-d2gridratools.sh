#!/bin/bash
# Assembles the D2GridraTools scripts (Diablo 2 1.14d) into a minimal Ghidra extension
# whose scripts run under the Jython extension. Run it via `make install-scripts`.
# The checkout is never modified; only the copies get a "#@runtime Jython" line,
# because PyGhidra would otherwise claim these Python 2 scripts.
# D2GridraTools has no license: it is fetched from upstream, never redistributed.
#
# Usage: install-d2gridratools.sh <D2GridraTools checkout> <Ghidra Extensions dir> <Ghidra version>
set -euo pipefail

usage="usage: install-d2gridratools.sh <checkout> <Ghidra Extensions dir> <Ghidra version>"
SRC=${1:?$usage}
EXT_DIR=${2:?$usage}
VERSION=${3:?$usage}
DEST="$EXT_DIR/D2GridraTools"

commit=$(git -C "$SRC" rev-parse HEAD)
if [[ -f "$DEST/.bundle-source" && "$(cat "$DEST/.bundle-source")" == "$commit" ]]; then
  echo "D2GridraTools already installed from ${commit:0:7}, skipping."
  exit 0
fi

shopt -s nullglob
scripts=("$SRC"/*.py)
((${#scripts[@]} > 0)) || { echo "ERROR: no .py scripts in $SRC" >&2; exit 1; }

tmp=$(mktemp -d "$EXT_DIR/.D2GridraTools-XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/ghidra_scripts"
cat > "$tmp/extension.properties" <<PROPS
name=D2GridraTools
description=Diablo 2 1.14d scripts by dzik87 (github.com/dzik87/D2GridraTools), run under Jython. Unlicensed upstream: fetched, not redistributed.
author=dzik87
createdOn=
version=$VERSION
PROPS
: > "$tmp/Module.manifest"

for script in "${scripts[@]}"; do
  out="$tmp/ghidra_scripts/$(basename "$script")"
  if grep -q '@runtime' "$script"; then
    cp "$script" "$out"
  else
    # Ghidra reads script metadata from the leading comment block; tag it at its end.
    awk 'BEGIN { tagged = 0 }
         !tagged && !/^#/ { print "#@runtime Jython"; tagged = 1 }
         { print }
         END { if (!tagged) print "#@runtime Jython" }' "$script" > "$out"
  fi
done

echo "$commit" > "$tmp/.bundle-source"
rm -rf "$DEST"
mv "$tmp" "$DEST"
trap - EXIT
echo "D2GridraTools installed from ${commit:0:7} (${#scripts[@]} scripts)."
