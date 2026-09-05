# Ghidra Bundle — Design

**Date:** 2026-09-05
**Status:** Approved (design review)

## Goal

Create a self-contained Ghidra bundle under `ghidra-bundle/` that is built from
source, easy to run, and fully isolated from any other Ghidra installs on the
machine ("Preview installs"). The bundle includes the NSA Ghidra framework, the
`ghidra-mcp` extension + Python bridge, and the `ghidra-lx-loader` extension.
A single `Makefile` is the primary interface, styled after the reference
`~/Downloads/Makefile` (numbered stage targets, `.NOTPARALLEL:` ordering, `make help` via grep,
venv-driven `$(PYTHON)`/`$(PIP)` variables, `clean`).

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ghidra version | Pin to `Ghidra_12.1.2_build` tag | Exact version `ghidra-mcp` is tested against; same build process as `build-ghidra.sh` |
| Build toolchain | JDK 21 + repo's pinned Gradle wrapper (9.4.1) | Matches the 12.1.2 tag's toolchain requirements (JDK 21, Gradle 8.5+) |
| Release layout | Normalize build output to `ghidra_12.1.2_PUBLIC` | Upstream tag defaults to `application.release.name=DEV`; normalizing to `ghidra_12.1.2_PUBLIC` keeps predictable paths |
| Extension path | Install into `<install>/Ghidra/Extensions/` | Ghidra's `GhidraApplicationLayout` only scans `Ghidra/Extensions` and user settings for installed extensions |
| lx-loader build | Build using `ghidra/gradlew` + JDK 21 | Avoids host Gradle mismatches (e.g. system Gradle 9.7+ on JDK 26) by reusing Ghidra's verified wrapper |
| Isolation | Full: user data, MCP ports, Java toolchain, all under bundle | Requested explicitly |
| MCP client | Auto-register bridge in opencode config | Requested explicitly |

## Bundle Layout

```
ghidra-bundle/
├── Makefile              # primary interface with numbered stages
├── build-ghidra.sh       # updated: pins 12.1.2 tag, JDK 21, gradle wrapper
├── ghidra/               # NSA source, shallow clone of Ghidra_12.1.2_build
├── ghidra-mcp/           # bethington/ghidra-mcp
├── lx-loader/            # yetmorecode/ghidra-lx-loader
├── dist/                 # build output + extracted install
│   └── ghidra_12.1.2_PUBLIC/          # normalized runnable install
│       ├── portable/                  # isolated user data (settings/cache/temp)
│       └── Ghidra/
│           └── Extensions/            # GhidraMCP/ + lx-loader/ (install-level)
└── .venv/                # Python deps (bridge-mcp-ghidra)
```

## Isolation Mechanics

### 1. Java toolchain

JDK 21 is resolved dynamically via `/usr/libexec/java_home -v 21` at runtime
(installable via `brew install --cask temurin@21`). Ghidra's own Gradle wrapper
(pinned in the 12.1.2 tag at Gradle 9.4.1) supplies the build toolchain; no
reliance on the default JDK 26 or system Gradle 9.7.1.

### 2. Ghidra user data (portable mode)

Ghidra 12.x supports a portable install via `support/launch.properties`. After
extracting the build, patch the install's `support/launch.properties`:

```properties
JAVA_HOME_OVERRIDE=<dynamically-resolved-jdk-21-path>
VMARGS=-Dapplication.settingsdir=${INSTALL_DIR}/portable/settings
VMARGS=-Dapplication.cachedir=${INSTALL_DIR}/portable/cache
VMARGS=-Dapplication.tempdir=${INSTALL_DIR}/portable/temp
```

Ghidra natively supports `${INSTALL_DIR}` variable expansion in
`launch.properties`. The install step also pre-creates
`dist/ghidra_12.1.2_PUBLIC/portable/{settings,cache,temp}`. Result: Ghidra's
settings, cache, and temp all live under `dist/ghidra_12.1.2_PUBLIC/portable/`;
nothing is written to `~/Library/ghidra` or the user's `$HOME`.

### 3. Extensions (install-level, auto-loaded)

In Ghidra 12.x distributions, `GhidraApplicationLayout` scans
`<install>/Ghidra/Extensions/` for install-level extensions. Both extensions are
built and unzipped into `dist/ghidra_12.1.2_PUBLIC/Ghidra/Extensions/`:

- `GhidraMCP/` — from `ghidra-mcp` Maven build output (`target/GhidraMCP-*.zip`)
- `lx-loader/` — from `lx-loader` build output (`dist/*.zip`)

`ghidra-mcp`'s `tools.setup deploy` step (which writes to the user-profile
`~/Library/ghidra/.../Extensions/`) is bypassed. We use `tools.setup
install-ghidra-deps` + `tools.setup build`, then place the zip ourselves.

