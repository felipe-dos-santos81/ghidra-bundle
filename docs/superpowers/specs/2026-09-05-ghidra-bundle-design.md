# Ghidra Bundle — Design

**Date:** 2026-09-05
**Status:** Approved (design review)

## Goal

Create a self-contained Ghidra bundle under `ghidra-bundle/` that is built from
source, easy to run, and fully isolated from any other Ghidra installs on the
machine ("Preview installs"). The bundle includes the NSA Ghidra framework, the
`ghidra-mcp` extension + Python bridge, and the `ghidra-lx-loader` extension.
A single `Makefile` is the primary interface, styled after the reference
`~/Downloads/Makefile` (numbered stage targets, `make help` via grep, venv-driven
`$(PYTHON)`/`$(PIP)` variables, `clean`).

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ghidra version | Pin to `Ghidra_12.1.2_build` tag | Exact version `ghidra-mcp` is tested against; same build process as `build-ghidra.sh` |
| Build toolchain | JDK 21 + repo's pinned Gradle wrapper (8.x) | Matches the 12.1.2 tag's documented toolchain (JDK 21, Gradle 8.5+) |
| Isolation | Full: user data, MCP ports, Java toolchain, all under bundle | Requested explicitly |
| MCP client | Auto-register bridge in opencode config | Requested explicitly |

## Bundle Layout

```
ghidra-bundle/
├── Makefile              # primary interface
├── build-ghidra.sh       # updated: pins 12.1.2 tag, JDK 21, gradle wrapper
├── ghidra/               # NSA source, pinned to Ghidra_12.1.2_build
├── ghidra-mcp/           # bethington/ghidra-mcp
├── lx-loader/            # yetmorecode/ghidra-lx-loader
├── dist/                 # build output + extracted install
│   └── ghidra_12.1.2_PUBLIC/          # the runnable install
│       ├── portable/                  # isolated user data (settings/cache/temp)
│       └── Extensions/                # GhidraMCP/ + lx-loader/ (install-level)
└── .venv/                # Python deps (bridge-mcp-ghidra)
```

## Isolation Mechanics

### 1. Java toolchain

JDK 21 is installed via Homebrew (`brew install --cask temurin@21`) and resolved
with `/usr/libexec/java_home -v 21` at runtime. Ghidra's own Gradle wrapper
(pinned in the 12.1.2 tag) supplies Gradle 8.x; no reliance on the default JDK 26
or system Gradle 9.7.1.

### 2. Ghidra user data (portable mode)

Ghidra 12.x supports a portable install via `support/launch.properties`. After
extracting the build, patch the install's `support/launch.properties`:

```properties
JAVA_HOME_OVERRIDE=/path/to/temurin-21.jdk/Contents/Home
VMARGS=-Dapplication.settingsdir=${INSTALL_DIR}/portable/settings
VMARGS=-Dapplication.cachedir=${INSTALL_DIR}/portable/cache
VMARGS=-Dapplication.tempdir=${INSTALL_DIR}/portable/temp
```

Ghidra natively supports the `${INSTALL_DIR}` variable in `launch.properties`
(since 12.0/12.1). Result: Ghidra's settings, cache, and temp all live under
`dist/ghidra_12.1.2_PUBLIC/portable/`; nothing is written to `~/Library/ghidra`
or the user's `$HOME`.

### 3. Extensions (install-level, auto-loaded)

Ghidra auto-loads extensions placed in the install's `Extensions/` directory.
Both extensions are built and unzipped into
`dist/ghidra_12.1.2_PUBLIC/Extensions/`:

- `GhidraMCP/` — from `ghidra-mcp` build output (`GhidraMCP-<version>.zip`)
- `lx-loader/` — from `lx-loader` build output

`ghidra-mcp`'s `tools.setup deploy` step (which writes to the user-profile
`~/Library/ghidra/.../Extensions/`) is bypassed. We use `tools.setup
ensure-prereqs` + `tools.setup build`, then place the zip ourselves.

