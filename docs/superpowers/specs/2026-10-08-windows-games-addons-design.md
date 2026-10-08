# Windows Game Add-ons and Central `dist/packages/` — Design

Date: 2026-10-08
Status: approved in conversation; awaiting review of this written spec

## 1. Goal

Extend the bundle for reverse engineering Windows games: Diablo 2 (1.14d and
the DLL-split releases before it), other Blizzard games (StarCraft, Warcraft;
Storm.dll and MPQ archives) and Win32 games in general. At the same time,
collect every built zip into one artifact folder at the repo root.

### Success criteria

- `make install` builds and installs GhidrAssist, RevEng.AI, ret-sync,
  GhidraFindcrypt, BinExport, the Jython extension, D2GridraTools and a
  PyGhidra virtualenv with an MPQ reader, and `make test` passes.
- Every zip the build produces (Ghidra and each extension) is in
  `dist/packages/`, one per artifact, and nowhere else for the current
  `GHIDRA_VERSION`.
- Portable mode holds: no run of Ghidra, `analyzeHeadless` or `pyghidraRun`
  writes to `~/.ghidra`, `~/.config/GhidrAssist`, `~/.reai` or a literal
  `${INSTALL_DIR}` directory.
- Cloud-connected add-ons (GhidrAssist, RevEng.AI) are installed but ship no
  keys or endpoints, so nothing leaves the machine until the user configures them.

### Out of scope

