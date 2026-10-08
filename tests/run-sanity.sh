#!/bin/bash
# Sanity test suite for the Ghidra bundle; run it with `make test`.
# Design: docs/superpowers/specs/2026-10-06-sanity-test-design.md
#
# Usage: tests/run-sanity.sh <ghidra install dir> <JDK 21 home>
# Env:   UPDATE_SNAPSHOTS=1  rewrite tests/snapshots/ from this run
#        TEST_MCP_PORT=18089  port for the GhidraMCP test server (default 18089)
#        TEST_IMPORT_TIMEOUT=600  seconds before a fixture import is killed (default 600)
#        SANITY_ONLY=dist,jython  run only these sections: extensions, fixtures, mcp,
#                                 dist, binexport, portable, jython, pyghidra
#        PACKAGES_DIR=<dir>       built zips to check (default: <install dir>/../packages)
# Needs GNU timeout (Linux: coreutils; macOS: `brew install coreutils` for gtimeout).
set -euo pipefail

INSTALL_DIR=${1:?usage: run-sanity.sh <ghidra install dir> <JDK 21 home>}
export JAVA_HOME=${2:?usage: run-sanity.sh <ghidra install dir> <JDK 21 home>}
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$REPO_DIR/tests"
HEADLESS="$INSTALL_DIR/support/analyzeHeadless"

