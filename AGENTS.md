# Agent Instructions: Ghidra Bundle

Operational context, invariants and conventions for AI coding agents working in this repository.

---

## 1. Project Overview

`ghidra-bundle` builds an isolated, reproducible **Ghidra 12.1.4** from source, with three extensions and a local Model Context Protocol (MCP) bridge:
- **Ghidra 12.1.4**: built headlessly with Gradle from the `Ghidra_12.1.4_build` tag.
- **GhidraMCP**: HTTP server plugin (port 8089) and Python bridge (`bridge-mcp-ghidra`).
- **lx-loader**: Linear Executable (`LE`/`LX`) loader (DOS/4GW, OS/2, VxD).
- **GhidraDosToolbox**: MS-DOS loader and analyzers (`wip-ghidra-12` branch).

---

## 2. Invariants

### 2.1 Portable Mode & Filesystem Isolation
- **Never write to `~/.ghidra`**: Ghidra must run in portable mode.
- `03-install-ghidra` appends this block to `support/launch.properties`:
  ```properties
  # --- Portable Mode Overrides ---
  JAVA_HOME_OVERRIDE=<JAVA21_HOME>
  VMARGS=-Dapplication.settingsdir=${INSTALL_DIR}/portable/settings
  VMARGS=-Dapplication.cachedir=${INSTALL_DIR}/portable/cache
  VMARGS=-Dapplication.tempdir=${INSTALL_DIR}/portable/temp
  ```
- All preferences, caches and temp files live under `dist/ghidra_12.1.4_PUBLIC/portable/`. Headless runs (`analyzeHeadless`) read the same `launch.properties`, so they write there too.
- To test whether the patch is already applied, grep for `^# --- Portable Mode Overrides ---`, not `application.settingsdir`, which also matches upstream's commented lines.

### 2.2 Extension Placement
- Extensions are unzipped into `dist/ghidra_12.1.4_PUBLIC/Ghidra/Extensions/`, keeping the directory name from their zip:
  - `GhidraMCP/` (`lib/GhidraMCP-<ver>.jar`)
  - `lx-loader/` (`lib/lx-loader.jar`)
  - `dos-toolbox/` (`lib/dos-toolbox.jar`)
- **Never rename an extension directory.** Outside development mode, Ghidra's `ClassSearcher` only scans `<ext>/lib/<jar>.jar` when the jar name starts with the directory name. A renamed extension still shows its scripts but silently loses its loaders, analyzers and plugins.
- `make verify-extensions` (run by `make test`) uses `ghidra_scripts/VerifyExtensions.java` to confirm headlessly that each extension's key classes are loaded. Add a check there when adding an extension.

### 2.3 Submodules & Versions
- Upstream repositories are shallow submodules:
  - `ghidra` (NSA, tag `Ghidra_12.1.4_build`)
  - `ghidra-mcp` (bethington/ghidra-mcp, `main`)
  - `lx-loader` (yetmorecode/ghidra-lx-loader, `master`)
  - `dos-toolbox` (plaes/GhidraDosToolbox, `wip-ghidra-12`)
- Sync with `git submodule update --init --recursive --depth 1` (`make checkout`). `distclean` uses `git submodule deinit -f --all`.
- `GHIDRA_VERSION` in the `Makefile` is the single version pin. Stage 02 fails if it differs from `application.version` in the `ghidra` submodule. `build-ghidra.sh` reads the version from the submodule.
- All three extensions are built with `ghidra/gradlew ... buildExtension` against the installed Ghidra, so their `extension.properties` carry the installed version.

### 2.4 Python Virtualenv
- `.venv/` (Python 3.10+) holds `ghidra-mcp` installed in editable mode (`pip install -e ./ghidra-mcp`).
- The bridge entry point is `$(BRIDGE_BIN)` = `.venv/bin/bridge-mcp-ghidra`.

### 2.5 Port 8089
- Port `8089` (`MCP_PORT`) is reserved for GhidraMCP's HTTP server.
- `make run` fails fast if the port is in use (checked with `lsof`, or `ss` when `lsof` is missing).

---

## 3. Makefile Pipeline

| Stage | Target (alias) | Description |
| :--- | :--- | :--- |
| `00` | `00-deps` (`deps`) | Installs missing OS packages (`apt`/`brew`) and `uv` |
| `00` | `00-env` (`env`) | Checks JDK 21, Maven, Clang, Python 3, uv, Git |
| `01` | `01-checkout` (`checkout`) | Fetches submodules (`--depth 1`) |
| `02` | `02-build-ghidra` (`build-ghidra`) | Checks the version pin, runs `build-ghidra.sh` |
| `03` | `03-install-ghidra` (`install-ghidra`) | Extracts the zip to `dist/`, patches `launch.properties` |
| `04` | `04-install-mcp` (`install-mcp`) | Builds and installs GhidraMCP (`install_extension` macro) |
| `05` | `05-install-lx-loader` (`install-lx-loader`) | Builds and installs lx-loader (`install_extension` macro) |
| `06` | `06-install-dos-toolbox` (`install-dos-toolbox`) | Builds and installs GhidraDosToolbox (`install_extension` macro) |
| `07` | `07-venv` (`venv`) | Creates `.venv` and installs `bridge-mcp-ghidra` |
| `08` | `08-register-mcp` (`register-mcp`) | Registers `ghidra` with opencode (atomic JSON write) and Claude Code (`claude mcp add --scope user`, skipped if `claude` is absent) |
| — | `test` | Sanity suite (`tests/run-sanity.sh`): runs `verify-extensions`, imports the ELF/DOS/LE fixtures headlessly and checks them with `SanityCheck.java`, then checks GhidraMCP over HTTP on `TEST_MCP_PORT` (18089) |

Runtime and maintenance: `install` (runs `$(PIPELINE)`, all of the above, ending with `test`; `verify-extensions` remains a standalone target), `run`, `run-bridge`, `verify` (probes `http://127.0.0.1:8089/check_connection`), `clean`, `distclean`.

---

## 4. Development Standards

1. **Makefile**
   - Recipes use **tabs**; `SHELL := /bin/bash`.
   - Every stage is idempotent: skip when its output exists, use `unzip -q -o` and `rm -rf`.
   - Propagate errors (`|| exit 1`, `{ ...; exit 1; }`).
   - Print messages with the `$(OK)`, `$(WARN)` and `$(ERR)` helpers (ANSI via `printf`).
   - Add new extensions through `$(call install_extension,dir,src,zip glob)` and add a check to `VerifyExtensions.java`.
   - Give every user-facing target a `## description`; `make help` lists those.
2. **Bash scripts:** use `set -euo pipefail` and validate with `bash -n <script>`. `build-ghidra.sh` expects `JAVA_HOME` (JDK 21) from the Makefile.
3. **Before merging:**
   - `make help` renders cleanly.
   - `make env` passes.
   - `make -n install` expands without errors.
   - `make test` passes (needs an installed Ghidra).
   - `git status` is clean.
4. **Adding a test fixture:** build it in `tests/make_fixtures.py` (or add a C file compiled by `tests/run-sanity.sh`), list its facts in `tests/expect/<name>.txt` (grammar in the sanity-test spec, section 5), add a `run_fixture <name> <file> [loader]` line to `tests/run-sanity.sh`, then record snapshots with `UPDATE_SNAPSHOTS=1 make test`. `SanityCheck.java` needs no change.
