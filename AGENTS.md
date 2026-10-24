# Agent Instructions: Ghidra Bundle

Operational context, invariants and conventions for AI coding agents working in this repository.

---

## 1. Project Overview

`ghidra-bundle` builds an isolated, reproducible **Ghidra 12.2** from source, with eight extensions, the Jython runtime, D2GridraTools scripts, a PyGhidra venv and a local Model Context Protocol (MCP) bridge:
- **Ghidra 12.2**: built headlessly with Gradle from the `Ghidra_12.2_build` tag.
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
- **REA** (`rea-agents` 6.3.0, optional): CLI and MCP server (`rea`) that analyzes files through this Ghidra headlessly, installed in `.rea/`. Needs Node.js.

---

## 2. Invariants

### 2.1 Portable Mode & Filesystem Isolation
- **Keep Ghidra, extension and REA runtime state under `portable/`**, not in Ghidra's defaults (`~/.config/ghidra` or `$XDG_CONFIG_HOME`, `~/Library/ghidra`, `/var/tmp/<user>-ghidra` or `$XDG_CACHE_HOME`; `~/.ghidra` before 11.1), `~/.config/GhidrAssist` or `~/.reai`. `make test` fails if any of them (or a directory literally named `${INSTALL_DIR}`) appears during the run, and requires the forks' default paths to lie under this install's `portable/settings`.
- `03-install-ghidra` appends this block to `support/launch.properties`, with the absolute install path:
  ```properties
  # --- Portable Mode Overrides ---
  JAVA_HOME_OVERRIDE=<JAVA25_HOME>
  VMARGS=-Dapplication.settingsdir=<INSTALL_DIR>/portable/settings
  VMARGS=-Dapplication.cachedir=<INSTALL_DIR>/portable/cache
  VMARGS=-Dapplication.tempdir=<INSTALL_DIR>/portable/temp
  ```
  The paths must be absolute: PyGhidra's launcher reads `application.settingsdir` without expanding `${INSTALL_DIR}`. Stage 03 rewrites the block whenever it differs from the expected one (old installs with `${INSTALL_DIR}`, a moved checkout, a new JDK).
- The GhidrAssist and RevEng.AI forks keep their data under Ghidra's user settings directory (`portable/settings/.../GhidrAssist`, `.../reai/reai.json`); `tests/probes/PortablePaths.java` checks their defaults.
- All preferences, caches and temp files live under `dist/ghidra_12.2_PUBLIC/portable/`. Headless runs (`analyzeHeadless`) read the same `launch.properties`, so they write there too.
- To test whether the patch is already applied, grep for `^# --- Portable Mode Overrides ---`, not `application.settingsdir`, which also matches upstream's commented lines.

### 2.2 Extension Placement
- Each extension stage records its source commit in `<ext>/.bundle-source` (and its patch identity in `<ext>/.bundle-patch`, §2.9) and rebuilds when either changes.
- Extensions are unzipped into `dist/ghidra_12.2_PUBLIC/Ghidra/Extensions/`, keeping the directory name from their zip:
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
  - `ghidra` (NSA, tag `Ghidra_12.2_build`)
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
- `build-ghidra.sh` keeps `ghidra/dependencies/flatRepo` in sync with the submodule: it fetches dependencies only when the cache is missing or `flatRepo/.bundle-source` differs from the submodule's `git rev-parse HEAD` (marker missing counts as a mismatch), and writes the marker only after a successful fetch. The marker is git-ignored (`flatRepo/` in the submodule's `.gitignore`), so an existing checkout refreshing for a new Ghidra version never dirties the submodule — but the cache itself is updated.
- All Gradle extensions are built with `ghidra/gradlew -I scripts/gradle-toolchain.init.gradle -PbundleJavaMajor=$(JAVA_MAJOR) ... buildExtension` against the installed Ghidra. The init script aligns upstream toolchain declarations with the bundle's JDK 25, so `extension.properties` carries the installed version without submodule source edits.

### 2.4 Python Virtualenv
- `.venv/` (Python 3.10+) holds `ghidra-mcp` installed in editable mode (`pip install -e ./ghidra-mcp`).
- The bridge entry point is `$(BRIDGE_BIN)` = `.venv/bin/bridge-mcp-ghidra`.

