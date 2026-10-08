# Windows Game Add-ons and `dist/packages/` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collect every built zip into `dist/packages/`, and add Windows-game RE add-ons to the bundle: GhidrAssist, RevEng.AI, ret-sync, GhidraFindcrypt, BinExport, Jython + D2GridraTools, and a PyGhidra venv with an MPQ reader. All of it is verified by `make test`.

**Architecture:** The Makefile's `install_extension` macro learns to move each built zip into `dist/packages/` and to build from a Gradle subdirectory. Five new extension submodules each get a numbered stage and a `VerifyExtensions.java` check. GhidrAssist and RevEng.AI come from forks that keep their files under Ghidra's settings directory. A new stage assembles D2GridraTools into a minimal Jython-run extension. Another creates PyGhidra's venv, with `bundle_mpq`, a small ctypes wrapper over StormLib. `tests/run-sanity.sh` gains a `SANITY_ONLY` section filter and new checks: dist, BinExport, portable, Jython, PyGhidra.

**Tech Stack:** GNU Make, bash, Gradle (Ghidra's `ghidra/gradlew`, Gradle 9.7.1), Java 21 GhidraScripts, Jython 2.7 (Ghidra extension), Python 3.9–3.14 with PyGhidra 3.1.0, ctypes + StormLib 9.x (`libstorm`), `gh` CLI for the forks.

**Spec:** `docs/superpowers/specs/2026-10-08-windows-games-addons-design.md`

## Global Constraints

- `GHIDRA_VERSION := 12.1.4` stays the single version pin; never hard-code `12.1.4` in new code. Derive it from `$(GHIDRA_VERSION)`, or in tests from `application.version` in `$INSTALL_DIR/Ghidra/application.properties`.
- Portable mode: no run of Ghidra, `analyzeHeadless` or `pyghidraRun` may create `~/.ghidra`, `~/.config/GhidrAssist`, `~/.reai` or a directory literally named `${INSTALL_DIR}`.
- `dist/packages/` holds exactly one zip per artifact for the current `GHIDRA_VERSION`. Subproject build folders hold no current-version zip after install.
- Submodule paths must be exactly `GhidrAssist`, `plugin-ghidra` and `GhidraFindcrypt`: Gradle names those extensions after their checkout directory. Never rename an extension directory under `Ghidra/Extensions/`.
- Forks live on `felipe-dos-santos81`, branch `portable-settings`, pinned by tags `bundle-pin-<sha7>`. Never force-push the branch or delete the tags.
- **Outward-facing actions** (creating forks, pushing branches or tags, opening PRs) need the user's explicit yes **at that step**. Approval of this plan does not cover them.
- Cloud add-ons ship unconfigured: no API keys, endpoints or tokens anywhere in the repo or in `dist/`.
- Ports: GhidraMCP 8089 (GUI) and 18089 (tests) are unchanged. ret-sync uses 127.0.0.1:9100 and only listens when enabled.
- D2GridraTools has no license. Fetch it as a submodule and never modify or commit its files. Only the assembled copy under `dist/` gets the runtime tag.
- Makefile: recipes use **tabs**. Every stage is idempotent (skips when its output is present). Errors propagate with `|| exit 1`. Use the `$(OK)`/`$(WARN)`/`$(ERR)` helpers, and give every user-facing target a `## description`.
- Bash: `set -euo pipefail`, validated with `bash -n`. Python runs with `python3 -I`. Avoid `cmd && action` as the *last* statement of a function or loop body under `set -e`; use `if`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Spec Amendments (decided while planning; recorded in the spec in Task 11)

1. **MPQ reader:** use the ctypes wrapper `bundle_mpq` (`python/bundle-mpq/`) from the start. PyPI `mpq` was last released in 2016, and its `setup.py` imports `distutils`, which Python 3.12 removed.
2. **Test MPQ:** written by `tests/make_mpq.py`, which writes the MPQ v1 container itself and gets PKWARE compression from StormLib's `SCompCompress`. `smpq` is dropped: Ubuntu noble's StormLib 9.22 aborts on every archive write (assertion in `FillWritableHandle`).
3. **BinExport test:** `tests/probes/BinExportProbe.java` calls `BinExportExporter.export(...)` directly, because the shipped `BinExport.java` calls `askChoices`, which is awkward to drive headlessly.
4. **Ghidra zip glob:** `ghidra_<ver>_*_64.zip` (the platform suffix: `linux_arm_64`, `mac_x86_64`, ...). `ghidra_<ver>_*.zip` also matches extension zips such as `ghidra_12.1.4_DEV_<date>_lx-loader.zip`.
5. **Extension skip rule:** an extension stage skips only if its zip is also present in `dist/packages/`. Existing installs therefore rebuild each extension once.
6. **Stage 13 without StormLib:** still installs `bundle_mpq`, which only loads libstorm when used, and warns.
7. **Helpers:** helper scripts go in `scripts/` and test probes in `tests/probes/`. `run-sanity.sh` gets `SANITY_ONLY=<sections>`.
8. **Fork check:** `tests/probes/PortablePaths.java` checks the forks' default paths headlessly.
9. **Name lookups:** `bundle_mpq.MpqArchive.read()` turns `/` into `\`, because StormLib's lookups are case-insensitive but slash-sensitive.

## Review Focus

1. **Upgrading an existing install.** The current `dist/` has its zips in subproject folders, extensions already installed, and `${INSTALL_DIR}` in `launch.properties`. `make install` must move the existing Ghidra zip *without rebuilding Ghidra*, rebuild each extension once, and rewrite the three VMARGS lines. Tests: Task 2 steps 4–6, Task 5 step 5.
2. **Ghidra and extension zips share the `ghidra_<ver>_` prefix.** Stages 02 and 03 must pick only Ghidra's own zip. Test: Task 2's dist check requires exactly one match for `ghidra_{v}_*_64.zip` while extension zips sit next to it.
3. **`pyghidraRun` started from an activated virtualenv, or without a TTY.** The launcher then prompts with `input()` and would hang or use the wrong venv. Test: Task 10's check runs with `VIRTUAL_ENV` unset, the venv stripped from `PATH`, and `</dev/null`, and asserts the "Switching to Ghidra virtual environment: <bundle venv>" line. Step 6 also runs it with `.venv` activated.
4. **Script file names with spaces** (`Imports fixer.py`): the D2 assembly must copy and tag them intact. Test: Task 8's check asserts that `Imports fixer.py` exists and is tagged.
5. **StormLib missing** (macOS, minimal Linux): stage 13 must warn and succeed, and `make test` must report SKIP, not FAIL. Tests: Task 9's `test_bad_override_raises_mpq_error`, and Task 10 step 7 (forced with `BUNDLE_STORMLIB=/nonexistent`).

---

### Task 1: `run-sanity.sh` section filter and shared helpers

**Files:**
- Modify: `tests/run-sanity.sh` (header, helpers after `fail_with_log`, gating of sections 1–4, summary)
- Modify: `Makefile` (`test` target passes `PACKAGES_DIR`, which only exists after Task 2; pass it now anyway)

**Interfaces:**
- Produces, all in `tests/run-sanity.sh`:
  - `want <section>`: true when `SANITY_ONLY` is unset or lists the section.
  - `skip <message>`: records a SKIP result.
  - `run_script <log> <file> <script> [args...]`: imports `<file>` into a throwaway project and runs `<script>` from `ghidra_scripts/` or `tests/probes/`. Files ending in `.bin` use `BinaryLoader`, x86:LE:32 and `-noanalysis`. Returns analyzeHeadless's status.
  - `$WORK/probe.bin`: a 2-byte probe program.
  - `count_matches <dir> <glob>`: prints the number of matches.
  - `$PACKAGES_DIR`: defaults to `$(dirname "$INSTALL_DIR")/packages`.
  - Section names: `extensions fixtures mcp dist binexport portable jython pyghidra`.

- [ ] **Step 1: Write the failing test (the filter doesn't exist yet)**

Run: `SANITY_ONLY=bogus make test 2>&1 | tail -3`
Expected now: the whole suite runs (takes minutes) and ignores the variable. Expected after this task: `ERROR: unknown SANITY_ONLY section 'bogus' ...` within a second. Press Ctrl-C once you see the suite start importing fixtures.

- [ ] **Step 2: Add the header lines and helpers**

In the header comment of `tests/run-sanity.sh`, after the `TEST_IMPORT_TIMEOUT` line, add:

```bash
#        SANITY_ONLY=dist,jython  run only these sections: extensions, fixtures, mcp,
#                                 dist, binexport, portable, jython, pyghidra
#        PACKAGES_DIR=<dir>       built zips to check (default: <install dir>/../packages)
```

Replace the counters block:

```bash
PASSED=0
FAILED=0
RESULTS=()
pass() { PASSED=$((PASSED + 1)); RESULTS+=("PASS  $1"); }
fail() { FAILED=$((FAILED + 1)); RESULTS+=("FAIL  $1"); }
```

with:

```bash
PASSED=0
FAILED=0
SKIPPED=0
RESULTS=()
pass() { PASSED=$((PASSED + 1)); RESULTS+=("PASS  $1"); }
fail() { FAILED=$((FAILED + 1)); RESULTS+=("FAIL  $1"); }
skip() { SKIPPED=$((SKIPPED + 1)); RESULTS+=("SKIP  $1"); }
```

After the `fail_with_log` line, add:

```bash

# want <section>: true when SANITY_ONLY is unset or lists <section> (comma-separated).
SECTIONS=",extensions,fixtures,mcp,dist,binexport,portable,jython,pyghidra,"
want() { [[ -z "${SANITY_ONLY:-}" || ",$SANITY_ONLY," == *",$1,"* ]]; }
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
```

`die` is defined on the line before `indent`. Check that the new block comes after it, and move `die` up if it doesn't.

After the `MCP_PORT=...` line, add:

```bash
PACKAGES_DIR="${PACKAGES_DIR:-$(dirname "$INSTALL_DIR")/packages}"
```

- [ ] **Step 3: Gate the existing sections**

Wrap section 1 (from `echo "Checking extension class discovery..."` through its `fi`) in `if want extensions; then` … `fi`.

Replace the three fixture calls:

```bash
[[ -n "$SAMPLE" ]] && run_fixture sample "$SAMPLE"
run_fixture dos "$WORK/fixtures/dos.exe" DosLoader
run_fixture le "$WORK/fixtures/le.exe" LeLoader
```

with:

```bash
if want fixtures; then
  if [[ -n "$SAMPLE" ]]; then run_fixture sample "$SAMPLE"; fi
  run_fixture dos "$WORK/fixtures/dos.exe" DosLoader
  run_fixture le "$WORK/fixtures/le.exe" LeLoader
fi
```

Replace the GhidraMCP call block:

```bash
if [[ -n "$SAMPLE" ]]; then
  check_mcp
else
  fail "GhidraMCP: not checked (needs sample.o, which clang could not build)"
fi
```

with:

```bash
if want mcp; then
  if [[ -n "$SAMPLE" ]]; then
    check_mcp
  else
    fail "GhidraMCP: not checked (needs sample.o, which clang could not build)"
  fi
fi
```

Replace the bare `report_snapshots` call with:

```bash
if want fixtures; then report_snapshots; fi
```

- [ ] **Step 4: Add `probe.bin` and `run_script`**

After the line `python3 -I "$TESTS/make_fixtures.py" "$WORK/fixtures" > /dev/null`, add:

```bash
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
```

Create the probe folder so `-scriptPath` never points at a missing directory:

```bash
mkdir -p tests/probes && touch tests/probes/.gitkeep
```

- [ ] **Step 5: Update the summary**

Replace the summary block (from `echo` after `# ── 5. Summary` to the end) with:

```bash
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
```

- [ ] **Step 6: Pass `PACKAGES_DIR` from the Makefile**

In the `test` recipe, replace `@tests/run-sanity.sh "$(INSTALL_DIR)" "$(JAVA21_HOME)"` with:

```make
	@PACKAGES_DIR="$(DIST_DIR)/packages" tests/run-sanity.sh "$(INSTALL_DIR)" "$(JAVA21_HOME)"
```

- [ ] **Step 7: Run the tests and make sure they pass**

```bash
bash -n tests/run-sanity.sh
SANITY_ONLY=bogus make test; echo "exit=$?"
SANITY_ONLY=extensions make test 2>&1 | tail -4
SANITY_ONLY=dist make test 2>&1 | tail -3
make test 2>&1 | tail -3
```

Expected:
- `ERROR: unknown SANITY_ONLY section 'bogus' (known: extensions fixtures mcp dist binexport portable jython pyghidra )`, `exit=2`.
- `PASS  extensions: ...` and `1 passed, 0 failed, 0 skipped`.
- `FAIL  no checks ran (SANITY_ONLY=dist)` and `0 passed, 1 failed, 0 skipped`. This is the red state that Task 2 turns green.
- The full suite has the same PASS count as before this task, with `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add tests/run-sanity.sh tests/probes/.gitkeep Makefile
git commit -m "test: add SANITY_ONLY sections and shared helpers to run-sanity.sh

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Central `dist/packages/`

**Files:**
- Modify: `Makefile` (configuration, stages 02 and 03, `install_extension`)
- Modify: `tests/run-sanity.sh` (new section `dist`)

**Interfaces:**
- Consumes: `want`, `pass`, `fail`, `count_matches` and `$PACKAGES_DIR` from Task 1.
- Produces:
  - `PACKAGES_DIR := $(DIST_DIR)/packages`.
  - `GHIDRA_ZIP = ghidra_$(1)_*_64.zip`, a make function: `$(call GHIDRA_ZIP,$(GHIDRA_VERSION))`, or `$(call GHIDRA_ZIP,*)` for any version.
  - `$(call install_extension,dir,src,zip glob[,legacy dir][,gradle subdir])`.
  - In `tests/run-sanity.sh`: the arrays `PACKAGE_PATTERNS` (`{v}` = Ghidra version) and `BUILD_OUTPUTS`. Later tasks append to both.

- [ ] **Step 1: Write the failing test**

In `tests/run-sanity.sh`, insert before `# ── 4. Snapshot report`:

```bash
# ── 3c. dist/packages ─────────────────────────────────────────────────────────
# Zips that must each match exactly one file in $PACKAGES_DIR ({v} = Ghidra version).
# Ghidra's own zip ends in its platform (linux_arm_64, mac_x86_64, ...); extension
# zips also start with ghidra_{v}_, so "_64.zip" keeps the two apart.
PACKAGE_PATTERNS=(
  "ghidra_{v}_*_64.zip"
  "GhidraMCP-*.zip"
  "ghidra_{v}_*_lx-loader.zip"
  "ghidra_{v}_*_dos-toolbox.zip"
)
# Build folders that must hold no current zip once install has moved them.
BUILD_OUTPUTS=(ghidra/build/dist ghidra-mcp/build/distributions lx-loader/dist dos-toolbox/dist)

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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `SANITY_ONLY=dist make test 2>&1 | tail -12`
Expected: every `packages/ has ...` line FAILs with `0 files match`. `ghidra/build/dist` and `dos-toolbox/dist` FAIL with `still holds 1 current zip(s)`. Exit status 1.

- [ ] **Step 3: Implement the configuration and stages 02 and 03**

In the `Makefile` configuration block, after `DIST_DIR := ...`, add:

```make
PACKAGES_DIR := $(DIST_DIR)/packages
```

After the `OK`/`WARN`/`ERR` helpers, add:

```make
# Ghidra's own zip name ends in its platform (linux_arm_64, mac_x86_64, ...). Extension
# zips also start with ghidra_<version>_, so match on "_64.zip" to tell them apart.
GHIDRA_ZIP = ghidra_$(1)_*_64.zip
```

Replace the `02-build-ghidra` recipe with the following (lines start with a tab):

```make
02-build-ghidra: 01-checkout ## Build the Ghidra distribution zip from source into dist/packages/
	@grep -qx 'application.version=$(GHIDRA_VERSION)' ghidra/Ghidra/application.properties || \
		{ $(ERR) "ghidra submodule is not Ghidra $(GHIDRA_VERSION): update GHIDRA_VERSION or the submodule"; exit 1; }
	@if compgen -G "$(PACKAGES_DIR)/$(call GHIDRA_ZIP,$(GHIDRA_VERSION))" >/dev/null; then \
		echo "Ghidra $(GHIDRA_VERSION) zip already in $(PACKAGES_DIR), skipping."; \
	else \
		compgen -G "ghidra/build/dist/$(call GHIDRA_ZIP,$(GHIDRA_VERSION))" >/dev/null || ./build-ghidra.sh || exit 1; \
		ZIP=$$(ls -1t ghidra/build/dist/$(call GHIDRA_ZIP,$(GHIDRA_VERSION)) 2>/dev/null | head -n 1); \
		[ -n "$$ZIP" ] || { $(ERR) "no Ghidra $(GHIDRA_VERSION) zip in ghidra/build/dist/"; exit 1; }; \
		mkdir -p "$(PACKAGES_DIR)" && rm -f "$(PACKAGES_DIR)"/$(call GHIDRA_ZIP,*) && \
			mv "$$ZIP" "$(PACKAGES_DIR)/" || exit 1; \
		$(OK) "Moved $${ZIP##*/} to $(PACKAGES_DIR)."; \
	fi
```

In `03-install-ghidra`, replace:

```make
		ZIP=$$(ls -1t ghidra/build/dist/ghidra_$(GHIDRA_VERSION)_*.zip 2>/dev/null | head -n 1); \
		[ -n "$$ZIP" ] || { $(ERR) "no Ghidra zip in ghidra/build/dist/"; exit 1; }; \
```

with:

```make
		ZIP=$$(ls -1t "$(PACKAGES_DIR)"/$(call GHIDRA_ZIP,$(GHIDRA_VERSION)) 2>/dev/null | head -n 1); \
		[ -n "$$ZIP" ] || { $(ERR) "no Ghidra zip in $(PACKAGES_DIR)/"; exit 1; }; \
```

- [ ] **Step 4: Rewrite `install_extension`**

Replace the comment block and `define install_extension … endef` with:

```make
# $(call install_extension,directory,source dir,zip glob[,legacy directory to remove][,gradle subdir])
# Builds an extension with ghidra/gradlew (in <source dir>/<gradle subdir>), moves the
# zip into $(PACKAGES_DIR) and unzips it into $(EXT_DIR). The zip glob names the build
# output and contains $(GHIDRA_VERSION); older versions of that zip in $(PACKAGES_DIR)
# are deleted. The source commit is recorded in <ext>/.bundle-source; the stage
# rebuilds when it changes or when the zip is missing from $(PACKAGES_DIR).
# Never rename the unzipped directory: Ghidra only loads classes from
# <ext>/lib/<jar> when the jar name starts with the directory name, so a
# renamed extension silently loses its loaders, analyzers and plugins.
define install_extension
@SRC=$$(git -C $(2) rev-parse HEAD 2>/dev/null); \
if [ -d "$(EXT_DIR)/$(1)" ] && compgen -G "$(PACKAGES_DIR)/$(notdir $(3))" >/dev/null && \
	{ [ -z "$$SRC" ] || [ "$$(cat "$(EXT_DIR)/$(1)/.bundle-source" 2>/dev/null)" = "$$SRC" ]; }; then \
	echo "$(1) already installed$${SRC:+ from $${SRC:0:7}}, skipping."; \
else \
	echo "Building $(1)$${SRC:+ from $${SRC:0:7}}..."; \
	(cd "$(2)/$(or $(5),.)" && "$(BUNDLE_DIR)/ghidra/gradlew" -p . \
		-PGHIDRA_INSTALL_DIR="$(INSTALL_DIR)" buildExtension) || exit 1; \
	ZIP=$$(ls -1t $(3) 2>/dev/null | head -n 1); \
	[ -n "$$ZIP" ] || { $(ERR) "no zip matching $(3)"; exit 1; }; \
	mkdir -p "$(PACKAGES_DIR)" && rm -f "$(PACKAGES_DIR)"/$(subst $(GHIDRA_VERSION),*,$(notdir $(3))) && \
		mv "$$ZIP" "$(PACKAGES_DIR)/" || exit 1; \
	ZIP="$(PACKAGES_DIR)/$${ZIP##*/}"; \
	rm -rf "$(EXT_DIR)/$(1)" $(if $(4),"$(EXT_DIR)/$(4)"); \
	unzip -q -o "$$ZIP" -d "$(EXT_DIR)" || exit 1; \
	[ -d "$(EXT_DIR)/$(1)" ] || { $(ERR) "$$ZIP did not create $(EXT_DIR)/$(1)"; exit 1; }; \
	[ -z "$$SRC" ] || echo "$$SRC" > "$(EXT_DIR)/$(1)/.bundle-source"; \
	$(OK) "$(1) installed ($${ZIP##*/} in $(PACKAGES_DIR))."; \
fi
endef
```

The three existing `$(call install_extension,...)` lines (stages 04–06) stay unchanged.

- [ ] **Step 5: Migrate the existing install (Review Focus 1)**

```bash
make install-ghidra 2>&1 | tail -3
make install-mcp install-lx-loader install-dos-toolbox 2>&1 | grep -E 'Building|installed|skipping|ERROR'
```

Expected:
- `Moved ghidra_12.1.4_DEV_<date>_linux_arm_64.zip to .../dist/packages.`, with **no** `Building Ghidra distribution zip...` line, then `... already installed, skipping.`
- Each extension prints `Building <ext>...` once, then `<ext> installed (<zip> in .../dist/packages).`

- [ ] **Step 6: Run again to confirm idempotency**

Run: `make install-ghidra install-mcp install-lx-loader install-dos-toolbox 2>&1 | grep -c skipping`
Expected: `5` (stage 02, stage 03 and three extensions), and no `Building` lines.

- [ ] **Step 7: Run the test to verify it passes**

Run: `SANITY_ONLY=dist make test 2>&1 | tail -12`
Expected: all `dist:` lines PASS, including `packages/ has ghidra_12.1.4_*_64.zip`. That match count is 1 even though `ghidra_12.1.4_*_lx-loader.zip` and `ghidra_12.1.4_*_dos-toolbox.zip` sit next to it (Review Focus 2).

- [ ] **Step 8: Break it on purpose, then restore**

```bash
mv dist/packages/ghidra_12.1.4_*_lx-loader.zip dist/
SANITY_ONLY=dist make test 2>&1 | grep FAIL
mv dist/ghidra_12.1.4_*_lx-loader.zip dist/packages/
```

Expected: `FAIL  dist: 0 files match ghidra_12.1.4_*_lx-loader.zip in .../dist/packages (want 1)`.

- [ ] **Step 9: Check the Makefile still expands, then commit**

```bash
make help >/dev/null && make -n install >/dev/null && echo OK
git add Makefile tests/run-sanity.sh
git commit -m "build: collect built zips in dist/packages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: ret-sync and GhidraFindcrypt; stage renumbering

**Files:**
- Modify: `.gitmodules`, plus the new submodules `ret-sync/` and `GhidraFindcrypt/`
- Modify: `Makefile` (stages 09 and 10; 07-venv becomes 14-venv and 08-register-mcp becomes 15-register-mcp; `.PHONY`, `PIPELINE`, the header comment, `clean`)
- Modify: `ghidra_scripts/VerifyExtensions.java`
- Modify: `tests/run-sanity.sh` (`PACKAGE_PATTERNS`, `BUILD_OUTPUTS`, the extensions pass message)

**Interfaces:**
- Consumes: `install_extension` with a fifth argument (Task 2), and `PACKAGE_PATTERNS`/`BUILD_OUTPUTS` (Task 2).
- Produces: the targets `09-install-retsync` (alias `install-retsync`), `10-install-findcrypt` (alias `install-findcrypt`), `14-venv` and `15-register-mcp`. The aliases `venv` and `register-mcp` are unchanged.

- [ ] **Step 1: Add the submodules**

```bash
git submodule add --depth 1 -b master https://github.com/bootleg/ret-sync.git ret-sync
git submodule add --depth 1 -b main https://github.com/antoniovazquezblanco/GhidraFindcrypt.git GhidraFindcrypt
git config -f .gitmodules submodule.ret-sync.shallow true
git config -f .gitmodules submodule.GhidraFindcrypt.shallow true
```

- [ ] **Step 2: Write the failing test**

In `ghidra_scripts/VerifyExtensions.java`, add to `run()` after the dos-toolbox lines:

```java
		check("retsync", Plugin.class, "RetSyncPlugin");
		check("GhidraFindcrypt", Analyzer.class, "FindCryptAnalyzer");
```

In `tests/run-sanity.sh`, append to `PACKAGE_PATTERNS`:

```bash
  "ghidra_{v}_*_retsync.zip"
  "ghidra_{v}_*_GhidraFindcrypt.zip"
```

and append `ret-sync/ext_ghidra/dist GhidraFindcrypt/dist` to `BUILD_OUTPUTS`. In section 1, change the pass message to:

```bash
  pass "extensions: every bundled extension's classes load"
```

Run: `make verify-extensions`
Expected: `MISSING retsync: RetSyncPlugin`, `MISSING GhidraFindcrypt: FindCryptAnalyzer`, and the error `some extension classes were not loaded`.

- [ ] **Step 3: Add the stages and renumber**

After `06-install-dos-toolbox`'s recipe, add:

```make
09-install-retsync: 03-install-ghidra ## Build and install ret-sync (sync with x64dbg/WinDbg)
	$(call install_extension,retsync,ret-sync,ret-sync/ext_ghidra/dist/ghidra_$(GHIDRA_VERSION)_*_retsync.zip,,ext_ghidra)

10-install-findcrypt: 03-install-ghidra ## Build and install GhidraFindcrypt (crypto constants)
	$(call install_extension,GhidraFindcrypt,GhidraFindcrypt,GhidraFindcrypt/dist/ghidra_$(GHIDRA_VERSION)_*_GhidraFindcrypt.zip)
```

ret-sync's glob names `ghidra_$(GHIDRA_VERSION)_*`, so the 10.x zips that upstream commits to `ext_ghidra/dist/` never match.

Next to `install-dos-toolbox: 06-install-dos-toolbox`, add:

```make
install-retsync: 09-install-retsync
install-findcrypt: 10-install-findcrypt
```

Rename the targets: `07-venv` becomes `14-venv` (both the rule and the `08-register-mcp` prerequisite), and `08-register-mcp` becomes `15-register-mcp`. Update the aliases to `venv: 14-venv` and `register-mcp: 15-register-mcp`.

Update `.PHONY`: replace `07-venv venv 08-register-mcp register-mcp` with `14-venv venv 15-register-mcp register-mcp`, and add `09-install-retsync install-retsync 10-install-findcrypt install-findcrypt`.

Set `PIPELINE` to:

```make
PIPELINE := 00-deps 00-env 01-checkout 02-build-ghidra 03-install-ghidra 04-install-mcp \
	05-install-lx-loader 06-install-dos-toolbox 09-install-retsync 10-install-findcrypt \
	verify-extensions 14-venv 15-register-mcp test
```

Set the header comment's pipeline lines to:

```make
#   00-deps → 00-env → 01-checkout → 02-build-ghidra → 03-install-ghidra →
#   04-install-mcp → 05-install-lx-loader → 06-install-dos-toolbox →
#   09-install-retsync → 10-install-findcrypt →
#   verify-extensions → 14-venv → 15-register-mcp → test
```

In `clean`, append these paths to the `rm -rf` list:

```make
		ret-sync/ext_ghidra/build ret-sync/ext_ghidra/.gradle \
		GhidraFindcrypt/dist GhidraFindcrypt/build GhidraFindcrypt/.gradle
```

Leave `ret-sync/ext_ghidra/dist` alone: upstream tracks old zips there.

- [ ] **Step 4: Build and run the tests**

```bash
make install-retsync install-findcrypt 2>&1 | grep -E 'Building|installed|ERROR'
make verify-extensions
SANITY_ONLY=extensions,dist make test 2>&1 | tail -16
```

Expected: both extensions install. `VERIFY OK retsync: RetSyncPlugin`, `VERIFY OK GhidraFindcrypt: FindCryptAnalyzer`, `All extension classes loaded.` All `extensions` and `dist` lines PASS.

If a build fails, stop and report the Gradle error. Do not patch upstream build files.

- [ ] **Step 5: Keep `git status` clean**

Run: `git status --short`
If `ret-sync` or `GhidraFindcrypt` shows `m` (untracked build output), run `git config -f .gitmodules submodule.<name>.ignore untracked` for it and re-check.

- [ ] **Step 6: Commit**

```bash
make help | grep -E 'retsync|findcrypt|14-venv|15-register' && make -n install >/dev/null
git add .gitmodules ret-sync GhidraFindcrypt Makefile ghidra_scripts/VerifyExtensions.java tests/run-sanity.sh
git commit -m "feat: add ret-sync and GhidraFindcrypt; renumber venv/register stages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: BinExport

**Files:**
- Modify: `.gitmodules`, plus the new submodule `binexport/`
- Modify: `Makefile` (stage 11, alias, `.PHONY`, `PIPELINE`, header comment, `clean`)
- Modify: `ghidra_scripts/VerifyExtensions.java` (Exporter kind)
- Create: `tests/probes/BinExportProbe.java`
- Modify: `tests/run-sanity.sh` (section `binexport`, `PACKAGE_PATTERNS`, `BUILD_OUTPUTS`)

**Interfaces:**
- Consumes: `run_script`, `want` and `$SAMPLE` (Task 1).
- Produces: `11-install-binexport` (alias `install-binexport`), and the probe `BinExportProbe.java <out file>`, which prints `BINEXPORT OK <bytes>` or `BINEXPORT FAIL`.

- [ ] **Step 1: Add the submodule**

```bash
git submodule add --depth 1 -b main https://github.com/google/binexport.git binexport
git config -f .gitmodules submodule.binexport.shallow true
```

- [ ] **Step 2: Write the failing tests**

In `VerifyExtensions.java`, add the import `import ghidra.app.util.exporter.Exporter;`, and in `run()`:

```java
		check("BinExport", Exporter.class, "BinExportExporter");
```

Create `tests/probes/BinExportProbe.java`:

```java
// Exports the current program with BinExport's exporter, as BinDiff would read it.
// Prints "BINEXPORT OK <bytes>" or "BINEXPORT FAIL". Script argument: output file.
//@category Bundle

import java.io.File;

import com.google.security.binexport.BinExportExporter;

import ghidra.app.script.GhidraScript;

public class BinExportProbe extends GhidraScript {

	@Override
	public void run() throws Exception {
		File out = new File(getScriptArgs()[0]);
		boolean ok = new BinExportExporter().export(out, currentProgram,
			currentProgram.getMemory(), monitor);
		println(ok && out.length() > 0 ? "BINEXPORT OK " + out.length() : "BINEXPORT FAIL");
	}
}
```

In `tests/run-sanity.sh`, append `"ghidra_{v}_*_BinExport.zip"` to `PACKAGE_PATTERNS` and `binexport/java/dist` to `BUILD_OUTPUTS`. Then insert after the `dist` section:

```bash
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
```

Run: `make verify-extensions; SANITY_ONLY=binexport make test 2>&1 | tail -6`
Expected: `MISSING BinExport: BinExportExporter`. The probe fails to compile (`package com.google.security.binexport does not exist`) and the result is `FAIL  BinExport: exporting sample.o failed`.

- [ ] **Step 3: Add the stage**

```make
11-install-binexport: 03-install-ghidra ## Build and install BinExport (exports for BinDiff)
	$(call install_extension,BinExport,binexport,binexport/java/dist/ghidra_$(GHIDRA_VERSION)_*_BinExport.zip,,java)
```

Add the alias `install-binexport: 11-install-binexport`, add both names to `.PHONY`, and insert `11-install-binexport` after `10-install-findcrypt` in `PIPELINE` and in the header comment. Append `binexport/java/dist binexport/java/build binexport/java/.gradle` to `clean`.

BinExport's Gradle build downloads `protoc` for the host platform from Maven Central on its first run.

- [ ] **Step 4: Build and run the tests**

```bash
make install-binexport 2>&1 | grep -E 'Building|installed|ERROR'
make verify-extensions | grep BinExport
SANITY_ONLY=extensions,dist,binexport make test 2>&1 | tail -20
```

Expected: `VERIFY OK BinExport: BinExportExporter`, then `PASS  BinExport: exported sample.o (<n> bytes)` with n > 0, and everything else PASS. If the export throws (upstream issue #166), report the stack trace from `binexport.log` and stop.

- [ ] **Step 5: Commit**

```bash
git status --short   # apply the ignore = untracked fix from Task 3 step 5 if needed
git add .gitmodules binexport Makefile ghidra_scripts/VerifyExtensions.java tests/probes/BinExportProbe.java tests/run-sanity.sh
git commit -m "feat: add BinExport, checked by a headless export

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Absolute paths in `launch.properties`; portable-mode checks

**Files:**
- Create: `scripts/pyghidra-venv-dir.py`
- Modify: `Makefile` (`LAUNCH_PROPS`, stage 03)
- Modify: `tests/run-sanity.sh` (records which leak paths exist at start; section `portable`)

**Interfaces:**
- Produces:
  - `python3 -I scripts/pyghidra-venv-dir.py <install dir> [--settings]` prints PyGhidra's venv directory, or with `--settings` its user settings directory, computed by Ghidra's own `pyghidra_launcher`.
  - In `tests/run-sanity.sh`: `LEAK_PATHS`, `LEAKS_BEFORE`, `check_leaks`, and the `portable` section, which Tasks 6 and 7 extend.

- [ ] **Step 1: Write the helper script**

Create `scripts/pyghidra-venv-dir.py`:

```python
"""Print where pyghidraRun keeps Ghidra's virtualenv (or, with --settings, its user
settings directory) for a Ghidra install. Uses Ghidra's own pyghidra_launcher, so the
answer always matches what pyghidraRun does.

Usage: python3 -I scripts/pyghidra-venv-dir.py <ghidra install dir> [--settings]
"""
import sys
from pathlib import Path

if len(sys.argv) < 2:
    sys.exit(__doc__)
install_dir = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(install_dir / "Ghidra" / "Features" / "PyGhidra" / "support"))
import pyghidra_launcher  # noqa: E402

if "--settings" in sys.argv[2:]:
    print(pyghidra_launcher.get_user_settings_dir(install_dir, False))
else:
    print(pyghidra_launcher.get_ghidra_venv(install_dir, False))
```

- [ ] **Step 2: Write the failing test**

In `tests/run-sanity.sh`, after `trap 'exit 130' INT TERM`, add:

```bash

# Paths that must not appear while the suite runs: Ghidra and the bundled extensions
# keep everything under portable/. "${INSTALL_DIR}" is the relative directory PyGhidra's
# launcher would create from an unexpanded launch.properties line.
LEAK_PATHS=("$HOME/.ghidra" "$HOME/.config/GhidrAssist" "$HOME/.reai"
            "$REPO_DIR/\${INSTALL_DIR}" "$PWD/\${INSTALL_DIR}" "$WORK/\${INSTALL_DIR}")
LEAKS_BEFORE=$'\n'
for leak in "${LEAK_PATHS[@]}"; do
  if [[ -e "$leak" ]]; then LEAKS_BEFORE+="$leak"$'\n'; fi
done
```

Insert after the `binexport` section:

```bash
# ── 3e. Portable mode ─────────────────────────────────────────────────────────
check_pyghidra_settings() {
  local settings
  settings=$(python3 -I "$REPO_DIR/scripts/pyghidra-venv-dir.py" "$INSTALL_DIR" --settings 2>&1) || true
  if [[ "$settings" == "$INSTALL_DIR/portable/settings/"* ]]; then
    pass "portable: pyghidraRun keeps its settings and venv under portable/settings"
  else
    fail "portable: pyghidraRun would keep its settings in '$settings'"
  fi
}

check_leaks() {  # run last: fails for each leak path that appeared during the run
  local leak
  for leak in "${LEAK_PATHS[@]}"; do
    if [[ -e "$leak" && "$LEAKS_BEFORE" != *$'\n'"$leak"$'\n'* ]]; then
      fail "portable: $leak was created during the run"
    fi
  done
  pass "portable: no writes outside portable/ were detected"
}

if want portable; then check_pyghidra_settings; fi
```

Directly before `# ── 4. Snapshot report`, add:

```bash
if want portable; then check_leaks; fi
```

Run: `SANITY_ONLY=portable make test 2>&1 | tail -4`
Expected: `FAIL  portable: pyghidraRun would keep its settings in '${INSTALL_DIR}/portable/settings/ghidra/ghidra_12.1.4_DEV'`.

- [ ] **Step 3: Write absolute paths in stage 03**

In the configuration block, after `PORTABLE_DIR := ...`, add:

```make
LAUNCH_PROPS := $(INSTALL_DIR)/support/launch.properties
```

Replace the start of the `03-install-ghidra` recipe:

```make
	@if grep -qs '^# --- Portable Mode Overrides ---' "$(INSTALL_DIR)/support/launch.properties"; then \
		echo "$(INSTALL_DIR) already installed, skipping."; \
	else \
```

with:

```make
	@if grep -qs '^# --- Portable Mode Overrides ---' "$(LAUNCH_PROPS)"; then \
		if sed -n '/^# --- Portable Mode Overrides ---/,$$p' "$(LAUNCH_PROPS)" | grep -qF '$${INSTALL_DIR}'; then \
			sed '/^# --- Portable Mode Overrides ---/,$$ s|$${INSTALL_DIR}|$(INSTALL_DIR)|g' "$(LAUNCH_PROPS)" \
				> "$(LAUNCH_PROPS).tmp" && mv "$(LAUNCH_PROPS).tmp" "$(LAUNCH_PROPS)" || exit 1; \
			$(OK) "Rewrote the portable-mode paths in launch.properties as absolute paths."; \
		fi; \
		echo "$(INSTALL_DIR) already installed, skipping."; \
	else \
```

PyGhidra's launcher reads `application.settingsdir` from `launch.properties` without expanding `${INSTALL_DIR}`, which is why the paths must be absolute.

Replace the three `VMARGS` lines of the `printf` with:

```make
			'VMARGS=-Dapplication.settingsdir=$(PORTABLE_DIR)/settings' \
			'VMARGS=-Dapplication.cachedir=$(PORTABLE_DIR)/cache' \
			'VMARGS=-Dapplication.tempdir=$(PORTABLE_DIR)/temp' \
```

Also replace `"$(INSTALL_DIR)/support/launch.properties"` at the end of that `printf` with `"$(LAUNCH_PROPS)"`.

- [ ] **Step 4: Run the existing-install path (Review Focus 1)**

```bash
make install-ghidra 2>&1 | tail -2
grep -n 'portable/' dist/ghidra_12.1.4_PUBLIC/support/launch.properties
make install-ghidra 2>&1 | grep -c Rewrote
```

Expected: the first run prints `Rewrote the portable-mode paths ...`. The three lines now read `VMARGS=-Dapplication.settingsdir=/home/.../dist/ghidra_12.1.4_PUBLIC/portable/settings` and so on. The second run prints `0`.

- [ ] **Step 5: Run the fresh-install path**

```bash
mv dist/ghidra_12.1.4_PUBLIC dist/ghidra_12.1.4_PUBLIC.bak
make install-ghidra 2>&1 | tail -1
grep -n 'VMARGS=-Dapplication' dist/ghidra_12.1.4_PUBLIC/support/launch.properties | tail -3
rm -rf dist/ghidra_12.1.4_PUBLIC && mv dist/ghidra_12.1.4_PUBLIC.bak dist/ghidra_12.1.4_PUBLIC
```

Expected: `Installed .../dist/ghidra_12.1.4_PUBLIC in portable mode.`, followed by three absolute `VMARGS` lines with no `${INSTALL_DIR}`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `SANITY_ONLY=portable make test 2>&1 | tail -4`
Expected: `PASS  portable: pyghidraRun keeps its settings and venv under portable/settings` and `PASS  portable: no writes outside portable/ were detected`.

- [ ] **Step 7: Commit**

```bash
git add scripts/pyghidra-venv-dir.py Makefile tests/run-sanity.sh
git commit -m "fix: write absolute portable-mode paths so PyGhidra stays in dist/

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: GhidrAssist from a portable fork

**Files:**
- Modify: `.gitmodules`, plus the new submodule `GhidrAssist/`. The fork commit lives in the submodule.
- Fork files (in `GhidrAssist/`): `src/main/java/ghidrassist/GAUtils.java`, `AnalysisDB.java`, `RLHFDatabase.java`, `ui/tabs/SettingsTab.java`
- Create: `tests/probes/PortablePaths.java`
- Modify: `Makefile` (stage 07, alias, `.PHONY`, `PIPELINE`, header comment, `clean`), `ghidra_scripts/VerifyExtensions.java`, `tests/run-sanity.sh`

**Interfaces:**
- Consumes: `run_script`, `$WORK/probe.bin` and the `portable` section (Tasks 1 and 5).
- Produces:
  - `07-install-ghidrassist` (alias `install-ghidrassist`).
  - `tests/probes/PortablePaths.java [GhidrAssist] [plugin-ghidra]` prints `PORTABLE OK|OUTSIDE|MISSING <label>: <path>`; with no arguments it checks both.
  - `check_portable_paths [ext...]` in `run-sanity.sh`.
  - Fork API: `GAUtils.getDataDirectory()` returns `File`; `GAUtils.getDefaultDataPath(String)` returns `String`.

- [ ] **Step 1: STOP and confirm with the user**

Ask: "Task 6 creates the public fork `felipe-dos-santos81/GhidrAssist` on GitHub and later pushes the `portable-settings` branch and a `bundle-pin-<sha7>` tag to it. OK to proceed?" Continue only after an explicit yes.

- [ ] **Step 2: Fork and add the submodule (stock upstream code first)**

```bash
gh repo fork symgraph/GhidrAssist --clone=false --default-branch-only
git submodule add --depth 1 -b master https://github.com/felipe-dos-santos81/GhidrAssist.git GhidrAssist
git config -f .gitmodules submodule.GhidrAssist.shallow true
```

- [ ] **Step 3: Add the stage and class check; install the stock build**

```make
07-install-ghidrassist: 03-install-ghidra ## Build and install GhidrAssist (LLM assistant; unconfigured)
	$(call install_extension,GhidrAssist,GhidrAssist,GhidrAssist/dist/ghidra_$(GHIDRA_VERSION)_*_GhidrAssist.zip)
```

Add the alias `install-ghidrassist: 07-install-ghidrassist`, add both to `.PHONY`, insert `07-install-ghidrassist` after `06-install-dos-toolbox` in `PIPELINE` and in the header comment, and append `GhidrAssist/dist GhidrAssist/build GhidrAssist/.gradle` to `clean`.

In `VerifyExtensions.java`:

```java
		check("GhidrAssist", Plugin.class, "GhidrAssistPlugin");
```

In `run-sanity.sh`, append `"ghidra_{v}_*_GhidrAssist.zip"` to `PACKAGE_PATTERNS` and `GhidrAssist/dist` to `BUILD_OUTPUTS`.

```bash
make install-ghidrassist 2>&1 | grep -E 'Building|installed|ERROR'
make verify-extensions | grep GhidrAssist
```

Expected: `VERIFY OK GhidrAssist: GhidrAssistPlugin`. If the build fails (it needs Maven Central and JitPack), stop and report the error.

- [ ] **Step 4: Write the failing portable test**

Create `tests/probes/PortablePaths.java`:

```java
// Prints where GhidrAssist and RevEng.AI keep their files by default, one line each:
// "PORTABLE OK|OUTSIDE|MISSING <label>: <path>". OK means inside Ghidra's user settings
// directory, which the bundle's portable mode puts under dist/.../portable/settings.
// Script arguments: extension directory names to check (GhidrAssist, plugin-ghidra);
// none checks both.
//@category Bundle

import java.lang.reflect.Field;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.Callable;

import ghidra.app.script.GhidraScript;
import ghidra.framework.Application;

public class PortablePaths extends GhidraScript {

	private Path settings;

	@Override
	public void run() throws Exception {
		settings = Application.getUserSettingsDirectory().toPath().toAbsolutePath().normalize();
		List<String> wanted = List.of(getScriptArgs());
		if (wanted.isEmpty() || wanted.contains("GhidrAssist")) {
			check("GhidrAssist Lucene index", () -> {
				Class<?> os = Class.forName("ghidrassist.GAUtils$OperatingSystem");
				Object current = os.getMethod("detect").invoke(null);
				return Class.forName("ghidrassist.GAUtils")
						.getMethod("getDefaultLucenePath", os)
						.invoke(null, current);
			});
			check("GhidrAssist analysis DB", () -> staticField("ghidrassist.AnalysisDB", "DEFAULT_DB_PATH"));
			check("GhidrAssist RLHF DB", () -> staticField("ghidrassist.RLHFDatabase", "DEFAULT_DB_PATH"));
		}
		if (wanted.isEmpty() || wanted.contains("plugin-ghidra")) {
			check("RevEng.AI config", () -> staticField(
				"ai.reveng.toolkit.ghidra.plugins.ReaiPluginPackage", "DEFAULT_CONFIG_PATH"));
		}
	}

	private static Object staticField(String className, String name) throws Exception {
		Field field = Class.forName(className).getDeclaredField(name);
		field.setAccessible(true);
		return field.get(null);
	}

	private void check(String label, Callable<Object> source) {
		try {
			Path path = Path.of(String.valueOf(source.call())).toAbsolutePath().normalize();
			println("PORTABLE " + (path.startsWith(settings) ? "OK" : "OUTSIDE") + " " + label + ": " + path);
		}
		catch (Exception | LinkageError e) {
			println("PORTABLE MISSING " + label + ": " + e);
		}
	}
}
```

In `tests/run-sanity.sh`, in the `portable` section, add after `check_pyghidra_settings() { … }`:

```bash
check_portable_paths() {  # check_portable_paths [extension dir...]: run PortablePaths.java
  local log="$WORK/portable-paths.log" line
  if ! run_script "$log" "$WORK/probe.bin" PortablePaths.java "$@"; then
    fail_with_log "portable: PortablePaths.java did not run" "$log"
    return
  fi
  if ! grep -q 'PORTABLE ' "$log"; then
    fail_with_log "portable: PortablePaths.java printed nothing" "$log"
    return
  fi
  while IFS= read -r line; do
    line=${line% }
    case "$line" in
      "PORTABLE OK "*) pass "portable: ${line#PORTABLE OK }" ;;
      *) fail "portable: ${line#PORTABLE }" ;;
    esac
  done < <(grep -o 'PORTABLE [A-Z]* [^(]*' "$log")
}
```

and change `if want portable; then check_pyghidra_settings; fi` to:

```bash
if want portable; then
  check_pyghidra_settings
  check_portable_paths GhidrAssist
