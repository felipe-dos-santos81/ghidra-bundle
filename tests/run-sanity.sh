#!/bin/bash
# Sanity test suite for the Ghidra bundle; run it with `make test`.
# Design: docs/superpowers/specs/2026-10-06-sanity-test-design.md
#
# Usage: tests/run-sanity.sh <ghidra install dir> <JDK 21 home>
# Env:   UPDATE_SNAPSHOTS=1  rewrite tests/snapshots/ from this run
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

WORK=$(mktemp -d "$INSTALL_DIR/portable/temp/sanity-XXXXXX")
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

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