### 4. MCP bridge and ports

The bridge runs from the bundle `.venv` (`bridge-mcp-ghidra`) and connects to the
GhidraMCP plugin's HTTP server on `127.0.0.1:8089`. The `run` target checks that
nothing else is bound to port 8089 before launching and fails loudly on
collision. The bridge is registered with opencode by adding an `mcp` server entry
to `~/.config/opencode/opencode.json` pointing at the bundle's venv binary.

## Build Flow

1. **Checkout:** clone the three repos; `git checkout Ghidra_12.1.2_build` on the
   Ghidra checkout.
2. **Build Ghidra:** from `ghidra/`, `./gradlew -I gradle/support/fetchDependencies.gradle`
   then `./gradlew buildGhidra`. Wrapped by the updated `build-ghidra.sh`; JDK 21
   exported. Output lands in `ghidra/build/dist/ghidra_*.zip`.
3. **Install:** unzip the build artifact into `dist/`, then patch
   `support/launch.properties` (portable mode + `JAVA_HOME_OVERRIDE`).
4. **ghidra-mcp:** `python -m tools.setup ensure-prereqs --ghidra-path <install>`
   then `python -m tools.setup build` (Maven, installs Ghidra JARs into local
   `~/.m2`). Unzip the resulting `GhidraMCP-*.zip` into
   `<install>/Extensions/`.
5. **lx-loader:** `GHIDRA_INSTALL_DIR=<install> gradle buildExtension` (no release
   zip exists for 12.1.2). Unzip output into `<install>/Extensions/`.
   - **Risk/fallback:** lx-loader's build scripts may not be Gradle 9.7.1
     compatible. If the build fails, fall back to installing the v12.0.1 release
     zip into `Extensions/` (minor version difference, loader API is stable).
6. **Venv:** `python3 -m venv .venv && .venv/bin/pip install -e ghidra-mcp`
   (installs the `bridge-mcp-ghidra` entry point).
7. **Register:** add the opencode MCP server entry pointing at
   `.venv/bin/bridge-mcp-ghidra`.

## Makefile Targets

```
make                 → help (lists targets)
make env             → ensure JDK 21 present (brew temurin@21 if missing)
make checkout        → clone + pin the three repos
make build-ghidra    → build Ghidra 12.1.2 via build-ghidra.sh (JDK 21 + wrapper)
make install-ghidra  → extract dist/ + patch launch.properties (portable mode)
make install-mcp     → build GhidraMCP extension + place into Extensions/
make install-lx-loader → build lx-loader + place into Extensions/
make venv            → create .venv + pip install -e ghidra-mcp
make register-mcp    → write opencode mcp config entry
make install         → checkout + build-ghidra + install-ghidra + install-mcp
                        + install-lx-loader + venv + register-mcp
make run             → launch isolated Ghidra (check port 8089 first)
make run-bridge      → start bridge-mcp-ghidra from .venv
make verify          → curl http://127.0.0.1:8089/check_connection
make clean           → rm -rf dist/ .venv/ build artifacts (keeps checkouts)
```

Targets are idempotent where cheap (skip work if already done), following the
reference Makefile's `if [ ! -d ... ]` guard pattern.

## Verification

`make install` completes without error; `make run` opens Ghidra; in the
CodeBrowser enable the GhidraMCP plugin and start the MCP server; `make verify`
returns `Connected: GhidraMCP plugin running with program '<name>'`; the
lx-loader appears under File > Import File for LX/LE binaries. The bundle leaves
no artifacts in `~/Library/ghidra`.

## Out of Scope

- Building Ghidra from `master` (dev) — pinned to the 12.1.2 release tag instead.
- Docker/containerized Ghidra — rejected during brainstorming (GUI plumbing on
  macOS, poor fit for interactive RE).
- Other MCP clients (only opencode registration is performed).