fi
```

Run: `SANITY_ONLY=portable make test 2>&1 | grep -E 'PASS|FAIL'`
Expected: three FAILs: `OUTSIDE GhidrAssist Lucene index: /home/.../.config/GhidrAssist/LuceneIndex`, and `OUTSIDE GhidrAssist analysis DB: .../ghidrassist_analysis.db` and `OUTSIDE GhidrAssist RLHF DB: ...`, which point at the current directory.

- [ ] **Step 5: Patch the fork**

```bash
cd GhidrAssist && git checkout -b portable-settings
```

In `src/main/java/ghidrassist/GAUtils.java`, add `import ghidra.framework.Application;` after `import java.io.File;`, and replace the whole `getDefaultLucenePath` method with:

```java
	/**
	 * Directory for GhidrAssist's own files (Lucene index, databases). It lives in
	 * Ghidra's user settings directory, so portable Ghidra installs keep everything
	 * in one place and nothing is written to the home directory.
	 */
	public static File getDataDirectory() {
		File dir = new File(Application.getUserSettingsDirectory(), "GhidrAssist");
		dir.mkdirs();
		return dir;
	}

	/** Default location of a GhidrAssist data file when no preference overrides it. */
	public static String getDefaultDataPath(String fileName) {
		return new File(getDataDirectory(), fileName).getPath();
	}

	public static String getDefaultLucenePath(OperatingSystem os) {
		return new File(getDataDirectory(), "LuceneIndex").getPath();
	}
