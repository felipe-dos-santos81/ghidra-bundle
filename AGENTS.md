# Agent Instructions: Ghidra Bundle

Operational context, invariants and conventions for AI coding agents working in this repository.

---

## 1. Project Overview

`ghidra-bundle` builds an isolated, reproducible **Ghidra 12.1.4** from source, with eight extensions, the Jython runtime, D2GridraTools scripts, a PyGhidra venv and a local Model Context Protocol (MCP) bridge:
- **Ghidra 12.1.4**: built headlessly with Gradle from the `Ghidra_12.1.4_build` tag.
- **GhidraMCP**: HTTP server plugin (port 8089) and Python bridge (`bridge-mcp-ghidra`).
- **lx-loader**: Linear Executable (`LE`/`LX`) loader (DOS/4GW, OS/2, VxD).
- **GhidraDosToolbox**: MS-DOS loader and analyzers (`wip-ghidra-12` branch).
- **GhidrAssist** (fork): LLM assistant, installed unconfigured; no provider or key ships.
- **RevEng.AI** (`plugin-ghidra`, fork): installed unconfigured; once a user runs its setup wizard with an API key it uploads binaries to `api.reveng.ai`.
- **ret-sync**: syncs Ghidra with x64dbg/WinDbg (127.0.0.1:9100, only when enabled).
- **GhidraFindcrypt**: analyzer for crypto constants.
- **BinExport**: exporter for BinDiff.
- **D2GridraTools** + **Jython**: Diablo 2 1.14d scripts, run under Ghidra's optional Jython extension.
- **PyGhidra + `bundle_mpq`**: PyGhidra's venv in `portable/`, with a ctypes StormLib MPQ reader (`python/bundle-mpq`).

---

## 2. Invariants

### 2.1 Portable Mode & Filesystem Isolation
- **Never write outside `portable/`**: not to Ghidra's own defaults (`~/.config/ghidra` or `$XDG_CONFIG_HOME`, `~/Library/ghidra`, `/var/tmp/<user>-ghidra` or `$XDG_CACHE_HOME`; `~/.ghidra` before 11.1), nor to `~/.config/GhidrAssist` or `~/.reai`. `make test` fails if any of them (or a directory literally named `${INSTALL_DIR}`) appears during the run, and requires the forks' default paths to lie under this install's `portable/settings`.
- `03-install-ghidra` appends this block to `support/launch.properties`, with the absolute install path:
  ```properties
  # --- Portable Mode Overrides ---
  JAVA_HOME_OVERRIDE=<JAVA21_HOME>
  VMARGS=-Dapplication.settingsdir=<INSTALL_DIR>/portable/settings
  VMARGS=-Dapplication.cachedir=<INSTALL_DIR>/portable/cache
  VMARGS=-Dapplication.tempdir=<INSTALL_DIR>/portable/temp
  ```
  The paths must be absolute: PyGhidra's launcher reads `application.settingsdir` without expanding `${INSTALL_DIR}`. Stage 03 rewrites old installs that still have `${INSTALL_DIR}` in the block.
- The GhidrAssist and RevEng.AI forks keep their data under Ghidra's user settings directory (`portable/settings/.../GhidrAssist`, `.../reai/reai.json`); `tests/probes/PortablePaths.java` checks their defaults.
- All preferences, caches and temp files live under `dist/ghidra_12.1.4_PUBLIC/portable/`. Headless runs (`analyzeHeadless`) read the same `launch.properties`, so they write there too.
- To test whether the patch is already applied, grep for `^# --- Portable Mode Overrides ---`, not `application.settingsdir`, which also matches upstream's commented lines.