### 2.5 Port 8089
- Port `8089` (`MCP_PORT`) is reserved for GhidraMCP's HTTP server.
- `make run` fails fast if the port is in use (checked with `lsof`, or `ss` when `lsof` is missing).
- ret-sync listens on 127.0.0.1:9100 only when enabled; `make test` uses 18089.

### 2.6 Packages
- Every built zip ends up in `dist/packages/`, one per artifact. `install_extension` moves the zip there (deleting older versions and stale same-version builds) and unzips from there; an extension stage skips only when its zip is present in `dist/packages/`.
- Stage 02 uses `$(call GHIDRA_ZIP,<version>)` to select Ghidra's date-suffixed installation zip (`ghidra_<version>_<release>_<yyyymmdd>.zip`) rather than extension zips. Ghidra 12.2 removed the old platform suffix. Legacy installations and packages are not migrated; remove superseded artifacts explicitly.

### 2.7 PyGhidra
- `13-pyghidra` creates the venv where `pyghidraRun` looks for it (`scripts/pyghidra-venv-dir.py` asks Ghidra's `pyghidra_launcher`), installs Ghidra's bundled `pyghidra` wheels offline, and installs `python/bundle-mpq` (rebuilt when its source hash changes).
- StormLib (`libstorm-dev`) is optional: without it the stage warns and `make test` reports SKIP for MPQ checks.

### 2.8 REA
- REA is **not a Ghidra extension**: nothing is installed into `Ghidra/Extensions/`, and `install_extension`, `VerifyExtensions.java` and `dist/packages/` do not apply. It loads its own bridge script through `-scriptPath` into a throwaway read-only project.
- `.rea/package.json` pins `rea-agents` exactly and the committed `.rea/package-lock.json` pins every transitive package with its hash; the stage installs with `npm ci` and reinstalls when the lockfile changes (its hash is kept in `.rea/node_modules/.bundle-lock`). To bump REA, edit the version in `package.json` and run `npm install --prefix .rea --package-lock-only --ignore-scripts`. Upstream ships breaking releases often (4.0.0 to 6.3.0 in five days). Its Ghidra provider admits Linux arm64 from 6.1.0 and needs the host-native decompiler this source build provides.
- REA 6.3.0 upstream verifies Ghidra 12.1.4 and accepts only 12.1.x. `scripts/patch-rea-ghidra.py` adds exactly 12.2 as compatible, not upstream-verified; 12.2.1 and other versions remain rejected, and Java bounds still come from `application.properties`. Stage 16 applies the fail-closed, idempotent patch on every eligible run.
- The package gate accepts only the exact pristine or patched policy SHA-256, so unexpected changes outside the replacement anchors are also fatal. Update `REA_VERSION` and both hashes with the REA pin, and the patched hash with the bundle's Ghidra version. `tests/test_patch_rea_ghidra.py` covers the transformation, real installed policy and outside-anchor rejection; the sanity suite also checks doctor and real decompilation.
- The stage is optional: without npm and Node.js 22.19+, 24.11+ or 26+, or when `npm ci` fails (no network), it warns and carries on, deleting a `.rea/rea` that no longer runs, and `make test` reports SKIP for the `rea` section.
- `$(REA_BIN)` = `.rea/rea` is a wrapper written on every run of the stage. It sets `GHIDRA_INSTALL_DIR`, `JAVA_HOME`, `REA_ANALYSIS_PROVIDER=ghidra` and `TMPDIR` (`portable/temp`, where REA keeps each session's project and its copy of the analyzed file) and calls node by absolute path, so both MCP registrations are just `.rea/rea --mcp`. Re-run `make install-rea` after changing Node or the JDK.
- REA's Ghidra sessions read `launch.properties`, so they write under `portable/` (in `<user>-ghidra/` directories, next to the GUI's `ghidra/`). Never run `rea setup`: it writes skills and registrations into several agent directories under `~`.
- REA has no NE, LE or LX support and imports DOS MZ with Ghidra's stock `MzLoader`, so GhidraMCP with lx-loader and GhidraDosToolbox stays the path for that work. It rejects such a file only when the MZ header points at the NE/LE/LX header. A DOS/4GW-bound program (the LE follows the extender stub) is admitted as plain MZ, and REA then analyzes only the 16-bit stub, without a warning.

### 2.9 Extension Source Compatibility (Ghidra 12.2 API breaks)
- Ghidra 12.2 removed or changed APIs that six extensions use. Stages 04–08 and 10 first run `scripts/prepare-extension-source.py`, which copies the extension's source into a fresh, git-ignored tree under `dist/build/<ext>/` (skipping `.git`, `.gradle`, `build`, `target`, `dist`, `__pycache__`), applies that extension's exact 12.2 replacements there, and leaves the original submodule byte-identical. The script is fail-closed: it accepts only the pinned Ghidra version (12.2; 12.2.1 and others are rejected), requires every anchor at its exact occurrence count, recognizes an already-patched source (idempotence), rejects missing/duplicated/mixed/partial forms, and replaces the destination only after all patches validate. The guarantee is precise: no original is ever modified, and a failed run stops the stage before the destination is replaced — but deleting/copying/writing the destination is not atomic, so an interrupted run can leave the generated copy missing or partial until the stage reruns (it is rebuilt from the pristine source). Ret-sync and BinExport build directly, without source patches.
- Covered transformations: GhidraMCP drops the removed second `DataTypeManager.remove` argument; lx-loader drops the removed `Writeable` interface from `DOSHeader` while retaining its public `write` method; dos-toolbox simplifies a `DosLoader` condition whose `OldDOSHeader.hasNewExeHeader()`/`hasPeHeader()` checks were always false; GhidrAssist drops two obsolete `@Override`s on the removed `TaskMonitor.checkCanceled`/`clearCanceled` aliases; GhidraFindcrypt renames `checkCanceled()` to `checkCancelled()`; RevEng.AI injects the `PluginTool` as the `ServiceProvider` for `BrowserLoader.display` and `GhidraRevengService`, including a real provider assertion in its existing plugin test.
- Rebuild identity: `install_extension`'s optional 6th argument names the original submodule whose `git rev-parse HEAD` goes into `<ext>/.bundle-source`; the optional 7th is the patch identity written to `<ext>/.bundle-patch`. Patched stages pass `<extension>-$(shell git hash-object scripts/prepare-extension-source.py)`, so editing the script forces every patched extension to rebuild; the build copy is regenerated on every stage run, so patched sources cannot go stale.
- To extend the mechanism for a new API break: add the extension's exact old→new anchors (with counts) to `EXTENSIONS` in `scripts/prepare-extension-source.py`, mirror a stage's `*_BUILD_DIR`/`*_PATCH_ID` wiring under `dist/build/`, add tests to `tests/test_prepare_extension_source.py`, and add its real zip output directory to `BUILD_OUTPUTS` in `tests/run-sanity.sh` (which guards both the original build-output dirs and the actual `dist/build/` copies). A break without an exact, tested transformation is still a stop, not a guess.
- `tests/test_prepare_extension_source.py` covers every transformation, idempotence, fail-closed anchor rejection and read-only application against the real pinned submodule sources; run it standalone (`python3 -I tests/test_prepare_extension_source.py`). The `rea` sanity section separately runs `tests/test_patch_rea_ghidra.py`.

---

## 3. Makefile Pipeline

| Stage | Target (alias) | Description |
| :--- | :--- | :--- |
| `00` | `00-deps` (`deps`) | Installs missing OS packages (`apt`/`brew`) and `uv` |
| `00` | `00-env` (`env`) | Checks JDK 25, Maven, Clang, Python 3, uv, Git, curl, GNU `timeout` (`gtimeout` on macOS); warns when the JDK is headless-only or the optional StormLib or Node.js is missing |
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
| `15` | `15-register-mcp` (`register-mcp`) | Registers `ghidra` with opencode (atomic JSON write; a config that is not plain JSON, such as JSONC, is left unchanged with a warning) and Claude Code (`claude mcp add --scope user`, skipped if `claude` is absent), through the `register_mcp` macro |
| `16` | `16-install-rea` (`install-rea`) | Installs REA 6.3.0 from its lockfile (`npm ci`), applies the Ghidra 12.2 compatibility patch, writes the `.rea/rea` wrapper and registers `rea` (`register_mcp`); warns and skips without suitable Node.js or when npm fails |
| — | `test` | Sanity suite (`tests/run-sanity.sh`), in sections: `env`, `extensions`, `fixtures` (ELF/DOS/LE via `SanityCheck.java`), `mcp` (GhidraMCP over HTTP on `TEST_MCP_PORT`, 18089), `dist`, `binexport`, `portable`, `jython`, `pyghidra`, `rea`. `SANITY_ONLY=dist,pyghidra make test` runs a subset |

Runtime and maintenance: `install` (runs `$(PIPELINE)`, all of the above, with `verify-extensions` after stage 12 so a broken extension stops the install before MCP registration, ending with `test`), `run`, `run-bridge`, `verify` (probes `http://127.0.0.1:8089/check_connection`), `clean`, `distclean`.

---

## 4. Development Standards

1. **Makefile**
   - Recipes use **tabs**; `SHELL := /bin/bash`.
   - Every stage is idempotent: skip when its output exists, use `unzip -q -o` and `rm -rf`.
   - Propagate errors (`|| exit 1`, `{ ...; exit 1; }`).
   - Print messages with the `$(OK)`, `$(WARN)` and `$(ERR)` helpers (ANSI via `printf`).
   - Add new extensions through `$(call install_extension,dir,src,zip glob[,legacy dir][,gradle subdir][,commit dir][,patch identity])`, add a check to `VerifyExtensions.java`, add `PACKAGE_PATTERNS` and `BUILD_OUTPUTS` entries in `tests/run-sanity.sh`, and add its build directories to `clean`.
   - Give every user-facing target a `## description`; `make help` lists those.
2. **Bash scripts:** use `set -euo pipefail` and validate with `bash -n <script>`. `build-ghidra.sh` expects `JAVA_HOME` (a full JDK 25, independently revalidated) from the Makefile.
3. **JDK requirement:** every JDK reference is a full JDK: `bin/java` and `bin/javac` must both be executable and report major 25. The reusable `$(call jdk_usable,dir)` check enforces this in `00-deps` (JDK package installation), `00-env`, `03-install-ghidra` and `test`; Linux discovery only accepts homes with both binaries. A JRE-only or wrong-major `JAVA25_HOME` fails `make env`/`make test` and `build-ghidra.sh` with an explicit message. A **headless-only** JDK (Ubuntu's `openjdk-25-jdk-headless` + `openjdk-25-jre-headless`) passes `jdk_usable` but cannot open Ghidra's GUI: it lacks `libawt_xawt.so`, so `GraphicsEnvironment.isHeadless()` is true and the GUI exits with code 1. `$(call jdk_gui_capable,dir)` detects this on Linux (always true on macOS); `00-deps` adds `openjdk-25-jre` for a headless JDK under `/usr/lib/jvm` (and warns for a custom headless `JAVA25_HOME`), `00-env` warns, and `make run` fails with an actionable message instead of launch.sh's generic "Exited with error". `make run` checks the JDK pinned in `support/launch.properties` (`LAUNCH_JDK`), which is what the launcher actually uses; `make test` only needs a headless JDK.
4. **Before merging:**
   - `make help` renders cleanly.
   - `make env` passes.
   - `make -n install` expands without errors.
   - `make test` passes (needs an installed Ghidra).
   - `python3 -I tests/test_prepare_extension_source.py` passes.
   - `git status` is clean.
5. **Adding a test fixture:** build it in `tests/make_fixtures.py` (or add a C file compiled by `tests/run-sanity.sh`), list its facts in `tests/expect/<name>.txt` (grammar in the sanity-test spec, section 5), add a `run_fixture <name> <file> [loader]` line to `tests/run-sanity.sh`, then record snapshots with `UPDATE_SNAPSHOTS=1 make test`. `SanityCheck.java` needs no change.