```

In `src/main/java/ghidrassist/AnalysisDB.java`, line 27:

```java
    private static final String DEFAULT_DB_PATH = GAUtils.getDefaultDataPath("ghidrassist_analysis.db");
```

In `src/main/java/ghidrassist/RLHFDatabase.java`, line 11:

```java
    private static final String DEFAULT_DB_PATH = GAUtils.getDefaultDataPath("ghidrassist_rlhf.db");
```

In `src/main/java/ghidrassist/ui/tabs/SettingsTab.java`, add `import ghidrassist.GAUtils;` if it is missing, and change lines 398 and 407 to:

```java
        analysisDbPathField.setText(Preferences.getProperty("GhidrAssist.AnalysisDBPath", GAUtils.getDefaultDataPath("ghidrassist_analysis.db")));
```

```java
        rlhfDbPathField.setText(Preferences.getProperty("GhidrAssist.RLHFDatabasePath", GAUtils.getDefaultDataPath("ghidrassist_rlhf.db")));
```

Check that nothing else still points at `user.home`. `AnthropicClaudeCliProvider` only *reads* `~` to find the Claude CLI, so that hit is expected:

```bash
grep -rn 'user.home\|"ghidrassist_analysis.db"\|"ghidrassist_rlhf.db"' src/main/java
```

Expected: only `AnthropicClaudeCliProvider.java`.

Commit inside the fork:

```bash
git commit -am "Keep GhidrAssist data in Ghidra's user settings directory

