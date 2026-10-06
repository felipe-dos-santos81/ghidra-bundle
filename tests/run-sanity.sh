#!/bin/bash
# Sanity test suite for the Ghidra bundle; run it with `make test`.
# Design: docs/superpowers/specs/2026-10-06-sanity-test-design.md
#
# Usage: tests/run-sanity.sh <ghidra install dir> <JDK 21 home>
# Env:   UPDATE_SNAPSHOTS=1  rewrite tests/snapshots/ from this run
#        TEST_MCP_PORT=18089  port for the GhidraMCP test server (default 18089)
set -euo pipefail

INSTALL_DIR=${1:?usage: run-sanity.sh <ghidra install dir> <JDK 21 home>}
export JAVA_HOME=${2:?usage: run-sanity.sh <ghidra install dir> <JDK 21 home>}
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$REPO_DIR/tests"
HEADLESS="$INSTALL_DIR/support/analyzeHeadless"

PASSED=0
FAILED=0
RESULTS=()
pass() { PASSED=$((PASSED + 1)); RESULTS+=("PASS  $1"); }
fail() { FAILED=$((FAILED + 1)); RESULTS+=("FAIL  $1"); }
die() { printf '\033[31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }
indent() { sed 's/^/    /'; }

[[ -x "$HEADLESS" ]] || die "$HEADLESS not found; run 'make install' first."
for tool in clang python3 curl; do
  command -v "$tool" >/dev/null || die "$tool not found on PATH (run 'make deps')."
done

MCP_PORT="${TEST_MCP_PORT:-18089}"
WORK=$(mktemp -d "$INSTALL_DIR/portable/temp/sanity-XXXXXX")
MCP_PID=""
cleanup() {
  if [[ -n "$MCP_PID" ]]; then
    kill "$MCP_PID" 2>/dev/null || true
    wait "$MCP_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ── 1. Extension classes ──────────────────────────────────────────────────────
echo "Checking extension class discovery..."
if make -C "$REPO_DIR" -s verify-extensions INSTALL_DIR="$INSTALL_DIR" > "$WORK/verify.log" 2>&1; then
  pass "extensions: GhidraMCP, lx-loader and dos-toolbox classes load"
else
  fail "extensions: some classes are not loaded"
  indent < "$WORK/verify.log"
fi

# ── 2. Fixtures ───────────────────────────────────────────────────────────────
echo "Building fixtures..."
mkdir -p "$WORK/fixtures" "$WORK/proj"
clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c "$TESTS/fixtures/sample.c" \
  -o "$WORK/fixtures/sample.o" 2> "$WORK/clang.log" \
  || die "clang could not build an i386 object: $(head -1 "$WORK/clang.log")"
python3 -I "$TESTS/make_fixtures.py" "$WORK/fixtures" > /dev/null

# ── 3. Headless import + SanityCheck.java per fixture ─────────────────────────
run_fixture() {  # run_fixture <name> <file> [loader]
  local name=$1 file=$2 loader=${3:-}
  local log="$WORK/$name.log" out="$WORK/out/$name" line
  local args=("$WORK/proj" "sanity-$name" -import "$file")
  [[ -n "$loader" ]] && args+=(-loader "$loader")
  args+=(-deleteProject -scriptPath "$REPO_DIR/ghidra_scripts"
         -postScript SanityCheck.java "$TESTS/expect/$name.txt" "$out")
  mkdir -p "$out"
  echo "Importing $name ($(basename "$file"), loader ${loader:-auto})..."
  # --foreground keeps analyzeHeadless in the terminal's process group so Ctrl-C reaches it.
  timeout --foreground 600 "$HEADLESS" "${args[@]}" > "$log" 2>&1 || echo "analyzeHeadless exit status $?" >> "$log"
  if ! grep -q 'Import succeeded' "$log"; then
    fail "$name: import failed (loader ${loader:-auto})"
    tail -20 "$log" | indent
    return
  fi
  while IFS= read -r line; do
    case "$line" in
      PASS\ *) pass "$name: ${line#PASS }" ;;
      FAIL\ *) fail "$name: ${line#FAIL }" ;;
    esac
  done < <(sed -nE 's/^.*SANITY (PASS|FAIL) (.*) \(GhidraScript\) *$/\1 \2/p' "$log")
  if ! grep -q 'SANITY DONE' "$log"; then
    fail "$name: SanityCheck.java did not finish"
    tail -20 "$log" | indent
  fi
}

run_fixture sample "$WORK/fixtures/sample.o"
run_fixture dos "$WORK/fixtures/dos.exe" DosLoader
run_fixture le "$WORK/fixtures/le.exe" LeLoader