### 4. MCP bridge and ports

The bridge runs from the bundle `.venv` (`bridge-mcp-ghidra`) and connects to
the GhidraMCP plugin's HTTP server on `127.0.0.1:8089`. The `run` target checks
that nothing else is bound to port 8089 before launching and fails loudly on
collision (`lsof -i :8089`). The bridge is registered with opencode by adding a
local `mcp` server entry to `~/.config/opencode/opencode.json` pointing at
`.venv/bin/bridge-mcp-ghidra`.

## Build Flow

1. **Checkout:** shallow-clone (`--depth 1`) the three repos:
   - `ghidra`: `https://github.com/NationalSecurityAgency/ghidra.git` at tag `Ghidra_12.1.2_build`
   - `ghidra-mcp`: `https://github.com/bethington/ghidra-mcp.git`
   - `lx-loader`: `https://github.com/yetmorecode/ghidra-lx-loader.git` into `lx-loader/`
2. **Build Ghidra:** from `ghidra/`, `./gradlew -I gradle/support/fetchDependencies.gradle`
   then `./gradlew buildGhidra`. Wrapped by updated `build-ghidra.sh`; JDK 21
   exported. Output lands in `ghidra/build/dist/ghidra_12.1.2_*.zip`.
3. **Install:** unzip the build artifact into `dist/`, normalize folder name to
   `dist/ghidra_12.1.2_PUBLIC`, create `portable/{settings,cache,temp}` and
   `Ghidra/Extensions/`, then patch `support/launch.properties` (portable mode +
   evaluated `JAVA_HOME_OVERRIDE`).
4. **ghidra-mcp:** from `ghidra-mcp/`, run:
   `python3 -m tools.setup install-ghidra-deps --ghidra-path <install>`
   followed by `python3 -m tools.setup build`. Unzip the resulting
   `target/GhidraMCP-*.zip` into `<install>/Ghidra/Extensions/`.
5. **lx-loader:** from `lx-loader/`, run:
   `JAVA_HOME=$(JAVA21_HOME) ../ghidra/gradlew -p . -PGHIDRA_INSTALL_DIR=<install> buildExtension`.
   Unzip the resulting `dist/*.zip` into `<install>/Ghidra/Extensions/`.
   - **Fallback:** If buildExtension fails, fall back to installing the v12.0.1
     release zip into `<install>/Ghidra/Extensions/`.
6. **Venv:** `python3 -m venv .venv && .venv/bin/pip install -e ./ghidra-mcp`
   (installs the `bridge-mcp-ghidra` entry point).
7. **Register:** safely update `~/.config/opencode/opencode.json` with the MCP
   entry for `ghidra` pointing to `.venv/bin/bridge-mcp-ghidra`.

## Makefile Targets

The Makefile specifies `.NOTPARALLEL:` to ensure stage ordering, with numbered
targets and user-friendly aliases:

```
make / make help       → print target summary
00-env / env           → validate prerequisites (JDK 21, Maven, Clang, Python 3, uv, git)
01-checkout / checkout → shallow clone the three repos
02-build-ghidra / build-ghidra → build Ghidra 12.1.2 via build-ghidra.sh
03-install-ghidra / install-ghidra → extract dist/, normalize folder, patch launch.properties
04-install-mcp / install-mcp → build GhidraMCP extension + place into Ghidra/Extensions/
05-install-lx-loader / install-lx-loader → build lx-loader with ghidra/gradlew + place into Ghidra/Extensions/
06-venv / venv         → create .venv + pip install -e ./ghidra-mcp
07-register-mcp / register-mcp → write opencode mcp config entry
install                → run pipeline stages 00 through 07 in order
run                    → launch isolated Ghidra (pre-check port 8089)
run-bridge             → run bridge-mcp-ghidra from .venv (stdio or testing)
verify                 → curl http://127.0.0.1:8089/check_connection
clean                  → remove dist/, .venv/, and repo build artifacts (keeps checkouts)
distclean              → remove dist/, .venv/, and cloned checkouts
```

Targets are idempotent where cheap (`if [ ! -d ... ]` guards), following the
reference Makefile pattern.

## Verification

`make install` completes without error; `make run` opens Ghidra; in the
CodeBrowser enable the GhidraMCP plugin and start the MCP server; `make verify`
returns `Connected: GhidraMCP plugin running with program '<name>'` (or `no program loaded`);
the lx-loader appears under File > Import File for LX/LE binaries. The bundle leaves
no artifacts in `~/Library/ghidra`.

## Out of Scope

- Building Ghidra from `master` (dev) — pinned to the 12.1.2 release tag instead.
- Docker/containerized Ghidra — rejected during brainstorming (GUI plumbing on
  macOS, poor fit for interactive RE).
- Other MCP clients (only opencode registration is performed).