The Lucene index went to ~/.config/GhidrAssist (or ~/Library/Application Support),
and the analysis and RLHF databases defaulted to paths relative to the directory
Ghidra was started from. Both now default to <Ghidra user settings>/GhidrAssist, so
portable Ghidra installs (application.settingsdir) keep all their data together.
User-set database paths are unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
cd ..
```

- [ ] **Step 6: Build and run the tests**

```bash
make install-ghidrassist 2>&1 | grep -E 'Building|installed|ERROR'
SANITY_ONLY=extensions,dist,portable make test 2>&1 | tail -20
```

Expected: `Building GhidrAssist from <new sha7>...`. The three GhidrAssist `portable:` lines PASS, and so do `extensions` and `dist`.

- [ ] **Step 7: Push and pin (the step 1 approval covers this)**

```bash
cd GhidrAssist
SHA=$(git rev-parse --short=7 HEAD)
git push -u origin portable-settings
git tag "bundle-pin-$SHA" && git push origin "bundle-pin-$SHA"
cd ..
git config -f .gitmodules submodule.GhidrAssist.branch portable-settings
```

- [ ] **Step 8: Commit the bundle**

```bash
git status --short   # apply the ignore = untracked fix from Task 3 step 5 if needed
git add .gitmodules GhidrAssist Makefile ghidra_scripts/VerifyExtensions.java tests/probes/PortablePaths.java tests/run-sanity.sh
git commit -m "feat: add GhidrAssist from a fork that keeps its data in portable/

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Ask the user whether to open an upstream PR (symgraph/GhidrAssist ← felipe-dos-santos81:portable-settings). Do not open it without a yes.

