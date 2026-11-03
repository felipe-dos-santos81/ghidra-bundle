#!/bin/bash
# Assembles the LLM4Decompile refine script into a scripts-only Ghidra extension (so the
# Script Manager finds it) and pulls its model into Ollama. Run it via
# `make install-llm4decompile`. The extension is always assembled; the pull is skipped
# with a warning when Ollama is absent or not serving, so the script can still be pointed
# at a model pulled later or served elsewhere (LLM4DECOMPILE_URL).
#
# Usage: install-llm4decompile.sh <LLM4DecompileRefine.java> <Ghidra Extensions dir> <Ghidra version> <model> <ollama url>
set -euo pipefail

usage="usage: install-llm4decompile.sh <script> <Ghidra Extensions dir> <Ghidra version> <model> <ollama url>"
SCRIPT=${1:?$usage}
EXT_DIR=${2:?$usage}
VERSION=${3:?$usage}
MODEL=${4:?$usage}
URL=${5:?$usage}
DEST="$EXT_DIR/LLM4Decompile"

warn() { printf '\033[33m%s\033[0m\n' "$1"; }

# Reinstall when the script, this installer, the model or the URL changes.
stamp="$(git hash-object "$SCRIPT") $(git hash-object "${BASH_SOURCE[0]}") $MODEL $URL"
if [[ -f "$DEST/.bundle-source" && "$(cat "$DEST/.bundle-source")" == "$stamp" ]]; then
  echo "LLM4Decompile scripts already installed, skipping."
else
  tmp=$(mktemp -d "$EXT_DIR/.LLM4Decompile-XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/ghidra_scripts"
  cat > "$tmp/extension.properties" <<PROPS
name=LLM4Decompile
description=Refines a function's pseudo-C with the LLM4Decompile model $MODEL served by Ollama (github.com/albertan017/LLM4Decompile). Script: LLM4DecompileRefine.java.
author=ghidra-bundle
createdOn=
version=$VERSION
PROPS
  : > "$tmp/Module.manifest"
  printf 'model=%s\nurl=%s\n' "$MODEL" "$URL" > "$tmp/llm4decompile.properties"
  cp "$SCRIPT" "$tmp/ghidra_scripts/LLM4DecompileRefine.java"
  echo "$stamp" > "$tmp/.bundle-source"
  rm -rf "$DEST"
  mv "$tmp" "$DEST"
  trap - EXIT
  echo "LLM4Decompile scripts installed in $DEST."
fi

if ! command -v ollama >/dev/null 2>&1 || ! ollama list >/dev/null 2>&1; then
  warn "WARNING: Ollama not found or not serving; skipping the LLM4Decompile model pull (optional). Pull it later with: ollama pull $MODEL"
  exit 0
fi
if ollama show "$MODEL" >/dev/null 2>&1; then
  echo "LLM4Decompile model $MODEL already pulled, skipping."
elif ollama pull "$MODEL"; then
  echo "LLM4Decompile model $MODEL pulled."
else
  warn "WARNING: could not pull $MODEL (no network or disk?); the LLM4Decompile script will fail until it is pulled."
fi