PASSED=0
FAILED=0
SKIPPED=0
RESULTS=()
pass() { PASSED=$((PASSED + 1)); RESULTS+=("PASS  $1"); }
fail() { FAILED=$((FAILED + 1)); RESULTS+=("FAIL  $1"); }
skip() { SKIPPED=$((SKIPPED + 1)); RESULTS+=("SKIP  $1"); }
die() { printf '\033[31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }
indent() { sed 's/^/    /'; }
fail_with_log() { fail "$1"; tail -20 "$2" | indent; }  # fail_with_log <message> <log file>

# want <section>: true when SANITY_ONLY is unset or lists <section> (comma-separated).
SECTIONS=",extensions,fixtures,mcp,dist,binexport,portable,jython,pyghidra,"
want() { [[ -z "${SANITY_ONLY:-}" || ",$SANITY_ONLY," == *",$1,"* ]]; }
SANITY_ONLY=${SANITY_ONLY:-}
for section in ${SANITY_ONLY//,/ }; do
  [[ "$SECTIONS" == *",$section,"* ]] \
    || die "unknown SANITY_ONLY section '$section' (known:${SECTIONS//,/ })"
done

# count_matches <dir> <glob>: number of files in <dir> matching <glob>.
count_matches() {
  local -a matches
  shopt -s nullglob
  matches=("$1"/$2)
  shopt -u nullglob
  echo "${#matches[@]}"
}

[[ -x "$HEADLESS" ]] || die "$HEADLESS not found; run 'make install' first."
for tool in clang python3 curl; do
  command -v "$tool" >/dev/null || die "$tool not found on PATH (run 'make deps')."
done

# Imports rely on `timeout --foreground`, which BusyBox and other non-GNU builds lack.
TIMEOUT=""
for candidate in timeout gtimeout; do
  path=$(command -v "$candidate") || continue
  if "$path" --foreground 5 true 2>/dev/null; then
    TIMEOUT=$path
    break
  fi
done
[[ -n "$TIMEOUT" ]] \
  || die "GNU timeout with --foreground not found (Linux: coreutils; macOS: brew install coreutils)."

MCP_PORT="${TEST_MCP_PORT:-18089}"
PACKAGES_DIR="${PACKAGES_DIR:-$(dirname "$INSTALL_DIR")/packages}"
WORK=$(mktemp -d "$INSTALL_DIR/portable/temp/sanity-XXXXXX")
# pkill -f takes an extended regex; escape the path so characters like [ ( + in it match literally.
WORK_RE=$(printf '%s' "$WORK" | sed 's/[][\\.*^$+?(){}|]/\\&/g')
MCP_PID=""
stop_mcp() {
  if [[ -n "$MCP_PID" ]]; then
    kill "$MCP_PID" 2>/dev/null || true
    wait "$MCP_PID" 2>/dev/null || true
    MCP_PID=""
  fi
}
cleanup() {
  stop_mcp
  pkill -f -- "$WORK_RE" 2>/dev/null || true  # stray analysis JVMs, e.g. from a timed-out import
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ── 1. Extension classes ──────────────────────────────────────────────────────
if want extensions; then
  echo "Checking extension class discovery..."
  if make -C "$REPO_DIR" -s verify-extensions INSTALL_DIR="$INSTALL_DIR" > "$WORK/verify.log" 2>&1; then
    pass "extensions: every bundled extension's classes load"
  else
    fail "extensions: some classes are not loaded"
    indent < "$WORK/verify.log"
  fi
fi

# ── 2. Fixtures ───────────────────────────────────────────────────────────────
echo "Building fixtures..."
mkdir -p "$WORK/fixtures" "$WORK/proj"
SAMPLE="$WORK/fixtures/sample.o"
if ! clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c "$TESTS/fixtures/sample.c" \
    -o "$SAMPLE" 2> "$WORK/clang.log"; then
  # Only the ELF fixture and the GhidraMCP check need sample.o; the rest still runs.
  fail "sample: clang could not build an i386 object: $(grep -m1 'error' "$WORK/clang.log" || head -1 "$WORK/clang.log")"
  SAMPLE=""
fi
python3 -I "$TESTS/make_fixtures.py" "$WORK/fixtures" > /dev/null
printf '\x90\xc3' > "$WORK/probe.bin"  # NOP; RET: a program for scripts that need no real binary

# run_script <log> <file> <script> [script args...]: import <file> into a throwaway project
# and run <script> (from ghidra_scripts/ or tests/probes/) after analysis. Files ending
# in .bin load raw as x86 without analysis. Returns analyzeHeadless's exit status.
run_script() {
  local log=$1 file=$2 script=$3
  shift 3
  local args=("$WORK/proj" "script-$RANDOM" -import "$file" -deleteProject
              -scriptPath "$REPO_DIR/ghidra_scripts;$TESTS/probes" -postScript "$script" "$@")
  if [[ "$file" == *.bin ]]; then
    args+=(-loader BinaryLoader -processor x86:LE:32:default -noanalysis)
  fi
  "$TIMEOUT" --foreground "${TEST_IMPORT_TIMEOUT:-600}" "$HEADLESS" "${args[@]}" > "$log" 2>&1
}

# ── 3. Headless import + SanityCheck.java per fixture ─────────────────────────
run_fixture() {  # run_fixture <name> <file> [loader]
  local name=$1 file=$2 loader=${3:-}
  local log="$WORK/$name.log" out="$WORK/out/$name" label=${loader:-auto} line
  local limit=${TEST_IMPORT_TIMEOUT:-600} status=0
  local args=("$WORK/proj" "sanity-$name" -import "$file")
  [[ -n "$loader" ]] && args+=(-loader "$loader")
  args+=(-deleteProject -scriptPath "$REPO_DIR/ghidra_scripts"
         -postScript SanityCheck.java "$TESTS/expect/$name.txt" "$out")
  mkdir -p "$out"
  echo "Importing $name ($(basename "$file"), loader $label)..."
  # --foreground keeps analyzeHeadless in the terminal's process group so Ctrl-C reaches it.
  "$TIMEOUT" --foreground "$limit" "$HEADLESS" "${args[@]}" > "$log" 2>&1 || status=$?
  ((status == 0)) || echo "analyzeHeadless exit status $status" >> "$log"
  if ((status == 124)); then
    # timeout only kills its direct child; analyzeHeadless's JVM keeps running.
    pkill -f -- "$WORK_RE/proj" || true
    fail_with_log "$name: import timed out after $limit s (loader $label)" "$log"
    return
  fi
  if ! grep -q 'Import succeeded' "$log"; then
    fail_with_log "$name: import failed (loader $label)" "$log"
    return
  fi
  # SanityCheck.java writes results.txt only when it finishes, ending with "SANITY DONE <p> <f>".
  if [[ ! -f "$out/results.txt" ]]; then
    fail_with_log "$name: SanityCheck.java did not finish" "$log"
    return
  fi
  while IFS= read -r line; do
    case "$line" in
      "SANITY PASS "*) pass "$name: ${line#SANITY PASS }" ;;
      "SANITY FAIL "*) fail "$name: ${line#SANITY FAIL }" ;;
      "SANITY DONE 0 0") fail "$name: no facts checked" ;;
    esac
  done < "$out/results.txt"
}