---

### Task 7: RevEng.AI plugin from a portable fork

**Files:**
- Modify: `.gitmodules`, plus the new submodule `plugin-ghidra/`
- Fork file: `plugin-ghidra/src/main/java/ai/reveng/toolkit/ghidra/plugins/ReaiPluginPackage.java`
- Modify: `Makefile` (stage 08 and the usual places), `ghidra_scripts/VerifyExtensions.java`, `tests/run-sanity.sh`

**Interfaces:**
- Consumes: `PortablePaths.java` and `check_portable_paths` (Task 6).
- Produces: `08-install-reveng` (alias `install-reveng`); the `portable` section calls `check_portable_paths` with no arguments (both extensions).

- [ ] **Step 1: STOP and confirm with the user**

Ask: "Task 7 creates the public fork `felipe-dos-santos81/plugin-ghidra` and later pushes `portable-settings` and a `bundle-pin-<sha7>` tag. OK to proceed?" Continue only after an explicit yes.

- [ ] **Step 2: Fork and add the submodule**

```bash
gh repo fork RevEngAI/plugin-ghidra --clone=false --default-branch-only
git submodule add --depth 1 -b main https://github.com/felipe-dos-santos81/plugin-ghidra.git plugin-ghidra
git config -f .gitmodules submodule.plugin-ghidra.shallow true
```

The path must be exactly `plugin-ghidra`: without a `settings.gradle`, Gradle names the extension, and so its jar, after this directory.

- [ ] **Step 3: Add the stage and class check; install the stock build**

```make
08-install-reveng: 03-install-ghidra ## Build and install the RevEng.AI plugin (cloud; unconfigured)
	$(call install_extension,plugin-ghidra,plugin-ghidra,plugin-ghidra/dist/ghidra_$(GHIDRA_VERSION)_*_plugin-ghidra.zip)
```

Add the alias `install-reveng: 08-install-reveng`, add both to `.PHONY`, insert `08-install-reveng` after `07-install-ghidrassist` in `PIPELINE` and in the header comment, and append `plugin-ghidra/dist plugin-ghidra/build plugin-ghidra/.gradle` to `clean`.

In `VerifyExtensions.java`:

```java
		check("plugin-ghidra", Plugin.class, "ReaiAPIServicePlugin");
```

In `run-sanity.sh`, append `"ghidra_{v}_*_plugin-ghidra.zip"` to `PACKAGE_PATTERNS` and `plugin-ghidra/dist` to `BUILD_OUTPUTS`, and change `check_portable_paths GhidrAssist` to `check_portable_paths` (no arguments: both extensions).

```bash
make install-reveng 2>&1 | grep -E 'Building|installed|ERROR'
make verify-extensions | grep plugin-ghidra
SANITY_ONLY=portable make test 2>&1 | grep -E 'PASS|FAIL'
```

Expected: `VERIFY OK plugin-ghidra: ReaiAPIServicePlugin`, then `FAIL  portable: OUTSIDE RevEng.AI config: /home/.../.reai/reai.json`, with the GhidrAssist lines still PASS.

- [ ] **Step 4: Patch the fork**

```bash
cd plugin-ghidra && git checkout -b portable-settings
```

In `src/main/java/ai/reveng/toolkit/ghidra/plugins/ReaiPluginPackage.java`, add `import ghidra.framework.Application;` with the other `ghidra.*` imports, and replace line 29 with:

```java
    /** Default config file, in Ghidra's user settings directory (portable installs keep it there). */
    public static final Path DEFAULT_CONFIG_PATH =
            Application.getUserSettingsDirectory().toPath().resolve("reai").resolve("reai.json");
```

`SetupWizardManager` already creates the parent directory. Check what else references the old path:

```bash
grep -rn 'user.home\|\.reai' src/main/java src/test/java
```

Expected: no `user.home` in `src/main/java`. Leave any test-only references alone and mention them in the PR.

```bash
git commit -am "Keep reai.json in Ghidra's user settings directory

The API key config went to ~/.reai/reai.json. It now defaults to
<Ghidra user settings>/reai/reai.json, so portable Ghidra installs
(application.settingsdir) keep it with the rest of their settings.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
cd ..
```

- [ ] **Step 5: Build and run the tests**

```bash
make install-reveng 2>&1 | grep -E 'Building|installed|ERROR'
SANITY_ONLY=extensions,dist,portable make test 2>&1 | tail -24
```

Expected: every line PASSes, including `portable: RevEng.AI config: .../portable/settings/ghidra/ghidra_12.1.4_DEV/reai/reai.json`.

- [ ] **Step 6: Push and pin**

```bash
cd plugin-ghidra
SHA=$(git rev-parse --short=7 HEAD)
git push -u origin portable-settings
git tag "bundle-pin-$SHA" && git push origin "bundle-pin-$SHA"
cd ..
git config -f .gitmodules submodule.plugin-ghidra.branch portable-settings
```

- [ ] **Step 7: Commit the bundle**