- Storm/D2 ordinal `.exports` files, a DirectX `.gdt`, extra Function ID
  databases and a `storm-fid` target. The user left game data out; Storm.dll
  FLIRT signatures go with it (no public set exists, and Storm.dll is
  Blizzard's copyrighted code).
- ghidra_bridge: unmaintained since 2023 and Jython-2.7-only, with an
  unauthenticated RPC port. PyGhidra (bundled with Ghidra 12) plus GhidraMCP
  cover its uses.
- CERT Kaiju / OOAnalyzer, ghidra-delinker-extension, GhidrAssistMCP,
  Ghidra-Cpp-Class-Analyzer (does not compile on 12), FLIRT appliers.
- Running the D2GridraTools scripts in tests (they are interactive and assume
  a 1.14d binary).
- BinDiff itself (amd64-only; BinExport files can be diffed on another machine).

## 2. Decisions

| Question | Decision |
| :--- | :--- |
| Why centralise dist | One artifact folder: every built zip in `dist/packages/`, ready to copy or archive |
| Spec granularity | One combined spec and plan for dist + all add-ons |
| Cloud add-ons | Install, leave unconfigured |
| Default add-ons | GhidrAssist, RevEng.AI, ret-sync, GhidraFindcrypt, BinExport, Jython + D2GridraTools, PyGhidra + MPQ |
| Portable-mode leaks in GhidrAssist / RevEng.AI | Forks on `felipe-dos-santos81`, pinned to `bundle-pin-*` tags, as with lx-loader. Rejected: patch files (dirty submodules mid-build), a global `-Duser.home` override (every plugin and file dialog sees a fake home), documenting the leak |
| Submodule paths | Must equal the extension name for projects without `settings.gradle` (section 4.2) |
| MPQ access | StormLib-backed reader in PyGhidra's venv; ctypes fallback (section 6.2) |

## 3. Dist layout

```text
dist/
├── packages/                       # every built zip, one per artifact
│   ├── ghidra_12.1.4_<release>_<date>_<platform>.zip
│   ├── GhidraMCP-<ver>.zip
│   ├── ghidra_12.1.4_*_lx-loader.zip, ghidra_12.1.4_*_dos-toolbox.zip
│   └── ghidra_12.1.4_*_{GhidrAssist,plugin-ghidra,retsync,GhidraFindcrypt,BinExport}.zip
└── ghidra_12.1.4_PUBLIC/           # the install (unchanged)
```

- New variable `PACKAGES_DIR := $(DIST_DIR)/packages`.
- **Stage 02** builds as today, then moves the new
  `ghidra/build/dist/ghidra_$(GHIDRA_VERSION)_*.zip` into `$(PACKAGES_DIR)`. Its
  "already built" check looks in `$(PACKAGES_DIR)` instead of `ghidra/build/dist/`.
  Older `ghidra_*.zip` files (other versions or dates) in `$(PACKAGES_DIR)` are
  deleted before the move.
- **Stage 03** unzips from `$(PACKAGES_DIR)`.
- **`install_extension`** moves the zip it just built into `$(PACKAGES_DIR)`,
  deleting older zips of the same artifact first, and unzips from there.
- Only zips matching the current `GHIDRA_VERSION` (or, for GhidraMCP, the
  build's `build/distributions/` output) are moved. Zips an upstream repo keeps
  under version control stay where they are: ret-sync commits
  `ext_ghidra/dist/ghidra_10.*_retsync.zip`.
- Moving out of the subprojects also fixes stale zips piling up there
  (e.g. today's 12.1.2 leftovers in `ghidra/build/dist/` and `dos-toolbox/dist/`).

## 4. Extensions

### 4.1 Pipeline

Numbered targets are renumbered; the short aliases stay stable.

```text
00-deps 00-env 01-checkout 02-build-ghidra 03-install-ghidra
04-install-mcp 05-install-lx-loader 06-install-dos-toolbox
07-install-ghidrassist 08-install-reveng 09-install-retsync
10-install-findcrypt 11-install-binexport
12-install-scripts            (Jython + D2GridraTools)
verify-extensions
13-pyghidra                   (PyGhidra venv + MPQ reader)
14-venv 15-register-mcp test
```

New aliases: `install-ghidrassist`, `install-reveng`, `install-retsync`,
`install-findcrypt`, `install-binexport`, `install-scripts`, `pyghidra`.
Existing aliases (`venv`, `register-mcp`, …) keep their names and now point at
the renumbered targets.

### 4.2 Submodules

| Path | URL | Branch / pin | Build dir | Extension dir / jar |
| :--- | :--- | :--- | :--- | :--- |
| `GhidrAssist` | `felipe-dos-santos81/GhidrAssist` (fork of `symgraph/GhidrAssist`) | `portable-settings`, tag `bundle-pin-<sha7>` | `.` | `GhidrAssist/lib/GhidrAssist.jar` |
| `plugin-ghidra` | `felipe-dos-santos81/plugin-ghidra` (fork of `RevEngAI/plugin-ghidra`) | `portable-settings`, tag `bundle-pin-<sha7>` | `.` | `plugin-ghidra/lib/plugin-ghidra.jar` |
| `ret-sync` | `bootleg/ret-sync` | `master` | `ext_ghidra` | `retsync/lib/retsync.jar` (`rootProject.name`) |
| `GhidraFindcrypt` | `antoniovazquezblanco/GhidraFindcrypt` (maintained fork) | default branch | `.` | `GhidraFindcrypt/lib/GhidraFindcrypt.jar` |
| `binexport` | `google/binexport` | `main` | `java` | `BinExport/lib/BinExport.jar` (`rootProject.name`) |
| `D2GridraTools` | `dzik87/D2GridraTools` | `main` | — | built by stage 12 (section 6.1) |

GhidrAssist, plugin-ghidra and GhidraFindcrypt have no `settings.gradle`, so
Gradle names the project, and therefore the zip, extension directory and jar,
after the checkout directory. Their submodule paths must stay exactly as
listed; renaming them silently breaks class loading (AGENTS.md 2.2).

### 4.3 `install_extension` changes

```make
# $(call install_extension,directory,source dir,zip glob[,legacy dir to remove][,gradle subdir])
```

- New optional fifth argument: the Gradle project subdirectory inside the
  submodule (`ext_ghidra` for ret-sync, `java` for BinExport). `.bundle-source`
  still records the submodule's `HEAD`.
- Gradle is invoked as `"$(BUNDLE_DIR)/ghidra/gradlew" -p "<src>/<subdir>"`, so
  nested directories work.
- After the build: find the newest zip matching the glob, delete older
  matches already in `$(PACKAGES_DIR)`, `mv` the new zip there, then unzip from
  `$(PACKAGES_DIR)` as today.
- Glob arguments name the build output, e.g.
  `ret-sync/ext_ghidra/dist/ghidra_$(GHIDRA_VERSION)_*_retsync.zip`, so the
  committed 10.x zips never match.

### 4.4 Build requirements

- GhidrAssist and plugin-ghidra resolve Maven Central and JitPack dependencies;
  BinExport downloads `protoc` for the host platform from Maven Central. The
  first build needs network access. Gradle's own error is the failure message;
  there is no offline fallback.
- GhidrAssist ships `sqlite-jdbc`, which includes linux-aarch64 natives.
- plugin-ghidra bundles gson 2.10.1 next to Ghidra's 2.13.2. `verify-extensions`
  and a manual smoke test catch a classpath conflict; if one appears, the fork
  drops the bundled gson.

## 5. Portable-mode fixes

### 5.1 Absolute paths in `launch.properties`

PyGhidra's launcher (`pyghidra_launcher.py`, `get_user_settings_dir`) reads
`VMARGS=-Dapplication.settingsdir=...` literally and does not expand
`${INSTALL_DIR}`, so today `pyghidraRun` would put its venv under a relative
directory named `${INSTALL_DIR}` in the current directory. Stage 03 now writes
the three `VMARGS` lines with the absolute `$(INSTALL_DIR)` path. The install
was already tied to its location through `JAVA_HOME_OVERRIDE`.

Upgrade path: stage 03 skips when the marker exists, so an existing install
keeps the old lines. Stage 03 also rewrites `${INSTALL_DIR}` to the absolute
path inside the marked block when it finds it (an idempotent `sed` on that block).

### 5.2 Forks

Both forks follow the lx-loader model: branch `portable-settings` on
`felipe-dos-santos81`, pinned to tag `bundle-pin-<sha7>` (never force-push or
delete those tags), and offered upstream as a PR. Once upstream merges, the
submodule goes back to upstream.

- **GhidrAssist**:
  - `GAUtils` base path becomes
    `Application.getUserSettingsDirectory()/GhidrAssist` instead of
    `~/.config/GhidrAssist` (Linux) or `~/Library/Application Support` (macOS).
  - The default `GhidrAssist.AnalysisDBPath` and `GhidrAssist.RLHFDatabasePath`
    (today relative `ghidrassist_analysis.db` and `ghidrassist_rlhf.db`, i.e. the
    current directory) resolve under that same directory when the preference
    is unset. A user-set path is respected.
  - Read-only lookups of `~` (the Claude CLI search in
    `AnthropicClaudeCliProvider`) stay unchanged.
- **plugin-ghidra (RevEng.AI)**: `ReaiPluginPackage.DEFAULT_CONFIG_PATH` becomes
  `Application.getUserSettingsDirectory()/reai/reai.json`. An existing
  `~/.reai/reai.json` is neither read nor migrated; the user re-enters the key
  once in the setup wizard.

Forks are created, pushed and tagged during implementation only after the user
confirms that step.

## 6. Scripts and Python

### 6.1 Stage 12: `12-install-scripts`

1. **Jython**: unzip the Ghidra build's own
   `$(INSTALL_DIR)/Extensions/Ghidra/ghidra_$(GHIDRA_VERSION)_*_Jython.zip` into
   `$(EXT_DIR)` (directory `Jython/`, jar `Jython.jar`). Skip if `$(EXT_DIR)/Jython` exists.
2. **D2GridraTools**: assemble `$(EXT_DIR)/D2GridraTools/`:
   - `extension.properties`: `name=D2GridraTools`, `description=` (Diablo 2
     1.14d scripts, fetched from dzik87/D2GridraTools), `author=dzik87`,
     `createdOn=`, `version=$(GHIDRA_VERSION)`.
   - an empty `Module.manifest`.
   - `ghidra_scripts/*.py` copied from the submodule, with `# @runtime Jython`
     inserted into each file's leading comment header (after the last leading
     `#` line, matching Ghidra's own scripts, e.g. BSim's `QueryFunction.py`).
     The submodule is never modified.
   - `.bundle-source` with the submodule `HEAD`; reassemble when it changes.

PyGhidra's script provider outranks Jython's, so without the tag PyGhidra would
run these Python 2 scripts and they would fail.

Licensing: D2GridraTools has no license. The bundle only fetches it from
upstream and assembles a local copy; it never redistributes it. The README says so.

### 6.2 Stage 13: `13-pyghidra`

1. Resolve the venv path the way `pyghidraRun` does: import
   `pyghidra_launcher` from `$(INSTALL_DIR)/Ghidra/Features/PyGhidra/support`
   and call `get_ghidra_venv(<install dir>, False)`. With section 5.1 this is
   `portable/settings/ghidra/ghidra_12.1.4_<release>/venv`.
2. If the venv is missing, create it with `python3 -m venv` and install the
   wheels the launcher installs (Ghidra's bundled `pyghidra` package), using
   the same steps `pyghidra_launcher.py` runs, so a later `pyghidraRun` finds it ready.
3. Install the MPQ reader into that venv:
   - Preferred: PyPI `mpq` (StormLib bindings), built against `libstorm-dev`.
   - Fallback, if `mpq` does not build or import on the host Python: a small
     ctypes wrapper over `libstorm.so` (`SFileOpenArchive`, `SFileOpenFileEx`,
     `SFileReadFile`, `SFileFindFirstFile`/`Next`, close calls), kept in the
     repo as `python/bundle_mpq/` and `pip install`ed into the venv. The plan's
     first task for this stage decides which applies.
4. Skip when the venv exists and already imports the reader.

`00-deps` adds `libstorm-dev` and `smpq` on apt, and `stormlib` on brew where
the formula exists. `00-env` reports StormLib as optional: a missing StormLib
makes stage 13 warn and install PyGhidra without the MPQ reader, rather than fail.

## 7. Verification and tests

### 7.1 `VerifyExtensions.java`

| Extension | Kind | Class |
| :--- | :--- | :--- |
| GhidrAssist | `Plugin` | `GhidrAssistPlugin` |
| plugin-ghidra | `Plugin` | `ReaiAPIServicePlugin` |
| retsync | `Plugin` | `RetSyncPlugin` |
| GhidraFindcrypt | `Analyzer` | `FindCryptAnalyzer` |
| BinExport | `Exporter` | `BinExportExporter` |
| Jython | `GhidraScriptProvider` | `JythonScriptProvider` |

`Exporter` and `GhidraScriptProvider` are new extension-point kinds for the
script; each needs its own `ClassSearcher.getClasses(...)` query, as the
existing comment explains. The plan confirms each simple class name against
the built jar.

### 7.2 `make test` additions (`tests/run-sanity.sh`)

1. **dist**: `dist/packages/` contains exactly one zip per artifact for
   `GHIDRA_VERSION` (Ghidra + eight extensions); the subprojects' `dist/` and
   `build/distributions/` folders contain no zip for the current version.
2. **BinExport**: a headless import of the existing `sample.o` fixture with
   `-postScript BinExport.java <out>.BinExport` (the script BinExport ships)
   produces a non-empty `.BinExport` file. This exercises upstream issue #166
   at runtime.
3. **Jython / D2GridraTools**: a headless run of a trivial
   `# @runtime Jython` probe script (`tests/probes/JythonProbe.py`) prints its
   marker; every `.py` under `$(EXT_DIR)/D2GridraTools/ghidra_scripts` contains
   `@runtime Jython`.
4. **PyGhidra + MPQ**: `smpq` builds a test MPQ holding a PKWARE-imploded file
   (the compression D2 archives use); `pyghidraRun -H` runs
   `tests/probes/mpq_probe.py`, which lists and extracts it and compares bytes.
   Skipped with a warning when StormLib or `smpq` is missing.
5. **Portable mode**: before and after the whole suite, record whether
   `~/.ghidra`, `~/.config/GhidrAssist`, `~/.reai`, and a `${INSTALL_DIR}`
   directory under the repo and the current directory exist; fail if any
   appeared during the run.

Each new check gets PASS/FAIL lines in the summary like the existing ones, and
section 8 of the sanity-test spec (testing the test) gets a broken-input case
for checks 1, 3 and 5.

## 8. Error handling

- New stages follow the Makefile rules: idempotent skip, `|| exit 1`,
  `$(OK)`/`$(WARN)`/`$(ERR)`, a `## description` per user-facing target.
- A failed extension build stops `install` before `verify-extensions`, as today.
- A missing extension zip, an unzip that does not create the expected
  directory, or a failed `mv` into `$(PACKAGES_DIR)` is an error.

## 9. Cleanup

- `clean` also removes `GhidrAssist/{build,dist,.gradle}`,
  `plugin-ghidra/{build,dist,.gradle}`, `ret-sync/ext_ghidra/{build,.gradle}`
  plus the 12.x zips there (keeping the tracked 10.x zips),
  `GhidraFindcrypt/{build,dist,.gradle}` and `binexport/java/{build,dist,.gradle}`.
  `$(DIST_DIR)` removal already covers `dist/packages/`.
- `distclean` is unchanged.

## 10. Documentation

- **AGENTS.md**: stage table, `dist/packages/` invariant, submodule list with
  the two new fork pins and their no-force-push rule, the
  submodule-path-equals-extension-name rule, Jython/D2GridraTools licensing,
  the absolute `launch.properties` paths (and the updated marker-grep note).
- **README.md**: a "Windows games" section covering what each add-on is for;
  which ones talk to the network (RevEng.AI uploads binaries to
  `api.reveng.ai` once configured; GhidrAssist calls the LLM provider you
  configure) and where their settings live; ret-sync's debugger side (build
  `x64dbg_sync` on Windows, port 9100); a `pyghidraRun` MPQ example; and
  updated install-tree and `dist/` descriptions.

## 11. Ports

| Port | Owner | When |
| :--- | :--- | :--- |
| 8089 | GhidraMCP | GUI (unchanged) |
| 18089 | GhidraMCP test server | `make test` (unchanged) |
| 9100 | ret-sync | only when enabled, 127.0.0.1 |
| 1455, 1456 | GhidrAssist OAuth callback | only during an OAuth login |