if want fixtures; then
  if [[ -n "$SAMPLE" ]]; then run_fixture sample "$SAMPLE"; fi
  run_fixture dos "$WORK/fixtures/dos.exe" DosLoader
  run_fixture le "$WORK/fixtures/le.exe" LeLoader
fi

# ── 3b. GhidraMCP end to end ──────────────────────────────────────────────────
check_mcp() {
  local url="http://127.0.0.1:$MCP_PORT" cp jar i out compute jars
  if (exec 3<>"/dev/tcp/127.0.0.1/$MCP_PORT") 2>/dev/null; then
    fail "GhidraMCP: port $MCP_PORT is already in use (set TEST_MCP_PORT to a free port)"
    return
  fi
  shopt -s nullglob
  jars=("$INSTALL_DIR"/Ghidra/Extensions/GhidraMCP/lib/GhidraMCP-*.jar)
  shopt -u nullglob
  if ((${#jars[@]} == 0)); then
    fail "GhidraMCP: no GhidraMCP jar in $INSTALL_DIR/Ghidra/Extensions/GhidraMCP/lib"
    return
  fi
  cp=${jars[0]}
  for jar in "$INSTALL_DIR"/Ghidra/{Framework,Features,Processors}/*/lib/*.jar; do
    cp+=":$jar"
  done
  mkdir -p "$WORK/mcp"/{home,settings,cache,temp}
  echo "Starting GhidraMCP headless server on 127.0.0.1:$MCP_PORT..."
  env -u GHIDRA_MCP_AUTH_TOKEN -u GHIDRA_MCP_PROJECT_FOLDER -u GHIDRA_MCP_FILE_ROOT \
    "$JAVA_HOME/bin/java" -Djava.awt.headless=true \
    -Duser.home="$WORK/mcp/home" -Djava.io.tmpdir="$WORK/mcp/temp" \
    -Dapplication.settingsdir="$WORK/mcp/settings" \
    -Dapplication.cachedir="$WORK/mcp/cache" \
    -Dapplication.tempdir="$WORK/mcp/temp" \
    -Dghidra.home="$INSTALL_DIR" -classpath "$cp" \
    com.xebyte.headless.GhidraMCPHeadlessServer \
    --bind 127.0.0.1 --port "$MCP_PORT" --file "$SAMPLE" \
    > "$WORK/mcp.log" 2>&1 &
  MCP_PID=$!
  out=""
  for ((i = 0; i < 120; i++)); do
    out=$(curl -sf -m 2 "$url/check_connection" 2>/dev/null) && break
    out=""
    kill -0 "$MCP_PID" 2>/dev/null || break
    sleep 1
  done
  if [[ -z "$out" ]]; then
    fail_with_log "GhidraMCP: server did not answer on port $MCP_PORT within 120 s" "$WORK/mcp.log"
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

  stop_mcp
}

if want mcp; then
  if [[ -n "$SAMPLE" ]]; then
    check_mcp
  else
    fail "GhidraMCP: not checked (needs sample.o, which clang could not build)"
  fi
fi

# ── 3c. dist/packages ─────────────────────────────────────────────────────────
# Zips that must each match exactly one file in $PACKAGES_DIR ({v} = Ghidra version).
# Ghidra's own zip ends in its platform (linux_arm_64, mac_x86_64, ...); extension
# zips also start with ghidra_{v}_, so "_64.zip" keeps the two apart.
PACKAGE_PATTERNS=(
  "ghidra_{v}_*_64.zip"
  "GhidraMCP-*.zip"
  "ghidra_{v}_*_lx-loader.zip"
  "ghidra_{v}_*_dos-toolbox.zip"
  "ghidra_{v}_*_retsync.zip"
  "ghidra_{v}_*_GhidraFindcrypt.zip"
  "ghidra_{v}_*_BinExport.zip"
)
# Build folders that must hold no current zip once install has moved them.
BUILD_OUTPUTS=(ghidra/build/dist ghidra-mcp/build/distributions lx-loader/dist dos-toolbox/dist
               ret-sync/ext_ghidra/dist GhidraFindcrypt/dist binexport/java/dist)

check_dist() {
  local version pattern dir n
  version=$(sed -n 's/^application\.version=//p' "$INSTALL_DIR/Ghidra/application.properties")
  for pattern in "${PACKAGE_PATTERNS[@]}"; do
    pattern=${pattern//\{v\}/$version}
    n=$(count_matches "$PACKAGES_DIR" "$pattern")
    if ((n == 1)); then
      pass "dist: packages/ has $pattern"
    else
      fail "dist: $n files match $pattern in $PACKAGES_DIR (want 1)"
    fi
  done
  for dir in "${BUILD_OUTPUTS[@]}"; do
    if [[ "$dir" == ghidra-mcp/* ]]; then  # GhidraMCP zips carry their own version
      n=$(count_matches "$REPO_DIR/$dir" "*.zip")
    else
      n=$(count_matches "$REPO_DIR/$dir" "*${version}*.zip")
    fi
    if ((n == 0)); then
      pass "dist: $dir holds no current zip"
    else
      fail "dist: $dir still holds $n current zip(s); install moves them to packages/"
    fi
  done
}

if want dist; then check_dist; fi

# ── 3d. BinExport ─────────────────────────────────────────────────────────────
check_binexport() {
  local log="$WORK/binexport.log" out="$WORK/sample.BinExport"
  if run_script "$log" "$SAMPLE" BinExportProbe.java "$out" && grep -q 'BINEXPORT OK' "$log"; then
    pass "BinExport: exported sample.o ($(grep -o 'BINEXPORT OK [0-9]*' "$log" | cut -d' ' -f3) bytes)"
  else
    fail_with_log "BinExport: exporting sample.o failed" "$log"
  fi
}

if want binexport; then
  if [[ -n "$SAMPLE" ]]; then
    check_binexport
  else
    fail "BinExport: not checked (needs sample.o, which clang could not build)"
  fi
fi

# ── 4. Snapshot report (never fails the run) ──────────────────────────────────
normalize() {  # drop decompiler warning comments and trailing whitespace
  sed -E -e '/^[[:space:]]*\/\* WARNING.*\*\/[[:space:]]*$/d' -e 's/[[:space:]]+$//' "$1"
}

report_snapshots() (  # subshell, so nullglob stays local
  shopt -s nullglob
  local f rel snap changed=0
  if [[ "${UPDATE_SNAPSHOTS:-}" == 1 ]]; then
    if ((FAILED > 0)); then
      echo "Not updating snapshots: $FAILED check(s) failed."
      return
    fi
    rm -rf "$TESTS/snapshots"
    for f in "$WORK"/out/*/*.c; do
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
)

if want fixtures; then report_snapshots; fi

# ── 5. Summary ────────────────────────────────────────────────────────────────
echo
((PASSED + FAILED + SKIPPED > 0)) || fail "no checks ran (SANITY_ONLY=${SANITY_ONLY:-})"
for r in "${RESULTS[@]}"; do
  case "$r" in
    PASS*) printf '  \033[32m%s\033[0m\n' "$r" ;;
    SKIP*) printf '  \033[33m%s\033[0m\n' "$r" ;;
    *) printf '  \033[31m%s\033[0m\n' "$r" ;;
  esac
done
echo "$PASSED passed, $FAILED failed, $SKIPPED skipped"
[[ $FAILED == 0 ]]