# ── 3b. GhidraMCP end to end ──────────────────────────────────────────────────
check_mcp() {
  local url="http://127.0.0.1:$MCP_PORT" cp jar i out compute
  if (exec 3<>"/dev/tcp/127.0.0.1/$MCP_PORT") 2>/dev/null; then
    fail "GhidraMCP: port $MCP_PORT is already in use (set TEST_MCP_PORT to a free port)"
    return
  fi
  cp=$(ls "$INSTALL_DIR"/Ghidra/Extensions/GhidraMCP/lib/GhidraMCP-*.jar 2>/dev/null | head -n 1)
  if [[ -z "$cp" ]]; then
    fail "GhidraMCP: no GhidraMCP jar in $INSTALL_DIR/Ghidra/Extensions/GhidraMCP/lib"
    return
  fi
  for jar in "$INSTALL_DIR"/Ghidra/{Framework,Features,Processors}/*/lib/*.jar; do
    cp+=":$jar"
  done
  mkdir -p "$WORK/mcp"/{home,settings,cache,temp}
  echo "Starting GhidraMCP headless server on 127.0.0.1:$MCP_PORT..."
  "$JAVA_HOME/bin/java" -Djava.awt.headless=true \
    -Duser.home="$WORK/mcp/home" -Djava.io.tmpdir="$WORK/mcp/temp" \
    -Dapplication.settingsdir="$WORK/mcp/settings" \
    -Dapplication.cachedir="$WORK/mcp/cache" \
    -Dapplication.tempdir="$WORK/mcp/temp" \
    -Dghidra.home="$INSTALL_DIR" -classpath "$cp" \
    com.xebyte.headless.GhidraMCPHeadlessServer \
    --bind 127.0.0.1 --port "$MCP_PORT" --file "$WORK/fixtures/sample.o" \
    > "$WORK/mcp.log" 2>&1 &
  MCP_PID=$!
  for ((i = 0; i < 120; i++)); do
    curl -sf -m 2 "$url/check_connection" > /dev/null 2>&1 && break
    kill -0 "$MCP_PID" 2>/dev/null || break
    sleep 1
  done
  if ! out=$(curl -sf -m 5 "$url/check_connection"); then
    fail "GhidraMCP: server did not answer on port $MCP_PORT within 120 s"
    tail -20 "$WORK/mcp.log" | indent
    return
  fi
  pass "GhidraMCP: /check_connection ($out)"

  if out=$(curl -sf -m 300 -X POST "$url/run_analysis") && [[ "$out" == *'"success":true'* ]]; then
    pass "GhidraMCP: /run_analysis"
  else
    fail "GhidraMCP: /run_analysis (got ${out:0:200})"
  fi

  out=$(curl -sf -m 30 "$url/list_functions" || true)
  compute=$(python3 -I -c '
import json, sys
funcs = json.load(sys.stdin).get("functions", [])
names = {f["name"]: f["address"] for f in funcs}
print(names["compute"] if {"compute", "helper"} <= names.keys() else "")
' <<< "$out" 2>/dev/null || true)
  if [[ -z "$compute" ]]; then
    fail "GhidraMCP: /list_functions lists helper and compute (got ${out:0:200})"
    return
  fi
  pass "GhidraMCP: /list_functions lists helper and compute"

  out=$(curl -sf -m 90 "$url/decompile_function?address=$compute" || true)
  if [[ "$out" == *0x1234abcd* && "$out" == *helper* ]]; then
    pass "GhidraMCP: /decompile_function compute"
  else
    fail "GhidraMCP: /decompile_function compute (got ${out:0:200})"
  fi

  kill "$MCP_PID" 2>/dev/null || true
  wait "$MCP_PID" 2>/dev/null || true
  MCP_PID=""
}

check_mcp

# ── 4. Snapshot report (never fails the run) ──────────────────────────────────
normalize() {  # drop decompiler warning comments and trailing whitespace
  sed -E -e '/^[[:space:]]*\/\* WARNING.*\*\/[[:space:]]*$/d' -e 's/[[:space:]]+$//' "$1"
}

report_snapshots() {
  local f rel snap changed=0
  if [[ "${UPDATE_SNAPSHOTS:-}" == 1 ]]; then
    rm -rf "$TESTS/snapshots"
    for f in "$WORK"/out/*/*.c; do
      [[ -e "$f" ]] || continue
      rel=${f#"$WORK/out/"}
      mkdir -p "$(dirname "$TESTS/snapshots/$rel")"
      normalize "$f" > "$TESTS/snapshots/$rel"
    done
    echo "Snapshots rewritten in tests/snapshots/."
    return
  fi
  echo
  echo "Snapshot changes (informational):"
  for f in "$WORK"/out/*/*.c; do
    [[ -e "$f" ]] || continue
    rel=${f#"$WORK/out/"}
    snap="$TESTS/snapshots/$rel"
    if [[ ! -f "$snap" ]]; then
      echo "  new: $rel"
      changed=1
    elif ! diff -u --label "snapshot/$rel" --label "now/$rel" "$snap" <(normalize "$f") | indent; then
      changed=1
    fi
  done
  for snap in "$TESTS"/snapshots/*/*.c; do
    [[ -e "$snap" ]] || continue
    rel=${snap#"$TESTS/snapshots/"}
    if [[ ! -e "$WORK/out/$rel" ]]; then
      echo "  gone: $rel (no longer produced)"
      changed=1
    fi
  done
  if [[ $changed == 0 ]]; then
    echo "  none"
  else
    echo "  (after a deliberate upgrade, record them with: UPDATE_SNAPSHOTS=1 make test)"
  fi
}

report_snapshots

# ── 5. Summary ────────────────────────────────────────────────────────────────
echo
for r in "${RESULTS[@]}"; do
  case "$r" in
    PASS*) printf '  \033[32m%s\033[0m\n' "$r" ;;
    *) printf '  \033[31m%s\033[0m\n' "$r" ;;
  esac
done
echo "$PASSED passed, $FAILED failed"
[[ $FAILED == 0 ]]