```bash
git status --short
git add .gitmodules plugin-ghidra Makefile ghidra_scripts/VerifyExtensions.java tests/run-sanity.sh
git commit -m "feat: add the RevEng.AI plugin from a fork that keeps its key in portable/

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Ask the user whether to open the upstream PR (RevEngAI/plugin-ghidra ← felipe-dos-santos81:portable-settings). Do not open it without a yes.

---

### Task 8: Jython and D2GridraTools

**Files:**
- Modify: `.gitmodules`, plus the new submodule `D2GridraTools/`
- Create: `scripts/install-d2gridratools.sh`
- Create: `tests/probes/JythonProbe.py`
- Modify: `Makefile` (stage 12 and the usual places), `ghidra_scripts/VerifyExtensions.java`, `tests/run-sanity.sh` (section `jython`)

**Interfaces:**
- Consumes: `run_script` and `$WORK/probe.bin` (Task 1).
- Produces:
  - `12-install-scripts` (alias `install-scripts`).
  - `scripts/install-d2gridratools.sh <D2GridraTools checkout> <Ghidra Extensions dir> <Ghidra version>`.
  - `JythonProbe.py`, which prints `JYTHON OK <version>` or `JYTHON WRONG <platform>`.

- [ ] **Step 1: Add the submodule**

```bash
git submodule add --depth 1 -b main https://github.com/dzik87/D2GridraTools.git D2GridraTools
git config -f .gitmodules submodule.D2GridraTools.shallow true
ls D2GridraTools/*.py | wc -l
```

Expected: `10`. One of the scripts is named `Imports fixer.py`, with a space.

- [ ] **Step 2: Write the failing tests**

In `VerifyExtensions.java`, add `import ghidra.app.script.GhidraScriptProvider;` and:

```java
		check("Jython", GhidraScriptProvider.class, "JythonScriptProvider");
```

Create `tests/probes/JythonProbe.py`:

```python
# Prints "JYTHON OK <version>" when Ghidra runs this script under Jython, and
# "JYTHON WRONG <platform>" under any other Python runtime.
# @category Bundle
# @runtime Jython
import sys

if sys.platform.startswith("java"):
    print("JYTHON OK " + sys.version.split()[0])
else:
    print("JYTHON WRONG " + sys.platform)
```

In `tests/run-sanity.sh`, insert after the `if want portable; then … fi` block that calls `check_pyghidra_settings` (not the `check_leaks` line, which stays last):

```bash
# ── 3f. Jython and D2GridraTools ──────────────────────────────────────────────
check_jython() {
  local log="$WORK/jython.log" d2="$INSTALL_DIR/Ghidra/Extensions/D2GridraTools/ghidra_scripts"
  local f total=0 tagged=0
  if run_script "$log" "$WORK/probe.bin" JythonProbe.py && grep -q 'JYTHON OK' "$log"; then
    pass "Jython: a @runtime Jython script runs under Jython"
  else
    fail_with_log "Jython: JythonProbe.py did not run under Jython" "$log"
  fi
  for f in "$d2"/*.py; do
    if [[ ! -e "$f" ]]; then continue; fi
    total=$((total + 1))
    if grep -q '^#[[:space:]]*@runtime Jython' "$f"; then tagged=$((tagged + 1)); fi
  done
  if ((total > 0 && tagged == total)); then
    pass "D2GridraTools: all $total scripts run under Jython"
  else
    fail "D2GridraTools: $tagged of $total scripts tagged '@runtime Jython' in $d2"
  fi
  if grep -q '@runtime Jython' "$d2/Imports fixer.py" 2>/dev/null; then
    pass "D2GridraTools: script names with spaces are kept"
  else
    fail "D2GridraTools: 'Imports fixer.py' is missing or untagged in $d2"
  fi
}

if want jython; then check_jython; fi
```

Run: `make verify-extensions | grep Jython; SANITY_ONLY=jython make test 2>&1 | grep -E 'PASS|FAIL'`
Expected: `MISSING Jython: JythonScriptProvider`. Three FAILs: the probe did not run (the log mentions no provider for `.py` with `@runtime Jython`), `0 of 0 scripts`, and `'Imports fixer.py' is missing`.

- [ ] **Step 3: Write the assembly script**

Create `scripts/install-d2gridratools.sh`:

```bash
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
cat > "$tmp/extension.properties" <<EOF
name=D2GridraTools
description=Diablo 2 1.14d scripts by dzik87 (github.com/dzik87/D2GridraTools), run under Jython. Unlicensed upstream: fetched, not redistributed.
author=dzik87
createdOn=
version=$VERSION
EOF
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
```

```bash
chmod +x scripts/install-d2gridratools.sh && bash -n scripts/install-d2gridratools.sh
```

- [ ] **Step 4: Add stage 12**

```make
12-install-scripts: 03-install-ghidra ## Install Jython and the D2GridraTools scripts (run under Jython)
	@if [ -d "$(EXT_DIR)/Jython" ]; then \
		echo "Jython already installed, skipping."; \
	else \
		ZIP=$$(ls -1t "$(INSTALL_DIR)"/Extensions/Ghidra/ghidra_$(GHIDRA_VERSION)_*_Jython.zip 2>/dev/null | head -n 1); \
		[ -n "$$ZIP" ] || { $(ERR) "no Jython extension zip in $(INSTALL_DIR)/Extensions/Ghidra/"; exit 1; }; \
		unzip -q -o "$$ZIP" -d "$(EXT_DIR)" || exit 1; \
		[ -d "$(EXT_DIR)/Jython" ] || { $(ERR) "$$ZIP did not create $(EXT_DIR)/Jython"; exit 1; }; \
		$(OK) "Jython installed."; \
	fi
	@scripts/install-d2gridratools.sh D2GridraTools "$(EXT_DIR)" "$(GHIDRA_VERSION)"
```

Add the alias `install-scripts: 12-install-scripts`, add both to `.PHONY`, and insert `12-install-scripts` after `11-install-binexport` (before `verify-extensions`) in `PIPELINE` and in the header comment.

- [ ] **Step 5: Install and run the tests**

```bash
make install-scripts
make install-scripts | grep -c skipping
SANITY_ONLY=extensions,jython make test 2>&1 | tail -16
head -8 "dist/ghidra_12.1.4_PUBLIC/Ghidra/Extensions/D2GridraTools/ghidra_scripts/Imports fixer.py"
git -C D2GridraTools status --short | wc -l
```

Expected:
- `Jython installed.` and `D2GridraTools installed from <sha7> (10 scripts).`, then `2` on the second run.
- All PASS, including `VERIFY OK Jython: JythonScriptProvider` inside the extensions check.
- The header ends with `#@toolbar`, followed by `#@runtime Jython`.
- `0`: the checkout is untouched.

- [ ] **Step 6: Break it on purpose, then restore**

```bash
D2="dist/ghidra_12.1.4_PUBLIC/Ghidra/Extensions/D2GridraTools"
sed -i.bak '/@runtime Jython/d' "$D2/ghidra_scripts/namespacer.py" && rm "$D2/ghidra_scripts/namespacer.py.bak"
SANITY_ONLY=jython make test 2>&1 | grep FAIL
rm "$D2/.bundle-source" && make install-scripts | tail -1
SANITY_ONLY=jython make test 2>&1 | tail -1
```

Expected: `FAIL  D2GridraTools: 9 of 10 scripts tagged '@runtime Jython' in ...`. Then the stage reassembles the extension (`D2GridraTools installed from <sha7> (10 scripts).`) and the run ends with `3 passed, 0 failed, 0 skipped`.

- [ ] **Step 7: Commit**

```bash
git add .gitmodules D2GridraTools scripts/install-d2gridratools.sh tests/probes/JythonProbe.py Makefile ghidra_scripts/VerifyExtensions.java tests/run-sanity.sh
git commit -m "feat: add Jython and the D2GridraTools scripts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `bundle_mpq`, a ctypes MPQ reader

**Files:**
- Create: `python/bundle-mpq/pyproject.toml`
- Create: `python/bundle-mpq/bundle_mpq/__init__.py`
- Create: `tests/make_mpq.py`
- Create: `tests/test_bundle_mpq.py`
- Modify: `Makefile` (`00-deps`, `00-env`, `clean`), `.gitignore`

**Interfaces:**
- Produces:
  - `bundle_mpq.MpqArchive(path)`: context manager. `.names(mask="*")` returns `list[str]`; `.read(name)` returns `bytes` (`/` is treated as `\`, case-insensitive); `.close()`.
  - `bundle_mpq.MpqError(OSError)`.
  - `bundle_mpq.load_stormlib()` returns a `ctypes.CDLL`. With `BUNDLE_STORMLIB` set, it tries only that path.
  - `tests/make_mpq.py`: `write_mpq(path, files: dict[str, bytes])`. CLI: `make_mpq.py <out.mpq> <expected-bytes file>` writes `NAME`, holding `TEXT`, and prints `NAME`.

- [ ] **Step 1: Install StormLib through `make deps`**

In `00-deps`, Darwin branch, before `command -v clang ...`, add:

```make
		brew list stormlib >/dev/null 2>&1 || brew install stormlib || \
			$(WARN) "stormlib not available from Homebrew; MPQ support stays off"; \
```

In the Linux branch, after the `python3 -c 'import venv' ...` line, add:

```make
		python3 -c 'import ctypes.util, sys; sys.exit(not ctypes.util.find_library("storm"))' \
			|| PKGS+=" libstorm-dev"; \
```

In `00-env`, before the final `$(OK)`, add the following (StormLib is optional):

```make
	@if python3 -c 'import ctypes.util, sys; sys.exit(not ctypes.util.find_library("storm"))' 2>/dev/null; then \
		printf '\033[32m✔ %-7s\033[0m %s\n' "StormLib" "found (MPQ support)"; \
	else \
		$(WARN) "StormLib not found: optional, needed to open MPQ archives (run 'make deps')"; \
	fi
```

Change `00-env`'s description to `## Check host prerequisites (JDK 21, Maven, Clang, Python 3, uv, Git, curl, GNU timeout; StormLib optional)`.

Run: `make deps && make env | tail -3`
Expected: apt installs `libstorm-dev` (a sudo prompt is expected), then `✔ StormLib found (MPQ support)`.

- [ ] **Step 2: Write the failing tests**

Create `tests/make_mpq.py`:

```python
"""Write a small MPQ v1 archive for tests, with PKWARE-compressed files (the
compression Diablo 2's archives use).

StormLib's SCompCompress does the compression; this file writes the container
(header, encrypted hash and block tables) itself, because StormLib's own archive
writing aborts on some distributions (Ubuntu noble's 9.22 package).

CLI: make_mpq.py <out.mpq> <expected-bytes file>  - writes NAME holding TEXT, prints NAME.
"""
import ctypes
import struct
import sys

from bundle_mpq import load_stormlib

NAME = "data\\global\\excel\\bundle.txt"
TEXT = b"Stay awhile and listen. " * 100

SECTOR_SHIFT = 3                  # sector size 512 << 3 = 4096 bytes
MPQ_FILE_COMPRESS = 0x00000200
MPQ_FILE_EXISTS = 0x80000000
MPQ_COMPRESSION_PKWARE = 0x08
KEY_HASH_TABLE = 0xC3AF3770       # HashString("(hash table)", 0x300)
KEY_BLOCK_TABLE = 0xEC83B3A3      # HashString("(block table)", 0x300)
MASK = 0xFFFFFFFF


def _crypt_table():
    table, seed = [0] * 0x500, 0x00100001
    for first in range(0x100):
        index = first
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            high = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            table[index] = high | (seed & 0xFFFF)
            index += 0x100
    return table


CRYPT_TABLE = _crypt_table()


def hash_string(name, kind):
    """MPQ name hash, as StormLib computes it: case-insensitive, slashes kept as-is."""
    seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in name.upper().encode("latin-1"):
        seed1 = (CRYPT_TABLE[kind + ch] ^ (seed1 + seed2)) & MASK
        seed2 = (ch + seed1 + seed2 + (seed2 << 5) + 3) & MASK
    return seed1


def encrypt(data, key):
    out, seed = [], 0xEEEEEEEE
    for (value,) in struct.iter_unpack("<I", data):
        seed = (seed + CRYPT_TABLE[0x400 + (key & 0xFF)]) & MASK
        out.append(value ^ ((key + seed) & MASK))
        key = ((((~key) << 0x15) + 0x11111111) & MASK) | (key >> 0x0B)
        seed = (value + seed + (seed << 5) + 3) & MASK
    return struct.pack(f"<{len(out)}I", *out)


def _pkware(lib, data):
    lib.SCompCompress.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.c_void_p,
                                  ctypes.c_int, ctypes.c_uint, ctypes.c_int, ctypes.c_int]
    lib.SCompCompress.restype = ctypes.c_int
    out = ctypes.create_string_buffer(len(data) * 2 + 64)
    size = ctypes.c_int(len(out))
    if not lib.SCompCompress(out, ctypes.byref(size), data, len(data), MPQ_COMPRESSION_PKWARE, 0, 0):
        raise RuntimeError("SCompCompress failed")
    return out.raw[:size.value]   # begins with the compression-type byte 0x08


def write_mpq(path, files):
    """Write files ({name: bytes}, each at most 4096 bytes) plus a (listfile) to path."""
    assert hash_string("(hash table)", 0x300) == KEY_HASH_TABLE
    assert hash_string("(block table)", 0x300) == KEY_BLOCK_TABLE
    lib = load_stormlib()
    files = dict(files)
    files["(listfile)"] = "".join(f"{n}\r\n" for n in files).encode("latin-1")
    hash_size, free = 16, b"\xff" * 16
    body, blocks, hashes = b"", [], [free] * hash_size
    for index, (name, data) in enumerate(files.items()):
        assert len(data) <= 512 << SECTOR_SHIFT, "single-sector files only"
        sector = _pkware(lib, data)
        if len(sector) < len(data):
            payload = struct.pack("<2I", 8, 8 + len(sector)) + sector   # sector offset table
            flags = MPQ_FILE_COMPRESS | MPQ_FILE_EXISTS
        else:                                                         # stored, as StormLib does
            payload, flags = data, MPQ_FILE_EXISTS
        blocks.append(struct.pack("<4I", 32 + len(body), len(payload), len(data), flags))
        body += payload
        slot = hash_string(name, 0x000) % hash_size
        while hashes[slot] != free:
            slot = (slot + 1) % hash_size
        hashes[slot] = struct.pack("<2I2HI", hash_string(name, 0x100), hash_string(name, 0x200),
                                   0, 0, index)
    hash_pos = 32 + len(body)
    block_pos = hash_pos + 16 * hash_size
    header = struct.pack("<4s2I2H4I", b"MPQ\x1a", 32, block_pos + 16 * len(blocks), 0,
                         SECTOR_SHIFT, hash_pos, block_pos, hash_size, len(blocks))
    with open(path, "wb") as f:
        f.write(header + body + encrypt(b"".join(hashes), KEY_HASH_TABLE)
                + encrypt(b"".join(blocks), KEY_BLOCK_TABLE))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: make_mpq.py <out.mpq> <expected-bytes file>")
    write_mpq(sys.argv[1], {NAME: TEXT})
    with open(sys.argv[2], "wb") as f:
        f.write(TEXT)
    print(NAME)
```

Create `tests/test_bundle_mpq.py`:

```python
"""Unit tests for bundle_mpq (python/bundle-mpq). `make test` runs them with the PyGhidra
venv's Python; by hand:

    PYTHONPATH=python/bundle-mpq python3 tests/test_bundle_mpq.py

Archive tests are skipped when StormLib (libstorm) is missing.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bundle_mpq  # noqa: E402
from make_mpq import NAME, TEXT, write_mpq  # noqa: E402

try:
    bundle_mpq.load_stormlib()
    HAVE_STORMLIB = True
except bundle_mpq.MpqError:
    HAVE_STORMLIB = False


@unittest.skipUnless(HAVE_STORMLIB, "StormLib (libstorm) not found")
class MpqArchiveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "test.mpq")
        write_mpq(self.path, {NAME: TEXT})

    def tearDown(self):
        self.tmp.cleanup()

    def test_reads_pkware_compressed_file(self):
        with bundle_mpq.MpqArchive(self.path) as mpq:
            self.assertEqual(mpq.read(NAME), TEXT)

    def test_fixture_is_really_compressed(self):
        self.assertLess(os.path.getsize(self.path), len(TEXT))

    def test_names_come_from_the_listfile(self):
        with bundle_mpq.MpqArchive(self.path) as mpq:
            self.assertEqual(sorted(mpq.names()), sorted([NAME, "(listfile)"]))

    def test_lookup_ignores_case_and_slash_direction(self):
        with bundle_mpq.MpqArchive(self.path) as mpq:
            self.assertEqual(mpq.read(NAME.upper().replace("\\", "/")), TEXT)

    def test_missing_file_raises(self):
        with bundle_mpq.MpqArchive(self.path) as mpq:
            with self.assertRaises(bundle_mpq.MpqError):
                mpq.read("no\\such\\file.txt")

    def test_non_mpq_raises(self):
        bad = os.path.join(self.tmp.name, "bad.mpq")
        with open(bad, "wb") as f:
            f.write(b"not an archive " * 20)
        with self.assertRaises(bundle_mpq.MpqError):
            bundle_mpq.MpqArchive(bad)

    def test_closed_archive_raises(self):
        mpq = bundle_mpq.MpqArchive(self.path)
        mpq.close()
        with self.assertRaises(bundle_mpq.MpqError):
            mpq.read(NAME)


class LoadStormlibTest(unittest.TestCase):
    def test_bad_override_raises_mpq_error(self):
        saved = os.environ.get("BUNDLE_STORMLIB")
        os.environ["BUNDLE_STORMLIB"] = "/nonexistent/libstorm.so"
        try:
            with self.assertRaises(bundle_mpq.MpqError) as ctx:
                bundle_mpq.load_stormlib()
            self.assertIn("/nonexistent/libstorm.so", str(ctx.exception))
        finally:
            if saved is None:
                del os.environ["BUNDLE_STORMLIB"]
            else:
                os.environ["BUNDLE_STORMLIB"] = saved


if __name__ == "__main__":
    unittest.main()
```

Run: `PYTHONPATH=python/bundle-mpq python3 tests/test_bundle_mpq.py`
Expected: `ModuleNotFoundError: No module named 'bundle_mpq'`.

- [ ] **Step 3: Write the package**

Create `python/bundle-mpq/pyproject.toml`:

```toml
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "bundle-mpq"
version = "1.0.0"
description = "Read-only MPQ archive access through StormLib (ctypes), for PyGhidra scripts"
requires-python = ">=3.9"
license = { text = "MIT" }

[tool.setuptools]
packages = ["bundle_mpq"]
```

Create `python/bundle-mpq/bundle_mpq/__init__.py`:

```python
"""Read-only MPQ (Blizzard archive) access through StormLib (libstorm), via ctypes.

    from bundle_mpq import MpqArchive
    with MpqArchive("d2data.mpq") as mpq:
        names = mpq.names()                        # needs a (listfile) in the archive
        data = mpq.read("data/global/excel/Weapons.txt")

Set BUNDLE_STORMLIB to a libstorm path to use a specific library.
"""
import ctypes
import ctypes.util
import os

__all__ = ["MpqArchive", "MpqError", "load_stormlib"]

_MAX_PATH = 1024              # StormPort.h, non-Windows
_MPQ_OPEN_READ_ONLY = 0x100   # STREAM_FLAG_READ_ONLY
_SFILE_OPEN_FROM_MPQ = 0
_ERROR_HANDLE_EOF = 1002      # StormPort.h, non-Windows
_DWORD = ctypes.c_uint
_HANDLE = ctypes.c_void_p


class _FindData(ctypes.Structure):  # SFILE_FIND_DATA
    _fields_ = [
        ("cFileName", ctypes.c_char * _MAX_PATH),
        ("szPlainName", ctypes.c_char_p),
        ("dwHashIndex", _DWORD),
        ("dwBlockIndex", _DWORD),
        ("dwFileSize", _DWORD),
        ("dwFileFlags", _DWORD),
        ("dwCompSize", _DWORD),
        ("dwFileTimeLo", _DWORD),
        ("dwFileTimeHi", _DWORD),
        ("lcLocale", _DWORD),
    ]


class MpqError(OSError):
    pass


def load_stormlib():
    """Load libstorm: only $BUNDLE_STORMLIB when set, else the usual library names."""
    override = os.environ.get("BUNDLE_STORMLIB")
    names = [override] if override else [
        ctypes.util.find_library("storm"), "libstorm.so.9", "libstorm.so", "libstorm.dylib"]
    errors = []
    for name in filter(None, names):
        try:
            lib = ctypes.CDLL(name)
        except OSError as e:
            errors.append(str(e))
            continue
        _declare(lib)
        return lib
    raise MpqError("StormLib (libstorm) not found; install libstorm-dev or set BUNDLE_STORMLIB"
                   + (f" ({'; '.join(errors)})" if errors else ""))


def _declare(lib):
    ptr, h = ctypes.POINTER, _HANDLE
    signatures = {
        "SFileOpenArchive": ([ctypes.c_char_p, _DWORD, _DWORD, ptr(h)], ctypes.c_bool),
        "SFileCloseArchive": ([h], ctypes.c_bool),
        "SFileOpenFileEx": ([h, ctypes.c_char_p, _DWORD, ptr(h)], ctypes.c_bool),
        "SFileGetFileSize": ([h, ptr(_DWORD)], _DWORD),
        "SFileReadFile": ([h, ctypes.c_void_p, _DWORD, ptr(_DWORD), ctypes.c_void_p], ctypes.c_bool),
        "SFileCloseFile": ([h], ctypes.c_bool),
        "SFileFindFirstFile": ([h, ctypes.c_char_p, ptr(_FindData), ctypes.c_char_p], h),
        "SFileFindNextFile": ([h, ptr(_FindData)], ctypes.c_bool),
        "SFileFindClose": ([h], ctypes.c_bool),
        "GetLastError": ([], _DWORD),
    }
    for name, (argtypes, restype) in signatures.items():
        function = getattr(lib, name)
        function.argtypes, function.restype = argtypes, restype


class MpqArchive:
    """A read-only MPQ archive."""

    def __init__(self, path):
        self._lib = load_stormlib()
        self._handle = _HANDLE()
        if not self._lib.SFileOpenArchive(os.fsencode(path), 0, _MPQ_OPEN_READ_ONLY,
                                          ctypes.byref(self._handle)):
            self._handle = _HANDLE()
            raise MpqError(f"cannot open MPQ {path} (StormLib error {self._lib.GetLastError()})")

    def close(self):
        if self._handle:
            self._lib.SFileCloseArchive(self._handle)
            self._handle = _HANDLE()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def _check_open(self):
        if not self._handle:
            raise MpqError("MPQ archive is closed")

    def names(self, mask="*"):
        """Names of the files in the archive (read from its (listfile))."""
        self._check_open()
        data = _FindData()
        find = self._lib.SFileFindFirstFile(self._handle, mask.encode("latin-1"),
                                            ctypes.byref(data), None)
        if not find:
            return []
        result = []
        try:
            while True:
                result.append(data.cFileName.decode("latin-1"))
                if not self._lib.SFileFindNextFile(find, ctypes.byref(data)):
                    break
        finally:
            self._lib.SFileFindClose(find)
        return result

    def read(self, name):
        """Decompressed contents of one file. Case-insensitive; "/" works like "\\"."""
        self._check_open()
        handle = _HANDLE()
        key = name.replace("/", "\\").encode("latin-1")
        if not self._lib.SFileOpenFileEx(self._handle, key, _SFILE_OPEN_FROM_MPQ,
                                         ctypes.byref(handle)):
            raise MpqError(f"{name}: not in archive (StormLib error {self._lib.GetLastError()})")
        try:
            size = self._lib.SFileGetFileSize(handle, None)
            buf = ctypes.create_string_buffer(size)
            got = _DWORD()
            ok = self._lib.SFileReadFile(handle, buf, size, ctypes.byref(got), None)
            if (not ok and self._lib.GetLastError() != _ERROR_HANDLE_EOF) or got.value != size:
                raise MpqError(f"{name}: read {got.value} of {size} bytes "
                               f"(StormLib error {self._lib.GetLastError()})")
            return buf.raw
        finally:
            self._lib.SFileCloseFile(handle)
```

Check the struct layout against the installed headers:

```bash
grep -n 'define MAX_PATH\|typedef unsigned int   LCID' /usr/include/StormPort.h
grep -n -A11 'typedef struct _SFILE_FIND_DATA' /usr/include/StormLib.h
```

Expected: `MAX_PATH 1024` (the non-Windows branch), `LCID` is `unsigned int`, and the struct fields appear in the order of `_FindData`. If they differ, update `_FindData` to match before going on.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `PYTHONPATH=python/bundle-mpq python3 tests/test_bundle_mpq.py -v`
Expected: 8 tests, all `ok`, none skipped.

- [ ] **Step 5: Keep build output out of git, then commit**

Append to `.gitignore`:

```gitignore

# pip's in-tree build of python/bundle-mpq
python/bundle-mpq/build/
*.egg-info/
```

Append `python/bundle-mpq/build python/bundle-mpq/bundle_mpq.egg-info` to `clean`.

```bash
git add python/bundle-mpq tests/make_mpq.py tests/test_bundle_mpq.py Makefile .gitignore
git commit -m "feat: add bundle_mpq, a ctypes StormLib MPQ reader, and its tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Stage 13, PyGhidra venv with `bundle_mpq`

**Files:**
- Create: `tests/probes/mpq_probe.py`
- Modify: `Makefile` (stage 13 and the usual places), `tests/run-sanity.sh` (section `pyghidra`)

**Interfaces:**
- Consumes: `scripts/pyghidra-venv-dir.py` (Task 5); `bundle_mpq`, `tests/make_mpq.py` and `tests/test_bundle_mpq.py` (Task 9); `skip` and `$WORK/probe.bin` (Task 1).
- Produces: `13-pyghidra` (alias `pyghidra`), and `mpq_probe.py <archive> <name> <expected-bytes file>`, which prints `MPQ OK <n> bytes` or `MPQ FAIL ...`.

- [ ] **Step 1: Write the failing test**

Create `tests/probes/mpq_probe.py`:

```python
# Opens an MPQ with bundle_mpq inside PyGhidra and compares one file with the expected
# bytes. Prints "MPQ OK <n> bytes" or "MPQ FAIL <reason>".
# Script arguments: <archive.mpq> <name in archive> <file holding the expected bytes>
# @category Bundle
# @runtime PyGhidra
from bundle_mpq import MpqArchive

archive, name, expected_path = getScriptArgs()
with open(expected_path, "rb") as f:
    expected = f.read()
with MpqArchive(archive) as mpq:
    names = mpq.names()
    data = mpq.read(name)
if name not in names:
    print(f"MPQ FAIL {name} not listed (names: {names})")
elif data != expected:
    print(f"MPQ FAIL {name}: {len(data)} bytes differ from the expected {len(expected)}")
else:
    print(f"MPQ OK {len(data)} bytes")
```

In `tests/run-sanity.sh`, insert after the `jython` section:

```bash
# ── 3g. PyGhidra and MPQ ──────────────────────────────────────────────────────
check_pyghidra() {
  local venv log="$WORK/pyghidra.log" mpq="$WORK/fixtures/test.mpq"
  local expected="$WORK/fixtures/test.mpq.bytes" name path status=0
  venv=$(python3 -I "$REPO_DIR/scripts/pyghidra-venv-dir.py" "$INSTALL_DIR")
  if ! "$venv/bin/python3" -I -c 'import pyghidra, bundle_mpq' 2>/dev/null; then
    fail "PyGhidra: $venv lacks pyghidra or bundle_mpq (run 'make pyghidra')"
    return
  fi
  if ! "$venv/bin/python3" -I -c 'import bundle_mpq; bundle_mpq.load_stormlib()' 2>/dev/null; then
    skip "PyGhidra MPQ: StormLib (libstorm) not found"
    return
  fi
  if "$venv/bin/python3" -I "$TESTS/test_bundle_mpq.py" > "$WORK/bundle_mpq.log" 2>&1; then
    pass "PyGhidra: bundle_mpq unit tests"
  else
    fail_with_log "PyGhidra: bundle_mpq unit tests" "$WORK/bundle_mpq.log"
  fi
  name=$("$venv/bin/python3" -I "$TESTS/make_mpq.py" "$mpq" "$expected")
  # pyghidraRun prompts (input()) when it is not in its own venv: run it outside any
  # active virtualenv and with no stdin, so a prompt fails fast instead of hanging.
  path=$PATH
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then path=${path//"$VIRTUAL_ENV/bin:"/}; fi
  (cd "$WORK" && env -u VIRTUAL_ENV PATH="$path" "$TIMEOUT" --foreground "${TEST_IMPORT_TIMEOUT:-600}" \
    "$INSTALL_DIR/support/pyghidraRun" -H "$WORK/proj" "pyghidra-$RANDOM" \
    -import "$WORK/probe.bin" -loader BinaryLoader -processor x86:LE:32:default -noanalysis \
    -deleteProject -scriptPath "$TESTS/probes" -preScript mpq_probe.py "$mpq" "$name" "$expected" \
    < /dev/null > "$log" 2>&1) || status=$?
  ((status == 0)) || echo "pyghidraRun exit status $status" >> "$log"
  if grep -qF "Switching to Ghidra virtual environment: $venv" "$log"; then
    pass "PyGhidra: pyghidraRun uses the bundle's venv"
  else
    fail_with_log "PyGhidra: pyghidraRun did not use $venv" "$log"
  fi
  if grep -q 'MPQ OK' "$log"; then
    pass "PyGhidra: bundle_mpq reads a PKWARE-compressed MPQ inside Ghidra"
  else
    fail_with_log "PyGhidra: mpq_probe.py did not read the MPQ" "$log"
  fi
}

if want pyghidra; then check_pyghidra; fi
```

Run: `SANITY_ONLY=pyghidra make test 2>&1 | tail -3`
Expected: `FAIL  PyGhidra: .../portable/settings/ghidra/ghidra_12.1.4_DEV/venv lacks pyghidra or bundle_mpq (run 'make pyghidra')`.

- [ ] **Step 2: Add stage 13**

```make
BUNDLE_MPQ_SRC := python/bundle-mpq

13-pyghidra: 03-install-ghidra ## Set up PyGhidra's venv (in portable/) with the bundle_mpq MPQ reader
	@VENV=$$(python3 -I scripts/pyghidra-venv-dir.py "$(INSTALL_DIR)") || exit 1; \
	PY="$$VENV/bin/python3"; WHEELS="$(INSTALL_DIR)/Ghidra/Features/PyGhidra/pypkg/dist"; \
	SRC=$$(git hash-object $(BUNDLE_MPQ_SRC)/pyproject.toml $(BUNDLE_MPQ_SRC)/bundle_mpq/*.py | tr -d '\n'); \
	if [ -x "$$PY" ] && [ "$$(cat "$$VENV/.bundle-mpq-source" 2>/dev/null)" = "$$SRC" ] && \
		"$$PY" -I -c 'import pyghidra, bundle_mpq' 2>/dev/null; then \
		echo "PyGhidra venv $$VENV already set up, skipping."; \
	else \
		SUPPORTED=$$(sed -n 's/^application\.python\.supported=//p' "$(INSTALL_DIR)/Ghidra/application.properties"); \
		PYVER=$$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])'); \
		case ", $$SUPPORTED," in *", $$PYVER,"*) ;; \
			*) $(ERR) "python3 is $$PYVER; PyGhidra supports $$SUPPORTED"; exit 1 ;; esac; \
		[ -x "$$PY" ] || python3 -m venv "$$VENV" || exit 1; \
		"$$PY" -m pip install -q --no-index -f "$$WHEELS" pyghidra setuptools wheel || exit 1; \
		"$$PY" -m pip install -q --no-index --no-build-isolation --no-deps --force-reinstall \
			"./$(BUNDLE_MPQ_SRC)" || exit 1; \
		echo "$$SRC" > "$$VENV/.bundle-mpq-source"; \
		$(OK) "PyGhidra venv ready at $$VENV."; \
	fi; \
	"$$PY" -I -c 'import bundle_mpq; bundle_mpq.load_stormlib()' 2>/dev/null || \
		$(WARN) "StormLib not found: bundle_mpq is installed but cannot open MPQs (run 'make deps')."
```

The venv is where `pyghidraRun` itself looks (`get_ghidra_venv`), and it uses the same bundled offline wheels as the launcher. So the first `pyghidraRun` launch neither prompts nor downloads anything.

Add the alias `pyghidra: 13-pyghidra`, add both to `.PHONY`, and insert `13-pyghidra` after `verify-extensions` in `PIPELINE` and in the header comment.

- [ ] **Step 3: Set up the venv and run the test**

```bash
make pyghidra
make pyghidra | grep -c skipping
SANITY_ONLY=pyghidra,portable make test 2>&1 | tail -10
```

Expected:
- `PyGhidra venv ready at .../portable/settings/ghidra/ghidra_12.1.4_DEV/venv.`, then `1` on the second run.
- `PASS  PyGhidra: bundle_mpq unit tests`, `PASS  PyGhidra: pyghidraRun uses the bundle's venv`, `PASS  PyGhidra: bundle_mpq reads a PKWARE-compressed MPQ inside Ghidra`.
- The portable checks still PASS: no `${INSTALL_DIR}` directory appeared.

- [ ] **Step 4: Rebuild when the source changes**

```bash
echo "# touch" >> python/bundle-mpq/bundle_mpq/__init__.py
make pyghidra | tail -1
git checkout python/bundle-mpq/bundle_mpq/__init__.py
make pyghidra | tail -1
```

Expected: `PyGhidra venv ready ...` both times (the source hash changed and then changed back), never `skipping`.

- [ ] **Step 5: Keep the README example working**

Run: `"$(python3 -I scripts/pyghidra-venv-dir.py dist/ghidra_12.1.4_PUBLIC)/bin/python3" -I -c 'from bundle_mpq import MpqArchive; print(MpqArchive)'`
Expected: `<class 'bundle_mpq.MpqArchive'>`.

- [ ] **Step 6: Run with an activated virtualenv (Review Focus 3)**

```bash
source .venv/bin/activate && SANITY_ONLY=pyghidra make test 2>&1 | tail -4; deactivate
```

Expected: the same three PASS lines. Without the `VIRTUAL_ENV`/`PATH` handling, pyghidraRun would pick `.venv` and fail at the install prompt.

- [ ] **Step 7: Run with StormLib missing (Review Focus 5)**

```bash
BUNDLE_STORMLIB=/nonexistent make pyghidra 2>&1 | tail -1
BUNDLE_STORMLIB=/nonexistent SANITY_ONLY=pyghidra make test 2>&1 | tail -3; echo "exit=${PIPESTATUS[0]}"
```

Expected: stage 13 ends with the yellow `StormLib not found: ...` warning and exit status 0. The test prints `SKIP  PyGhidra MPQ: StormLib (libstorm) not found` and `0 passed, 0 failed, 1 skipped`, with `exit=0`.

- [ ] **Step 8: Commit**

```bash
git add tests/probes/mpq_probe.py Makefile tests/run-sanity.sh
git commit -m "feat: set up PyGhidra's venv with bundle_mpq (stage 13)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Docs, spec amendments, full verification

**Files:**
- Modify: `AGENTS.md`, `README.md`, `docs/superpowers/specs/2026-10-08-windows-games-addons-design.md`, `Makefile` (header comment only, if it has drifted)

**Interfaces:**
- Consumes: everything above. This task produces no code.

- [ ] **Step 1: Update `AGENTS.md`**

- §1: replace "with three extensions" with "with eight extensions, the Jython runtime, D2GridraTools scripts and a PyGhidra venv". Add bullets for GhidrAssist (fork, unconfigured LLM assistant), RevEng.AI (fork, unconfigured, uploads binaries to `api.reveng.ai` once configured), ret-sync, GhidraFindcrypt, BinExport, D2GridraTools (+ Jython), and PyGhidra + `bundle_mpq`.
- §2.1: say that the three VMARGS lines use the absolute `$(PORTABLE_DIR)` path, because PyGhidra's launcher does not expand `${INSTALL_DIR}`, and that stage 03 rewrites old installs. Add `~/.config/GhidrAssist` and `~/.reai` to the list of directories that must never be written.
- §2.2: add the directories `GhidrAssist/`, `plugin-ghidra/`, `retsync/`, `GhidraFindcrypt/`, `BinExport/`, `Jython/` and `D2GridraTools/`. Add the rule: "Submodule paths `GhidrAssist`, `plugin-ghidra` and `GhidraFindcrypt` must not change: without `settings.gradle`, Gradle names the extension after the checkout directory."
- New §2.6 **Packages**: every built zip goes to `dist/packages/`, one per artifact. `install_extension` moves it there. Stage 02 uses `$(call GHIDRA_ZIP,…)` (`*_64.zip`) to tell Ghidra's zip from extension zips.
- §2.3: add the submodules with their branches. Note the GhidrAssist and plugin-ghidra forks on `felipe-dos-santos81` (branch `portable-settings`, tags `bundle-pin-<sha7>`; never force-push or delete them; point back at upstream once merged). Note that D2GridraTools is unlicensed: fetched, never modified or redistributed.
- §3: replace the stage table with the full pipeline: 00–06, 07-install-ghidrassist, 08-install-reveng, 09-install-retsync, 10-install-findcrypt, 11-install-binexport, 12-install-scripts, verify-extensions, 13-pyghidra, 14-venv, 15-register-mcp, test. Describe `SANITY_ONLY` in the `test` row.
- §4.1: add "new extensions also add a `PACKAGE_PATTERNS` and `BUILD_OUTPUTS` entry in `tests/run-sanity.sh`".

- [ ] **Step 2: Update `README.md`**

- Line 3: "built from source with eight extensions, Jython, Diablo 2 scripts, PyGhidra with MPQ support and an MCP bridge".
- Stage table: the same rows as AGENTS §3.
- Add a section `## Windows games`:

````markdown
## Windows games

| Add-on | What it is for | Network |
| :--- | :--- | :--- |
| ret-sync (`retsync`) | Follow a running game in x32dbg/x64dbg/WinDbg from Ghidra. Build `ext_x64dbg` from `ret-sync/` on Windows; Ghidra listens on 127.0.0.1:9100 once you enable it (CodeBrowser: ret-sync) | local only |
| GhidraFindcrypt | Analyzer that labels crypto constants (SHA-1/SRP in Battle.net code, zlib/CRC tables) | none |
| BinExport | Export → BinExport, for BinDiff between game patches (e.g. D2 1.13c vs 1.14d). BinDiff itself is amd64-only | none |
| D2GridraTools | Diablo 2 1.14d scripts (Script Manager → Diablo 2), run under the Jython extension. Unlicensed upstream: fetched, never redistributed | none |
| GhidrAssist | LLM assistant (explain, rename, chat). Configure a provider in its Settings tab; data stays under `portable/settings/.../GhidrAssist` | your LLM provider |
| RevEng.AI | Uploads the open binary to `api.reveng.ai` for AI decompilation and similarity search, **only after** you run its setup wizard with an API key (stored in `portable/settings/.../reai/reai.json`) | **uploads binaries** |
| PyGhidra + `bundle_mpq` | Python 3 scripts with MPQ access (StormLib) | none |

Read a file from an MPQ in a PyGhidra script (`dist/ghidra_12.1.4_PUBLIC/support/pyghidraRun`):

```python
from bundle_mpq import MpqArchive
with MpqArchive("/games/d2/d2data.mpq") as mpq:
    weapons = mpq.read("data/global/excel/weapons.txt")
```

Storm.dll FLIRT signatures are not included: none are public, and Storm.dll is Blizzard's code.
````

- Layout: add `scripts/`, `python/bundle-mpq/`, the new submodules, `dist/packages/`, the new extension directories and `tests/probes/`.
- Notes: add "**Built zips** are collected in `dist/packages/` (one per artifact)", and the `SANITY_ONLY` example `SANITY_ONLY=dist,pyghidra make test`.

- [ ] **Step 3: Record the spec amendments**

Append to the spec a section `## 12. Amendments (2026-10-08, from planning)` containing items 1–9 of this plan's "Spec Amendments" list, verbatim. Change the spec's `Status:` line to `approved; implemented (see section 12 for amendments)`.

- [ ] **Step 4: Run the full verification**

```bash
make help
make env
make -n install > /dev/null && echo "make -n install OK"
LOG=$(mktemp) && make install 2>&1 | tee "$LOG" | grep -E 'ERROR|Building'; tail -3 "$LOG"; rm -f "$LOG"
git status --short
```

Expected:
- `make help` lists every new target with its description.
- `make env` ends with `Environment check passed.`
- `make install` runs end to end with no `ERROR` and no `Building` lines, since everything was built in earlier tasks. It ends with the full `make test` summary, `N passed, 0 failed, 0 skipped`, then `Ghidra Bundle installed.`
- `git status` is empty.

- [ ] **Step 5: Hand the GUI smoke test to the user**

Ask the user to run `make run`, open any program in the CodeBrowser, and check:
- File → Configure → Miscellaneous lists GhidrAssist, RevEng.AI, ret-sync, BinExport and Findcrypt as enabled-able plugins.
- Enabling RevEng.AI shows its setup wizard without errors. This checks for a gson classpath conflict, spec §4.4.
- Script Manager has a "Diablo 2" category.
- `ls ~/.config/GhidrAssist ~/.reai` still fails afterwards.

Record their answer. If something fails, open a follow-up task; don't patch it here.

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md README.md docs/superpowers/specs/2026-10-08-windows-games-addons-design.md Makefile
git commit -m "docs: document the Windows game add-ons and dist/packages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