### 2.2 Extension Placement
- Each extension stage records its source commit in `<ext>/.bundle-source` and rebuilds when the submodule commit changes.
- Extensions are unzipped into `dist/ghidra_12.1.4_PUBLIC/Ghidra/Extensions/`, keeping the directory name from their zip:
  - `GhidraMCP/` (`lib/GhidraMCP-<ver>.jar`)
  - `lx-loader/` (`lib/lx-loader.jar`)
  - `dos-toolbox/` (`lib/dos-toolbox.jar`)
  - `GhidrAssist/`, `plugin-ghidra/`, `retsync/`, `GhidraFindcrypt/`, `BinExport/` (each `lib/<same name>.jar`)
  - `Jython/` (from Ghidra's own `Extensions/Ghidra/` zip) and `D2GridraTools/` (assembled by `scripts/install-d2gridratools.sh`)
- **Never rename an extension directory.** Outside development mode, Ghidra's `ClassSearcher` only scans `<ext>/lib/<jar>.jar` when the jar name starts with the directory name. A renamed extension still shows its scripts but silently loses its loaders, analyzers and plugins.
- **Submodule paths `GhidrAssist`, `plugin-ghidra` and `GhidraFindcrypt` must not change**: those projects have no `settings.gradle`, so Gradle names the extension (zip, directory and jar) after the checkout directory.
- `make verify-extensions` (a pipeline stage before `13-pyghidra`, and run again by `make test`) uses `ghidra_scripts/VerifyExtensions.java` to confirm headlessly that each extension's key classes are loaded. Add a check there when adding an extension.

### 2.3 Submodules & Versions
- Upstream repositories are shallow submodules:
  - `ghidra` (NSA, tag `Ghidra_12.1.4_build`)
  - `ghidra-mcp` (bethington/ghidra-mcp, `main`)
  - `lx-loader` (felipe-dos-santos81/ghidra-lx-loader, `fix-object-permissions`): upstream yetmorecode/ghidra-lx-loader `master` plus the object-permissions fix. Pinned to tag `bundle-pin-6fa8cd7` on the fork (earlier pins: `bundle-pin-bce85fd`), so never force-push the branch or delete those tags. Point it back at upstream once that fix is merged there.
  - `dos-toolbox` (plaes/GhidraDosToolbox, `wip-ghidra-12`)
  - `GhidrAssist` (felipe-dos-santos81/GhidrAssist, `portable-settings`): symgraph/GhidrAssist `master` plus the portable-settings fix, pinned to tag `bundle-pin-267c45a`.
  - `plugin-ghidra` (felipe-dos-santos81/plugin-ghidra, `portable-settings`): RevEngAI/plugin-ghidra `main` plus the portable-settings fix, pinned to tag `bundle-pin-7e8a68b`.
  - Never force-push the forks' `portable-settings` branches or delete their `bundle-pin-*` tags; point them back at upstream once the fixes are merged there.
  - `ret-sync` (bootleg/ret-sync, `master`; the Ghidra extension is in `ext_ghidra/`, and upstream commits old 10.x zips to `ext_ghidra/dist/`)
  - `GhidraFindcrypt` (antoniovazquezblanco/GhidraFindcrypt, `main`)
  - `binexport` (google/binexport, `main`; the Ghidra extension is in `java/`)
  - `D2GridraTools` (dzik87/D2GridraTools, `main`): **unlicensed**. Fetched only; never modify, commit to or redistribute its files.
- Sync with `git submodule sync --recursive` then `git submodule update --init --recursive --depth 1` (`make checkout`); the sync carries `.gitmodules` URL changes into existing clones. `distclean` uses `git submodule deinit -f --all`.
- `GHIDRA_VERSION` in the `Makefile` is the single version pin. Stage 02 fails if it differs from `application.version` in the `ghidra` submodule. `build-ghidra.sh` reads the version from the submodule.
- All Gradle extensions are built with `ghidra/gradlew ... buildExtension` against the installed Ghidra, so their `extension.properties` carry the installed version.

### 2.4 Python Virtualenv
- `.venv/` (Python 3.10+) holds `ghidra-mcp` installed in editable mode (`pip install -e ./ghidra-mcp`).
- The bridge entry point is `$(BRIDGE_BIN)` = `.venv/bin/bridge-mcp-ghidra`.

### 2.5 Port 8089
- Port `8089` (`MCP_PORT`) is reserved for GhidraMCP's HTTP server.
- `make run` fails fast if the port is in use (checked with `lsof`, or `ss` when `lsof` is missing).
- ret-sync listens on 127.0.0.1:9100 only when enabled; `make test` uses 18089.

### 2.6 Packages
- Every built zip ends up in `dist/packages/`, one per artifact. `install_extension` moves the zip there (deleting older versions and stale same-version builds) and unzips from there; an extension stage skips only when its zip is present in `dist/packages/`.
- Stage 02 moves Ghidra's zip there and uses `$(call GHIDRA_ZIP,<version>)` (`ghidra_<version>_*_64.zip`), because extension zips also start with `ghidra_<version>_`.

### 2.7 PyGhidra
- `13-pyghidra` creates the venv where `pyghidraRun` looks for it (`scripts/pyghidra-venv-dir.py` asks Ghidra's `pyghidra_launcher`), installs Ghidra's bundled `pyghidra` wheels offline, and installs `python/bundle-mpq` (rebuilt when its source hash changes).
- StormLib (`libstorm-dev`) is optional: without it the stage warns and `make test` reports SKIP for MPQ checks.

---

## 3. Makefile Pipeline

| Stage | Target (alias) | Description |
| :--- | :--- | :--- |
| `00` | `00-deps` (`deps`) | Installs missing OS packages (`apt`/`brew`) and `uv` |
| `00` | `00-env` (`env`) | Checks JDK 21, Maven, Clang, Python 3, uv, Git, curl, GNU `timeout` (`gtimeout` on macOS) |
| `01` | `01-checkout` (`checkout`) | Fetches submodules (`--depth 1`) |
| `02` | `02-build-ghidra` (`build-ghidra`) | Checks the version pin, runs `build-ghidra.sh` |
| `03` | `03-install-ghidra` (`install-ghidra`) | Extracts the zip to `dist/`, patches `launch.properties` |
| `04` | `04-install-mcp` (`install-mcp`) | Builds and installs GhidraMCP (`install_extension` macro) |
| `05` | `05-install-lx-loader` (`install-lx-loader`) | Builds and installs lx-loader (`install_extension` macro) |
| `06` | `06-install-dos-toolbox` (`install-dos-toolbox`) | Builds and installs GhidraDosToolbox (`install_extension` macro) |
| `07` | `07-install-ghidrassist` (`install-ghidrassist`) | Builds and installs GhidrAssist from the fork |
| `08` | `08-install-reveng` (`install-reveng`) | Builds and installs the RevEng.AI plugin from the fork |
| `09` | `09-install-retsync` (`install-retsync`) | Builds and installs ret-sync (`ext_ghidra/`) |
| `10` | `10-install-findcrypt` (`install-findcrypt`) | Builds and installs GhidraFindcrypt |
| `11` | `11-install-binexport` (`install-binexport`) | Builds and installs BinExport (`java/`) |
| `12` | `12-install-scripts` (`install-scripts`) | Installs Ghidra's Jython extension and assembles D2GridraTools |
| — | `verify-extensions` | Checks headlessly that every extension's key classes load |
| `13` | `13-pyghidra` (`pyghidra`) | Sets up PyGhidra's venv in `portable/` with `bundle_mpq` |
| `14` | `14-venv` (`venv`) | Creates `.venv` and installs `bridge-mcp-ghidra` |
| `15` | `15-register-mcp` (`register-mcp`) | Registers `ghidra` with opencode (atomic JSON write) and Claude Code (`claude mcp add --scope user`, skipped if `claude` is absent) |
| — | `test` | Sanity suite (`tests/run-sanity.sh`), in sections: `extensions`, `fixtures` (ELF/DOS/LE via `SanityCheck.java`), `mcp` (GhidraMCP over HTTP on `TEST_MCP_PORT`, 18089), `dist`, `binexport`, `portable`, `jython`, `pyghidra`. `SANITY_ONLY=dist,pyghidra make test` runs a subset |

Runtime and maintenance: `install` (runs `$(PIPELINE)`, all of the above, with `verify-extensions` after stage 12 so a broken extension stops the install before MCP registration, ending with `test`), `run`, `run-bridge`, `verify` (probes `http://127.0.0.1:8089/check_connection`), `clean`, `distclean`.

---

## 4. Development Standards

1. **Makefile**
   - Recipes use **tabs**; `SHELL := /bin/bash`.
   - Every stage is idempotent: skip when its output exists, use `unzip -q -o` and `rm -rf`.
   - Propagate errors (`|| exit 1`, `{ ...; exit 1; }`).
   - Print messages with the `$(OK)`, `$(WARN)` and `$(ERR)` helpers (ANSI via `printf`).
   - Add new extensions through `$(call install_extension,dir,src,zip glob[,legacy dir][,gradle subdir])`, add a check to `VerifyExtensions.java`, and add a `PACKAGE_PATTERNS` and `BUILD_OUTPUTS` entry in `tests/run-sanity.sh`.
   - Give every user-facing target a `## description`; `make help` lists those.
2. **Bash scripts:** use `set -euo pipefail` and validate with `bash -n <script>`. `build-ghidra.sh` expects `JAVA_HOME` (JDK 21) from the Makefile.
3. **Before merging:**
   - `make help` renders cleanly.
   - `make env` passes.
   - `make -n install` expands without errors.
   - `make test` passes (needs an installed Ghidra).
   - `git status` is clean.
4. **Adding a test fixture:** build it in `tests/make_fixtures.py` (or add a C file compiled by `tests/run-sanity.sh`), list its facts in `tests/expect/<name>.txt` (grammar in the sanity-test spec, section 5), add a `run_fixture <name> <file> [loader]` line to `tests/run-sanity.sh`, then record snapshots with `UPDATE_SNAPSHOTS=1 make test`. `SanityCheck.java` needs no change.
